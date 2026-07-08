import AVFoundation
import CoreMedia
import ScreenCaptureKit
import Foundation

final class LiveInterpreterService {
    var onUpdate: ((LiveInterpreterUpdate) -> Void)?

    private let microphoneStreamer = MicrophoneAudioStreamer()
    private let systemAudioStreamer = SystemAudioStreamer()
    private let provisionalSubtitleTranslator = ProvisionalLiveSubtitleTranslator()
    private let stateQueue = DispatchQueue(label: "R2Trans.LiveInterpreterService.state")
    private let audioLevelQueue = DispatchQueue(label: "R2Trans.LiveInterpreterService.audioLevel")
    private var translationSession: RealtimeTranslationSocket?
    private var closingTranslationSessions: [RealtimeTranslationSocket] = []
    private var sourceTranscript = ""
    private var translatedSubtitle = ""
    private var provisionalSubtitle = ""
    private var targetLanguageDisplayName = ""
    private var lastOfficialSubtitleUpdateTime: TimeInterval = 0
    private var lastAudioLevelUpdate: [LiveInterpreterAudioSource: TimeInterval] = [:]
    private var audioChunkCount = 0

    private(set) var isRunning = false

    func start(
        inputSource: LiveInterpreterInputSource,
        targetLanguageCode: String,
        systemAudioTarget: LiveInterpreterSystemAudioTarget
    ) async throws {
        guard !isRunning else {
            return
        }

        let apiKey = KeychainStore.loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw R2TransError.apiKeyMissing
        }

        if inputSource.includesMicrophone {
            try await requestMicrophoneAccess()
        }

        resetTranscriptState()
        targetLanguageDisplayName = SupportedLanguage.displayName(for: targetLanguageCode)

        let translationSession = makeTranslationSocket(
            targetLanguage: RealtimeTranslationLanguage(
                code: targetLanguageCode,
                displayName: targetLanguageDisplayName
            )
        )
        self.translationSession = translationSession

        sendUpdate(.status(AppText.text(.liveInterpreterConnecting)))
        sendUpdate(.debug("target: \(targetLanguageCode)"))
        translationSession.connect(apiKey: apiKey)

        do {
            if inputSource.includesMicrophone {
                try microphoneStreamer.start { [weak self] audioData in
                    self?.sendAudio(audioData, from: .microphone)
                }
            }

            if inputSource.includesSystemAudio {
                try await systemAudioStreamer.start(target: systemAudioTarget) { [weak self] audioData in
                    self?.sendAudio(audioData, from: .systemAudio)
                }
            }
        } catch {
            stop()
            throw error
        }

