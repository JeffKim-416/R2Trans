import AppKit

@MainActor
final class LiveTranscriptionWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let windowWidth: CGFloat = 860
        static let windowHeight: CGFloat = 620
        static let contentInset: CGFloat = 20
        static let labelWidth: CGFloat = 120
        static let controlWidth: CGFloat = 430
    }

    private let service = LiveTranscriptionService()
    private let statusLabel = NSTextField(labelWithString: "")
    private let inputSourceLabel = NSTextField(labelWithString: "")
    private let inputSourcePopup = NSPopUpButton()
    private let audioApplicationLabel = NSTextField(labelWithString: "")
    private let audioApplicationPopup = NSPopUpButton()
    private let reloadAudioApplicationsButton = NSButton()
    private let audioApplicationRow = NSStackView()
    private let spokenLanguageLabel = NSTextField(labelWithString: "")
    private let spokenLanguagePopup = NSPopUpButton()
    private let transcriptTextView = NSTextView()
    private let debugLabel = NSTextField(labelWithString: "")
    private let startStopButton = NSButton()
    private let clearButton = NSButton()
    private let closeButton = NSButton()
    private let keepOnTopButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let billingNoteLabel = NSTextField(labelWithString: "")

    private var startTask: Task<Void, Never>?
    private var startGeneration = 0
    private var isStarting = false
    private var systemAudioTargets: [LiveInterpreterSystemAudioTarget] = [.allSystemAudio]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.minSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        setupContent()
        configureCallbacks()
        refreshLocalizedText()
        applyRunningState(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        guard let contentView = window?.contentView else {
            return
        }

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor

        configureLabel(inputSourceLabel)
        inputSourcePopup.addItems(withTitles: LiveInterpreterInputSource.allCases.map(\.displayName))
        inputSourcePopup.target = self
        inputSourcePopup.action = #selector(inputSourceDidChange)
        let inputSourceRow = makeFormRow(label: inputSourceLabel, control: inputSourcePopup)

        configureLabel(audioApplicationLabel)
        audioApplicationPopup.addItems(withTitles: systemAudioTargets.map(\.displayName))
        audioApplicationPopup.translatesAutoresizingMaskIntoConstraints = false
        audioApplicationPopup.widthAnchor.constraint(equalToConstant: Layout.controlWidth - 44).isActive = true

        reloadAudioApplicationsButton.title = "↻"
        reloadAudioApplicationsButton.bezelStyle = .rounded
        reloadAudioApplicationsButton.target = self
        reloadAudioApplicationsButton.action = #selector(reloadAudioApplications)
        reloadAudioApplicationsButton.translatesAutoresizingMaskIntoConstraints = false
        reloadAudioApplicationsButton.widthAnchor.constraint(equalToConstant: 36).isActive = true

        let applicationControls = NSStackView(views: [audioApplicationPopup, reloadAudioApplicationsButton])
        applicationControls.orientation = .horizontal
        applicationControls.alignment = .centerY
        applicationControls.spacing = 8
        applicationControls.translatesAutoresizingMaskIntoConstraints = false
        applicationControls.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true

        audioApplicationRow.orientation = .horizontal
        audioApplicationRow.alignment = .centerY
        audioApplicationRow.spacing = 10
        audioApplicationRow.addArrangedSubview(audioApplicationLabel)
        audioApplicationRow.addArrangedSubview(applicationControls)

        configureLabel(spokenLanguageLabel)
        spokenLanguagePopup.addItem(withTitle: AppText.text(.automaticLanguage))
        spokenLanguagePopup.addItems(withTitles: SupportedLanguage.all.map(\.displayName))
        let languageRow = makeFormRow(label: spokenLanguageLabel, control: spokenLanguagePopup)

        let formStack = NSStackView(views: [inputSourceRow, audioApplicationRow, languageRow])
        formStack.orientation = .vertical
        formStack.alignment = .centerX
        formStack.spacing = 12

        transcriptTextView.isEditable = false
        transcriptTextView.isSelectable = true
        transcriptTextView.drawsBackground = false
        transcriptTextView.font = .systemFont(ofSize: 22, weight: .regular)
        transcriptTextView.textContainerInset = NSSize(width: 14, height: 14)
        transcriptTextView.isRichText = false
        transcriptTextView.isVerticallyResizable = true
        transcriptTextView.isHorizontallyResizable = false
        transcriptTextView.autoresizingMask = [.width]
        transcriptTextView.textContainer?.widthTracksTextView = true
        transcriptTextView.textContainer?.containerSize = NSSize(
            width: Layout.windowWidth - (Layout.contentInset * 2),
            height: .greatestFiniteMagnitude
        )
        transcriptTextView.string = AppText.text(.liveTranscriptionNoTranscript)

        let transcriptScrollView = NSScrollView()
        transcriptScrollView.borderType = .bezelBorder
        transcriptScrollView.hasVerticalScroller = true
        transcriptScrollView.autohidesScrollers = true
        transcriptScrollView.documentView = transcriptTextView
        transcriptScrollView.translatesAutoresizingMaskIntoConstraints = false
        transcriptScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        debugLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        debugLabel.textColor = .tertiaryLabelColor
        debugLabel.lineBreakMode = .byTruncatingMiddle
        debugLabel.maximumNumberOfLines = 1

        startStopButton.target = self
        startStopButton.action = #selector(toggleListening)
        startStopButton.bezelStyle = .rounded

        clearButton.target = self
        clearButton.action = #selector(clearTranscript)
        clearButton.bezelStyle = .rounded

        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.bezelStyle = .rounded

        keepOnTopButton.target = self
        keepOnTopButton.action = #selector(toggleKeepOnTop)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonStack = NSStackView(views: [keepOnTopButton, spacer, clearButton, startStopButton, closeButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        billingNoteLabel.font = .systemFont(ofSize: 11)
        billingNoteLabel.textColor = .tertiaryLabelColor
        billingNoteLabel.lineBreakMode = .byWordWrapping
        billingNoteLabel.maximumNumberOfLines = 3

        let rootStack = NSStackView(views: [statusLabel, formStack, transcriptScrollView, debugLabel, buttonStack, billingNoteLabel])
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 12
        rootStack.edgeInsets = NSEdgeInsets(
            top: Layout.contentInset,
            left: Layout.contentInset,
            bottom: Layout.contentInset,
            right: Layout.contentInset
        )
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        Task { @MainActor [weak self] in
            await self?.refreshAudioApplications()
        }
    }

    private func configureLabel(_ label: NSTextField) {
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true
    }

    private func makeFormRow(label: NSTextField, control: NSView) -> NSView {
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func configureCallbacks() {
        service.onUpdate = { [weak self] update in
            guard let self else {
                return
            }

            switch update {
            case .runningStateChanged(let isRunning):
                self.applyRunningState(isRunning)
            case .status(let text):
                self.statusLabel.stringValue = text
            case .transcript(let text):
                self.setTranscript(text)
            case .debug(let text):
                self.debugLabel.stringValue = text
            case .error(let message):
                self.statusLabel.stringValue = AppText.text(.liveTranscriptionError)
                self.debugLabel.stringValue = "error: \(message)"
                self.showError(message)
            }
        }
    }

    private func refreshLocalizedText() {
        window?.title = AppText.text(.liveTranscriptionTitle)
        statusLabel.stringValue = AppText.text(.liveInterpreterStopped)
        inputSourceLabel.stringValue = AppText.text(.inputSource)
        audioApplicationLabel.stringValue = AppText.text(.audioApplication)
        spokenLanguageLabel.stringValue = AppText.text(.spokenLanguage)
        keepOnTopButton.title = AppText.text(.keepInterpreterOnTop)
        clearButton.title = AppText.text(.clear)
        closeButton.title = AppText.text(.close)
        billingNoteLabel.stringValue = AppText.text(.liveTranscriptionBillingNote)
        refreshAudioApplicationAvailability()
    }

    private func applyRunningState(_ isRunning: Bool) {
        startStopButton.title = isStarting || isRunning
            ? AppText.text(.stop)
            : AppText.text(.start)
        startStopButton.isEnabled = true
        clearButton.isEnabled = !isRunning && !isStarting
        inputSourcePopup.isEnabled = !isRunning && !isStarting
        spokenLanguagePopup.isEnabled = !isRunning && !isStarting
        reloadAudioApplicationsButton.isEnabled = !isRunning && !isStarting
        refreshAudioApplicationAvailability()
    }

    @objc private func inputSourceDidChange() {
        refreshAudioApplicationAvailability()
    }

    private func refreshAudioApplicationAvailability() {
        let includesSystemAudio = selectedInputSource.includesSystemAudio
        let controlsEnabled = !service.isRunning && !isStarting
        audioApplicationRow.isHidden = !includesSystemAudio
        audioApplicationPopup.isEnabled = includesSystemAudio && controlsEnabled
        reloadAudioApplicationsButton.isEnabled = includesSystemAudio && controlsEnabled
    }

    @objc private func reloadAudioApplications() {
        Task { @MainActor [weak self] in
            await self?.refreshAudioApplications()
        }
    }

    private func refreshAudioApplications() async {
        let previousTarget = selectedSystemAudioTarget
        audioApplicationPopup.isEnabled = false
        reloadAudioApplicationsButton.isEnabled = false

        do {
            let applications = try await service.availableSystemAudioApplications()
            systemAudioTargets = [.allSystemAudio] + applications.map { .application($0) }
        } catch {
            systemAudioTargets = [.allSystemAudio]
            debugLabel.stringValue = error.localizedDescription
        }

        audioApplicationPopup.removeAllItems()
        audioApplicationPopup.addItems(withTitles: systemAudioTargets.map(\.displayName))
        if let index = systemAudioTargets.firstIndex(of: previousTarget) {
            audioApplicationPopup.selectItem(at: index)
        } else {
            audioApplicationPopup.selectItem(at: 0)
        }
        refreshAudioApplicationAvailability()
    }

    @objc private func toggleListening() {
        if service.isRunning || isStarting {
            cancelStartAndStop()
            return
        }

        isStarting = true
        applyRunningState(false)
        let inputSource = selectedInputSource
        let languageCode = selectedLanguageCode
        let audioTarget = selectedSystemAudioTarget
        startGeneration &+= 1
        let generation = startGeneration

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                if generation == self.startGeneration {
                    self.isStarting = false
                    self.startTask = nil
                    self.applyRunningState(self.service.isRunning)
                }
            }

            do {
                try await self.service.start(
                    inputSource: inputSource,
                    languageCode: languageCode,
                    systemAudioTarget: audioTarget
                )
            } catch is CancellationError {
                guard generation == self.startGeneration else {
                    return
                }
                self.service.stop()
            } catch {
                guard generation == self.startGeneration else {
                    return
                }
                self.service.stop()
                self.showError(error.localizedDescription)
            }
        }
        startTask = task
    }

    private func cancelStartAndStop() {
        startGeneration &+= 1
        startTask?.cancel()
        startTask = nil
        isStarting = false
        service.stop()
        applyRunningState(false)
    }

    @objc private func clearTranscript() {
        service.clear()
        setTranscript("")
    }

    @objc private func closeWindow() {
        close()
    }

    @objc private func toggleKeepOnTop() {
        window?.level = keepOnTopButton.state == .on ? .floating : .normal
    }

    func windowWillClose(_ notification: Notification) {
        cancelStartAndStop()
    }

    private var selectedInputSource: LiveInterpreterInputSource {
        let index = max(inputSourcePopup.indexOfSelectedItem, 0)
        return LiveInterpreterInputSource.allCases[min(index, LiveInterpreterInputSource.allCases.count - 1)]
    }

    private var selectedLanguageCode: String? {
        let index = spokenLanguagePopup.indexOfSelectedItem
        guard index > 0, index - 1 < SupportedLanguage.all.count else {
            return nil
        }
        return SupportedLanguage.all[index - 1].code
    }

    private var selectedSystemAudioTarget: LiveInterpreterSystemAudioTarget {
        let index = audioApplicationPopup.indexOfSelectedItem
        guard systemAudioTargets.indices.contains(index) else {
            return .allSystemAudio
        }
        return systemAudioTargets[index]
    }

    private func setTranscript(_ text: String) {
        transcriptTextView.string = text.isEmpty ? AppText.text(.liveTranscriptionNoTranscript) : text
        transcriptTextView.scrollToEndOfDocument(nil)
    }

    private func showError(_ message: String) {
        guard window?.attachedSheet == nil else {
            return
        }

        let alert = NSAlert()
        alert.messageText = AppText.text(.liveTranscriptionError)
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.text(.ok))

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
