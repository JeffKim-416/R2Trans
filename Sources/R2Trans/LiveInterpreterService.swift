import Foundation

@MainActor
final class LiveInterpreterService {
    var onUpdate: ((LiveInterpreterUpdate) -> Void)?

    private let provisionalSubtitleTranslator = ProvisionalLiveSubtitleTranslator()
    private var translationSession: RealtimeTranslationSocket?
    private var closingTranslationSessions: [RealtimeTranslationSocket] = []
    private var microphoneCapture: MicrophonePCM16AudioCapture?
    private var systemAudioCapture: SystemPCM16AudioCapture?
    private var audioMixer: PCM16AudioMixer?
    private var sourceTranscript = ""
    private var sourceTranscriptSinceOfficialOutput = ""
    private var translatedSubtitle = ""
    private var provisionalSubtitle = ""
    private var targetLanguageDisplayName = ""
    private var lastOfficialSubtitleUpdateTime: TimeInterval = 0
    private var lastAudioLevelUpdate: [LiveInterpreterAudioSource: TimeInterval] = [:]
    private var audioChunkCount = 0
    private var provisionalSubtitlesEnabled = true
    private var sessionGeneration = 0
    private var isStarting = false

    private(set) var isRunning = false

    func start(
        inputSource: LiveInterpreterInputSource,
        targetLanguageCode: String,
        systemAudioTarget: LiveInterpreterSystemAudioTarget,
        provisionalSubtitlesEnabled: Bool
    ) async throws {
        guard !isRunning, !isStarting else {
            return
        }

        let apiKey = try KeychainStore.loadAPIKeyOrThrow().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw R2TransError.apiKeyMissing
        }

        sessionGeneration &+= 1
        let generation = sessionGeneration
        isStarting = true
        self.provisionalSubtitlesEnabled = provisionalSubtitlesEnabled
        resetTranscriptState()
        targetLanguageDisplayName = SupportedLanguage.displayName(for: targetLanguageCode)

        let translationSession = makeTranslationSocket(
            targetLanguage: RealtimeTranslationLanguage(
                code: targetLanguageCode,
                displayName: targetLanguageDisplayName
            ),
            generation: generation
        )
        self.translationSession = translationSession

        sendUpdate(.status(AppText.text(.liveInterpreterConnecting)))
        sendUpdate(.debug("target: \(targetLanguageCode)"))

        var startedMicrophoneCapture: MicrophonePCM16AudioCapture?
        var startedSystemAudioCapture: SystemPCM16AudioCapture?
        let startedAudioMixer: PCM16AudioMixer? = inputSource == .microphoneAndSystemAudio
            ? PCM16AudioMixer()
            : nil

        do {
            if inputSource.includesMicrophone {
                try await MicrophonePCM16AudioCapture.requestAccess()
                try ensureCurrentSession(translationSession, generation: generation)
            }

            try await translationSession.connect(apiKey: apiKey)
            try ensureCurrentSession(translationSession, generation: generation)

            if let startedAudioMixer {
                audioMixer = startedAudioMixer
                startedAudioMixer.start { [weak translationSession] data in
                    translationSession?.sendAudio(data)
                }
            }

            if inputSource.includesSystemAudio {
                let capture = SystemPCM16AudioCapture()
                startedSystemAudioCapture = capture
                systemAudioCapture = capture
                try await capture.start(
                    target: systemAudioTarget,
                    onAudioData: makeAudioHandler(
                        for: .systemAudio,
                        socket: translationSession,
                        generation: generation,
                        mixer: startedAudioMixer
                    ),
                    onFailure: makeCaptureFailureHandler(
                        socket: translationSession,
                        generation: generation
                    )
                )
                try ensureCurrentSession(translationSession, generation: generation)
            }

            if inputSource.includesMicrophone {
                let capture = MicrophonePCM16AudioCapture()
                startedMicrophoneCapture = capture
                microphoneCapture = capture
                try capture.start(
                    onAudioData: makeAudioHandler(
                        for: .microphone,
                        socket: translationSession,
                        generation: generation,
                        mixer: startedAudioMixer
                    )
                )
                try ensureCurrentSession(translationSession, generation: generation)
            }
        } catch {
            cleanupFailedStart(
                socket: translationSession,
                generation: generation,
                microphoneCapture: startedMicrophoneCapture,
                systemAudioCapture: startedSystemAudioCapture,
                audioMixer: startedAudioMixer
            )
            throw error
        }

