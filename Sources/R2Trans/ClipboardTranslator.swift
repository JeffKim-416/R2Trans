import AppKit
import ApplicationServices

final class ClipboardTranslator {
    private let translator = OpenAITranslator()
    private let settings = AppSettings.shared
    private var isTranslating = false

    @MainActor
    func translateSelection() async throws -> TranslationOutcome {
        guard !isTranslating else {
            throw R2TransError.alreadyTranslating
        }

        isTranslating = true
        defer { isTranslating = false }

        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        let originalChangeCount = pasteboard.changeCount
        let targetApplication = NSWorkspace.shared.frontmostApplication

        do {
            sendCommandKey(.c)
            let selectedText = try await waitForCopiedText(after: originalChangeCount, pasteboard: pasteboard)
            let translatedText = try await translator.translate(selectedText)

            if settings.confirmBeforeReplace {
                NotificationCenter.default.post(name: .rtTransTranslationReadyForConfirmation, object: nil)

                switch TranslationConfirmationPanel.confirm(translatedText) {
                case .replace:
                    try await paste(translatedText, to: targetApplication, pasteboard: pasteboard)
                    snapshot.restore(to: pasteboard)
                    return .replaced
                case .copy:
                    pasteboard.clearContents()
                    pasteboard.setString(translatedText, forType: .string)
                    return .copied
                case .cancel:
                    snapshot.restore(to: pasteboard)
                    return .cancelled
                }
            }

            try await paste(translatedText, to: targetApplication, pasteboard: pasteboard)
            snapshot.restore(to: pasteboard)
            return .replaced
        } catch {
            snapshot.restore(to: pasteboard)
            throw error
        }
    }

    private func waitForCopiedText(after changeCount: Int, pasteboard: NSPasteboard) async throws -> String {
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 50_000_000)

            if pasteboard.changeCount != changeCount,
               let text = pasteboard.string(forType: .string),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        throw R2TransError.clipboardTextMissing
    }

    private func sendCommandKey(_ key: VirtualKey) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    @MainActor
    private func paste(
        _ translatedText: String,
        to targetApplication: NSRunningApplication?,
        pasteboard: NSPasteboard
    ) async throws {
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)

        if let targetApplication, targetApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApplication.activate(options: [.activateIgnoringOtherApps])
            try await Task.sleep(nanoseconds: 180_000_000)
        }

        sendCommandKey(.v)
        try await Task.sleep(nanoseconds: 450_000_000)
    }
}

extension Notification.Name {
    static let rtTransTranslationReadyForConfirmation = Notification.Name("rtTransTranslationReadyForConfirmation")
}

enum TranslationOutcome {
    case replaced
    case copied
    case cancelled
}

private enum TranslationConfirmationAction {
    case replace
    case copy
    case cancel
}

@MainActor
private enum TranslationConfirmationPanel {
    static func confirm(_ translatedText: String) -> TranslationConfirmationAction {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = AppText.text(.confirmTranslationTitle)
        alert.informativeText = AppText.text(.confirmTranslationMessage)
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppText.text(.replace))
        alert.addButton(withTitle: AppText.text(.copyOnly))
        alert.addButton(withTitle: AppText.text(.cancel))
        alert.accessoryView = makeTextPreview(translatedText)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .copy
        default:
            return .cancel
        }
    }

    private static func makeTextPreview(_ text: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true

        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = .textBackgroundColor

        scrollView.documentView = textView
        return scrollView
    }
}

private struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                result[type] = item.data(forType: type)
            }
        } ?? []

        return ClipboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let restoredItems = items.map { itemData in
            let item = NSPasteboardItem()
            itemData.forEach { type, data in
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}
