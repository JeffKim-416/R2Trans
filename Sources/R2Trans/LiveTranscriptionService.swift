import Foundation

@MainActor
final class LiveTranscriptionService {
    var onUpdate: ((LiveTranscriptionUpdate) -> Void)?

    private let microphoneStreamer = MicrophonePCM16AudioCapture()
    private let systemAudioStreamer = SystemPCM16AudioCapture()
    private var socket: RealtimeTranscriptionSocket?
    private var audioSender: RealtimeTranscriptionAudioSender?
    private var audioMixer: PCM16AudioMixer?
    private var generation = 0
    private var transcriptAssembler = LiveTranscriptAssembler(
        maximumItemCount: 200,
        maximumCharacterCount: 50_000
    )
    private var lastErrorGeneration: Int?

    private(set) var isStarting = false
    private(set) var isRunning = false

    func start(
        inputSource: LiveInterpreterInputSource,
        languageCode: String?,
        systemAudioTarget: LiveInterpreterSystemAudioTarget
    ) async throws {
        guard !isStarting, !isRunning, socket == nil else {
            return
        }

        let apiKey = try KeychainStore.loadAPIKeyOrThrow()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw R2TransError.apiKeyMissing
        }

        isStarting = true
        generation &+= 1
        let startGeneration = generation
        lastErrorGeneration = nil
        defer {
            if generation == startGeneration {
                isStarting = false
            }
        }

        if inputSource.includesMicrophone {
            try await MicrophonePCM16AudioCapture.requestAccess()
            try Task.checkCancellation()
            guard generation == startGeneration else {
                throw CancellationError()
            }
        }

        resetTranscriptState()
        sendUpdate(.status(AppText.text(.liveInterpreterConnecting)))
        sendUpdate(.debug("model: \(LiveTranscriptionProtocol.model)"))

        let sessionID = UUID()
        let newSocket = RealtimeTranscriptionSocket(
            sessionID: sessionID,
            onEvent: { [weak self] event in
                self?.handle(event, generation: startGeneration, sessionID: sessionID)
            },
            onTerminalError: { [weak self] message in
                self?.handleTerminalError(message, generation: startGeneration, sessionID: sessionID)
            }
        )
        socket = newSocket
        let newAudioSender = RealtimeTranscriptionAudioSender(socket: newSocket)
        audioSender = newAudioSender
        let newAudioMixer = inputSource == .microphoneAndSystemAudio
            ? PCM16AudioMixer()
            : nil
        audioMixer = newAudioMixer

        do {
            try await newSocket.connect(
                apiKey: apiKey,
                safetyIdentifier: OpenAISafetyIdentifier.value,
                languageCode: LiveTranscriptionProtocol.realtimeLanguageCode(from: languageCode)
            )
            try Task.checkCancellation()
            guard generation == startGeneration, socket === newSocket else {
                throw CancellationError()
            }

            if let newAudioMixer {
                newAudioMixer.start { data in
                    newAudioSender.send(data)
                }
            }

            if inputSource.includesSystemAudio {
                try await systemAudioStreamer.start(
                    target: systemAudioTarget,
                    onAudioData: Self.audioHandler(
                        source: .systemAudio,
                        mixer: newAudioMixer,
                        sender: newAudioSender
                    ),
                    onFailure: { [weak self] error in
                        Task { @MainActor [weak self] in
                            self?.handleCaptureFailure(
                                error,
                                generation: startGeneration,
                                sessionID: sessionID
                            )
                        }
                    }
                )
                try Task.checkCancellation()
                guard generation == startGeneration, socket === newSocket else {
                    throw CancellationError()
                }
            }

            if inputSource.includesMicrophone {
                try microphoneStreamer.start(
                    onAudioData: Self.audioHandler(
                        source: .microphone,
                        mixer: newAudioMixer,
                        sender: newAudioSender
                    )
                )
            }
        } catch {
            if socket === newSocket {
                stopInternal(sendStoppedUpdate: false)
            } else {
                await newSocket.close()
            }
            throw error
        }

