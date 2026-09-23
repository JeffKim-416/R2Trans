import AppKit

@MainActor
final class LiveInterpreterWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let windowWidth: CGFloat = 980
        static let windowHeight: CGFloat = 740
        static let contentInset: CGFloat = 20
        static let formLabelWidth: CGFloat = 116
        static let formControlWidth: CGFloat = 420
        static let formRowSpacing: CGFloat = 8
        static let formWidth: CGFloat = 600
        static let meterLabelWidth: CGFloat = 116
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
    private let provisionalSubtitlesLabel = NSTextField(labelWithString: "")
    private let provisionalSubtitlesSwitch = NSSwitch()
    private let audioLevelLabel = NSTextField(labelWithString: "")
    private let microphoneLevelLabel = NSTextField(labelWithString: "")
    private let systemAudioLevelLabel = NSTextField(labelWithString: "")
    private let microphoneWaveView = AudioWaveView()
    private let systemAudioWaveView = AudioWaveView()
    private let sourceTranscriptScrollView = TranscriptScrollView()
    private let sourceTranscriptTextView = NSTextView()
    private let subtitleScrollView = TranscriptScrollView()
    private let subtitleTextView = NSTextView()
    private let latestSourceTitleLabel = NSTextField(labelWithString: "")
    private let latestSourceTextLabel = NSTextField(wrappingLabelWithString: "")
    private let latestSubtitleTitleLabel = NSTextField(labelWithString: "")
    private let latestSubtitleStateLabel = NSTextField(labelWithString: "")
    private let historyTitleLabel = NSTextField(labelWithString: "")
    private let historyLanguagePicker = NSSegmentedControl()
    private let jumpToLatestButton = NSButton()
    private let historyDisclosureButton = NSButton()
    private let decreaseTextButton = NSButton()
    private let increaseTextButton = NSButton()
    private let captionLegendLabel = NSTextField(labelWithString: "")
    private let settingsDisclosureButton = NSButton()
    private var settingsPane: NSView?
    private var isSettingsExpanded = true
    private var isHistoryAtLatest = true
    private var hasNewHistory = false
    private var isHistoryExpanded = false
    private var subtitleTextSize: CGFloat = 30
    private var latestOfficialText = ""
    private var latestProvisionalText = ""
    private var transcriptSnapshot = LiveInterpreterTranscriptSnapshot()
    private var renderedHistory = ""
    private var historyShowsTranslation = true
    private var isUpdatingHistory = false
    private var historyHeightConstraint: NSLayoutConstraint?
    private let debugLabel = NSTextField(labelWithString: "")
    private let startStopButton = NSButton()
    private let clearButton = NSButton()
    private let closeButton = NSButton()
    private let keepOnTopButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let billingNoteLabel = NSTextField(labelWithString: "")
    private var isStarting = false
    private var startTask: Task<Void, Never>?
    private var startGeneration = 0
    private var systemAudioTargets: [LiveInterpreterSystemAudioTarget] = [.allSystemAudio]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentMinSize = NSSize(width: 760, height: 650)
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupContent() {
        guard let contentView = window?.contentView else {
            return
        }

        settingsDisclosureButton.bezelStyle = .rounded
        settingsDisclosureButton.isBordered = false
        settingsDisclosureButton.target = self
        settingsDisclosureButton.action = #selector(toggleSettings)
        settingsDisclosureButton.setContentHuggingPriority(.required, for: .horizontal)

        let headerStack = NSStackView(views: [statusLabel, targetLanguageLabel, settingsDisclosureButton])
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

        provisionalSubtitlesLabel.alignment = .left
        provisionalSubtitlesSwitch.state = AppSettings.shared.liveInterpreterProvisionalSubtitlesEnabled ? .on : .off
        provisionalSubtitlesSwitch.target = self
        provisionalSubtitlesSwitch.action = #selector(provisionalSubtitlesDidChange)
        let provisionalControls = NSStackView(views: [provisionalSubtitlesSwitch, provisionalSubtitlesLabel])
        provisionalControls.orientation = .horizontal
        provisionalControls.alignment = .centerY
        provisionalControls.spacing = 8
        provisionalSubtitlesLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let provisionalSpacer = NSTextField(labelWithString: "")
        provisionalSpacer.widthAnchor.constraint(equalToConstant: Layout.formLabelWidth).isActive = true
        let provisionalSubtitlesRow = makeFormRow(label: provisionalSpacer, control: provisionalControls)

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

        let settingsStack = NSStackView(views: [
            inputSourceRow,
            audioApplicationRow,
            translationLanguageRow,
            provisionalSubtitlesRow,
            audioLevelRow
        ])
        settingsStack.orientation = .vertical
        settingsStack.alignment = .centerX
        settingsStack.spacing = Layout.formRowSpacing
        settingsStack.translatesAutoresizingMaskIntoConstraints = false
        settingsStack.widthAnchor.constraint(equalToConstant: Layout.formWidth).isActive = true

        configureTranscriptTextView(sourceTranscriptTextView, fontSize: 15, weight: .regular)
        configureTranscriptScrollView(sourceTranscriptScrollView, textView: sourceTranscriptTextView)
        configureTranscriptTextView(subtitleTextView, fontSize: subtitleTextSize, weight: .bold)
        configureTranscriptScrollView(subtitleScrollView, textView: subtitleTextView)

        latestSourceTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        latestSourceTitleLabel.textColor = .secondaryLabelColor
        latestSourceTextLabel.font = .systemFont(ofSize: 18, weight: .regular)
        latestSourceTextLabel.textColor = .secondaryLabelColor
        latestSourceTextLabel.maximumNumberOfLines = 2
        latestSourceTextLabel.lineBreakMode = .byTruncatingHead
        latestSourceTextLabel.isSelectable = true
        latestSubtitleTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        latestSubtitleTitleLabel.textColor = .secondaryLabelColor
        latestSubtitleStateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        latestSubtitleStateLabel.textColor = .secondaryLabelColor
        historyTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        historyTitleLabel.textColor = .secondaryLabelColor
        captionLegendLabel.font = .systemFont(ofSize: 11)
        captionLegendLabel.textColor = .tertiaryLabelColor
        jumpToLatestButton.bezelStyle = .rounded
        jumpToLatestButton.target = self
        jumpToLatestButton.action = #selector(jumpToLatest)
        jumpToLatestButton.isHidden = true
        historyDisclosureButton.bezelStyle = .rounded
        historyDisclosureButton.isBordered = false
        historyDisclosureButton.target = self
        historyDisclosureButton.action = #selector(toggleHistory)
        decreaseTextButton.bezelStyle = .rounded
        decreaseTextButton.title = "A−"
        decreaseTextButton.toolTip = AppText.text(.liveSmallerText)
        decreaseTextButton.target = self
        decreaseTextButton.action = #selector(decreaseSubtitleText)
        increaseTextButton.bezelStyle = .rounded
        increaseTextButton.title = "A+"
        increaseTextButton.toolTip = AppText.text(.liveLargerText)
        increaseTextButton.target = self
        increaseTextButton.action = #selector(increaseSubtitleText)
        historyLanguagePicker.segmentCount = 2
        historyLanguagePicker.trackingMode = .selectOne
        historyLanguagePicker.selectedSegment = 1
        historyLanguagePicker.translatesAutoresizingMaskIntoConstraints = false
        historyLanguagePicker.widthAnchor.constraint(equalToConstant: 118).isActive = true
        historyLanguagePicker.target = self
        historyLanguagePicker.action = #selector(historyLanguageDidChange)

        let transcriptPanel = makeTranscriptPanel()

        debugLabel.lineBreakMode = .byTruncatingMiddle
        debugLabel.maximumNumberOfLines = 1
        debugLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        debugLabel.textColor = .tertiaryLabelColor

        startStopButton.target = self
        startStopButton.action = #selector(toggleListening)
        startStopButton.bezelStyle = .rounded
        startStopButton.keyEquivalent = "\r"

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
        billingNoteLabel.textColor = .secondaryLabelColor
        billingNoteLabel.lineBreakMode = .byWordWrapping
        billingNoteLabel.maximumNumberOfLines = 0
        billingNoteLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let settingsPane = NSStackView(views: [
            makeFullWidthContainer(for: settingsStack, centered: true),
            debugLabel,
            billingNoteLabel
        ])
        settingsPane.orientation = .vertical
        settingsPane.alignment = .width
        settingsPane.spacing = 8
        self.settingsPane = settingsPane

        let rootStack = NSStackView(views: [headerStack, settingsPane, transcriptPanel, buttonStack])
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
            case .transcript(let snapshot, let languageLabel):
                self.updateTranscript(snapshot)
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
        provisionalSubtitlesLabel.stringValue = AppText.text(.liveInterpreterProvisionalSubtitles)
        audioLevelLabel.stringValue = AppText.text(.audioLevel)
        microphoneLevelLabel.stringValue = AppText.text(.microphoneLevel)
        systemAudioLevelLabel.stringValue = AppText.text(.systemAudioLevel)
        latestSourceTitleLabel.stringValue = AppText.text(.liveRecentSource)
        latestSubtitleTitleLabel.stringValue = AppText.text(.liveFocusTitle)
        historyTitleLabel.stringValue = AppText.text(.liveHistory)
        captionLegendLabel.stringValue = AppText.text(.liveCaptionLegend)
        historyLanguagePicker.setLabel(AppText.text(.liveHistorySource), forSegment: 0)
        historyLanguagePicker.setLabel(AppText.text(.liveHistoryTranslation), forSegment: 1)
        settingsDisclosureButton.title = isSettingsExpanded
            ? AppText.text(.liveHideSettings)
            : AppText.text(.liveShowSettings)
        jumpToLatestButton.title = hasNewHistory
            ? AppText.text(.liveNewHistory)
            : AppText.text(.liveJumpToLatest)
        historyDisclosureButton.title = isHistoryExpanded
            ? AppText.text(.liveHideHistory)
            : AppText.text(.liveShowHistory)
        decreaseTextButton.toolTip = AppText.text(.liveSmallerText)
        increaseTextButton.toolTip = AppText.text(.liveLargerText)
        latestSourceTitleLabel.toolTip = AppText.text(.liveRecentSourceHelp)
        renderedHistory = ""
        updateTranscriptHistory(
            sourceHistory: transcriptSnapshot.sourceHistory,
            officialHistory: transcriptSnapshot.officialHistory,
            historyTruncated: transcriptSnapshot.historyTruncated
        )
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
        if latestSourceTextLabel.stringValue.isEmpty {
            latestSourceTextLabel.stringValue = AppText.text(.liveInterpreterNoSource)
        }
        if subtitleTextView.string.isEmpty {
            updateLatestSubtitle(official: "", provisional: "")
        }
        debugLabel.stringValue = ""
        refreshAudioApplicationAvailability()
        refreshMeterAvailability()
    }

    private func applyRunningState(_ isRunning: Bool) {
        startStopButton.title = isStarting || isRunning ? AppText.text(.stop) : AppText.text(.start)
        startStopButton.isEnabled = true
        clearButton.isEnabled = !isRunning && !isStarting
        inputSourcePopup.isEnabled = !isRunning && !isStarting
        audioApplicationPopup.isEnabled = !isRunning && !isStarting
        reloadAudioApplicationsButton.isEnabled = !isRunning && !isStarting
        outputLanguagePopup.isEnabled = !isRunning && !isStarting
        provisionalSubtitlesSwitch.isEnabled = !isRunning && !isStarting

        if !isRunning && !isStarting {
            resetAudioMeters()
            refreshAudioApplicationAvailability()
            refreshMeterAvailability()
        }
    }

    @objc private func toggleListening() {
        if service.isRunning || isStarting {
            cancelStartAndStop()
            return
        }

        guard !isStarting else {
            return
        }

        let inputSource = LiveInterpreterInputSource.allCases[inputSourcePopup.indexOfSelectedItem]
        let targetLanguage = SupportedLanguage.all[outputLanguagePopup.indexOfSelectedItem]
        let systemAudioTarget = selectedSystemAudioTarget()
        let provisionalSubtitlesEnabled = provisionalSubtitlesSwitch.state == .on
        startGeneration &+= 1
        let generation = startGeneration
        isStarting = true
        applyRunningState(false)
        resetAudioMeters()
        refreshMeterAvailability()
        debugLabel.stringValue = ""

        startTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await service.start(
                    inputSource: inputSource,
                    targetLanguageCode: targetLanguage.code,
                    systemAudioTarget: systemAudioTarget,
                    provisionalSubtitlesEnabled: provisionalSubtitlesEnabled
                )
                guard generation == startGeneration else {
                    return
                }
                isStarting = false
                startTask = nil
                if service.isRunning && isSettingsExpanded {
                    toggleSettings()
                }
                applyRunningState(service.isRunning)
            } catch is CancellationError {
                guard generation == startGeneration else {
                    return
                }
                isStarting = false
                startTask = nil
                applyRunningState(false)
            } catch {
                guard generation == startGeneration else {
                    return
                }
                isStarting = false
                startTask = nil
                applyRunningState(false)
                statusLabel.stringValue = AppText.text(.liveInterpreterError)
                showError(error.localizedDescription)
            }
        }
    }

    private func cancelStartAndStop() {
        startGeneration &+= 1
        startTask?.cancel()
        startTask = nil
        isStarting = false
        service.stop()
        applyRunningState(false)
    }

    @objc private func clearTranscripts() {
        service.clear()
    }

    @objc private func inputSourceDidChange() {
        resetAudioMeters()
        refreshAudioApplicationAvailability()
        refreshMeterAvailability()
    }

    @objc private func provisionalSubtitlesDidChange() {
        AppSettings.shared.liveInterpreterProvisionalSubtitlesEnabled = provisionalSubtitlesSwitch.state == .on
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

    private func updateTranscript(_ snapshot: LiveInterpreterTranscriptSnapshot) {
        transcriptSnapshot = snapshot
        latestSourceTextLabel.stringValue = snapshot.latestSource.isEmpty
            ? AppText.text(.liveInterpreterNoSource)
            : snapshot.latestSource
        latestOfficialText = snapshot.latestOfficial
        latestProvisionalText = snapshot.provisional
        updateLatestSubtitle(official: snapshot.latestOfficial, provisional: snapshot.provisional)
        updateTranscriptHistory(
            sourceHistory: snapshot.sourceHistory,
            officialHistory: snapshot.officialHistory,
            historyTruncated: snapshot.historyTruncated
        )
    }

    private func updateLatestSubtitle(official: String, provisional: String) {
        let attributed = NSMutableAttributedString()
        if !official.isEmpty {
            attributed.append(NSAttributedString(
                string: official,
                attributes: [
                    .font: NSFont.systemFont(ofSize: subtitleTextSize, weight: .bold),
                    .foregroundColor: NSColor.labelColor
                ]
            ))
        } else if provisional.isEmpty {
            attributed.append(NSAttributedString(
                string: AppText.text(.liveInterpreterWaitingSubtitle),
                attributes: [
                    .font: NSFont.systemFont(ofSize: subtitleTextSize, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ))
        }

        if !provisional.isEmpty {
            if !attributed.string.isEmpty {
                attributed.append(NSAttributedString(string: "\n"))
            }
            attributed.append(NSAttributedString(
                string: "\(AppText.text(.liveProvisionalSubtitle))  \(provisional)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: max(21, subtitleTextSize - 4), weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ))
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        paragraphStyle.paragraphSpacing = 12
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))
        subtitleTextView.textStorage?.setAttributedString(attributed)
        subtitleScrollView.resizeDocumentViewToContentWidth()
        // The focus panel always follows live speech. Review belongs to history.
        subtitleTextView.scrollToEndOfDocument(nil)
        latestSubtitleStateLabel.stringValue = provisional.isEmpty
            ? AppText.text(.liveOfficialSubtitle)
            : AppText.text(.liveProvisionalSubtitle)
        latestSubtitleStateLabel.isHidden = official.isEmpty && provisional.isEmpty
        latestSubtitleStateLabel.textColor = provisional.isEmpty ? .secondaryLabelColor : .controlAccentColor
    }

    private func updateTranscriptHistory(
        sourceHistory: String,
        officialHistory: String,
        historyTruncated: Bool
    ) {
        let selectedHistory = historyShowsTranslation ? officialHistory : sourceHistory
        let renderKey = "\(historyShowsTranslation ? "translation" : "source")|\(historyTruncated)|\(selectedHistory)"
        guard renderKey != renderedHistory else {
            return
        }
        renderedHistory = renderKey
        let wasAtBottom = isHistoryAtLatest
        let previousOrigin = sourceTranscriptScrollView.contentView.bounds.origin
        isUpdatingHistory = true
        defer { isUpdatingHistory = false }
        let attributed = NSMutableAttributedString()
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let sourceAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let officialAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]

        if selectedHistory.isEmpty {
            attributed.append(NSAttributedString(
                string: AppText.text(.liveHistoryEmpty),
                attributes: sourceAttributes
            ))
        } else {
            let heading = historyShowsTranslation
                ? AppText.text(.liveHistoryTranslation)
                : AppText.text(.liveHistorySource)
            let attributes = historyShowsTranslation ? officialAttributes : sourceAttributes
            attributed.append(NSAttributedString(string: "\(heading)\n", attributes: headingAttributes))
            attributed.append(NSAttributedString(string: selectedHistory, attributes: attributes))
            if historyTruncated {
                attributed.append(NSAttributedString(
                    string: "\n\n\(AppText.text(.liveHistoryLimit))",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor.tertiaryLabelColor
                    ]
                ))
            }
        }

        sourceTranscriptTextView.textStorage?.setAttributedString(attributed)
        sourceTranscriptScrollView.resizeDocumentViewToContentWidth()
        if selectedHistory.isEmpty {
            isHistoryAtLatest = true
            hasNewHistory = false
        } else if wasAtBottom {
            sourceTranscriptTextView.scrollToEndOfDocument(nil)
            hasNewHistory = false
        } else if !sourceHistory.isEmpty || !officialHistory.isEmpty {
            hasNewHistory = true
            sourceTranscriptScrollView.contentView.scroll(to: previousOrigin)
            sourceTranscriptScrollView.reflectScrolledClipView(sourceTranscriptScrollView.contentView)
        }
        jumpToLatestButton.isHidden = !isHistoryExpanded || !hasNewHistory
        jumpToLatestButton.title = hasNewHistory
            ? AppText.text(.liveNewHistory)
            : AppText.text(.liveJumpToLatest)
    }

    @objc private func jumpToLatest() {
        isHistoryAtLatest = true
        hasNewHistory = false
        jumpToLatestButton.isHidden = true
        sourceTranscriptTextView.scrollToEndOfDocument(nil)
    }

    @objc private func historyLanguageDidChange() {
        historyShowsTranslation = historyLanguagePicker.selectedSegment == 1
        isHistoryAtLatest = true
        renderedHistory = ""
        updateTranscriptHistory(
            sourceHistory: transcriptSnapshot.sourceHistory,
            officialHistory: transcriptSnapshot.officialHistory,
            historyTruncated: transcriptSnapshot.historyTruncated
        )
    }

    @objc private func historyScrollViewDidScroll() {
        guard !isUpdatingHistory, isHistoryExpanded else { return }
        let isAtBottom = sourceTranscriptScrollView.documentVisibleRect.maxY
            >= sourceTranscriptTextView.bounds.maxY - 24
        isHistoryAtLatest = isAtBottom
        if isAtBottom {
            hasNewHistory = false
            jumpToLatestButton.isHidden = true
        }
    }

    @objc private func toggleSettings() {
        isSettingsExpanded.toggle()
        settingsPane?.isHidden = !isSettingsExpanded
        settingsDisclosureButton.title = isSettingsExpanded
            ? AppText.text(.liveHideSettings)
            : AppText.text(.liveShowSettings)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window?.layoutIfNeeded()
        }
    }

    @objc private func toggleHistory() {
        isHistoryExpanded.toggle()
        historyHeightConstraint?.constant = isHistoryExpanded ? 180 : 0
        historyDisclosureButton.title = isHistoryExpanded
            ? AppText.text(.liveHideHistory)
            : AppText.text(.liveShowHistory)
        sourceTranscriptScrollView.isHidden = !isHistoryExpanded
        jumpToLatestButton.isHidden = !isHistoryExpanded || !hasNewHistory
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func decreaseSubtitleText() {
        subtitleTextSize = max(24, subtitleTextSize - 2)
        updateLatestSubtitle(official: latestOfficialText, provisional: latestProvisionalText)
    }

    @objc private func increaseSubtitleText() {
        subtitleTextSize = min(40, subtitleTextSize + 2)
        updateLatestSubtitle(official: latestOfficialText, provisional: latestProvisionalText)
    }

    private func makeTranscriptPanel() -> NSView {
        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.layer?.borderWidth = 1
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.setContentHuggingPriority(.defaultLow, for: .vertical)
        panel.setContentCompressionResistancePriority(.required, for: .vertical)
        panel.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        let latestPanel = NSView()
        latestPanel.wantsLayer = true
        latestPanel.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        latestPanel.layer?.cornerRadius = 10
        latestPanel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(latestPanel)

        [latestSourceTitleLabel, latestSourceTextLabel, latestSubtitleTitleLabel, latestSubtitleStateLabel, subtitleScrollView].forEach(latestPanel.addSubview)

        let historyHeaderSpacer = NSView()
        historyHeaderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let historyHeader = NSStackView(views: [
            historyTitleLabel,
            historyLanguagePicker,
            historyHeaderSpacer,
            decreaseTextButton,
            increaseTextButton,
            jumpToLatestButton,
            historyDisclosureButton
        ])
        historyHeader.orientation = .horizontal
        historyHeader.alignment = .centerY
        historyHeader.spacing = 8
        historyHeader.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(historyHeader)
        panel.addSubview(sourceTranscriptScrollView)

        latestSourceTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        latestSourceTextLabel.translatesAutoresizingMaskIntoConstraints = false
        latestSubtitleTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        latestSubtitleStateLabel.translatesAutoresizingMaskIntoConstraints = false

        let inset: CGFloat = 16
        let spacing: CGFloat = 7
        NSLayoutConstraint.activate([
            latestPanel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: inset),
            latestPanel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -inset),
            latestPanel.topAnchor.constraint(equalTo: panel.topAnchor, constant: inset),
            latestPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 188),

            latestSourceTitleLabel.leadingAnchor.constraint(equalTo: latestPanel.leadingAnchor, constant: inset),
            latestSourceTitleLabel.trailingAnchor.constraint(equalTo: latestPanel.trailingAnchor, constant: -inset),
            latestSourceTitleLabel.topAnchor.constraint(equalTo: latestPanel.topAnchor, constant: inset),
            latestSourceTextLabel.leadingAnchor.constraint(equalTo: latestSourceTitleLabel.leadingAnchor),
            latestSourceTextLabel.trailingAnchor.constraint(equalTo: latestSourceTitleLabel.trailingAnchor),
            latestSourceTextLabel.topAnchor.constraint(equalTo: latestSourceTitleLabel.bottomAnchor, constant: 4),
            latestSubtitleTitleLabel.leadingAnchor.constraint(equalTo: latestSourceTitleLabel.leadingAnchor),
            latestSubtitleTitleLabel.topAnchor.constraint(equalTo: latestSourceTextLabel.bottomAnchor, constant: 14),
            latestSubtitleStateLabel.leadingAnchor.constraint(equalTo: latestSubtitleTitleLabel.trailingAnchor, constant: 8),
            latestSubtitleStateLabel.centerYAnchor.constraint(equalTo: latestSubtitleTitleLabel.centerYAnchor),
            subtitleScrollView.leadingAnchor.constraint(equalTo: latestSourceTitleLabel.leadingAnchor),
            subtitleScrollView.trailingAnchor.constraint(equalTo: latestSourceTitleLabel.trailingAnchor),
            subtitleScrollView.topAnchor.constraint(equalTo: latestSubtitleTitleLabel.bottomAnchor, constant: spacing),
            subtitleScrollView.bottomAnchor.constraint(equalTo: latestPanel.bottomAnchor, constant: -inset),

            historyHeader.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: inset),
            historyHeader.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -inset),
            historyHeader.topAnchor.constraint(equalTo: latestPanel.bottomAnchor, constant: 14),
            sourceTranscriptScrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: inset),
            sourceTranscriptScrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -inset),
            sourceTranscriptScrollView.topAnchor.constraint(equalTo: historyHeader.bottomAnchor, constant: spacing),
            sourceTranscriptScrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -inset)
        ])

        historyHeightConstraint = sourceTranscriptScrollView.heightAnchor.constraint(equalToConstant: 180)
        historyHeightConstraint?.priority = .defaultLow
        historyHeightConstraint?.isActive = true
        sourceTranscriptScrollView.isHidden = !isHistoryExpanded
        historyHeightConstraint?.constant = isHistoryExpanded ? 180 : 0

        sourceTranscriptScrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyScrollViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: sourceTranscriptScrollView.contentView
        )

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
        cancelStartAndStop()
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
