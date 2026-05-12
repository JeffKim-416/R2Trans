import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let translator = ClipboardTranslator()
    private let hotKeyManager = HotKeyManager()
    private var settingsWindowController: SettingsWindowController?
    private var progressWindowController: TranslationProgressWindowController?
    private var liveInterpreterWindowController: LiveInterpreterWindowController?
    private var statusItem: NSStatusItem?
    private weak var autoPairMenuItem: NSMenuItem?
    private weak var sourceLanguageMenuItem: NSMenuItem?
    private weak var targetLanguageMenuItem: NSMenuItem?
    private weak var styleMenuItem: NSMenuItem?
    private weak var workModeMenuItem: NSMenuItem?
    private weak var autoDetectMenuItem: NSMenuItem?
    private weak var confirmBeforeReplaceMenuItem: NSMenuItem?
    private var statusResetTask: Task<Void, Never>?
    private var isRecordingHotKey = false
    private var openAIAPIKeyURL: URL {
        URL(string: "https://platform.openai.com/api-keys")!
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        refreshStatusItemVisibility()
        registerHotKey()
        try? requestAccessibilityIfNeeded(prompt: false)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(translationReadyForConfirmation),
            name: .rtTransTranslationReadyForConfirmation,
            object: nil
        )
        openSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "R2Trans")
        let liveInterpreterItem = NSMenuItem(
            title: AppText.text(.liveInterpreter),
            action: #selector(openLiveInterpreterFromMenu),
            keyEquivalent: "i"
        )
        liveInterpreterItem.target = self
        appMenu.addItem(liveInterpreterItem)

        let settingsItem = NSMenuItem(
            title: AppText.text(.settings),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: AppText.text(.quitR2Trans), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: AppText.text(.edit))
        editMenu.addItem(withTitle: AppText.text(.cut), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: AppText.text(.copy), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: AppText.text(.paste), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: AppText.text(.selectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        if statusItem != nil {
            restoreStatusIcon()
            rebuildMenu()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: 30)
        statusItem = item
        restoreStatusIcon()
        rebuildMenu()
    }

    private func refreshStatusItemVisibility() {
        if settings.showStatusBarIcon {
            setupStatusItem()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(makeSectionHeader(AppText.text(.menuSectionMode)))

        let workModeItem = makeWorkModeMenuItem()
        workModeMenuItem = workModeItem
        menu.addItem(configureMenuItem(workModeItem, indentationLevel: 1))

        let isTranslationMode = settings.workMode == .translation

        let autoDetectItem = makeToggleMenuItem(
            title: AppText.text(.autoDetect),
            isOn: settings.autoDetectEnabled,
            action: #selector(toggleAutoDetect)
        )
        autoDetectItem.isEnabled = isTranslationMode
        autoDetectMenuItem = autoDetectItem
        menu.addItem(autoDetectItem)

        let autoPairItem = makeAutoPairMenuItem()
        autoPairItem.isEnabled = isTranslationMode && settings.autoDetectEnabled
        autoPairMenuItem = autoPairItem
        menu.addItem(configureMenuItem(autoPairItem, indentationLevel: 1))

        let sourceLanguageItem = makeLanguageMenuItem(
            title: "\(AppText.text(.sourceLanguage)): \(settings.sourceLanguageCode)",
            selectedCode: settings.sourceLanguageCode,
            action: #selector(selectSourceLanguage(_:))
        )
        sourceLanguageItem.isEnabled = isTranslationMode && !settings.autoDetectEnabled
        sourceLanguageMenuItem = sourceLanguageItem
        menu.addItem(configureMenuItem(sourceLanguageItem, indentationLevel: 1))

        let targetLanguageItem = makeLanguageMenuItem(
            title: "\(AppText.text(.targetLanguage)): \(settings.targetLanguageCode)",
            selectedCode: settings.targetLanguageCode,
            action: #selector(selectTargetLanguage(_:))
        )
        targetLanguageItem.isEnabled = isTranslationMode && !settings.autoDetectEnabled
        targetLanguageMenuItem = targetLanguageItem
        menu.addItem(configureMenuItem(targetLanguageItem, indentationLevel: 1))

        menu.addItem(configureMenuItem(makeStyleMenuItem(), indentationLevel: 1))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeSectionHeader(AppText.text(.menuSectionOptions)))

        let confirmItem = makeToggleMenuItem(
            title: AppText.text(.confirmBeforeReplace),
            isOn: settings.confirmBeforeReplace,
            action: #selector(toggleConfirmBeforeReplace)
        )
        confirmBeforeReplaceMenuItem = confirmItem
        menu.addItem(confirmItem)

        menu.addItem(makeLiveInterpreterMenuItem())
        menu.addItem(makeSettingsMenuItem())

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: AppText.text(.quitR2Trans),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func makeSectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }

    private func configureMenuItem(_ item: NSMenuItem, indentationLevel: Int) -> NSMenuItem {
        item.indentationLevel = indentationLevel
        return item
    }

    private func makeWorkModeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(AppText.text(.workMode)): \(settings.workMode.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()

        for workMode in WorkMode.allCases {
            let modeItem = NSMenuItem(
                title: workMode.displayName,
                action: #selector(selectWorkMode(_:)),
                keyEquivalent: ""
            )
            modeItem.target = self
            modeItem.representedObject = workMode.rawValue
            modeItem.state = settings.workMode == workMode ? .on : .off
            submenu.addItem(modeItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeToggleMenuItem(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        return configureMenuItem(item, indentationLevel: 1)
    }

    private func makeSettingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: settingsMenuText(), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        item.target = self
        return configureMenuItem(item, indentationLevel: 1)
    }

    private func makeLiveInterpreterMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: AppText.text(.liveInterpreter), action: #selector(openLiveInterpreterFromMenu), keyEquivalent: "i")
        item.target = self
        return configureMenuItem(item, indentationLevel: 1)
    }

    private func settingsMenuText() -> String {
        AppText.text(.settings)
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: "…", with: "")
    }
    private func makeAutoPairMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(AppText.text(.autoDetectPair)): \(settings.autoDetectPair.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()

        for pair in AutoDetectPair.allCases {
            let pairItem = NSMenuItem(
                title: pair.displayName,
                action: #selector(selectAutoDetectPair(_:)),
                keyEquivalent: ""
            )
            pairItem.target = self
            pairItem.representedObject = pair.rawValue
            pairItem.state = settings.autoDetectPair == pair ? .on : .off
            submenu.addItem(pairItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeLanguageMenuItem(title: String, selectedCode: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for language in SupportedLanguage.all {
            let languageItem = NSMenuItem(
                title: language.displayName,
                action: action,
                keyEquivalent: ""
            )
            languageItem.target = self
            languageItem.representedObject = language.code
            languageItem.state = language.code == selectedCode ? .on : .off
            submenu.addItem(languageItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeStyleMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(AppText.text(.translationStyle)): \(settings.translationStyle.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()

        for style in TranslationStyle.allCases {
            let styleItem = NSMenuItem(
                title: style.displayName,
                action: #selector(selectTranslationStyle(_:)),
                keyEquivalent: ""
            )
            styleItem.target = self
            styleItem.representedObject = style.rawValue
            styleItem.state = settings.translationStyle == style ? .on : .off
            submenu.addItem(styleItem)
        }

        item.submenu = submenu
        return item
    }

    private func registerHotKey(shouldShowError: Bool = true) {
        hotKeyManager.unregister()

        do {
            try HotKeyValidator.validate(settings.hotKeyString)
            let hotKey = try HotKeyParser.parse(settings.hotKeyString)
            try hotKeyManager.register(hotKey: hotKey) { [weak self] in
                guard self?.isRecordingHotKey == false else {
                    return
                }

                self?.translateSelectedText()
            }
        } catch {
            if shouldShowError {
                showError(AppText.text(.hotkeyError), message: error.localizedDescription)
            }
        }
    }

    @objc private func translateSelectedText() {
        Task { @MainActor in
            setStatus("...")
            showTranslationProgress()

            do {
                try requestAccessibilityIfNeeded(prompt: true)
                let outcome = try await translator.translateSelection()
                hideTranslationProgress()
                switch outcome {
                case .replaced:
                    setStatus("OK")
                case .copied:
                    setStatus("Copy")
                case .cancelled:
                    setStatus("Cancel")
                }
            } catch {
                hideTranslationProgress()

                if case R2TransError.alreadyTranslating = error {
                    return
                }

                setStatus("!")

                if case R2TransError.apiKeyMissing = error {
                    showError(
                        "R2Trans",
                        message: error.localizedDescription,
                        actionButtonTitle: AppText.text(.createAPIKey),
                        actionURL: openAIAPIKeyURL
                    )
                } else {
                    showError("R2Trans", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func translationReadyForConfirmation() {
        hideTranslationProgress()
    }

    @objc private func selectWorkMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let workMode = WorkMode(rawValue: rawValue)
        else {
            return
        }

        settings.workMode = workMode
        refreshAfterQuickSettingsChange()
    }

    @objc private func toggleAutoDetect() {
        guard settings.workMode == .translation else {
            refreshOpenMenuItems()
            return
        }

        settings.autoDetectEnabled.toggle()
        refreshAfterQuickSettingsChange()
    }

    @objc private func selectAutoDetectPair(_ sender: NSMenuItem) {
        guard settings.workMode == .translation, settings.autoDetectEnabled else {
            refreshOpenMenuItems()
            return
        }

        guard
            let rawValue = sender.representedObject as? String,
            let pair = AutoDetectPair(rawValue: rawValue)
        else {
            return
        }

        settings.autoDetectPair = pair
        refreshAfterQuickSettingsChange()
    }

    @objc private func selectSourceLanguage(_ sender: NSMenuItem) {
        guard settings.workMode == .translation, !settings.autoDetectEnabled else {
            refreshOpenMenuItems()
            return
        }

        guard let code = sender.representedObject as? String else {
            return
        }

        settings.sourceLanguageCode = code
        refreshAfterQuickSettingsChange()
    }

    @objc private func selectTargetLanguage(_ sender: NSMenuItem) {
        guard settings.workMode == .translation, !settings.autoDetectEnabled else {
            refreshOpenMenuItems()
            return
        }

        guard let code = sender.representedObject as? String else {
            return
        }

        settings.targetLanguageCode = code
        refreshAfterQuickSettingsChange()
    }

    @objc private func toggleConfirmBeforeReplace() {
        settings.confirmBeforeReplace.toggle()
        refreshAfterQuickSettingsChange()
    }

    @objc private func selectTranslationStyle(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let style = TranslationStyle(rawValue: rawValue)
        else {
            return
        }

        settings.translationStyle = style
        refreshAfterQuickSettingsChange()
    }

    private func refreshAfterQuickSettingsChange() {
        refreshOpenMenuItems()
        settingsWindowController?.reloadOptionControls()
    }

    private func refreshOpenMenuItems() {
        let isTranslationMode = settings.workMode == .translation
        workModeMenuItem?.title = "\(AppText.text(.workMode)): \(settings.workMode.displayName)"
        autoDetectMenuItem?.state = settings.autoDetectEnabled ? .on : .off
        autoDetectMenuItem?.isEnabled = isTranslationMode
        confirmBeforeReplaceMenuItem?.state = settings.confirmBeforeReplace ? .on : .off
        autoPairMenuItem?.title = "\(AppText.text(.autoDetectPair)): \(settings.autoDetectPair.displayName)"
        autoPairMenuItem?.isEnabled = isTranslationMode && settings.autoDetectEnabled
        sourceLanguageMenuItem?.title = "\(AppText.text(.sourceLanguage)): \(settings.sourceLanguageCode)"
        sourceLanguageMenuItem?.isEnabled = isTranslationMode && !settings.autoDetectEnabled
        targetLanguageMenuItem?.title = "\(AppText.text(.targetLanguage)): \(settings.targetLanguageCode)"
        targetLanguageMenuItem?.isEnabled = isTranslationMode && !settings.autoDetectEnabled
    }

    @objc private func openSettingsFromMenu() {
        statusItem?.menu?.cancelTracking()
        openSettings()
    }

    @objc private func openLiveInterpreterFromMenu() {
        statusItem?.menu?.cancelTracking()
        openLiveInterpreter()
    }

    @objc private func openLiveInterpreter() {
        if liveInterpreterWindowController == nil {
            liveInterpreterWindowController = LiveInterpreterWindowController()
        }

        NSApp.activate(ignoringOtherApps: true)
        liveInterpreterWindowController?.showWindow(nil)
        liveInterpreterWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                onSave: { [weak self] in
                    self?.setupMainMenu()
                    self?.refreshStatusItemVisibility()
                    self?.registerHotKey()
                    self?.rebuildMenu()
                    self?.settingsWindowController = nil
                },
                onAppLanguageChange: { [weak self] in
                    self?.setupMainMenu()
                    self?.rebuildMenu()
                },
                onHotKeyRecordingChange: { [weak self] isRecording in
                    self?.isRecordingHotKey = isRecording

                    if isRecording {
                        self?.hotKeyManager.unregister()
                    } else {
                        self?.registerHotKey(shouldShowError: false)
                    }
                },
                onLiveInterpreter: { [weak self] in
                    self?.openLiveInterpreter()
                }
            )
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func requestAccessibilityIfNeeded(prompt: Bool) throws {
        if AXIsProcessTrusted() {
            return
        }

        if prompt {
            let key = "AXTrustedCheckOptionPrompt"
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }

        throw R2TransError.accessibilityPermissionRequired(Bundle.main.bundlePath)
    }

    private func setStatus(_ text: String) {
        statusResetTask?.cancel()
        statusItem?.length = 44
        statusItem?.button?.image = nil
        statusItem?.button?.title = text
        statusItem?.button?.attributedTitle = statusTitle(text, size: 11)

        statusResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            restoreStatusIcon()
        }
    }

    private func restoreStatusIcon() {
        statusItem?.length = 30
        statusItem?.button?.image = nil
        statusItem?.button?.title = "RT"
        statusItem?.button?.attributedTitle = statusTitle("RT", size: 11)
        statusItem?.button?.toolTip = "R2Trans"
    }

    private func showTranslationProgress() {
        if progressWindowController == nil {
            progressWindowController = TranslationProgressWindowController()
        }

        progressWindowController?.showProgress()
    }

    private func hideTranslationProgress() {
        progressWindowController?.hideProgress()
    }

    private func statusTitle(_ text: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: size),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private func showError(
        _ title: String,
        message: String,
        actionButtonTitle: String? = nil,
        actionURL: URL? = nil
    ) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning

        alert.addButton(withTitle: AppText.text(.ok))
        if let actionButtonTitle {
            alert.addButton(withTitle: actionButtonTitle)
        }

        let response = alert.runModal()
        if response == .alertSecondButtonReturn, let actionURL {
            NSWorkspace.shared.open(actionURL)
        }
    }
}