        isRunning = true
        sendUpdate(.runningStateChanged(true))
        sendUpdate(.status(AppText.text(.liveInterpreterListening)))
    }

    func stop() {
        stopInternal(sendStoppedUpdate: true)
    }

    func clear() {
        resetTranscriptState()
        sendUpdate(.transcript(""))
    }

    func availableSystemAudioApplications() async throws -> [LiveInterpreterApplicationAudioTarget] {
        guard #available(macOS 13.0, *) else {
            throw R2TransError.systemAudioUnavailable
        }

        return try await SystemPCM16AudioCapture.availableApplications()
    }

    private func stopInternal(sendStoppedUpdate: Bool) {
        let wasActive = isStarting || isRunning
        generation &+= 1
        isStarting = false
        microphoneStreamer.stop()
        systemAudioStreamer.stop()
        audioMixer?.stop()
        audioMixer = nil
        audioSender?.stop()
        audioSender = nil

        if let socket {
            self.socket = nil
            Task {
                await socket.close()
            }
        }

        isRunning = false

        if wasActive || sendStoppedUpdate {
            sendUpdate(.runningStateChanged(false))
            sendUpdate(.status(AppText.text(.liveInterpreterStopped)))
        }
    }

    private func handle(
        _ event: RealtimeTranscriptionEvent,
        generation eventGeneration: Int,
        sessionID: UUID
    ) {
        guard generation == eventGeneration, socket?.sessionID == sessionID else {
            return
        }

        switch event {
        case .itemCreated(let itemID, let previousItemID):
            guard transcriptAssembler.register(itemID: itemID, previousItemID: previousItemID) else {
                return
            }
            publishTranscript()
        case .transcriptDelta(let itemID, let delta):
            guard transcriptAssembler.append(delta: delta, to: itemID) else {
                return
            }
            publishTranscript()
        case .transcriptCompleted(let itemID, let transcript):
            guard transcriptAssembler.complete(itemID: itemID, transcript: transcript) else {
                return
            }
            publishTranscript()
        case .transcriptFailed(let itemID, let message):
            guard transcriptAssembler.observe(itemID: itemID) else {
                return
            }
            publishTranscript()
            sendUpdate(.error(Self.userFacingError(message)))
        case .sessionCreated:
            sendUpdate(.debug("transcription session created"))
        case .sessionUpdated:
            sendUpdate(.debug("transcription session ready"))
        case .speechStarted:
            sendUpdate(.status(AppText.text(.liveInterpreterListening)))
        case .speechStopped:
            sendUpdate(.debug("speech turn committed"))
        case .serverError(let message):
            sendUpdate(.error(Self.userFacingError(message)))
        case .status(let message):
            sendUpdate(.status(message))
        case .debug(let message):
            sendUpdate(.debug(message))
        }
    }

    private func handleTerminalError(
        _ message: String,
        generation eventGeneration: Int,
        sessionID: UUID
    ) {
        guard
            generation == eventGeneration,
            socket?.sessionID == sessionID,
            lastErrorGeneration != eventGeneration
        else {
            return
        }

        lastErrorGeneration = eventGeneration
        stopInternal(sendStoppedUpdate: false)
        sendUpdate(.error(Self.userFacingError(message)))
    }

    private func handleCaptureFailure(
        _ error: Error,
        generation eventGeneration: Int,
        sessionID: UUID
    ) {
        guard
            generation == eventGeneration,
            socket?.sessionID == sessionID,
            lastErrorGeneration != eventGeneration
        else {
            return
        }

        lastErrorGeneration = eventGeneration
        stopInternal(sendStoppedUpdate: false)
        sendUpdate(.error(error.localizedDescription))
    }

    private func publishTranscript() {
        sendUpdate(.transcript(transcriptAssembler.transcript))
    }

    private func resetTranscriptState() {
        transcriptAssembler.reset()
    }

    private func sendUpdate(_ update: LiveTranscriptionUpdate) {
        onUpdate?(update)
    }

    nonisolated private static func audioHandler(
        source: LiveInterpreterAudioSource,
        mixer: PCM16AudioMixer?,
        sender: RealtimeTranscriptionAudioSender
    ) -> @Sendable (Data) -> Void {
        { data in
            if let mixer {
                mixer.append(data, from: source)
            } else {
                sender.send(data)
            }
        }
    }

    private static func userFacingError(_ message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("api key") || lowercased.contains("unauthorized") || lowercased.contains("401") {
            return AppText.text(.openAIUnauthorized)
        }
        if lowercased.contains("rate limit") || lowercased.contains("quota") || lowercased.contains("429") {
            return AppText.text(.openAIRateLimited)
        }
        return message.isEmpty ? AppText.text(.networkError) : message
    }

}

