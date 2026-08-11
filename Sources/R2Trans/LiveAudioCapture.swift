@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

/// Captures microphone audio as 24 kHz, mono, signed little-endian PCM16 data.
final class MicrophonePCM16AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    static func requestAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }

            guard granted else {
                throw R2TransError.microphonePermissionDenied
            }
        default:
            throw R2TransError.microphonePermissionDenied
        }
    }

    func start(onAudioData: @escaping @Sendable (Data) -> Void) throws {
        stop()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw R2TransError.microphoneUnavailable
        }

        let converter = PCM16AudioConverter()
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { buffer, _ in
            guard let audioData = converter.convert(buffer), !audioData.isEmpty else {
                return
            }

            onAudioData(audioData)
        }
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            tapInstalled = false
            throw error
        }
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        if engine.isRunning {
            engine.stop()
        }
    }
}

/// Captures system audio as 24 kHz, mono, signed little-endian PCM16 data.
/// Each `start` owns a generation so a concurrent `stop` cannot publish a stale stream.
final class SystemPCM16AudioCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var activeSession: SystemAudioStreamSession?

    static func availableApplications() async throws -> [LiveInterpreterApplicationAudioTarget] {
        guard #available(macOS 13.0, *) else {
            throw R2TransError.systemAudioUnavailable
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var seenProcessIDs = Set<pid_t>()

        return content.applications
            .filter { application in
                let appName = application.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard
                    !appName.isEmpty,
                    application.processID != getpid(),
                    !seenProcessIDs.contains(application.processID)
                else {
                    return false
                }

                seenProcessIDs.insert(application.processID)
                return true
            }
            .map { application in
                LiveInterpreterApplicationAudioTarget(
                    processID: application.processID,
                    appName: application.applicationName,
                    bundleIdentifier: application.bundleIdentifier.isEmpty ? nil : application.bundleIdentifier
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    func start(
        target: LiveInterpreterSystemAudioTarget,
        onAudioData: @escaping @Sendable (Data) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) async throws {
        let startGeneration = beginStart()

        do {
            try Task.checkCancellation()

            guard #available(macOS 13.0, *) else {
                throw R2TransError.systemAudioUnavailable
            }

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard isCurrent(startGeneration) else {
                throw CancellationError()
            }

            guard let display = content.displays.first else {
                throw R2TransError.systemAudioUnavailable
            }

            let filter = try Self.contentFilter(for: target, content: content, display: display)
            let configuration = Self.streamConfiguration()
            let session = SystemAudioStreamSession(
                onAudioData: onAudioData,
                onFailure: { [weak self] error in
                    guard self?.isCurrent(startGeneration) == true else {
                        return
                    }

                    onFailure(error)
                }
            )
            let stream = SCStream(filter: filter, configuration: configuration, delegate: session)
            session.attach(stream)
            do {
                try stream.addStreamOutput(session, type: .audio, sampleHandlerQueue: session.sampleQueue)
            } catch {
                session.finishStartOperation()
                session.stop()
                throw error
            }

            guard install(session, for: startGeneration) else {
                session.finishStartOperation()
                session.stop()
                throw CancellationError()
            }

            do {
                try await withTaskCancellationHandler {
                    try await stream.startCapture()
                } onCancel: {
                    session.stop()
                }
                session.finishStartOperation()
            } catch {
                session.finishStartOperation()
                remove(session, for: startGeneration)
                session.stop()
                throw error
            }

            try session.confirmStarted()
            try Task.checkCancellation()
            guard isActive(session, for: startGeneration) else {
                session.stop()
                throw CancellationError()
            }
        } catch is CancellationError {
            cancelStart(generation: startGeneration)
            throw CancellationError()
        } catch let error as R2TransError {
            cancelStart(generation: startGeneration)
            throw error
        } catch {
            cancelStart(generation: startGeneration)
            throw R2TransError.systemAudioUnavailable
        }
    }

    func stop() {
        let session: SystemAudioStreamSession?

        lock.lock()
        generation &+= 1
        session = activeSession
        activeSession = nil
        lock.unlock()

        session?.stop()
    }

    private func beginStart() -> Int {
        let previousSession: SystemAudioStreamSession?
        let startGeneration: Int

        lock.lock()
        generation &+= 1
        startGeneration = generation
        previousSession = activeSession
        activeSession = nil
        lock.unlock()

        previousSession?.stop()
        return startGeneration
    }

    private func cancelStart(generation expectedGeneration: Int) {
        let session: SystemAudioStreamSession?

        lock.lock()
        if generation == expectedGeneration {
            session = activeSession
            activeSession = nil
        } else {
            session = nil
        }
        lock.unlock()

        session?.stop()
    }

    private func install(_ session: SystemAudioStreamSession, for expectedGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard generation == expectedGeneration, activeSession == nil else {
            return false
        }

        activeSession = session
        return true
    }

    private func remove(_ session: SystemAudioStreamSession, for expectedGeneration: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard generation == expectedGeneration, activeSession === session else {
            return
        }

        activeSession = nil
    }

    private func isCurrent(_ expectedGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == expectedGeneration
    }

    private func isActive(_ session: SystemAudioStreamSession, for expectedGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == expectedGeneration && activeSession === session
    }

    private static func streamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        configuration.queueDepth = 3
        configuration.capturesAudio = true
        configuration.sampleRate = 24_000
        configuration.channelCount = 1
        configuration.excludesCurrentProcessAudio = true
        configuration.showsCursor = false
        return configuration
    }

    private static func contentFilter(
        for target: LiveInterpreterSystemAudioTarget,
        content: SCShareableContent,
        display: SCDisplay
    ) throws -> SCContentFilter {
        switch target {
        case .allSystemAudio:
            let currentApplication = content.applications.first { application in
                application.processID == getpid()
            }
            let excludedApplications = currentApplication.map { [$0] } ?? []
            return SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
        case .application(let targetApplication):
            guard let application = matchingApplication(for: targetApplication, in: content.applications) else {
                throw R2TransError.systemAudioUnavailable
            }

            return SCContentFilter(
                display: display,
                including: [application],
                exceptingWindows: []
            )
        }
    }

    private static func matchingApplication(
        for target: LiveInterpreterApplicationAudioTarget,
        in applications: [SCRunningApplication]
    ) -> SCRunningApplication? {
        if let application = applications.first(where: { $0.processID == target.processID }) {
            return application
        }

        if
            let bundleIdentifier = target.bundleIdentifier,
            let application = applications.first(where: { $0.bundleIdentifier == bundleIdentifier })
        {
            return application
        }

        return applications.first { $0.applicationName == target.appName }
    }
}

