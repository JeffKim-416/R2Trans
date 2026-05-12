import AppKit
import Carbon
import Foundation

enum VirtualKey: CGKeyCode {
    case a = 0
    case s = 1
    case d = 2
    case f = 3
    case h = 4
    case g = 5
    case z = 6
    case x = 7
    case c = 8
    case v = 9
    case b = 11
    case q = 12
    case w = 13
    case e = 14
    case r = 15
    case y = 16
    case t = 17
    case one = 18
    case two = 19
    case three = 20
    case four = 21
    case six = 22
    case five = 23
    case equal = 24
    case nine = 25
    case seven = 26
    case minus = 27
    case eight = 28
    case zero = 29
    case rightBracket = 30
    case o = 31
    case u = 32
    case leftBracket = 33
    case i = 34
    case p = 35
    case l = 37
    case j = 38
    case quote = 39
    case k = 40
    case semicolon = 41
    case backslash = 42
    case comma = 43
    case slash = 44
    case n = 45
    case m = 46
    case period = 47
    case space = 49
}

enum HotKeyParser {
    static func parse(_ value: String) throws -> HotKey {
        let parts = value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "+")
            .map(String.init)

        guard parts.count >= 2 else {
            throw R2TransError.invalidHotKey(value)
        }

        var modifiers: UInt32 = 0
        var selectedKeyCode: UInt32?

        for part in parts {
            switch part {
            case "cmd", "command":
                modifiers |= UInt32(cmdKey)
            case "option", "opt", "alt":
                modifiers |= UInt32(optionKey)
            case "control", "ctrl":
                modifiers |= UInt32(controlKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            default:
                guard selectedKeyCode == nil, let parsedKeyCode = keyCode(for: part) else {
                    throw R2TransError.invalidHotKey(value)
                }

                selectedKeyCode = UInt32(parsedKeyCode)
            }
        }

        guard let selectedKeyCode, modifiers != 0 else {
            throw R2TransError.invalidHotKey(value)
        }

        return HotKey(keyCode: selectedKeyCode, modifiers: modifiers)
    }

    static func string(for event: NSEvent) throws -> String {
        guard let token = keyToken(for: CGKeyCode(event.keyCode)) else {
            throw R2TransError.invalidHotKey(AppText.text(.unsupportedKey))
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts = modifierTokens(for: flags)

        guard !parts.isEmpty else {
            throw R2TransError.invalidHotKey(AppText.text(.pressModifierAndCharacter))
        }

        parts.append(token)
        let value = parts.joined(separator: "+")
        _ = try parse(value)
        return value
    }

    static func normalizedString(for value: String) throws -> String {
        let hotKey = try parse(value)
        var parts = modifierTokens(for: hotKey.modifiers)

        guard let token = keyToken(for: CGKeyCode(hotKey.keyCode)) else {
            throw R2TransError.invalidHotKey(value)
        }

        parts.append(token)
        return parts.joined(separator: "+")
    }

    static func displayString(for value: String) -> String {
        value
            .split(separator: "+")
            .map { part in
                switch part {
                case "command", "cmd":
                    return "⌘"
                case "control", "ctrl":
                    return "⌃"
                case "option", "opt", "alt":
                    return "⌥"
                case "shift":
                    return "⇧"
                case "space":
                    return "Space"
                default:
                    return part.uppercased()
                }
            }
            .joined(separator: " ")
    }

    private static func keyCode(for token: String) -> CGKeyCode? {
        switch token {
        case "a": return VirtualKey.a.rawValue
        case "b": return VirtualKey.b.rawValue
        case "c": return VirtualKey.c.rawValue
        case "d": return VirtualKey.d.rawValue
        case "e": return VirtualKey.e.rawValue
        case "f": return VirtualKey.f.rawValue
        case "g": return VirtualKey.g.rawValue
        case "h": return VirtualKey.h.rawValue
        case "i": return VirtualKey.i.rawValue
        case "j": return VirtualKey.j.rawValue
        case "k": return VirtualKey.k.rawValue
        case "l": return VirtualKey.l.rawValue
        case "m": return VirtualKey.m.rawValue
        case "n": return VirtualKey.n.rawValue
        case "o": return VirtualKey.o.rawValue
        case "p": return VirtualKey.p.rawValue
        case "q": return VirtualKey.q.rawValue
        case "r": return VirtualKey.r.rawValue
        case "s": return VirtualKey.s.rawValue
        case "t": return VirtualKey.t.rawValue
        case "u": return VirtualKey.u.rawValue
        case "v": return VirtualKey.v.rawValue
        case "w": return VirtualKey.w.rawValue
        case "x": return VirtualKey.x.rawValue
        case "y": return VirtualKey.y.rawValue
        case "z": return VirtualKey.z.rawValue
        case "0": return VirtualKey.zero.rawValue
        case "1": return VirtualKey.one.rawValue
        case "2": return VirtualKey.two.rawValue
        case "3": return VirtualKey.three.rawValue
        case "4": return VirtualKey.four.rawValue
        case "5": return VirtualKey.five.rawValue
        case "6": return VirtualKey.six.rawValue
        case "7": return VirtualKey.seven.rawValue
        case "8": return VirtualKey.eight.rawValue
        case "9": return VirtualKey.nine.rawValue
        case "space": return VirtualKey.space.rawValue
        case "-": return VirtualKey.minus.rawValue
        case "=": return VirtualKey.equal.rawValue
        case "[": return VirtualKey.leftBracket.rawValue
        case "]": return VirtualKey.rightBracket.rawValue
        case "\\": return VirtualKey.backslash.rawValue
        case ";": return VirtualKey.semicolon.rawValue
        case "'": return VirtualKey.quote.rawValue
        case ",": return VirtualKey.comma.rawValue
        case ".": return VirtualKey.period.rawValue
        case "/": return VirtualKey.slash.rawValue
        default: return nil
        }
    }

    private static func modifierTokens(for flags: NSEvent.ModifierFlags) -> [String] {
        var parts: [String] = []

        if flags.contains(.control) {
            parts.append("control")
        }
        if flags.contains(.option) {
            parts.append("option")
        }
        if flags.contains(.shift) {
            parts.append("shift")
        }
        if flags.contains(.command) {
            parts.append("command")
        }

        return parts
    }

    private static func modifierTokens(for modifiers: UInt32) -> [String] {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("control")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("option")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("shift")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("command")
        }

        return parts
    }