enum LiveTranscriptionUpdate {
    case runningStateChanged(Bool)
    case status(String)
    case transcript(String)
    case debug(String)
    case error(String)
}

struct LiveTranscriptAssembler {
    private struct Item {
        var partial = ""
        var final: String?
    }

    private enum Predecessor {
        case unknown
        case known(String?)
    }

    private let maximumItemCount: Int
    private let maximumCharacterCount: Int
    private var items: [String: Item] = [:]
    private var predecessors: [String: Predecessor] = [:]
    private var discoveryIndexes: [String: Int] = [:]
    private var nextDiscoveryIndex = 0
    private var orderedItemIDs: [String] = []
    private var evictedItemIDs = Set<String>()

    init(maximumItemCount: Int = 200, maximumCharacterCount: Int = 50_000) {
        self.maximumItemCount = max(1, maximumItemCount)
        self.maximumCharacterCount = max(1, maximumCharacterCount)
    }

    var transcript: String {
        let text = orderedItemIDs.compactMap { itemID -> String? in
            guard let item = items[itemID] else {
                return nil
            }

            let value = (item.final ?? item.partial)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }.joined(separator: "\n")

        guard text.count > maximumCharacterCount else {
            return text
        }
        return String(text.suffix(maximumCharacterCount))
    }

    /// Records authoritative ordering metadata from item-created/added or buffer-committed
    /// events. This may move a placeholder that was first observed through a transcript event.
    @discardableResult
    mutating func register(itemID: String, previousItemID: String?) -> Bool {
        guard prepareItem(itemID) else {
            return false
        }

        predecessors[itemID] = .known(previousItemID)
        rebuildOrderAndEnforceLimit()
        return items[itemID] != nil
    }

    /// Observes an item without ordering metadata. Returns false only for an item that was
    /// deliberately evicted, preventing late events from resurrecting old transcript turns.
    @discardableResult
    mutating func observe(itemID: String) -> Bool {
        guard prepareItem(itemID) else {
            return false
        }

        rebuildOrderAndEnforceLimit()
        return items[itemID] != nil
    }

    @discardableResult
    mutating func append(delta: String, to itemID: String) -> Bool {
        guard observe(itemID: itemID), items[itemID]?.final == nil else {
            return false
        }

        items[itemID]?.partial.append(delta)
        return true
    }

    @discardableResult
    mutating func complete(itemID: String, transcript: String) -> Bool {
        guard observe(itemID: itemID) else {
            return false
        }

        items[itemID]?.final = transcript
        items[itemID]?.partial = ""
        return true
    }

    mutating func reset() {
        items.removeAll(keepingCapacity: true)
        predecessors.removeAll(keepingCapacity: true)
        discoveryIndexes.removeAll(keepingCapacity: true)
        orderedItemIDs.removeAll(keepingCapacity: true)
        evictedItemIDs.removeAll(keepingCapacity: true)
        nextDiscoveryIndex = 0
    }

    private mutating func prepareItem(_ itemID: String) -> Bool {
        guard !itemID.isEmpty, !evictedItemIDs.contains(itemID) else {
            return false
        }

        if items[itemID] == nil {
            items[itemID] = Item()
            predecessors[itemID] = .unknown
            discoveryIndexes[itemID] = nextDiscoveryIndex
            nextDiscoveryIndex &+= 1
        }
        return true
    }