private final class SystemAudioStreamSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "R2Trans.SystemPCM16AudioCapture.samples")

    private let lock = NSLock()
    private let converter = PCM16AudioConverter()
    private let onAudioData: @Sendable (Data) -> Void
    private let onFailure: @Sendable (Error) -> Void
    private var stream: SCStream?
    private var stopped = false
    private var startOperationFinished = false
    private var startConfirmed = false
    private var pendingStartFailure: Error?
    private var failureReported = false

    init(
        onAudioData: @escaping @Sendable (Data) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        self.onAudioData = onAudioData
        self.onFailure = onFailure
    }

    func attach(_ stream: SCStream) {
        lock.lock()
        self.stream = stream
        lock.unlock()
    }

    func stop() {
        let stream: SCStream?
        let canReleaseStream: Bool

        lock.lock()
        stopped = true
        stream = self.stream
        canReleaseStream = startOperationFinished
        lock.unlock()

        stream?.stopCapture { [weak self, weak stream] _ in
            guard canReleaseStream, let stream else {
                return
            }
            self?.releaseStream(stream)
        }
    }

    func finishStartOperation() {
        let stream: SCStream?
        let shouldStopAgain: Bool

        lock.lock()
        startOperationFinished = true
        stream = self.stream
        shouldStopAgain = stopped
        lock.unlock()

        guard shouldStopAgain, let stream else {
            return
        }

        stream.stopCapture { [weak self, weak stream] _ in
            guard let stream else {
                return
            }
            self?.releaseStream(stream)
        }
    }

    func confirmStarted() throws {
        lock.lock()
        if stopped {
            lock.unlock()
            throw CancellationError()
        }
        if let pendingStartFailure {
            self.pendingStartFailure = nil
            failureReported = true
            lock.unlock()
            throw pendingStartFailure
        }
        startConfirmed = true
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer), isAcceptingAudio else {
            return
        }

        guard let audioData = converter.convert(sampleBuffer), !audioData.isEmpty else {
            return
        }

        onAudioData(audioData)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        guard !stopped, !failureReported else {
            lock.unlock()
            return
        }
        guard startConfirmed else {
            pendingStartFailure = error
            lock.unlock()
            return
        }
        failureReported = true
        lock.unlock()

        onFailure(error)
    }

    private var isAcceptingAudio: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stopped
    }

    private func releaseStream(_ stream: SCStream) {
        lock.lock()
        if self.stream === stream {
            self.stream = nil
        }
        lock.unlock()
    }
}

private final class PCM16AudioConverter: @unchecked Sendable {
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func convert(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        var streamDescription = streamDescriptionPointer.pointee
        guard let inputFormat = AVAudioFormat(streamDescription: &streamDescription) else {
            return nil
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard
            frameCount > 0,
            let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        else {
            return nil
        }

        inputBuffer.frameLength = AVAudioFrameCount(frameCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: inputBuffer.mutableAudioBufferList
        )

        guard status == noErr else {
            return nil
        }

        return convert(inputBuffer)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter = converter(for: buffer.format) else {
            return nil
        }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate) + 32
        ) else {
            return nil
        }

