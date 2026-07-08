import Foundation

struct SupportedLanguage: Equatable {
    let code: String
    let name: String

    var displayName: String {
        code
    }

    static let all: [SupportedLanguage] = [
        SupportedLanguage(code: "en-US", name: "English"),
        SupportedLanguage(code: "ko-KR", name: "Korean"),
        SupportedLanguage(code: "es-ES", name: "Spanish"),
        SupportedLanguage(code: "ja-JP", name: "Japanese"),
        SupportedLanguage(code: "zh-CN", name: "Chinese")
    ]

    static let defaultSourceCode = "ko-KR"
    static let defaultTargetCode = "en-US"

    static func language(for code: String) -> SupportedLanguage {
        all.first { $0.code == normalizedCode(code, fallback: defaultTargetCode) } ?? all[0]
    }

    static func displayName(for code: String) -> String {
        language(for: code).displayName
    }

    static func englishName(for code: String) -> String {
        language(for: code).name
    }

    static func normalizedCode(_ code: String, fallback: String) -> String {
        let normalized = code.lowercased()
        let aliases = [
            "en": "en-US",
            "en-us": "en-US",
            "ko": "ko-KR",
            "kr": "ko-KR",
            "ko-kr": "ko-KR",
            "es": "es-ES",
            "sp": "es-ES",
            "es-es": "es-ES",
            "ja": "ja-JP",
            "jp": "ja-JP",
            "ja-jp": "ja-JP",
            "zh": "zh-CN",
            "cn": "zh-CN",
            "zh-cn": "zh-CN"
        ]

        let resolved = aliases[normalized] ?? normalized
        return all.contains { $0.code == resolved } ? resolved : fallback
    }
}

struct SupportedModel: Equatable {
    let id: String
    let displayName: String

    static let all: [SupportedModel] = [
        SupportedModel(id: "gpt-5.5", displayName: "GPT-5.5 - latest highest quality"),
        SupportedModel(id: "gpt-5.4", displayName: "GPT-5.4 - balanced"),
        SupportedModel(id: "gpt-5.4-mini", displayName: "GPT-5.4 mini - fast and efficient"),
        SupportedModel(id: "gpt-5.4-nano", displayName: "GPT-5.4 nano - lowest cost")
    ]

    static let defaultID = "gpt-5.4-nano"

    static func displayName(for id: String) -> String {
        all.first { $0.id == normalizedID(id) }?.displayName ?? id
    }

    static func normalizedID(_ id: String) -> String {
        let aliases = [
            "gpt-5.2": "gpt-5.5",
            "gpt-5.3-codex": "gpt-5.5"
        ]

        return aliases[id] ?? id
    }
}

enum AppLanguage: String, CaseIterable {
    case english
    case korean
    case japanese
    case chinese

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .korean:
            return "Korean"
        case .japanese:
            return "Japanese"
        case .chinese:
            return "Chinese"
        }
    }
}

enum AutoDetectPair: String, CaseIterable {
    case koreanEnglish = "ko-KR <-> en-US"
    case koreanJapanese = "ko-KR <-> ja-JP"

    static let defaultValue = AutoDetectPair.koreanEnglish

    var displayName: String {
        rawValue
    }

    var firstLanguageCode: String {
        switch self {
        case .koreanEnglish, .koreanJapanese:
            return "ko-KR"
        }
    }

    var secondLanguageCode: String {
        switch self {
        case .koreanEnglish:
            return "en-US"
        case .koreanJapanese:
            return "ja-JP"
        }
    }
}

enum TranslationStyle: String, CaseIterable {
    case natural
    case formal
    case polite
    case groveling
    case nyang

    static let defaultValue = TranslationStyle.natural

    var displayName: String {
        switch self {
        case .natural:
            return AppText.text(.styleNatural)
        case .formal:
            return AppText.text(.styleFormal)
        case .polite:
            return AppText.text(.stylePolite)
        case .groveling:
            return AppText.text(.styleGroveling)
        case .nyang:
            return AppText.text(.styleNyang)
        }
    }
}

enum WorkMode: String, CaseIterable {
    case translation
    case rewrite

    static let defaultValue = WorkMode.translation

    var displayName: String {
        switch self {
        case .translation:
            return AppText.text(.multilingualTranslationMode)
        case .rewrite:
            return AppText.text(.sameLanguageRewriteMode)
        }
    }
}