        isRunning = true
        sendUpdate(.runningStateChanged(true))
        sendUpdate(.status(AppText.text(.liveInterpreterListening)))
    }

    func stop() {
        microphoneStreamer.stop()
        systemAudioStreamer.stop()
        provisionalSubtitleTranslator.cancel()
        closeTranslationSession()

        sendUpdate(.audioLevel(.microphone, 0))
        sendUpdate(.audioLevel(.systemAudio, 0))

        guard isRunning else {
            return
        }

        isRunning = false
        sendUpdate(.runningStateChanged(false))
        sendUpdate(.status(AppText.text(.liveInterpreterStopped)))
    }

    func clear() {
        resetTranscriptState()
        sendUpdate(.sourceTranscript(""))
        sendUpdate(.subtitle("", languageLabel: ""))
        sendUpdate(.audioLevel(.microphone, 0))
        sendUpdate(.audioLevel(.systemAudio, 0))
    }

    func availableSystemAudioApplications() async throws -> [LiveInterpreterApplicationAudioTarget] {
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

    private func makeTranslationSocket(targetLanguage: RealtimeTranslationLanguage) -> RealtimeTranslationSocket {
        RealtimeTranslationSocket(
            targetLanguage: targetLanguage,
            onEvent: { [weak self] targetLanguage, event in
                self?.handle(event, from: targetLanguage)
            },
            onError: { [weak self] message in
                self?.sendUpdate(.error(message))
            },
            onClosed: { [weak self] socket in
                self?.removeClosedTranslationSession(socket)
            }
        )
    }

    private func closeTranslationSession() {
        guard let translationSession else {
            return
        }

        self.translationSession = nil
        closingTranslationSessions.append(translationSession)
        translationSession.closeGracefully()
    }

    private func removeClosedTranslationSession(_ socket: RealtimeTranslationSocket) {
        closingTranslationSessions.removeAll { $0 === socket }

        if translationSession === socket {
            translationSession = nil
        }
    }

    private func sendAudio(_ data: Data, from source: LiveInterpreterAudioSource) {
        publishAudioLevelIfNeeded(for: data, from: source)
        publishAudioChunkDebugIfNeeded()

        let base64Audio = data.base64EncodedString()
        translationSession?.sendAudio(base64Audio)
    }

    private func publishAudioChunkDebugIfNeeded() {
        audioLevelQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.audioChunkCount += 1
            if self.audioChunkCount == 1 || self.audioChunkCount % 120 == 0 {
                self.sendUpdate(.debug("audio chunks sent: \(self.audioChunkCount)"))
            }
        }
    }

    private func publishAudioLevelIfNeeded(for data: Data, from source: LiveInterpreterAudioSource) {
        let level = Self.audioLevel(for: data)

        audioLevelQueue.async { [weak self] in
            guard let self else {
                return
            }

            let now = CFAbsoluteTimeGetCurrent()
            let lastUpdate = self.lastAudioLevelUpdate[source] ?? 0
            guard now - lastUpdate >= 0.08 else {
                return
            }

            self.lastAudioLevelUpdate[source] = now
            self.sendUpdate(.audioLevel(source, level))
        }
    }

    private func handle(_ event: RealtimeTranslationEvent, from targetLanguage: RealtimeTranslationLanguage) {
        stateQueue.async { [weak self] in
            guard let self else {
                return
            }

            switch event {
            case .inputTranscriptDelta(let delta):
                self.sendUpdate(.debug("input transcript delta"))
                self.sourceTranscript = Self.trimmedTail(self.sourceTranscript + delta, limit: 800)
                self.sendUpdate(.sourceTranscript(Self.lineBrokenSentences(in: self.sourceTranscript)))
                self.requestProvisionalSubtitle(targetLanguage: targetLanguage)
            case .outputTranscriptDelta(let delta):
                self.sendUpdate(.debug("output transcript delta"))
                self.translatedSubtitle = Self.trimmedTail(self.translatedSubtitle + delta, limit: 1_500)
                self.provisionalSubtitle = ""
                self.lastOfficialSubtitleUpdateTime = CFAbsoluteTimeGetCurrent()
                self.publishSubtitle(preferProvisional: false)
            case .status(let message):
                self.sendUpdate(.status(message))
            case .debug(let message):
                self.sendUpdate(.debug(message))
            case .error(let message):
                self.sendUpdate(.error(message))
            }
        }
    }

    private func requestProvisionalSubtitle(targetLanguage: RealtimeTranslationLanguage) {
        provisionalSubtitleTranslator.submit(
            sourceTranscript: sourceTranscript,
            targetLanguageCode: targetLanguage.code
        ) { [weak self] subtitle in
            self?.stateQueue.async { [weak self] in
                guard let self else {
                    return
                }

                let officialAge = CFAbsoluteTimeGetCurrent() - self.lastOfficialSubtitleUpdateTime
                guard self.translatedSubtitle.isEmpty || officialAge > 0.65 else {
                    return
                }

                self.provisionalSubtitle = subtitle
                self.publishSubtitle(preferProvisional: true)
            }
        }
    }

    private func publishSubtitle(preferProvisional: Bool) {
        let subtitle: String

        if preferProvisional, !provisionalSubtitle.isEmpty {
            subtitle = translatedSubtitle.isEmpty
                ? provisionalSubtitle
                : "\(translatedSubtitle)\n\(provisionalSubtitle)"
        } else {
            subtitle = translatedSubtitle
        }

        sendUpdate(.subtitle(Self.lineBrokenSentences(in: subtitle), languageLabel: targetLanguageDisplayName))
    }

    private func resetTranscriptState() {
        stateQueue.sync {
            sourceTranscript = ""
            translatedSubtitle = ""
            provisionalSubtitle = ""
            lastOfficialSubtitleUpdateTime = 0
            audioChunkCount = 0
            provisionalSubtitleTranslator.cancel()
        }
        targetLanguageDisplayName = ""
    }

    private func requestMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }

            if granted {
                return
            }

            throw R2TransError.microphonePermissionDenied
        default:
            throw R2TransError.microphonePermissionDenied
        }
    }

    private func sendUpdate(_ update: LiveInterpreterUpdate) {
        Task { @MainActor in
            onUpdate?(update)
        }
    }

    private static func trimmedTail(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }

        return String(value.suffix(limit))
    }

    private static func lineBrokenSentences(in text: String) -> String {
        var result = ""
        var previousWasLineBreak = false
        let terminators = Set<Character>([".", "!", "?", "。", "！", "？"])

        for character in text {
            if character == "\n" {
                if !previousWasLineBreak {
                    result.append(character)
                }
                previousWasLineBreak = true
                continue
            }

            if previousWasLineBreak, character.isWhitespace {
                continue
            }

            result.append(character)

            if terminators.contains(character) {
                result.append("\n")
                previousWasLineBreak = true
            } else {
                previousWasLineBreak = false
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func audioLevel(for data: Data) -> Double {
        let sampleCount = data.count / 2
        guard sampleCount > 0 else {
            return 0
        }

        let sumSquares = data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var sum = 0.0

            for index in stride(from: 0, to: sampleCount * 2, by: 2) {
                let sampleBits = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
                let sample = Double(Int16(bitPattern: sampleBits))
                sum += sample * sample
            }

            return sum
        }

        let rms = sqrt(sumSquares / Double(sampleCount)) / Double(Int16.max)
        return min(1, rms * 8)
    }
}

private final class ProvisionalLiveSubtitleTranslator: @unchecked Sendable {
    private let translator = OpenAITranslator()
    private let queue = DispatchQueue(label: "R2Trans.ProvisionalLiveSubtitleTranslator")
    private var scheduledTask: Task<Void, Never>?
    private var inFlight = false
    private var latestText = ""
    private var targetLanguageCode = ""
    private var lastRequestedText = ""
    private var lastRequestTime: TimeInterval = 0
    private var generation = 0

    func submit(
        sourceTranscript: String,
        targetLanguageCode: String,
        onResult: @escaping (String) -> Void
    ) {
        let text = Self.translationWindow(from: sourceTranscript)
        guard Self.shouldTranslate(text) else {
            return
        }

        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.latestText = text
            self.targetLanguageCode = targetLanguageCode

            guard Self.isMeaningfullyDifferent(text, from: self.lastRequestedText) else {
                return
            }

            if !self.inFlight {
                self.scheduleNextTranslation(onResult: onResult)
            }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            self?.scheduledTask?.cancel()
            self?.scheduledTask = nil
            self?.inFlight = false
            self?.latestText = ""
            self?.targetLanguageCode = ""
            self?.lastRequestedText = ""
            self?.lastRequestTime = 0
            self?.generation += 1
        }
    }

    private func scheduleNextTranslation(onResult: @escaping (String) -> Void) {
        scheduledTask?.cancel()

        let now = CFAbsoluteTimeGetCurrent()
        let delay = max(0.25, 0.9 - (now - lastRequestTime))
        let scheduledGeneration = generation

        scheduledTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            self?.queue.async { [weak self] in
                guard self?.generation == scheduledGeneration else {
                    return
                }

                self?.startTranslation(onResult: onResult)
            }
        }
    }

    private func startTranslation(onResult: @escaping (String) -> Void) {
        guard !inFlight, Self.isMeaningfullyDifferent(latestText, from: lastRequestedText) else {
            return
        }

        let requestText = latestText
        let requestTargetLanguageCode = targetLanguageCode
        lastRequestedText = requestText
        lastRequestTime = CFAbsoluteTimeGetCurrent()
        inFlight = true
        let requestGeneration = generation

        Task { [weak self] in
            let translated = try? await self?.translator.translateLiveTranscript(
                requestText,
                targetLanguageCode: requestTargetLanguageCode
            )

            self?.queue.async { [weak self] in
                guard let self else {
                    return
                }

                guard self.generation == requestGeneration else {
                    return
                }

                self.inFlight = false

                if let translated = translated?.trimmingCharacters(in: .whitespacesAndNewlines), !translated.isEmpty {
                    onResult(translated)
                }

                if Self.isMeaningfullyDifferent(self.latestText, from: self.lastRequestedText) {
                    self.scheduleNextTranslation(onResult: onResult)
                }
            }
        }
    }

    private static func translationWindow(from sourceTranscript: String) -> String {
        let trimmed = sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 280 else {
            return trimmed
        }

        return String(trimmed.suffix(280)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldTranslate(_ text: String) -> Bool {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
            .count >= 8
    }

    private static func isMeaningfullyDifferent(_ lhs: String, from rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)

        guard left != right else {
            return false
        }

        return abs(left.count - right.count) >= 6 || !left.hasPrefix(right)
    }
}