        let inputProvider = PCMInputProvider(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.next(status: inputStatus)
        }

        guard status != .error, conversionError == nil, outputBuffer.frameLength > 0 else {
            return nil
        }

        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let dataPointer = audioBuffer.mData else {
            return nil
        }

        return Data(bytes: dataPointer, count: Int(audioBuffer.mDataByteSize))
    }

    private func converter(for format: AVAudioFormat) -> AVAudioConverter? {
        if inputFormat == format, let converter {
            return converter
        }

        guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
            return nil
        }

        converter.channelMap = [0]
        inputFormat = format
        self.converter = converter
        return converter
    }
}

private final class PCMInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if didProvideInput {
            status.pointee = .noDataNow
            return nil
        }

        didProvideInput = true
        status.pointee = .haveData
        return buffer
    }
}

/// Mixes independently delivered 24 kHz mono PCM16 sources onto one real-time timeline.
/// A fixed 20 ms cadence prevents microphone and system chunks from being concatenated
/// as if they occurred one after another.
final class PCM16AudioMixer: @unchecked Sendable {
    static let frameSampleCount = 480

    private static let bytesPerSample = MemoryLayout<Int16>.size
    private static let frameByteCount = frameSampleCount * bytesPerSample
    private static let maximumBufferedByteCount = 24_000 * bytesPerSample * 2

    private let queue = DispatchQueue(label: "R2Trans.PCM16AudioMixer")
    private var buffers: [LiveInterpreterAudioSource: Data] = [
        .microphone: Data(),
        .systemAudio: Data()
    ]
    private var timer: DispatchSourceTimer?
    private var onMixedAudio: (@Sendable (Data) -> Void)?

    func append(_ data: Data, from source: LiveInterpreterAudioSource) {
        guard !data.isEmpty else {
            return
        }

        queue.async { [weak self] in
            guard let self, self.timer != nil else {
                return
            }

            self.buffers[source, default: Data()].append(data)
            let overflow = self.buffers[source, default: Data()].count - Self.maximumBufferedByteCount
            if overflow > 0 {
                let evenOverflow = overflow + overflow % Self.bytesPerSample
                self.buffers[source, default: Data()].removeFirst(evenOverflow)
            }
        }
    }

    func start(onMixedAudio: @escaping @Sendable (Data) -> Void) {
        queue.sync {
            guard timer == nil else {
                return
            }

            self.onMixedAudio = onMixedAudio
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now() + .milliseconds(20),
                repeating: .milliseconds(20),
                leeway: .milliseconds(3)
            )
            timer.setEventHandler { [weak self] in
                self?.emitNextFrame()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
            onMixedAudio = nil
            buffers[.microphone] = Data()
            buffers[.systemAudio] = Data()
        }
    }

    static func mix(
        microphone: Data,
        systemAudio: Data,
        frameSampleCount: Int = frameSampleCount
    ) -> Data {
        var output = Data(count: frameSampleCount * bytesPerSample)

        output.withUnsafeMutableBytes { outputBytes in
            let outputSamples = outputBytes.bindMemory(to: Int16.self)
            microphone.withUnsafeBytes { microphoneBytes in
                let microphoneSamples = microphoneBytes.bindMemory(to: Int16.self)
                systemAudio.withUnsafeBytes { systemBytes in
                    let systemSamples = systemBytes.bindMemory(to: Int16.self)

                    for index in 0..<frameSampleCount {
                        let microphoneSample = index < microphoneSamples.count
                            ? Int32(microphoneSamples[index])
                            : 0
                        let systemSample = index < systemSamples.count
                            ? Int32(systemSamples[index])
                            : 0
                        let mixed = max(
                            Int32(Int16.min),
                            min(Int32(Int16.max), microphoneSample + systemSample)
                        )
                        outputSamples[index] = Int16(mixed)
                    }
                }
            }
        }

        return output
    }

    private func emitNextFrame() {
        let microphone = takeFrame(from: .microphone)
        let systemAudio = takeFrame(from: .systemAudio)
        guard !microphone.isEmpty || !systemAudio.isEmpty else {
            return
        }

        onMixedAudio?(
            Self.mix(
                microphone: microphone,
                systemAudio: systemAudio
            )
        )
    }

    private func takeFrame(from source: LiveInterpreterAudioSource) -> Data {
        var buffer = buffers[source, default: Data()]
        let byteCount = min(Self.frameByteCount, buffer.count - buffer.count % Self.bytesPerSample)
        guard byteCount > 0 else {
            return Data()
        }

        let frame = Data(buffer.prefix(byteCount))
        buffer.removeFirst(byteCount)
        buffers[source] = buffer
        return frame
    }
}