    private mutating func rebuildOrderAndEnforceLimit() {
        rebuildOrder()

        while items.count > maximumItemCount, let evictedItemID = orderedItemIDs.first {
            evictedItemIDs.insert(evictedItemID)
            items.removeValue(forKey: evictedItemID)
            predecessors.removeValue(forKey: evictedItemID)
            discoveryIndexes.removeValue(forKey: evictedItemID)
            rebuildOrder()
        }
    }

    private mutating func rebuildOrder() {
        let activeItemIDs = items.keys.sorted(by: discoveredBefore)
        let activeItemIDSet = Set(activeItemIDs)
        var childItemIDs: [String: [String]] = [:]
        var rootItemIDs: [String] = []

        for itemID in activeItemIDs {
            if
                case .known(.some(let previousItemID)) = predecessors[itemID],
                previousItemID != itemID,
                activeItemIDSet.contains(previousItemID)
            {
                childItemIDs[previousItemID, default: []].append(itemID)
            } else {
                rootItemIDs.append(itemID)
            }
        }

        for parentItemID in childItemIDs.keys {
            childItemIDs[parentItemID]?.sort(by: discoveredBefore)
        }
        rootItemIDs.sort { lhs, rhs in
            let lhsRank = rootRank(for: lhs, activeItemIDs: activeItemIDSet)
            let rhsRank = rootRank(for: rhs, activeItemIDs: activeItemIDSet)
            return lhsRank == rhsRank ? discoveredBefore(lhs, rhs) : lhsRank < rhsRank
        }

        var rebuiltOrder: [String] = []
        var visitedItemIDs = Set<String>()

        func visit(_ itemID: String) {
            guard visitedItemIDs.insert(itemID).inserted else {
                return
            }
            rebuiltOrder.append(itemID)
            for childItemID in childItemIDs[itemID] ?? [] {
                visit(childItemID)
            }
        }

        for rootItemID in rootItemIDs {
            visit(rootItemID)
        }
        // Cyclic or otherwise malformed predecessor data must not make an item disappear.
        for itemID in activeItemIDs {
            visit(itemID)
        }

        orderedItemIDs = rebuiltOrder
    }

    private func rootRank(for itemID: String, activeItemIDs: Set<String>) -> Int {
        switch predecessors[itemID] ?? .unknown {
        case .known(nil):
            return 0
        case .known(.some(let previousItemID)) where !activeItemIDs.contains(previousItemID):
            return 1
        case .known:
            return 2
        case .unknown:
            return 3
        }
    }

    private func discoveredBefore(_ lhs: String, _ rhs: String) -> Bool {
        (discoveryIndexes[lhs] ?? .max) < (discoveryIndexes[rhs] ?? .max)
    }
}

enum LiveTranscriptionProtocol {
    static let model = "gpt-live-transcribe"
    static let endpointURL = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")!

    static func realtimeLanguageCode(from languageCode: String?) -> String? {
        guard let languageCode else {
            return nil
        }

        switch languageCode.lowercased() {
        case let code where code.hasPrefix("en"):
            return "en"
        case let code where code.hasPrefix("ko"):
            return "ko"
        case let code where code.hasPrefix("es"):
            return "es"
        case let code where code.hasPrefix("ja"):
            return "ja"
        case let code where code.hasPrefix("zh"):
            return code.contains("tw") || code.contains("hk") ? "zh-tw" : "zh-cn"
        default:
            return nil
        }
    }

    static func sessionUpdatePayload(languageCode: String?) -> [String: Any] {
        var transcription: [String: Any] = [
            "model": model,
            "delay": "low"
        ]
        if let languageCode {
            transcription["languages"] = [languageCode]
        }

        return [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000
                        ],
                        "transcription": transcription,
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.5,
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 500
                        ]
                    ]
                ]
            ]
        ]
    }
}

enum RealtimeTranscriptionEvent: Equatable, Sendable {
    case sessionCreated
    case sessionUpdated
    case itemCreated(itemID: String, previousItemID: String?)
    case transcriptDelta(itemID: String, delta: String)
    case transcriptCompleted(itemID: String, transcript: String)
    case transcriptFailed(itemID: String, message: String)
    case speechStarted
    case speechStopped
    case serverError(String)
    case status(String)
    case debug(String)