enum LiveInterpreterUpdate {
    case runningStateChanged(Bool)
    case status(String)
    case sourceTranscript(String)
    case subtitle(String, languageLabel: String)
    case audioLevel(LiveInterpreterAudioSource, Double)
    case debug(String)
    case error(String)
}

enum LiveInterpreterAudioSource: Hashable {
    case microphone
    case systemAudio
}

enum LiveInterpreterSystemAudioTarget: Hashable {
    case allSystemAudio
    case application(LiveInterpreterApplicationAudioTarget)

    var displayName: String {
        switch self {
        case .allSystemAudio:
            return AppText.text(.allSystemAudio)
        case .application(let application):
            return application.displayName
        }
    }
}

struct LiveInterpreterApplicationAudioTarget: Hashable {
    let processID: pid_t
    let appName: String
    let bundleIdentifier: String?

    var displayName: String {
        appName
    }
}

enum LiveInterpreterInputSource: String, CaseIterable {
    case microphone
    case systemAudio
    case microphoneAndSystemAudio

    var displayName: String {
        switch self {
        case .microphone:
            return AppText.text(.microphoneInput)
        case .systemAudio:
            return AppText.text(.systemAudioInput)
        case .microphoneAndSystemAudio:
            return AppText.text(.microphoneAndSystemAudioInput)
        }
    }