final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let mode = "mode"
        static let sourceLanguageCode = "sourceLanguageCode"
        static let targetLanguageCode = "targetLanguageCode"
        static let appLanguage = "appLanguage"
        static let hotKeyString = "hotKeyString"
        static let model = "model"
        static let autoDetectEnabled = "autoDetectEnabled"
        static let autoDetectPair = "autoDetectPair"
        static let confirmBeforeReplace = "confirmBeforeReplace"
        static let translationStyle = "translationStyle"
        static let showStatusBarIcon = "showStatusBarIcon"
        static let workMode = "workMode"
    }

    var sourceLanguageCode: String {
        get {
            let migratedCode = migratedLanguageCodesIfNeeded().source
            let storedCode = defaults.string(forKey: Key.sourceLanguageCode) ?? migratedCode
            return SupportedLanguage.normalizedCode(storedCode, fallback: SupportedLanguage.defaultSourceCode)
        }
        set {
            let normalizedValue = SupportedLanguage.normalizedCode(newValue, fallback: SupportedLanguage.defaultSourceCode)
            defaults.set(normalizedValue, forKey: Key.sourceLanguageCode)
        }
    }

    var targetLanguageCode: String {
        get {
            let migratedCode = migratedLanguageCodesIfNeeded().target
            let storedCode = defaults.string(forKey: Key.targetLanguageCode) ?? migratedCode
            return SupportedLanguage.normalizedCode(storedCode, fallback: SupportedLanguage.defaultTargetCode)
        }
        set {
            let normalizedValue = SupportedLanguage.normalizedCode(newValue, fallback: SupportedLanguage.defaultTargetCode)
            defaults.set(normalizedValue, forKey: Key.targetLanguageCode)
        }
    }

    var hotKeyString: String {
        get {
            defaults.string(forKey: Key.hotKeyString) ?? "control+option+t"
        }
        set {
            defaults.set(newValue, forKey: Key.hotKeyString)
        }
    }

    var appLanguage: AppLanguage {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.appLanguage),
                let appLanguage = AppLanguage(rawValue: rawValue)
            else {
                return .english
            }

            return appLanguage
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appLanguage)
        }
    }

    var model: String {
        get {
            let storedModel = SupportedModel.normalizedID(defaults.string(forKey: Key.model) ?? SupportedModel.defaultID)
            return SupportedModel.all.contains { $0.id == storedModel } ? storedModel : SupportedModel.defaultID
        }
        set {
            defaults.set(SupportedModel.normalizedID(newValue), forKey: Key.model)
        }
    }

    var autoDetectEnabled: Bool {
        get {
            defaults.bool(forKey: Key.autoDetectEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.autoDetectEnabled)
        }
    }

    var autoDetectPair: AutoDetectPair {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.autoDetectPair),
                let pair = AutoDetectPair(rawValue: rawValue)
            else {
                return AutoDetectPair.defaultValue
            }

            return pair
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.autoDetectPair)
        }
    }

    var confirmBeforeReplace: Bool {
        get {
            defaults.bool(forKey: Key.confirmBeforeReplace)
        }
        set {
            defaults.set(newValue, forKey: Key.confirmBeforeReplace)
        }
    }

    var translationStyle: TranslationStyle {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.translationStyle),
                let style = TranslationStyle(rawValue: rawValue)
            else {
                return TranslationStyle.defaultValue
            }

            return style
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.translationStyle)
        }
    }

    var showStatusBarIcon: Bool {
        get {
            guard defaults.object(forKey: Key.showStatusBarIcon) != nil else {
                return true
            }

            return defaults.bool(forKey: Key.showStatusBarIcon)
        }
        set {
            defaults.set(newValue, forKey: Key.showStatusBarIcon)
        }
    }

    var workMode: WorkMode {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.workMode),
                let workMode = WorkMode(rawValue: rawValue)
            else {
                return WorkMode.defaultValue
            }

            return workMode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.workMode)
        }
    }

    var languagePairDisplayName: String {
        if autoDetectEnabled {
            return "Auto \(autoDetectPair.displayName)"
        }

        return "\(SupportedLanguage.displayName(for: sourceLanguageCode))->\(SupportedLanguage.displayName(for: targetLanguageCode))"
    }

    private func migratedLanguageCodesIfNeeded() -> (source: String, target: String) {
        if defaults.string(forKey: Key.sourceLanguageCode) != nil,
           defaults.string(forKey: Key.targetLanguageCode) != nil {
            return (SupportedLanguage.defaultSourceCode, SupportedLanguage.defaultTargetCode)
        }

        switch defaults.string(forKey: Key.mode) {
        case "englishToKorean":
            return ("en-US", "ko-KR")
        default:
            return (SupportedLanguage.defaultSourceCode, SupportedLanguage.defaultTargetCode)
        }
    }
}
