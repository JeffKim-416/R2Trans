import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let windowWidth: CGFloat = 640
        static let windowHeight: CGFloat = 730
        static let labelWidth: CGFloat = 164
        static let controlWidth: CGFloat = 400
        static let rowSpacing: CGFloat = 10
        static let columnSpacing: CGFloat = 16
    }

    private let settings = AppSettings.shared
    private let onSave: () -> Void
    private let onRegisterHotKey: (String) throws -> Void
    private let onAppLanguageChange: () -> Void
    private let onHotKeyRecordingChange: (Bool) -> Void
    private let onLiveInterpreter: () -> Void

    private let apiKeyField = NSSecureTextField()
    private let workModePopup = NSPopUpButton()
    private let sourceLanguagePopup = NSPopUpButton()
    private let targetLanguagePopup = NSPopUpButton()
    private let autoDetectSwitch = NSSwitch()
    private let autoDetectPairPopup = NSPopUpButton()
    private let confirmBeforeReplaceSwitch = NSSwitch()
    private let stylePopup = NSPopUpButton()
    private let hotKeyButton = HotKeyRecorderButton()
    private let modelPopup = NSPopUpButton()
    private let launchAtLoginSwitch = NSSwitch()
    private let showStatusBarSwitch = NSSwitch()
    private let liveInterpreterButton = NSButton()
    private var apiKeyLoadError: Error?

    private let apiKeyLabel = NSTextField(labelWithString: "")
    private let apiKeyLinkLabel = NSTextField(labelWithString: "")
    private let workModeLabel = NSTextField(labelWithString: "")
    private let translationModeLabel = NSTextField(labelWithString: "")
    private let autoDetectLabel = NSTextField(labelWithString: "")
    private let confirmBeforeReplaceLabel = NSTextField(labelWithString: "")
    private let styleLabel = NSTextField(labelWithString: "")
    private let hotKeyLabel = NSTextField(labelWithString: "")
    private let modelLabel = NSTextField(labelWithString: "")
    private let launchAtLoginLabel = NSTextField(labelWithString: "")
    private let showStatusBarLabel = NSTextField(labelWithString: "")
    private let apiKeyLinkButton = NSButton()
    private let pasteButton = NSButton()
    private let saveButton = NSButton()
    private let closeButton = NSButton()
    private let versionLabel = NSTextField(labelWithString: "")
    private let appLanguageButton = NSButton()
    private let titlebarAccessory = NSTitlebarAccessoryViewController()
    private let connectionHeading = NSTextField(labelWithString: "")
    private let translationHeading = NSTextField(labelWithString: "")
    private let optionsHeading = NSTextField(labelWithString: "")
    private let modelHelp = NSTextField(wrappingLabelWithString: "")
    private let directionHelp = NSTextField(wrappingLabelWithString: "")

    init(
        onSave: @escaping () -> Void,
        onRegisterHotKey: @escaping (String) throws -> Void,
        onAppLanguageChange: @escaping () -> Void,
        onHotKeyRecordingChange: @escaping (Bool) -> Void,
        onLiveInterpreter: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onRegisterHotKey = onRegisterHotKey
        self.onAppLanguageChange = onAppLanguageChange
        self.onHotKeyRecordingChange = onHotKeyRecordingChange
        self.onLiveInterpreter = onLiveInterpreter

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()

        super.init(window: window)

        window.delegate = self
        setupTitlebarSettingsButton()
        setupContent()
        refreshLocalizedText()
        reloadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = Layout.rowSpacing
        stackView.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 18, right: 24)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        workModePopup.addItems(withTitles: WorkMode.allCases.map(\.displayName))
        sourceLanguagePopup.addItems(withTitles: SupportedLanguage.all.map(\.displayName))
        targetLanguagePopup.addItems(withTitles: SupportedLanguage.all.map(\.displayName))
        autoDetectPairPopup.addItems(withTitles: AutoDetectPair.allCases.map(\.displayName))
        stylePopup.addItems(withTitles: TranslationStyle.allCases.map(\.displayName))
        modelPopup.addItems(withTitles: SupportedModel.all.map(\.displayName))
        configureCenteredControls()
        configureControlActions()
        hotKeyButton.onHotKeyCaptured = { [weak self] value in
            self?.hotKeyButton.hotKeyString = value
        }
        hotKeyButton.onRecordingStateChange = { [weak self] isRecording in
            self?.onHotKeyRecordingChange(isRecording)
        }

        configureButtons()

        stackView.addArrangedSubview(makeSectionHeading(connectionHeading))
        stackView.addArrangedSubview(makeAPIKeyRow())
        stackView.addArrangedSubview(makeAPIKeyLinkRow())
        stackView.addArrangedSubview(makeSectionHeading(translationHeading))
        stackView.addArrangedSubview(makeWorkModeRow())
        stackView.addArrangedSubview(makeAutoDetectRow())
        stackView.addArrangedSubview(makeLanguageRow())
        stackView.addArrangedSubview(makeHelpRow(directionHelp))
        stackView.addArrangedSubview(makeSwitchRow(label: confirmBeforeReplaceLabel, switchControl: confirmBeforeReplaceSwitch))
        stackView.addArrangedSubview(makeRow(label: styleLabel, control: stylePopup))
        stackView.addArrangedSubview(makeRow(label: hotKeyLabel, control: hotKeyButton))
        stackView.addArrangedSubview(makeRow(label: modelLabel, control: modelPopup))
        stackView.addArrangedSubview(makeHelpRow(modelHelp))
        stackView.addArrangedSubview(makeSectionHeading(optionsHeading))
        stackView.addArrangedSubview(makeLiveInterpreterRow())
        stackView.addArrangedSubview(makeSwitchRow(label: launchAtLoginLabel, switchControl: launchAtLoginSwitch))
        stackView.addArrangedSubview(makeSwitchRow(label: showStatusBarLabel, switchControl: showStatusBarSwitch))
        let buttons = makeButtonRow()
        buttons.widthAnchor.constraint(equalToConstant: Layout.labelWidth + Layout.columnSpacing + Layout.controlWidth).isActive = true
        stackView.addArrangedSubview(buttons)
        stackView.addArrangedSubview(makeVersionRow())

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    private func makeSectionHeading(_ label: NSTextField) -> NSView {
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let line = NSBox()
        line.boxType = .separator
        let row = NSStackView(views: [label, line])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.widthAnchor.constraint(equalToConstant: Layout.labelWidth + Layout.columnSpacing + Layout.controlWidth).isActive = true
        return row
    }

    private func makeHelpRow(_ label: NSTextField) -> NSView {
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return makeRow(label: NSTextField(labelWithString: ""), control: label)
    }

    private func setupTitlebarSettingsButton() {
        appLanguageButton.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: AppText.text(.appLanguage))
        appLanguageButton.bezelStyle = .texturedRounded
        appLanguageButton.isBordered = false
        appLanguageButton.target = self
        appLanguageButton.action = #selector(showAppLanguageMenu)
        appLanguageButton.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 34, height: 28))
        container.addSubview(appLanguageButton)

        NSLayoutConstraint.activate([
            appLanguageButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            appLanguageButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            appLanguageButton.widthAnchor.constraint(equalToConstant: 24),
            appLanguageButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        titlebarAccessory.view = container
        titlebarAccessory.layoutAttribute = .right
        window?.addTitlebarAccessoryViewController(titlebarAccessory)
    }

    private func configureButtons() {
        apiKeyLinkButton.target = self
        apiKeyLinkButton.action = #selector(openAPIKeyPage)
        apiKeyLinkButton.bezelStyle = .rounded
        apiKeyLinkButton.isBordered = true
        apiKeyLinkButton.alignment = .center

        pasteButton.target = self
        pasteButton.action = #selector(pasteAPIKey)
        pasteButton.bezelStyle = .rounded

        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}"

        liveInterpreterButton.target = self
        liveInterpreterButton.action = #selector(openLiveInterpreter)
        liveInterpreterButton.bezelStyle = .rounded
    }

    private func configureControlActions() {
        workModePopup.target = self
        workModePopup.action = #selector(workModeDidChange)
        sourceLanguagePopup.target = self
        sourceLanguagePopup.action = #selector(popupDidChange)
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(popupDidChange)
        autoDetectPairPopup.target = self
        autoDetectPairPopup.action = #selector(popupDidChange)
        stylePopup.target = self
        stylePopup.action = #selector(popupDidChange)
        modelPopup.target = self
        modelPopup.action = #selector(popupDidChange)

        autoDetectSwitch.target = self
        autoDetectSwitch.action = #selector(autoDetectDidChange)
    }

    private func configureCenteredControls() {
        apiKeyField.alignment = .center
        workModePopup.alignment = .center
        sourceLanguagePopup.alignment = .center
        targetLanguagePopup.alignment = .center
        autoDetectPairPopup.alignment = .center
        stylePopup.alignment = .center
        modelPopup.alignment = .center
        hotKeyButton.alignment = .center
    }

    private func refreshLocalizedText() {
        let selectedWorkModeIndex = selectedIndex(
            in: workModePopup,
            count: WorkMode.allCases.count,
            fallback: WorkMode.allCases.firstIndex(of: settings.workMode) ?? 0
        )
        let selectedStyleIndex = selectedIndex(
            in: stylePopup,
            count: TranslationStyle.allCases.count,
            fallback: TranslationStyle.allCases.firstIndex(of: settings.translationStyle) ?? 0
        )

        window?.title = AppText.text(.settingsTitle)
        connectionHeading.stringValue = AppText.text(.openAIAPIKey)
        translationHeading.stringValue = AppText.text(.menuSectionTranslate)
        optionsHeading.stringValue = AppText.text(.menuSectionOptions)
        modelHelp.stringValue = AppText.text(.textModelHelp)
        appLanguageButton.toolTip = AppText.text(.appLanguage)
        appLanguageButton.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: AppText.text(.appLanguage))

        apiKeyLabel.stringValue = AppText.text(.openAIAPIKey)
        apiKeyLinkButton.title = AppText.text(.createAPIKey)
        apiKeyLinkButton.toolTip = AppText.text(.openAIAPIKeyHelp)
        apiKeyLinkLabel.stringValue = ""
        workModeLabel.stringValue = AppText.text(.workMode)
        translationModeLabel.stringValue = AppText.text(.translationMode)
        autoDetectLabel.stringValue = AppText.text(.autoDetect)
        confirmBeforeReplaceLabel.stringValue = AppText.text(.confirmBeforeReplace)
        styleLabel.stringValue = AppText.text(.translationStyle)
        hotKeyLabel.stringValue = AppText.text(.hotkey)
        modelLabel.stringValue = AppText.text(.model)
        launchAtLoginLabel.stringValue = AppText.text(.launchAtLogin)
        showStatusBarLabel.stringValue = AppText.text(.showStatusBarIcon)
        liveInterpreterButton.title = AppText.text(.liveInterpreter)
        pasteButton.title = AppText.text(.paste)
        saveButton.title = AppText.text(.save)
        closeButton.title = AppText.text(.close)
        versionLabel.stringValue = "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")"

        workModePopup.removeAllItems()
        workModePopup.addItems(withTitles: WorkMode.allCases.map(\.displayName))
        workModePopup.selectItem(at: selectedWorkModeIndex)
        stylePopup.removeAllItems()
        stylePopup.addItems(withTitles: TranslationStyle.allCases.map(\.displayName))
        stylePopup.selectItem(at: selectedStyleIndex)
        refreshModeAvailability()
        refreshPopupAlignment()
    }

    private func selectedIndex(in popup: NSPopUpButton, count: Int, fallback: Int) -> Int {
        let index = popup.indexOfSelectedItem
        guard 0..<count ~= index else {
            return fallback
        }

        return index
    }

    private func makeRow(label: NSTextField, control: NSView) -> NSView {
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.columnSpacing
        return row
    }

    private func makeAPIKeyRow() -> NSView {
        apiKeyLabel.alignment = .right
        apiKeyLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true

        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.widthAnchor.constraint(equalToConstant: Layout.controlWidth - 106).isActive = true
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.widthAnchor.constraint(equalToConstant: 98).isActive = true

        let controlStack = NSStackView(views: [apiKeyField, pasteButton])
        controlStack.orientation = .horizontal
        controlStack.alignment = .centerY
        controlStack.spacing = 8
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true

        let row = NSStackView(views: [apiKeyLabel, controlStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.columnSpacing
        return row
    }

    private func makeAPIKeyLinkRow() -> NSView {
        apiKeyLinkLabel.alignment = .right
        apiKeyLinkLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true

        apiKeyLinkButton.translatesAutoresizingMaskIntoConstraints = false
        apiKeyLinkButton.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true
        apiKeyLinkButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let row = NSStackView(views: [apiKeyLinkLabel, apiKeyLinkButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.columnSpacing
        return row
    }

    private func makeWorkModeRow() -> NSView {
        workModeLabel.alignment = .right
        workModeLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true

        workModePopup.translatesAutoresizingMaskIntoConstraints = false
        workModePopup.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true

        let row = NSStackView(views: [workModeLabel, workModePopup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.columnSpacing
        return row
    }

    private func makeLanguageRow() -> NSView {
        translationModeLabel.alignment = .right
        translationModeLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true

        let arrowLabel = NSTextField(labelWithString: "→")
        arrowLabel.alignment = .center
        arrowLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true

        sourceLanguagePopup.translatesAutoresizingMaskIntoConstraints = false
        targetLanguagePopup.translatesAutoresizingMaskIntoConstraints = false
        sourceLanguagePopup.widthAnchor.constraint(equalToConstant: (Layout.controlWidth - 36) / 2).isActive = true
        targetLanguagePopup.widthAnchor.constraint(equalToConstant: (Layout.controlWidth - 36) / 2).isActive = true

        let controlStack = NSStackView(views: [sourceLanguagePopup, arrowLabel, targetLanguagePopup])
        controlStack.orientation = .horizontal
        controlStack.alignment = .centerY
        controlStack.spacing = 4
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true

        let row = NSStackView(views: [translationModeLabel, controlStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.columnSpacing
        return row
    }

    private func makeAutoDetectRow() -> NSView {
        autoDetectLabel.alignment = .right
        autoDetectLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true

        autoDetectSwitch.translatesAutoresizingMaskIntoConstraints = false
        autoDetectSwitch.widthAnchor.constraint(equalToConstant: 46).isActive = true
        autoDetectPairPopup.translatesAutoresizingMaskIntoConstraints = false
        autoDetectPairPopup.widthAnchor.constraint(equalToConstant: Layout.controlWidth - 54).isActive = true

        let controlStack = NSStackView(views: [autoDetectSwitch, autoDetectPairPopup])
        controlStack.orientation = .horizontal
        controlStack.alignment = .centerY
        controlStack.spacing = 8
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true

        let row = NSStackView(views: [autoDetectLabel, controlStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.columnSpacing
        return row
    }

    private func makeSwitchRow(label: NSTextField, switchControl: NSSwitch) -> NSView {
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        switchControl.translatesAutoresizingMaskIntoConstraints = false
        switchControl.widthAnchor.constraint(equalToConstant: 46).isActive = true

        let controlStack = NSStackView(views: [switchControl, spacer])
        controlStack.orientation = .horizontal
        controlStack.alignment = .centerY
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true

        let row = NSStackView(views: [label, controlStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.columnSpacing
        return row
    }

    private func makeLiveInterpreterRow() -> NSView {
        let label = NSTextField(labelWithString: "")
        label.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true

        liveInterpreterButton.translatesAutoresizingMaskIntoConstraints = false
        liveInterpreterButton.widthAnchor.constraint(equalToConstant: Layout.controlWidth).isActive = true
        liveInterpreterButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let row = NSStackView(views: [label, liveInterpreterButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.columnSpacing
        return row
    }

    private func makeButtonRow() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [spacer, closeButton, saveButton])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func makeVersionRow() -> NSView {
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .right
        versionLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth + Layout.columnSpacing + Layout.controlWidth).isActive = true
        return versionLabel
    }

    func reloadValues() {
        do {
            apiKeyField.stringValue = try KeychainStore.loadAPIKeyOrThrow()
            apiKeyLoadError = nil
        } catch {
            apiKeyField.stringValue = ""
            apiKeyLoadError = error
            showSettingsError(error)
        }
        hotKeyButton.hotKeyString = settings.hotKeyString
        modelPopup.selectItem(withTitle: SupportedModel.displayName(for: settings.model))
        reloadOptionControls()
    }

    func reloadOptionControls() {
        workModePopup.selectItem(withTitle: settings.workMode.displayName)
        sourceLanguagePopup.selectItem(withTitle: SupportedLanguage.displayName(for: settings.sourceLanguageCode))
        targetLanguagePopup.selectItem(withTitle: SupportedLanguage.displayName(for: settings.targetLanguageCode))
        autoDetectSwitch.state = settings.autoDetectEnabled ? .on : .off
        autoDetectPairPopup.selectItem(withTitle: settings.autoDetectPair.displayName)
        confirmBeforeReplaceSwitch.state = settings.confirmBeforeReplace ? .on : .off
        stylePopup.selectItem(withTitle: settings.translationStyle.displayName)
        launchAtLoginSwitch.state = LaunchAtLoginManager.isEnabled ? .on : .off
        showStatusBarSwitch.state = settings.showStatusBarIcon ? .on : .off
        refreshModeAvailability()
        refreshPopupAlignment()
    }

    @objc private func save() {
        let previousHotKeyString = settings.hotKeyString
        let previousLaunchAtLoginEnabled = LaunchAtLoginManager.isEnabled
        var didRegisterHotKey = false
        var didChangeLaunchAtLogin = false

        do {
            if apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let apiKeyLoadError {
                throw apiKeyLoadError
            }

            try HotKeyValidator.validate(hotKeyButton.hotKeyString)

            let selectedWorkMode = WorkMode.allCases[workModePopup.indexOfSelectedItem]
            let selectedSourceLanguage = SupportedLanguage.all[sourceLanguagePopup.indexOfSelectedItem]
            let selectedTargetLanguage = SupportedLanguage.all[targetLanguagePopup.indexOfSelectedItem]
            let selectedAutoDetectPair = AutoDetectPair.allCases[autoDetectPairPopup.indexOfSelectedItem]
            let selectedStyle = TranslationStyle.allCases[stylePopup.indexOfSelectedItem]
            let selectedModel = SupportedModel.all[modelPopup.indexOfSelectedItem]
            try onRegisterHotKey(hotKeyButton.hotKeyString)
            didRegisterHotKey = true

            let requestedLaunchAtLoginEnabled = launchAtLoginSwitch.state == .on
            if requestedLaunchAtLoginEnabled != previousLaunchAtLoginEnabled {
                didChangeLaunchAtLogin = true
                try LaunchAtLoginManager.setEnabled(requestedLaunchAtLoginEnabled)
            }

            try KeychainStore.saveAPIKey(apiKeyField.stringValue)
            apiKeyLoadError = nil

            settings.workMode = selectedWorkMode
            settings.sourceLanguageCode = selectedSourceLanguage.code
            settings.targetLanguageCode = selectedTargetLanguage.code
            settings.autoDetectEnabled = autoDetectSwitch.state == .on
            settings.autoDetectPair = selectedAutoDetectPair
            settings.confirmBeforeReplace = confirmBeforeReplaceSwitch.state == .on
            settings.translationStyle = selectedStyle
            settings.hotKeyString = hotKeyButton.hotKeyString
            settings.model = selectedModel.id
            settings.showStatusBarIcon = showStatusBarSwitch.state == .on
            refreshPopupAlignment()
            onSave()
            close()
        } catch {
            var rollbackErrors: [Error] = []

            if didChangeLaunchAtLogin {
                do {
                    try LaunchAtLoginManager.setEnabled(previousLaunchAtLoginEnabled)
                    launchAtLoginSwitch.state = previousLaunchAtLoginEnabled ? .on : .off
                } catch {
                    rollbackErrors.append(error)
                }
            }

            if didRegisterHotKey {
                do {
                    try onRegisterHotKey(previousHotKeyString)
                } catch {
                    rollbackErrors.append(error)
                }
            }

            let rollbackMessage = rollbackErrors.isEmpty
                ? error.localizedDescription
                : ([error.localizedDescription, "", "Rollback errors:"] + rollbackErrors.map(\.localizedDescription)).joined(separator: "\n")
            showSettingsErrorMessage(rollbackMessage)
        }
    }

    private func showSettingsError(_ error: Error) {
        showSettingsErrorMessage(error.localizedDescription)
    }

    private func showSettingsErrorMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = AppText.text(.settingsError)
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func closeWindow() {
        close()
    }

    @objc private func pasteAPIKey() {
        apiKeyField.stringValue = NSPasteboard.general.string(forType: .string) ?? ""
    }

    @objc private func openAPIKeyPage() {
        guard let url = URL(string: "https://platform.openai.com/api-keys") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc private func openLiveInterpreter() {
        onLiveInterpreter()
    }

    @objc private func popupDidChange() {
        refreshPopupAlignment()
    }

    @objc private func workModeDidChange() {
        refreshModeAvailability()
        refreshPopupAlignment()
    }

    @objc private func autoDetectDidChange() {
        refreshModeAvailability()
        refreshPopupAlignment()
    }

    private func refreshModeAvailability() {
        let selectedWorkMode = WorkMode.allCases[workModePopup.indexOfSelectedItem]
        let isTranslationMode = selectedWorkMode == .translation
        let autoDetectEnabled = autoDetectSwitch.state == .on
        directionHelp.stringValue = AppText.text(isTranslationMode
            ? (autoDetectEnabled ? .autoDirectionHelp : .fixedDirectionHelp)
            : .rewriteDirectionHelp)
        sourceLanguagePopup.isEnabled = isTranslationMode && !autoDetectEnabled
        targetLanguagePopup.isEnabled = isTranslationMode && !autoDetectEnabled
        autoDetectSwitch.isEnabled = isTranslationMode
        autoDetectPairPopup.isEnabled = isTranslationMode && autoDetectEnabled
    }

    private func refreshPopupAlignment() {
        centerSelectedTitle(in: workModePopup)
        centerSelectedTitle(in: sourceLanguagePopup)
        centerSelectedTitle(in: targetLanguagePopup)
        centerSelectedTitle(in: autoDetectPairPopup)
        centerSelectedTitle(in: stylePopup)
        centerSelectedTitle(in: modelPopup)
    }

    private func centerSelectedTitle(in popup: NSPopUpButton) {
        guard let title = popup.selectedItem?.title else {
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        popup.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .paragraphStyle: paragraphStyle,
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
        )
    }

    @objc private func showAppLanguageMenu() {
        let menu = NSMenu()

        for language in AppLanguage.allCases {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(setAppLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            item.state = settings.appLanguage == language ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: appLanguageButton.bounds.height + 2), in: appLanguageButton)
    }

    @objc private func setAppLanguage(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let appLanguage = AppLanguage(rawValue: rawValue)
        else {
            return
        }

        settings.appLanguage = appLanguage
        refreshLocalizedText()
        onAppLanguageChange()
    }

    func windowWillClose(_ notification: Notification) {
        hotKeyButton.cancelRecordingIfNeeded()
    }
}

final class HotKeyRecorderButton: NSButton {
    var onHotKeyCaptured: ((String) -> Void)?
    var onRecordingStateChange: ((Bool) -> Void)?

    var hotKeyString: String = "control+option+t" {
        didSet {
            title = HotKeyParser.displayString(for: hotKeyString)
            alignment = .center
        }
    }

    private var isRecording = false
    private var previousHotKeyString = "control+option+t"

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        alignment = .center
        title = HotKeyParser.displayString(for: hotKeyString)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }

        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            cancelRecording()
            return
        }

        do {
            let capturedHotKey = try HotKeyParser.string(for: event)
            try HotKeyValidator.validate(capturedHotKey)
            hotKeyString = capturedHotKey
            onHotKeyCaptured?(capturedHotKey)
            stopRecording()
        } catch {
            NSSound.beep()
            title = error.localizedDescription
            toolTip = error.localizedDescription
        }
    }

    private func beginRecording() {
        guard !isRecording else {
            return
        }

        previousHotKeyString = hotKeyString
        isRecording = true
        title = AppText.text(.pressShortcut)
        toolTip = nil
        onRecordingStateChange?(true)
        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        guard isRecording else {
            return
        }

        isRecording = false
        onRecordingStateChange?(false)
        window?.makeFirstResponder(nil)
    }

    private func cancelRecording() {
        hotKeyString = previousHotKeyString
        stopRecording()
    }

    func cancelRecordingIfNeeded() {
        guard isRecording else {
            return
        }

        cancelRecording()
    }
}