    var includesMicrophone: Bool {
        switch self {
        case .microphone, .microphoneAndSystemAudio:
            return true
        case .systemAudio:
            return false
        }
    }

    var includesSystemAudio: Bool {
        switch self {
        case .systemAudio, .microphoneAndSystemAudio:
            return true
        case .microphone:
            return false
        }
    }
}

private final class MicrophoneAudioStreamer {
    private let engine = AVAudioEngine()
    private var converter = PCM16AudioConverter()
    private var onAudioData: ((Data) -> Void)?

    func start(onAudioData: @escaping (Data) -> Void) throws {
        stop()

        self.onAudioData = onAudioData

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw R2TransError.microphoneUnavailable
        }

        converter = PCM16AudioConverter()

        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let audioData = self?.convert(buffer), !audioData.isEmpty else {
                return
            }

            self?.onAudioData?(audioData)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        onAudioData = nil
        converter = PCM16AudioConverter()
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        converter.convert(buffer)
    }
}

private final class SystemAudioStreamer: NSObject, SCStreamOutput, SCStreamDelegate {
    private let sampleQueue = DispatchQueue(label: "R2Trans.SystemAudioStreamer.samples")
    private var stream: SCStream?
    private var converter = PCM16AudioConverter()
    private var onAudioData: ((Data) -> Void)?

    func start(
        target: LiveInterpreterSystemAudioTarget,
        onAudioData: @escaping (Data) -> Void
    ) async throws {
        stop()

        guard #available(macOS 13.0, *) else {
            throw R2TransError.systemAudioUnavailable
        }

