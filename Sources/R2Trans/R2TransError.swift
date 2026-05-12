import Foundation

enum R2TransError: LocalizedError {
    case accessibilityPermissionRequired(String)
    case apiKeyMissing
    case clipboardTextMissing
    case invalidHotKey(String)
    case openAIRequestFailed(String)
    case openAIResponseMissing
    case alreadyTranslating
    case microphonePermissionDenied
    case microphoneUnavailable
    case systemAudioUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired(let appPath):
            return [
                AppText.text(.accessibilityPermissionRequired),
                "",
                "\(AppText.text(.currentAppPath)): \(appPath)",
                "",
                AppText.text(.accessibilityPermissionAlreadyEnabledHelp)
            ].joined(separator: "\n")
        case .apiKeyMissing:
            return AppText.text(.apiKeyMissing)
        case .clipboardTextMissing:
            return AppText.text(.clipboardTextMissing)
        case .invalidHotKey(let value):
            return "\(AppText.text(.invalidHotkey)): \(value)."
        case .openAIRequestFailed(let message):
            return message
        case .openAIResponseMissing:
            return AppText.text(.responseMissing)
        case .alreadyTranslating:
            return AppText.text(.alreadyTranslating)
        case .microphonePermissionDenied:
            return AppText.text(.microphonePermissionDenied)
        case .microphoneUnavailable:
            return AppText.text(.microphoneUnavailable)
        case .systemAudioUnavailable:
            return AppText.text(.systemAudioUnavailable)
        }
    }
}
