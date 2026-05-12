import Carbon
import Foundation

enum HotKeyValidator {
    private static let blockedShortcuts: Set<String> = [
        "command+a",
        "command+c",
        "command+f",
        "command+h",
        "command+m",
        "command+n",
        "command+o",
        "command+p",
        "command+q",
        "command+s",
        "command+t",
        "command+v",
        "command+w",
        "command+x",
        "command+z",
        "shift+command+z",
        "command+=",
        "shift+command+=",
        "command+-",
        "command+0",
        "option+command+=",
        "option+command+-",
        "option+command+8",
        "option+command+esc",
        "command+space",
        "command+tab",
        "shift+command+3",
        "shift+command+4",
        "shift+command+5",
        "control+command+q",
        "control+command+space",
        "control+space",
        "control+option+command+power",
        "shift+command+q"
    ]

    static func validate(_ value: String) throws {
        let hotKey = try HotKeyParser.parse(value)
        let normalizedValue = try HotKeyParser.normalizedString(for: value)

        if blockedShortcuts.contains(normalizedValue) {
            throw R2TransError.invalidHotKey(AppText.text(.shortcutConflictsWithMacOS))
        }

        if modifierCount(in: hotKey.modifiers) < 2 {
            throw R2TransError.invalidHotKey(AppText.text(.shortcutNeedsMoreModifiers))
        }
    }

    private static func modifierCount(in modifiers: UInt32) -> Int {
        [
            UInt32(controlKey),
            UInt32(optionKey),
            UInt32(shiftKey),
            UInt32(cmdKey)
        ].filter { modifiers & $0 != 0 }.count
    }
}