        self.onAudioData = onAudioData
        converter = PCM16AudioConverter()

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                throw R2TransError.systemAudioUnavailable
            }

            let filter = try Self.contentFilter(for: target, content: content, display: display)

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

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            self.stream = stream
            try await stream.startCapture()
        } catch let error as R2TransError {
            self.onAudioData = nil
            throw error
        } catch {
            self.onAudioData = nil
            throw R2TransError.systemAudioUnavailable
        }
    }

    func stop() {
        let stream = self.stream
        self.stream = nil
        onAudioData = nil
        converter = PCM16AudioConverter()

        if let stream {
            stream.stopCapture { _ in }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        guard let audioData = converter.convert(sampleBuffer), !audioData.isEmpty else {
            return
        }

        onAudioData?(audioData)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onAudioData = nil
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
            guard let application = Self.matchingApplication(for: targetApplication, in: content.applications) else {
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

private final class PCM16AudioConverter {
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

        var didProvideInput = false
        var conversionError: NSError?

        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            status.pointee = .haveData
            return buffer
        }

        guard conversionError == nil, outputBuffer.frameLength > 0 else {
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

private final class RealtimeTranslationSocket {
    private let targetLanguage: RealtimeTranslationLanguage
    private let session = URLSession(configuration: .default)
    private let sendQueue: DispatchQueue
    private let onEvent: (RealtimeTranslationLanguage, RealtimeTranslationEvent) -> Void
    private let onError: (String) -> Void
    private let onClosed: (RealtimeTranslationSocket) -> Void
    private var task: URLSessionWebSocketTask?
    private var isDisconnected = false
    private var isClosing = false
    private var closeFallbackWorkItem: DispatchWorkItem?

    init(
        targetLanguage: RealtimeTranslationLanguage,
        onEvent: @escaping (RealtimeTranslationLanguage, RealtimeTranslationEvent) -> Void,
        onError: @escaping (String) -> Void,
        onClosed: @escaping (RealtimeTranslationSocket) -> Void
    ) {
        self.targetLanguage = targetLanguage
        self.onEvent = onEvent
        self.onError = onError
        self.onClosed = onClosed
        self.sendQueue = DispatchQueue(label: "R2Trans.RealtimeTranslationSocket.\(targetLanguage.apiLanguageCode)")
    }

    func connect(apiKey: String) {
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("r2trans-local-user", forHTTPHeaderField: "OpenAI-Safety-Identifier")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        onEvent(targetLanguage, .debug("socket started: \(targetLanguage.apiLanguageCode)"))
        sendSessionUpdate()
        receiveNextMessage()
    }

    func sendAudio(_ base64Audio: String) {
        guard !isClosing else {
            return
        }

        sendJSON([
            "type": "session.input_audio_buffer.append",
            "audio": base64Audio
        ])
    }

    func closeGracefully() {
        guard !isDisconnected else {
            onClosed(self)
            return
        }

        guard task != nil else {
            finishClosed()
            return
        }

        guard !isClosing else {
            return
        }

        isClosing = true
        sendJSON(["type": "session.close"], allowWhileClosing: true)

        let fallback = DispatchWorkItem { [weak self] in
            guard let self, self.isClosing, !self.isDisconnected else {
                return
            }

            self.onEvent(self.targetLanguage, .debug("session.close timed out"))
            self.finishClosed()
        }
        closeFallbackWorkItem = fallback
        sendQueue.asyncAfter(deadline: .now() + 5, execute: fallback)
    }

    private func disconnect() {
        isDisconnected = true
        isClosing = false
        closeFallbackWorkItem?.cancel()
        closeFallbackWorkItem = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session.invalidateAndCancel()
    }

    private func finishClosed() {
        guard !isDisconnected else {
            return
        }

        disconnect()
        onClosed(self)
    }

    private func sendSessionUpdate() {
        sendJSON([
            "type": "session.update",
            "session": [
                "audio": [
                    "output": [
                        "language": targetLanguage.apiLanguageCode
                    ]
                ]
            ]
        ])
    }

    private func sendJSON(_ object: [String: Any], allowWhileClosing: Bool = false) {
        guard
            let task,
            let data = try? JSONSerialization.data(withJSONObject: object),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        sendQueue.async { [weak self] in
            guard
                let self,
                !self.isDisconnected,
                allowWhileClosing || !self.isClosing
            else {
                return
            }

            task.send(.string(json)) { error in
                if let error {
                    self.onError(error.localizedDescription)
                }
            }
        }
    }

    private func receiveNextMessage() {
        task?.receive { [weak self] result in
            guard let self, !self.isDisconnected else {
                return
            }

            switch result {
            case .success(let message):
                self.handle(message)
                self.receiveNextMessage()
            case .failure(let error):
                if self.isClosing {
                    self.finishClosed()
                } else {
                    self.onError(error.localizedDescription)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?

        switch message {
        case .string(let string):
            data = string.data(using: .utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            data = nil
        }

        guard let data else {
            return
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else {
            return
        }

        switch type {
        case "session.input_transcript.delta":
            if let delta = object["delta"] as? String {
                onEvent(targetLanguage, .inputTranscriptDelta(delta))
            }
        case "session.output_transcript.delta":
            if let delta = object["delta"] as? String {
                onEvent(targetLanguage, .outputTranscriptDelta(delta))
            }
        case "session.created", "session.updated":
            onEvent(targetLanguage, .debug(type))
        case "session.closed":
            onEvent(targetLanguage, .debug(type))
            finishClosed()
        case "error", "session.error":
            onEvent(targetLanguage, .error(Self.errorMessage(from: object)))
        default:
            if type.lowercased().contains("error") {
                onEvent(targetLanguage, .error(Self.errorMessage(from: object)))
            } else {
                onEvent(targetLanguage, .debug(type))
            }
        }
    }

    private static func errorMessage(from object: [String: Any]) -> String {
        if let message = object["message"] as? String {
            return message
        }

        if
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            return message
        }

        return "Realtime translation failed."
    }
}

private enum RealtimeTranslationEvent {
    case inputTranscriptDelta(String)
    case outputTranscriptDelta(String)
    case status(String)
    case debug(String)
    case error(String)
}

private struct RealtimeTranslationLanguage: Hashable {
    let code: String
    let displayName: String
    
    var apiLanguageCode: String {
        code
            .split(separator: "-")
            .first
            .map { String($0).lowercased() }
            ?? code.lowercased()
    }
}