    var terminalFailureMessage: String? {
        guard case .serverError(let message) = self else {
            return nil
        }
        return message
    }

    static func decode(_ data: Data) throws -> RealtimeTranscriptionEvent? {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else {
            return nil
        }

        switch type {
        case "session.created":
            return .sessionCreated
        case "session.updated":
            return .sessionUpdated
        case "conversation.item.created", "conversation.item.added":
            guard
                let item = object["item"] as? [String: Any],
                let itemID = item["id"] as? String
            else {
                return nil
            }
            return .itemCreated(
                itemID: itemID,
                previousItemID: object["previous_item_id"] as? String
            )
        case "input_audio_buffer.committed":
            guard let itemID = object["item_id"] as? String else {
                return nil
            }
            return .itemCreated(
                itemID: itemID,
                previousItemID: object["previous_item_id"] as? String
            )
        case "conversation.item.input_audio_transcription.delta":
            guard
                let itemID = object["item_id"] as? String,
                let delta = object["delta"] as? String,
                !delta.isEmpty
            else {
                return nil
            }
            return .transcriptDelta(itemID: itemID, delta: delta)
        case "conversation.item.input_audio_transcription.completed":
            guard
                let itemID = object["item_id"] as? String,
                let transcript = object["transcript"] as? String
            else {
                return nil
            }
            return .transcriptCompleted(itemID: itemID, transcript: transcript)
        case "conversation.item.input_audio_transcription.failed":
            guard let itemID = object["item_id"] as? String else {
                return nil
            }
            let errorObject = object["error"] as? [String: Any]
            let message = (errorObject?["message"] as? String)
                ?? (errorObject?["code"] as? String)
                ?? "Transcription failed."
            return .transcriptFailed(itemID: itemID, message: message)
        case "input_audio_buffer.speech_started":
            return .speechStarted
        case "input_audio_buffer.speech_stopped":
            return .speechStopped
        case "error":
            let errorObject = object["error"] as? [String: Any]
            let message = (errorObject?["message"] as? String)
                ?? (errorObject?["code"] as? String)
                ?? "OpenAI Realtime API error."
            return .serverError(message)
        default:
            return nil
        }
    }
}

private struct RealtimeTranscriptionFailure: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

/// Preserves callback order while forwarding audio into the socket actor. This keeps
/// sequential microphone frames from being reordered by independent unstructured tasks.
private final class RealtimeTranscriptionAudioSender: @unchecked Sendable {
    private let lock = NSLock()
    private let socket: RealtimeTranscriptionSocket
    private var generation = 0
    private var tail: Task<Void, Never>?

    init(socket: RealtimeTranscriptionSocket) {
        self.socket = socket
    }

    func send(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        let previous = tail
        let sendGeneration = generation
        let socket = self.socket
        let task = Task { [weak self] in
            if let previous {
                await previous.value
            }
            guard !Task.isCancelled, self?.isCurrent(sendGeneration) == true else {
                return
            }
            await socket.sendAudio(data)
        }
        tail = task
        lock.unlock()
    }

    func stop() {
        lock.lock()
        generation &+= 1
        let tail = self.tail
        self.tail = nil
        lock.unlock()
        tail?.cancel()
    }

    private func isCurrent(_ expectedGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == expectedGeneration
    }
}

