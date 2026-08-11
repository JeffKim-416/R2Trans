import Foundation

enum OpenAISafetyIdentifier {
    /// A pseudonymous, installation-scoped identifier shared by Responses and Realtime requests.
    static let value = loadOrCreate()

    private static let storageKey = "openAISafetyIdentifier.v1"
    private static let identifierPrefix = "r2trans_"

    static func loadOrCreate(
        defaults: UserDefaults = .standard,
        makeUUID: () -> UUID = UUID.init
    ) -> String {
        if let storedIdentifier = defaults.string(forKey: storageKey),
           isValid(storedIdentifier) {
            return storedIdentifier
        }

        let identifier = identifierPrefix
            + makeUUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(identifier, forKey: storageKey)
        return identifier
    }

    private static func isValid(_ identifier: String) -> Bool {
        guard identifier.hasPrefix(identifierPrefix) else {
            return false
        }

        let value = identifier.dropFirst(identifierPrefix.count)
        return value.count == 32 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
