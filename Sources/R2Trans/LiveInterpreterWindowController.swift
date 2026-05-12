import AppKit

@MainActor
final class LiveInterpreterWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let windowWidth: CGFloat = 980
        static let windowHeight: CGFloat = 680
        static let contentInset: CGFloat = 20
        static let formLabelWidth: CGFloat = 116
        static let formControlWidth: CGFloat = 420
        static let formRowSpacing: CGFloat = 12
        static let formWidth: CGFloat = 600
        static let meterLabelWidth: CGFloat = 116
        static let transcriptSpacing: CGFloat = 16
        static let transcriptMinHeight: CGFloat = 280
    }

    private let service = LiveInterpreterService()

    private let statusLabel = NSTextField(labelWithString: "")
    private let targetLanguageLabel = NSTextField(labelWithString: "")
    private let inputSourceLabel = NSTextField(labelWithString: "")
    private let inputSourcePopup = NSPopUpButton()
    private let audioApplicationLabel = NSTextField(labelWithString: "")
    private let audioApplicationPopup = NSPopUpButton()
    private let reloadAudioApplicationsButton = NSButton()
    private let audioApplicationRow = NSStackView()
    private let translationLanguageLabel = NSTextField(labelWithString: "")
    private let outputLanguagePopup = NSPopUpButton()
    private let audioLevelLabel = NSTextField(labelWithString: "")
    private let microphoneLevelLabel = NSTextField(labelWithString: "")
    private let systemAudioLevelLabel = NSTextField(labelWithString: "")
    private let microphoneWaveView = AudioWaveView()
    private let systemAudioWaveView = AudioWaveView()
    private let transcriptPanelTitleLabel = NSTextField(labelWithString: "")
    private let sourceTranscriptTitleLabel = NSTextField(labelWithString: "")
    private let translatedSubtitleTitleLabel = NSTextField(labelWithString: "")
    private let sourceTranscriptScrollView = TranscriptScrollView()
    private let sourceTranscriptTextView = NSTextView()
    private let subtitleScrollView = TranscriptScrollView()
    private let subtitleTextView = NSTextView()
    private let debugLabel = NSTextField(labelWithString: "")
    private let startStopButton = NSButton()
    private let clearButton = NSButton()
    private let closeButton = NSButton()
    private let keepOnTopButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let billingNoteLabel = NSTextField(labelWithString: "")
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
        window.minSize = NSSize(width: 760, height: 520)
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

        let controlsPane = NSView()
        controlsPane.translatesAutoresizingMaskIntoConstraints = false

        let transcriptPane = NSView()
        transcriptPane.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [statusLabel, targetLanguageLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.distribution = .fill
        headerStack.spacing = 12

        targetLanguageLabel.alignment = .right
        targetLanguageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        inputSourceLabel.alignment = .right
        inputSourceLabel.widthAnchor.constraint(equalToConstant: Layout.formLabelWidth).isActive = true
        inputSourcePopup.addItems(withTitles: LiveInterpreterInputSource.allCases.map(\.displayName))
        inputSourcePopup.selectItem(at: 0)
        inputSourcePopup.alignment = .center
        inputSourcePopup.target = self
        inputSourcePopup.action = #selector(inputSourceDidChange)
        inputSourcePopup.translatesAutoresizingMaskIntoConstraints = false
        inputSourcePopup.widthAnchor.constraint(equalToConstant: Layout.formControlWidth).isActive = true

        let inputSourceRow = makeFormRow(label: inputSourceLabel, control: inputSourcePopup)

        audioApplicationLabel.alignment = .right
        audioApplicationLabel.widthAnchor.constraint(equalToConstant: Layout.formLabelWidth).isActive = true
        audioApplicationPopup.addItems(withTitles: systemAudioTargets.map(\.displayName))
        audioApplicationPopup.selectItem(at: 0)
        audioApplicationPopup.alignment = .center
        audioApplicationPopup.translatesAutoresizingMaskIntoConstraints = false
        audioApplicationPopup.widthAnchor.constraint(equalToConstant: Layout.formControlWidth - 42).isActive = true

        reloadAudioApplicationsButton.target = self
        reloadAudioApplicationsButton.action = #selector(reloadAudioApplications)
        reloadAudioApplicationsButton.bezelStyle = .rounded
        reloadAudioApplicationsButton.title = "↻"
        reloadAudioApplicationsButton.translatesAutoresizingMaskIntoConstraints = false
        reloadAudioApplicationsButton.widthAnchor.constraint(equalToConstant: 34).isActive = true

        let audioApplicationControlStack = NSStackView(views: [audioApplicationPopup, reloadAudioApplicationsButton])
        audioApplicationControlStack.orientation = .horizontal
        audioApplicationControlStack.alignment = .centerY
        audioApplicationControlStack.spacing = 8
        audioApplicationControlStack.translatesAutoresizingMaskIntoConstraints = false
        audioApplicationControlStack.widthAnchor.constraint(equalToConstant: Layout.formControlWidth).isActive = true

        audioApplicationRow.orientation = .horizontal
        audioApplicationRow.alignment = .centerY
        audioApplicationRow.spacing = 10
        audioApplicationRow.addArrangedSubview(audioApplicationLabel)
        audioApplicationRow.addArrangedSubview(audioApplicationControlStack)

        translationLanguageLabel.alignment = .right
        translationLanguageLabel.widthAnchor.constraint(equalToConstant: Layout.formLabelWidth).isActive = true

        outputLanguagePopup.addItems(withTitles: SupportedLanguage.all.map(\.displayName))
        outputLanguagePopup.selectItem(withTitle: SupportedLanguage.displayName(for: AppSettings.shared.targetLanguageCode))
        outputLanguagePopup.alignment = .center
        outputLanguagePopup.translatesAutoresizingMaskIntoConstraints = false
        outputLanguagePopup.widthAnchor.constraint(equalToConstant: Layout.formControlWidth).isActive = true

        let translationLanguageRow = makeFormRow(label: translationLanguageLabel, control: outputLanguagePopup)

        configureWaveView(microphoneWaveView)
        configureWaveView(systemAudioWaveView)

        audioLevelLabel.alignment = .right
        audioLevelLabel.widthAnchor.constraint(equalToConstant: Layout.meterLabelWidth).isActive = true

        let meterStack = NSStackView(views: [
            makeAudioMeterRow(label: microphoneLevelLabel, waveView: microphoneWaveView),
            makeAudioMeterRow(label: systemAudioLevelLabel, waveView: systemAudioWaveView)
        ])
        meterStack.orientation = .vertical
        meterStack.spacing = 8
        meterStack.translatesAutoresizingMaskIntoConstraints = false
        meterStack.widthAnchor.constraint(equalToConstant: Layout.formControlWidth).isActive = true

        let audioLevelRow = makeFormRow(label: audioLevelLabel, control: meterStack)

        let controlsStack = NSStackView(views: [
            headerStack,
            inputSourceRow,
            audioApplicationRow,
            translationLanguageRow,
            audioLevelRow
        ])
        controlsStack.orientation = .vertical
        controlsStack.alignment = .centerX
        controlsStack.spacing = Layout.formRowSpacing
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.widthAnchor.constraint(equalToConstant: Layout.formWidth).isActive = true

        configureTranscriptTextView(sourceTranscriptTextView, fontSize: 18, weight: .regular)
        configureTranscriptScrollView(sourceTranscriptScrollView, textView: sourceTranscriptTextView)
        configureTranscriptTextView(subtitleTextView, fontSize: 18, weight: .regular)
        configureTranscriptScrollView(subtitleScrollView, textView: subtitleTextView)

        let transcriptPanel = makeTranscriptPanel()

        debugLabel.lineBreakMode = .byTruncatingMiddle
        debugLabel.maximumNumberOfLines = 1
        debugLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        debugLabel.textColor = .tertiaryLabelColor

        startStopButton.target = self
        startStopButton.action = #selector(toggleListening)
        startStopButton.bezelStyle = .rounded

        clearButton.target = self
        clearButton.action = #selector(clearTranscripts)
        clearButton.bezelStyle = .rounded

        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.bezelStyle = .rounded

        keepOnTopButton.target = self
        keepOnTopButton.action = #selector(toggleKeepOnTop)
        keepOnTopButton.state = .off

        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonStack = NSStackView(views: [keepOnTopButton, buttonSpacer, clearButton, startStopButton, closeButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        billingNoteLabel.font = .systemFont(ofSize: 11)
        billingNoteLabel.textColor = .tertiaryLabelColor
        billingNoteLabel.lineBreakMode = .byWordWrapping
        billingNoteLabel.maximumNumberOfLines = 2

        let controlsSpacer = NSView()
        controlsSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        let controlsPaneStack = NSStackView(views: [
            makeFullWidthContainer(for: controlsStack, centered: true),
            controlsSpacer,
            debugLabel,
            buttonStack,
            billingNoteLabel
        ])
        controlsPaneStack.orientation = .vertical
        controlsPaneStack.alignment = .width
        controlsPaneStack.spacing = 8
        controlsPaneStack.edgeInsets = NSEdgeInsets(
            top: Layout.contentInset,
            left: Layout.contentInset,
            bottom: Layout.contentInset,
            right: Layout.contentInset
        )
        controlsPaneStack.translatesAutoresizingMaskIntoConstraints = false

        controlsPane.addSubview(controlsPaneStack)
        transcriptPane.addSubview(transcriptPanel)

        contentView.addSubview(controlsPane)
        contentView.addSubview(transcriptPane)

        NSLayoutConstraint.activate([
            controlsPane.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controlsPane.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            controlsPane.topAnchor.constraint(equalTo: contentView.topAnchor),
            controlsPane.bottomAnchor.constraint(equalTo: contentView.centerYAnchor),

            transcriptPane.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            transcriptPane.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            transcriptPane.topAnchor.constraint(equalTo: contentView.centerYAnchor),
            transcriptPane.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            controlsPaneStack.leadingAnchor.constraint(equalTo: controlsPane.leadingAnchor),
            controlsPaneStack.trailingAnchor.constraint(equalTo: controlsPane.trailingAnchor),
            controlsPaneStack.topAnchor.constraint(equalTo: controlsPane.topAnchor),
            controlsPaneStack.bottomAnchor.constraint(equalTo: controlsPane.bottomAnchor),

            transcriptPanel.leadingAnchor.constraint(equalTo: transcriptPane.leadingAnchor),
            transcriptPanel.trailingAnchor.constraint(equalTo: transcriptPane.trailingAnchor),
            transcriptPanel.topAnchor.constraint(equalTo: transcriptPane.topAnchor),
            transcriptPanel.bottomAnchor.constraint(equalTo: transcriptPane.bottomAnchor)
        ])

        Task {
            await refreshAudioApplications()
        }
    }

    private func makeFormRow(label: NSTextField, control: NSView) -> NSView {
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: Layout.formControlWidth).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: Layout.formWidth).isActive = true
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
            case .status(let status):
                self.statusLabel.stringValue = status
            case .sourceTranscript(let transcript):
                self.updateTranscriptTextView(
                    self.sourceTranscriptTextView,
                    in: self.sourceTranscriptScrollView,
                    text: transcript.isEmpty ? AppText.text(.liveInterpreterNoSource) : transcript
                )
            case .subtitle(let subtitle, let languageLabel):
                self.updateTranscriptTextView(
                    self.subtitleTextView,
                    in: self.subtitleScrollView,
                    text: subtitle.isEmpty ? AppText.text(.liveInterpreterWaitingSubtitle) : subtitle
                )
                self.targetLanguageLabel.stringValue = languageLabel.isEmpty ? "" : "\(AppText.text(.targetLanguage)): \(languageLabel)"
            case .audioLevel(let source, let level):
                self.updateAudioLevel(source, level: level)
            case .debug(let message):
                self.debugLabel.stringValue = message
            case .error(let message):
                self.statusLabel.stringValue = AppText.text(.liveInterpreterError)
                self.debugLabel.stringValue = "error: \(message)"
                self.showError(message)
            }
        }
    }

    private func refreshLocalizedText() {
        window?.title = AppText.text(.liveInterpreterTitle)
        inputSourceLabel.stringValue = AppText.text(.inputSource)
        audioApplicationLabel.stringValue = AppText.text(.audioApplication)
        translationLanguageLabel.stringValue = AppText.text(.targetLanguage)
        audioLevelLabel.stringValue = AppText.text(.audioLevel)
        microphoneLevelLabel.stringValue = AppText.text(.microphoneLevel)
        systemAudioLevelLabel.stringValue = AppText.text(.systemAudioLevel)
        transcriptPanelTitleLabel.stringValue = AppText.text(.translatedSubtitle)
        sourceTranscriptTitleLabel.stringValue = AppText.text(.sourceTranscript)
        translatedSubtitleTitleLabel.stringValue = AppText.text(.targetLanguage)
        inputSourcePopup.removeAllItems()
        inputSourcePopup.addItems(withTitles: LiveInterpreterInputSource.allCases.map(\.displayName))
        inputSourcePopup.selectItem(at: 0)
        audioApplicationPopup.removeAllItems()
        audioApplicationPopup.addItems(withTitles: systemAudioTargets.map(\.displayName))
        audioApplicationPopup.selectItem(at: 0)
        outputLanguagePopup.removeAllItems()
        outputLanguagePopup.addItems(withTitles: SupportedLanguage.all.map(\.displayName))
        outputLanguagePopup.selectItem(withTitle: SupportedLanguage.displayName(for: AppSettings.shared.targetLanguageCode))
        keepOnTopButton.title = AppText.text(.keepInterpreterOnTop)
        clearButton.title = AppText.text(.clear)
        closeButton.title = AppText.text(.close)
        billingNoteLabel.stringValue = AppText.text(.liveInterpreterBillingNote)
        statusLabel.stringValue = AppText.text(.liveInterpreterStopped)
        updateTranscriptTextView(
            sourceTranscriptTextView,
            in: sourceTranscriptScrollView,
            text: AppText.text(.liveInterpreterNoSource)
        )
        updateTranscriptTextView(
            subtitleTextView,
            in: subtitleScrollView,
            text: AppText.text(.liveInterpreterWaitingSubtitle)
        )
        debugLabel.stringValue = ""
        refreshAudioApplicationAvailability()
        refreshMeterAvailability()
    }

    private func applyRunningState(_ isRunning: Bool) {
        startStopButton.title = isStarting ? AppText.text(.liveInterpreterConnecting) : (isRunning ? AppText.text(.stop) : AppText.text(.start))
        startStopButton.isEnabled = !isStarting
        clearButton.isEnabled = !isRunning && !isStarting
        inputSourcePopup.isEnabled = !isRunning && !isStarting
        audioApplicationPopup.isEnabled = !isRunning && !isStarting
        reloadAudioApplicationsButton.isEnabled = !isRunning && !isStarting
        outputLanguagePopup.isEnabled = !isRunning && !isStarting

        if !isRunning && !isStarting {
            resetAudioMeters()
            refreshAudioApplicationAvailability()
            refreshMeterAvailability()
        }
    }

    @objc private func toggleListening() {
        if service.isRunning {
            service.stop()
            return
        }

        guard !isStarting else {
            return
        }

        Task {
            do {
                let inputSource = LiveInterpreterInputSource.allCases[inputSourcePopup.indexOfSelectedItem]
                let targetLanguage = SupportedLanguage.all[outputLanguagePopup.indexOfSelectedItem]
                isStarting = true
                applyRunningState(false)
                resetAudioMeters()
                refreshMeterAvailability()
                debugLabel.stringValue = ""
                try await service.start(
                    inputSource: inputSource,
                    targetLanguageCode: targetLanguage.code,
                    systemAudioTarget: selectedSystemAudioTarget()
                )
                isStarting = false
                applyRunningState(service.isRunning)
            } catch {
                isStarting = false
                applyRunningState(false)
                statusLabel.stringValue = AppText.text(.liveInterpreterError)
                showError(error.localizedDescription)
            }
        }
    }

    @objc private func clearTranscripts() {
        service.clear()
    }

    @objc private func inputSourceDidChange() {
        resetAudioMeters()
        refreshAudioApplicationAvailability()
        refreshMeterAvailability()
    }

    @objc private func reloadAudioApplications() {
        Task {
            await refreshAudioApplications()
        }
    }

    @objc private func closeWindow() {
        close()
    }

    @objc private func toggleKeepOnTop() {
        applyKeepOnTopState()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = AppText.text(.liveInterpreterError)
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.text(.ok))
        alert.beginSheetModal(for: window!)
    }

    private func configureWaveView(_ waveView: AudioWaveView) {
        waveView.translatesAutoresizingMaskIntoConstraints = false
        waveView.heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    private func configureTranscriptTextView(
        _ textView: NSTextView,
        fontSize: CGFloat,
        weight: NSFont.Weight
    ) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.alignment = .left
        textView.font = .systemFont(ofSize: fontSize, weight: weight)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
    }

    private func configureTranscriptScrollView(_ scrollView: TranscriptScrollView, textView: NSTextView) {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateTranscriptTextView(
        _ textView: NSTextView,
        in scrollView: TranscriptScrollView,
        text: String
    ) {
        textView.string = text
        scrollView.resizeDocumentViewToContentWidth()
        textView.scrollToEndOfDocument(nil)
    }

    private func makeTranscriptPanel() -> NSView {
        transcriptPanelTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        transcriptPanelTitleLabel.textColor = .secondaryLabelColor

        sourceTranscriptTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sourceTranscriptTitleLabel.textColor = .secondaryLabelColor

        translatedSubtitleTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        translatedSubtitleTitleLabel.textColor = .secondaryLabelColor

        transcriptPanelTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceTranscriptTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        translatedSubtitleTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.layer?.borderWidth = 1
        panel.translatesAutoresizingMaskIntoConstraints = false

        [
            transcriptPanelTitleLabel,
            sourceTranscriptTitleLabel,
            sourceTranscriptScrollView,
            translatedSubtitleTitleLabel,
            subtitleScrollView
        ].forEach(panel.addSubview)

        let inset: CGFloat = 16
        let spacing: CGFloat = 8

        NSLayoutConstraint.activate([
            transcriptPanelTitleLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: inset),
            transcriptPanelTitleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -inset),
            transcriptPanelTitleLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: inset),

            sourceTranscriptTitleLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: inset),
            sourceTranscriptTitleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -inset),
            sourceTranscriptTitleLabel.topAnchor.constraint(equalTo: transcriptPanelTitleLabel.bottomAnchor, constant: spacing),

            sourceTranscriptScrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            sourceTranscriptScrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            sourceTranscriptScrollView.topAnchor.constraint(equalTo: sourceTranscriptTitleLabel.bottomAnchor, constant: spacing),
            sourceTranscriptScrollView.heightAnchor.constraint(equalTo: panel.heightAnchor, multiplier: 0.28),

            translatedSubtitleTitleLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: inset),
            translatedSubtitleTitleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -inset),
            translatedSubtitleTitleLabel.topAnchor.constraint(equalTo: sourceTranscriptScrollView.bottomAnchor, constant: spacing),

            subtitleScrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            subtitleScrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            subtitleScrollView.topAnchor.constraint(equalTo: translatedSubtitleTitleLabel.bottomAnchor, constant: spacing),
            subtitleScrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])

        return panel
    }

    private func makeFullWidthContainer(for view: NSView, centered: Bool = false) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)

        if centered {
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                view.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
                view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        return container
    }




    private func makeAudioMeterRow(label: NSTextField, waveView: AudioWaveView) -> NSView {
        label.widthAnchor.constraint(equalToConstant: 96).isActive = true
        label.alignment = .right
        label.font = .systemFont(ofSize: 12)

        waveView.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        let row = NSStackView(views: [label, waveView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func updateAudioLevel(_ source: LiveInterpreterAudioSource, level: Double) {
        switch source {
        case .microphone:
            microphoneWaveView.setLevel(level)
        case .systemAudio:
            systemAudioWaveView.setLevel(level)
        }
    }

    private func resetAudioMeters() {
        microphoneWaveView.reset()
        systemAudioWaveView.reset()
    }

    private func refreshMeterAvailability() {
        let inputSource = LiveInterpreterInputSource.allCases[inputSourcePopup.indexOfSelectedItem]
        setMeterEnabled(inputSource.includesMicrophone, label: microphoneLevelLabel, waveView: microphoneWaveView)
        setMeterEnabled(inputSource.includesSystemAudio, label: systemAudioLevelLabel, waveView: systemAudioWaveView)
    }

    private func refreshAudioApplicationAvailability() {
        let inputSource = LiveInterpreterInputSource.allCases[inputSourcePopup.indexOfSelectedItem]
        let isAvailable = inputSource.includesSystemAudio
        let isEditable = isAvailable && !service.isRunning && !isStarting

        audioApplicationRow.isHidden = !isAvailable
        audioApplicationLabel.textColor = isEditable ? .labelColor : .tertiaryLabelColor
        audioApplicationPopup.isEnabled = isEditable
        reloadAudioApplicationsButton.isEnabled = isEditable
    }

    private func selectedSystemAudioTarget() -> LiveInterpreterSystemAudioTarget {
        let selectedIndex = audioApplicationPopup.indexOfSelectedItem
        guard systemAudioTargets.indices.contains(selectedIndex) else {
            return .allSystemAudio
        }

        return systemAudioTargets[selectedIndex]
    }

    private func refreshAudioApplications() async {
        let previousTarget = selectedSystemAudioTarget()
        audioApplicationPopup.removeAllItems()
        audioApplicationPopup.addItem(withTitle: AppText.text(.loadingAudioApplications))
        audioApplicationPopup.selectItem(at: 0)
        audioApplicationPopup.isEnabled = false
        reloadAudioApplicationsButton.isEnabled = false

        do {
            let applications = try await service.availableSystemAudioApplications()
            systemAudioTargets = [.allSystemAudio] + applications.map { .application($0) }
        } catch {
            systemAudioTargets = [.allSystemAudio]
            debugLabel.stringValue = "audio apps unavailable: \(error.localizedDescription)"
        }

        audioApplicationPopup.removeAllItems()
        audioApplicationPopup.addItems(withTitles: systemAudioTargets.map(\.displayName))
        audioApplicationPopup.selectItem(at: restoredTargetIndex(for: previousTarget))
        refreshAudioApplicationAvailability()
    }

    private func restoredTargetIndex(for previousTarget: LiveInterpreterSystemAudioTarget) -> Int {
        systemAudioTargets.firstIndex { candidate in
            systemAudioTargetsMatch(candidate, previousTarget)
        } ?? 0
    }

    private func systemAudioTargetsMatch(
        _ lhs: LiveInterpreterSystemAudioTarget,
        _ rhs: LiveInterpreterSystemAudioTarget
    ) -> Bool {
        switch (lhs, rhs) {
        case (.allSystemAudio, .allSystemAudio):
            return true
        case (.application(let lhsApplication), .application(let rhsApplication)):
            if lhsApplication.processID == rhsApplication.processID {
                return true
            }

            if
                let lhsBundleIdentifier = lhsApplication.bundleIdentifier,
                let rhsBundleIdentifier = rhsApplication.bundleIdentifier,
                lhsBundleIdentifier == rhsBundleIdentifier
            {
                return true
            }

            return lhsApplication.appName == rhsApplication.appName
        default:
            return false
        }
    }

    private func setMeterEnabled(_ isEnabled: Bool, label: NSTextField, waveView: AudioWaveView) {
        label.textColor = isEnabled ? .labelColor : .tertiaryLabelColor
        waveView.alphaValue = isEnabled ? 1 : 0.35
    }

    private func applyKeepOnTopState() {
        window?.level = keepOnTopButton.state == .on ? .floating : .normal
    }

    func windowWillClose(_ notification: Notification) {
        service.stop()
        window?.level = .normal
    }
}

private final class TranscriptScrollView: NSScrollView {
    override func layout() {
        super.layout()
        resizeDocumentViewToContentWidth()
    }

    func resizeDocumentViewToContentWidth() {
        guard let textView = documentView as? NSTextView else {
            return
        }

        let contentSize = contentView.bounds.size
        guard contentSize.width > 0 else {
            return
        }

        textView.setFrameSize(NSSize(width: contentSize.width, height: max(contentSize.height, textView.frame.height)))

        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
        textView.setFrameSize(NSSize(width: contentSize.width, height: max(contentSize.height, usedHeight)))
    }
}

private final class AudioWaveView: NSView {
    private var levels = Array(repeating: CGFloat(0.04), count: 28)
    private var smoothedLevel: CGFloat = 0.04

    override var isFlipped: Bool {
        true
    }

    func setLevel(_ level: Double) {
        let incoming = max(0.04, min(CGFloat(level), 1))
        smoothedLevel = smoothedLevel * 0.72 + incoming * 0.28
        levels.removeFirst()
        levels.append(smoothedLevel)
        needsDisplay = true
    }

    func reset() {
        smoothedLevel = 0.04
        levels = Array(repeating: 0.04, count: levels.count)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.separatorColor.withAlphaComponent(0.18).setFill()
        backgroundPath.fill()

        let barCount = levels.count
        let spacing: CGFloat = 3
        let availableWidth = bounds.width - spacing * CGFloat(barCount - 1)
        let barWidth = max(2, floor(availableWidth / CGFloat(barCount)))
        let midY = bounds.midY
        let accentColor = NSColor.controlAccentColor.withAlphaComponent(0.55)

        for (index, level) in levels.enumerated() {
            let x = CGFloat(index) * (barWidth + spacing)
            let easedLevel = 0.18 + pow(level, 0.72) * 0.82
            let height = max(4, bounds.height * easedLevel)
            let rect = NSRect(
                x: x,
                y: midY - height / 2,
                width: barWidth,
                height: height
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            accentColor.setFill()
            path.fill()
        }
    }
}