        isStarting = false
        isRunning = true
        sendUpdate(.runningStateChanged(true))
        sendUpdate(.status(AppText.text(.liveInterpreterListening)))
    }

    func stop() {
        let wasActive = isStarting || isRunning || translationSession != nil
        sessionGeneration &+= 1
        isStarting = false
        isRunning = false
        stopAudioCapture()
        closeActiveTranslationSession()
        provisionalSubtitleTranslator.cancel()

        sendUpdate(.audioLevel(.microphone, 0))
        sendUpdate(.audioLevel(.systemAudio, 0))

        guard wasActive else {
            return
        }

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
        try await SystemPCM16AudioCapture.availableApplications()
    }

    private func makeTranslationSocket(
        targetLanguage: RealtimeTranslationLanguage,
        generation: Int
    ) -> RealtimeTranslationSocket {
        RealtimeTranslationSocket(
            targetLanguage: targetLanguage,
            onEvent: { [weak self] socket, targetLanguage, event in
                Task { @MainActor [weak self] in
                    self?.handle(
                        event,
                        from: targetLanguage,
                        socket: socket,
                        generation: generation
                    )
                }
            },
            onTerminalFailure: { [weak self] socket, message in
                Task { @MainActor [weak self] in
                    self?.handleTerminalFailure(
                        message,
                        socket: socket,
                        generation: generation,
                        closeSocket: false
                    )
                }
            },
            onClosed: { [weak self] socket in
                Task { @MainActor [weak self] in
                    self?.removeClosedTranslationSession(socket)
                }
            }
        )
    }

    private func closeActiveTranslationSession() {
        guard let translationSession else {
            return
        }

        self.translationSession = nil
        retainWhileClosing(translationSession)
    }

    private func removeClosedTranslationSession(_ socket: RealtimeTranslationSocket) {
        closingTranslationSessions.removeAll { $0 === socket }
    }

    private func makeAudioHandler(
        for source: LiveInterpreterAudioSource,
        socket: RealtimeTranslationSocket,
        generation: Int,
        mixer: PCM16AudioMixer?
    ) -> @Sendable (Data) -> Void {
        { [weak self, weak socket] data in
            guard let socket else {
                return
            }

            if let mixer {
                mixer.append(data, from: source)
            } else {
                socket.sendAudio(data)
            }
            let level = Self.audioLevel(for: data)

            Task { @MainActor [weak self, weak socket] in
                guard let self, let socket else {
                    return
                }

                self.publishAudioActivity(
                    source: source,
                    level: level,
                    socket: socket,
                    generation: generation
                )
            }
        }
    }

    private func makeCaptureFailureHandler(
        socket: RealtimeTranslationSocket,
        generation: Int
    ) -> @Sendable (Error) -> Void {
        { [weak self, weak socket] error in
            guard let socket else {
                return
            }

            Task { @MainActor [weak self, weak socket] in
                guard let self, let socket else {
                    return
                }

                self.handleTerminalFailure(
                    error.localizedDescription,
                    socket: socket,
                    generation: generation,
                    closeSocket: true
                )
            }
        }
    }

    private func publishAudioActivity(
        source: LiveInterpreterAudioSource,
        level: Double,
        socket: RealtimeTranslationSocket,
        generation: Int
    ) {
        guard isCurrentSession(socket, generation: generation) else {
            return
        }

        audioChunkCount += 1
        if audioChunkCount == 1 || audioChunkCount % 120 == 0 {
            sendUpdate(.debug("audio chunks sent: \(audioChunkCount)"))
        }

        let now = CFAbsoluteTimeGetCurrent()
        let lastUpdate = lastAudioLevelUpdate[source] ?? 0
        guard now - lastUpdate >= 0.08 else {
            return
        }

        lastAudioLevelUpdate[source] = now
        sendUpdate(.audioLevel(source, level))
    }

    private func handle(
        _ event: RealtimeTranslationEvent,
        from targetLanguage: RealtimeTranslationLanguage,
        socket: RealtimeTranslationSocket,
        generation: Int
    ) {
        guard isCurrentSession(socket, generation: generation) else {
            return
        }

        switch event {
        case .inputTranscriptDelta(let delta):
            sourceTranscript = Self.trimmedTail(sourceTranscript + delta, limit: 50_000)
            sourceTranscriptSinceOfficialOutput = Self.trimmedTail(
                sourceTranscriptSinceOfficialOutput + delta,
                limit: 2_000
            )
            let sourceDisplay = Self.trimmedTail(sourceTranscript, limit: 800)
            sendUpdate(.sourceTranscript(Self.lineBrokenSentences(in: sourceDisplay)))
            if provisionalSubtitlesEnabled {
                requestProvisionalSubtitle(
                    targetLanguage: targetLanguage,
                    socket: socket,
                    generation: generation
                )
            }
        case .outputTranscriptDelta(let delta):
            translatedSubtitle = Self.trimmedTail(translatedSubtitle + delta, limit: 1_500)
            provisionalSubtitle = ""
            sourceTranscriptSinceOfficialOutput = ""
            provisionalSubtitleTranslator.cancel()
            lastOfficialSubtitleUpdateTime = CFAbsoluteTimeGetCurrent()
            publishSubtitle(preferProvisional: false)
        case .status(let message):
            sendUpdate(.status(message))
        case .debug(let message):
            sendUpdate(.debug(message))
        }
    }

    private func requestProvisionalSubtitle(
        targetLanguage: RealtimeTranslationLanguage,
        socket: RealtimeTranslationSocket,
        generation: Int
    ) {
        provisionalSubtitleTranslator.submit(
            sourceTranscript: sourceTranscriptSinceOfficialOutput,
            targetLanguageCode: targetLanguage.code
        ) { [weak self] subtitle in
            Task { @MainActor [weak self, weak socket] in
                guard let self, let socket else {
                    return
                }

                guard self.isCurrentSession(socket, generation: generation) else {
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
        sourceTranscript = ""
        sourceTranscriptSinceOfficialOutput = ""
        translatedSubtitle = ""
        provisionalSubtitle = ""
        lastOfficialSubtitleUpdateTime = 0
        lastAudioLevelUpdate = [:]
        audioChunkCount = 0
        provisionalSubtitleTranslator.cancel()
        targetLanguageDisplayName = ""
    }

    private func ensureCurrentSession(
        _ socket: RealtimeTranslationSocket,
        generation: Int
    ) throws {
        try Task.checkCancellation()
        guard isCurrentSession(socket, generation: generation) else {
            throw CancellationError()
        }
    }

    private func isCurrentSession(_ socket: RealtimeTranslationSocket, generation: Int) -> Bool {
        sessionGeneration == generation
            && translationSession === socket
            && (isStarting || isRunning)
    }

    private func cleanupFailedStart(
        socket: RealtimeTranslationSocket,
        generation: Int,
        microphoneCapture: MicrophonePCM16AudioCapture?,
        systemAudioCapture: SystemPCM16AudioCapture?,
        audioMixer: PCM16AudioMixer?
    ) {
        audioMixer?.stop()
        microphoneCapture?.stop()
        systemAudioCapture?.stop()

        guard sessionGeneration == generation, translationSession === socket else {
            socket.closeGracefully()
            return
        }

        sessionGeneration &+= 1
        isStarting = false
        isRunning = false
        if self.microphoneCapture === microphoneCapture {
            self.microphoneCapture = nil
        }
        if self.systemAudioCapture === systemAudioCapture {
            self.systemAudioCapture = nil
        }
        if self.audioMixer === audioMixer {
            self.audioMixer = nil
        }
        translationSession = nil
        provisionalSubtitleTranslator.cancel()
        retainWhileClosing(socket)
    }

    private func handleTerminalFailure(
        _ message: String,
        socket: RealtimeTranslationSocket,
        generation: Int,
        closeSocket: Bool
    ) {
        guard isCurrentSession(socket, generation: generation) else {
            return
        }

        sessionGeneration &+= 1
        isStarting = false
        isRunning = false
        stopAudioCapture()
        translationSession = nil
        provisionalSubtitleTranslator.cancel()
        if closeSocket {
            retainWhileClosing(socket)
        }

        sendUpdate(.audioLevel(.microphone, 0))
        sendUpdate(.audioLevel(.systemAudio, 0))
        sendUpdate(.runningStateChanged(false))
        sendUpdate(.error(message))
    }

    private func stopAudioCapture() {
        let audioMixer = self.audioMixer
        let microphoneCapture = self.microphoneCapture
        let systemAudioCapture = self.systemAudioCapture
        self.audioMixer = nil
        self.microphoneCapture = nil
        self.systemAudioCapture = nil
        audioMixer?.stop()
        microphoneCapture?.stop()
        systemAudioCapture?.stop()
    }

    private func retainWhileClosing(_ socket: RealtimeTranslationSocket) {
        if !closingTranslationSessions.contains(where: { $0 === socket }) {
            closingTranslationSessions.append(socket)
        }
        socket.closeGracefully()
    }

    private func sendUpdate(_ update: LiveInterpreterUpdate) {
        onUpdate?(update)
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

    nonisolated private static func audioLevel(for data: Data) -> Double {
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
        onResult: @escaping @Sendable (String) -> Void
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

    private func scheduleNextTranslation(onResult: @escaping @Sendable (String) -> Void) {
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

    private func startTranslation(onResult: @escaping @Sendable (String) -> Void) {
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

enum LiveInterpreterUpdate: Sendable {
    case runningStateChanged(Bool)
    case status(String)
    case sourceTranscript(String)
    case subtitle(String, languageLabel: String)
    case audioLevel(LiveInterpreterAudioSource, Double)
    case debug(String)
    case error(String)
}

enum LiveInterpreterAudioSource: Hashable, Sendable {
    case microphone
    case systemAudio
}

enum LiveInterpreterSystemAudioTarget: Hashable, Sendable {
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

struct LiveInterpreterApplicationAudioTarget: Hashable, Sendable {
    let processID: pid_t
    let appName: String
    let bundleIdentifier: String?

    var displayName: String {
        appName
    }
}

enum LiveInterpreterInputSource: String, CaseIterable, Sendable {
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

private final class RealtimeTranslationSocket: @unchecked Sendable {
    private enum State {
        case idle
        case connecting
        case ready
        case closing
        case closed
    }

    private let targetLanguage: RealtimeTranslationLanguage
    private let session = URLSession(configuration: .default)
    private let queue: DispatchQueue
    private let onEvent: @Sendable (
        RealtimeTranslationSocket,
        RealtimeTranslationLanguage,
        RealtimeTranslationEvent
    ) -> Void
    private let onTerminalFailure: @Sendable (RealtimeTranslationSocket, String) -> Void
    private let onClosed: @Sendable (RealtimeTranslationSocket) -> Void
    private var state = State.idle
    private var task: URLSessionWebSocketTask?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var readyTimeoutWorkItem: DispatchWorkItem?
    private var closeTimeoutWorkItem: DispatchWorkItem?

    init(
        targetLanguage: RealtimeTranslationLanguage,
        onEvent: @escaping @Sendable (
            RealtimeTranslationSocket,
            RealtimeTranslationLanguage,
            RealtimeTranslationEvent
        ) -> Void,
        onTerminalFailure: @escaping @Sendable (RealtimeTranslationSocket, String) -> Void,
        onClosed: @escaping @Sendable (RealtimeTranslationSocket) -> Void
    ) {
        self.targetLanguage = targetLanguage
        self.onEvent = onEvent
        self.onTerminalFailure = onTerminalFailure
        self.onClosed = onClosed
        self.queue = DispatchQueue(label: "R2Trans.RealtimeTranslationSocket.\(targetLanguage.apiLanguageCode)")
    }

    func connect(apiKey: String) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [weak self] in
                    self?.startConnection(apiKey: apiKey, continuation: continuation)
                }
            }
        } onCancel: { [weak self] in
            self?.closeGracefully()
        }
    }

    func sendAudio(_ audioData: Data) {
        queue.async { [weak self] in
            guard let self, self.state == .ready else {
                return
            }

            self.sendJSONLocked([
                "type": "session.input_audio_buffer.append",
                "audio": audioData.base64EncodedString()
            ])
        }
    }

    func closeGracefully() {
        queue.async { [weak self] in
            self?.beginCloseLocked()
        }
    }

    private func startConnection(apiKey: String, continuation: CheckedContinuation<Void, Error>) {
        guard state == .idle else {
            continuation.resume(throwing: CancellationError())
            return
        }

        state = .connecting
        readyContinuation = continuation

        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(OpenAISafetyIdentifier.value, forHTTPHeaderField: "OpenAI-Safety-Identifier")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        emit(.debug("socket started: \(targetLanguage.apiLanguageCode)"))
        scheduleReadyTimeoutLocked()
        receiveNextLocked()
    }

    private func scheduleReadyTimeoutLocked() {
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .connecting else {
                return
            }

            self.failLocked("Realtime translation connection timed out.")
        }
        readyTimeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + 15, execute: timeout)
    }

    private func sendSessionUpdateLocked() {
        sendJSONLocked([
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

    private func sendJSONLocked(_ object: [String: Any]) {
        guard
            let task,
            let data = try? JSONSerialization.data(withJSONObject: object),
            let json = String(data: data, encoding: .utf8)
        else {
            failLocked("Unable to encode a Realtime translation request.")
            return
        }

        task.send(.string(json)) { [weak self] error in
            guard let error else {
                return
            }

            self?.queue.async { [weak self] in
                guard let self else {
                    return
                }

                if self.state == .closing {
                    self.finishClosedLocked()
                } else {
                    self.failLocked(error.localizedDescription)
                }
            }
        }
    }

    private func receiveNextLocked() {
        guard let task, state != .closed else {
            return
        }

        task.receive { [weak self] result in
            self?.queue.async { [weak self] in
                self?.handleReceiveLocked(result)
            }
        }
    }

    private func handleReceiveLocked(
        _ result: Result<URLSessionWebSocketTask.Message, Error>
    ) {
        guard state != .closed else {
            return
        }

        switch result {
        case .success(let message):
            handleMessageLocked(message)
            if state != .closed {
                receiveNextLocked()
            }
        case .failure(let error):
            if state == .closing {
                finishClosedLocked()
            } else {
                failLocked(error.localizedDescription)
            }
        }
    }

    private func handleMessageLocked(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?

        switch message {
        case .string(let string):
            data = string.data(using: .utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            data = nil
        }

        guard
            let data,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else {
            return
        }

        switch type {
        case "session.created":
            guard state == .connecting else {
                return
            }
            emit(.debug(type))
            sendSessionUpdateLocked()
        case "session.updated":
            guard state == .connecting else {
                return
            }
            state = .ready
            readyTimeoutWorkItem?.cancel()
            readyTimeoutWorkItem = nil
            let continuation = readyContinuation
            readyContinuation = nil
            emit(.debug(type))
            continuation?.resume()
        case "session.input_transcript.delta":
            guard state == .ready, let delta = object["delta"] as? String else {
                return
            }
            emit(.inputTranscriptDelta(delta))
        case "session.output_transcript.delta":
            guard state == .ready, let delta = object["delta"] as? String else {
                return
            }
            emit(.outputTranscriptDelta(delta))
        case "session.closed":
            emit(.debug(type))
            if state == .closing {
                finishClosedLocked()
            } else {
                failLocked("Realtime translation session closed unexpectedly.")
            }
        case "error", "session.error":
            failLocked(Self.errorMessage(from: object))
        default:
            if type.lowercased().contains("error") {
                failLocked(Self.errorMessage(from: object))
            } else {
                emit(.debug(type))
            }
        }
    }

    private func beginCloseLocked() {
        switch state {
        case .idle:
            state = .closed
            session.invalidateAndCancel()
            onClosed(self)
        case .connecting:
            finishClosedLocked()
        case .ready:
            state = .closing
            sendJSONLocked(["type": "session.close"])

            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.state == .closing else {
                    return
                }

                self.emit(.debug("session.close timed out"))
                self.finishClosedLocked()
            }
            closeTimeoutWorkItem = timeout
            queue.asyncAfter(deadline: .now() + 5, execute: timeout)
        case .closing:
            return
        case .closed:
            // The owner may retain a socket immediately after an asynchronous failure.
            // Re-notify it so that retention can be released deterministically.
            onClosed(self)
        }
    }

    private func failLocked(_ message: String) {
        guard state != .closed else {
            return
        }

        let wasConnecting = state == .connecting
        let continuation = readyContinuation
        readyContinuation = nil
        closeTransportLocked()
        continuation?.resume(throwing: RealtimeTranslationSocketError(message: message))

        if !wasConnecting {
            onTerminalFailure(self, message)
        }
        onClosed(self)
    }

    private func finishClosedLocked() {
        guard state != .closed else {
            return
        }

        let continuation = readyContinuation
        readyContinuation = nil
        closeTransportLocked()
        continuation?.resume(throwing: CancellationError())
        onClosed(self)
    }

    private func closeTransportLocked() {
        state = .closed
        readyTimeoutWorkItem?.cancel()
        readyTimeoutWorkItem = nil
        closeTimeoutWorkItem?.cancel()
        closeTimeoutWorkItem = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session.invalidateAndCancel()
    }

    private func emit(_ event: RealtimeTranslationEvent) {
        onEvent(self, targetLanguage, event)
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

private struct RealtimeTranslationSocketError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

private enum RealtimeTranslationEvent: Sendable {
    case inputTranscriptDelta(String)
    case outputTranscriptDelta(String)
    case status(String)
    case debug(String)
}

private struct RealtimeTranslationLanguage: Hashable, Sendable {
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