private actor RealtimeTranscriptionSocket {
    nonisolated let sessionID: UUID

    private enum State {
        case idle
        case connecting
        case ready
        case closing
        case closed
    }

    private let session = URLSession(configuration: .default)
    private let onEvent: @MainActor @Sendable (RealtimeTranscriptionEvent) -> Void
    private let onTerminalError: @MainActor @Sendable (String) -> Void
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var connectionFailure: Error?
    private var state = State.idle
    private var didNotifyTerminalError = false

    init(
        sessionID: UUID,
        onEvent: @escaping @MainActor @Sendable (RealtimeTranscriptionEvent) -> Void,
        onTerminalError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.sessionID = sessionID
        self.onEvent = onEvent
        self.onTerminalError = onTerminalError
    }

    func connect(apiKey: String, safetyIdentifier: String, languageCode: String?) async throws {
        guard state == .idle else {
            return
        }

        var request = URLRequest(url: LiveTranscriptionProtocol.endpointURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(safetyIdentifier, forHTTPHeaderField: "OpenAI-Safety-Identifier")

        let webSocketTask = session.webSocketTask(with: request)
        task = webSocketTask
        state = .connecting
        webSocketTask.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        do {
            try await sendSessionUpdate(languageCode: languageCode)
            try await waitUntilReady()
        } catch {
            await terminate(with: error, notifyTerminalError: false)
            throw error
        }
    }

    func sendAudio(_ data: Data) async {
        guard state == .ready, !data.isEmpty else {
            return
        }

        do {
            try await sendJSON([
                "type": "input_audio_buffer.append",
                "audio": data.base64EncodedString()
            ])
        } catch {
            await terminate(with: error, notifyTerminalError: true)
        }
    }

    func close() async {
        guard state != .closed, state != .closing else {
            return
        }

        state = .closing
        timeoutTask?.cancel()
        timeoutTask = nil
        readyContinuation?.resume(throwing: CancellationError())
        readyContinuation = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .closed
    }

    private func sendSessionUpdate(languageCode: String?) async throws {
        try await sendJSON(
            LiveTranscriptionProtocol.sessionUpdatePayload(languageCode: languageCode)
        )
    }

    private func waitUntilReady() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                switch state {
                case .ready:
                    continuation.resume()
                case .connecting:
                    readyContinuation = continuation
                    timeoutTask?.cancel()
                    timeoutTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 12_000_000_000)
                        guard !Task.isCancelled else {
                            return
                        }
                        await self?.connectionTimedOut()
                    }
                case .closing, .closed:
                    continuation.resume(throwing: connectionFailure ?? CancellationError())
                case .idle:
                    continuation.resume(throwing: RealtimeTranscriptionFailure(message: AppText.text(.networkError)))
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.close()
            }
        }
    }

    private func connectionTimedOut() async {
        guard state == .connecting else {
            return
        }
        await terminate(
            with: RealtimeTranscriptionFailure(message: AppText.text(.networkError)),
            notifyTerminalError: false
        )
    }

    private func receiveLoop() async {
        guard let task else {
            return
        }

        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                try await handle(message)
            }
        } catch is CancellationError {
            return
        } catch {
            await terminate(with: error, notifyTerminalError: true)
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) async throws {
        let data: Data
        switch message {
        case .data(let value):
            data = value
        case .string(let value):
            guard let valueData = value.data(using: .utf8) else {
                return
            }
            data = valueData
        @unknown default:
            return
        }

        guard let event = try RealtimeTranscriptionEvent.decode(data) else {
            return
        }

        if let terminalFailureMessage = event.terminalFailureMessage {
            throw RealtimeTranscriptionFailure(message: terminalFailureMessage)
        }

        switch event {
        case .sessionUpdated:
            if state == .connecting {
                state = .ready
                timeoutTask?.cancel()
                timeoutTask = nil
                readyContinuation?.resume()
                readyContinuation = nil
            }
            await onEvent(event)
        default:
            await onEvent(event)
        }
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let task else {
            throw RealtimeTranscriptionFailure(message: AppText.text(.networkError))
        }

        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeTranscriptionFailure(message: AppText.text(.networkError))
        }
        try await task.send(.string(text))
    }

    private func terminate(with error: Error, notifyTerminalError: Bool) async {
        guard state != .closed, state != .closing else {
            return
        }

        let wasReady = state == .ready
        if state == .connecting {
            connectionFailure = error
        }
        state = .closing
        timeoutTask?.cancel()
        timeoutTask = nil
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .closed

        if notifyTerminalError, wasReady, !didNotifyTerminalError {
            didNotifyTerminalError = true
            await onTerminalError(error.localizedDescription)
        }
    }
}