    private static func keyToken(for keyCode: CGKeyCode) -> String? {
        switch keyCode {
        case VirtualKey.a.rawValue: return "a"
        case VirtualKey.b.rawValue: return "b"
        case VirtualKey.c.rawValue: return "c"
        case VirtualKey.d.rawValue: return "d"
        case VirtualKey.e.rawValue: return "e"
        case VirtualKey.f.rawValue: return "f"
        case VirtualKey.g.rawValue: return "g"
        case VirtualKey.h.rawValue: return "h"
        case VirtualKey.i.rawValue: return "i"
        case VirtualKey.j.rawValue: return "j"
        case VirtualKey.k.rawValue: return "k"
        case VirtualKey.l.rawValue: return "l"
        case VirtualKey.m.rawValue: return "m"
        case VirtualKey.n.rawValue: return "n"
        case VirtualKey.o.rawValue: return "o"
        case VirtualKey.p.rawValue: return "p"
        case VirtualKey.q.rawValue: return "q"
        case VirtualKey.r.rawValue: return "r"
        case VirtualKey.s.rawValue: return "s"
        case VirtualKey.t.rawValue: return "t"
        case VirtualKey.u.rawValue: return "u"
        case VirtualKey.v.rawValue: return "v"
        case VirtualKey.w.rawValue: return "w"
        case VirtualKey.x.rawValue: return "x"
        case VirtualKey.y.rawValue: return "y"
        case VirtualKey.z.rawValue: return "z"
        case VirtualKey.zero.rawValue: return "0"
        case VirtualKey.one.rawValue: return "1"
        case VirtualKey.two.rawValue: return "2"
        case VirtualKey.three.rawValue: return "3"
        case VirtualKey.four.rawValue: return "4"
        case VirtualKey.five.rawValue: return "5"
        case VirtualKey.six.rawValue: return "6"
        case VirtualKey.seven.rawValue: return "7"
        case VirtualKey.eight.rawValue: return "8"
        case VirtualKey.nine.rawValue: return "9"
        case VirtualKey.space.rawValue: return "space"
        case VirtualKey.minus.rawValue: return "-"
        case VirtualKey.equal.rawValue: return "="
        case VirtualKey.leftBracket.rawValue: return "["
        case VirtualKey.rightBracket.rawValue: return "]"
        case VirtualKey.backslash.rawValue: return "\\"
        case VirtualKey.semicolon.rawValue: return ";"
        case VirtualKey.quote.rawValue: return "'"
        case VirtualKey.comma.rawValue: return ","
        case VirtualKey.period.rawValue: return "."
        case VirtualKey.slash.rawValue: return "/"
        default: return nil
        }
    }
}
