import Foundation
import Security

enum KeychainStore {
    private static let service = "R2Trans.OpenAI"
    private static let account = "apiKey"
    private static let legacyFallbackInfoKey = "R2TransAllowsLegacyKeychainFallback"

    private enum Backend {
        case dataProtection
        case legacy
    }

    private enum LookupResult {
        case found(Data)
        case notFound
    }

    enum StoreError: LocalizedError {
        case operationFailed(operation: String, status: OSStatus)
        case invalidData
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .operationFailed(let operation, let status):
                return "\(operation) \(Self.message(for: status)) (OSStatus \(status))."
            case .invalidData:
                return "The API key stored in Keychain is not valid UTF-8 data."
            case .verificationFailed:
                return "The API key could not be verified after saving it to the data-protection Keychain."
            }
        }

        private static func message(for status: OSStatus) -> String {
            switch status {
            case errSecInteractionNotAllowed:
                return "failed because the Keychain is locked or user interaction is not currently allowed"
            case errSecAuthFailed:
                return "failed because Keychain authorization was denied"
            case errSecMissingEntitlement:
                return "failed because the app's code signature is missing a required Keychain entitlement"
            case errSecDecode:
                return "failed because Keychain data could not be decoded"
            case errSecNotAvailable:
                return "failed because Keychain Services is unavailable"
            default:
                let systemMessage = SecCopyErrorMessageString(status, nil) as String?
                return systemMessage.map { "failed: \($0)" } ?? "failed"
            }
        }
    }

    static func loadAPIKeyOrThrow() throws -> String {
        if allowsLegacyFallback {
            return try loadLegacyAPIKey()
        }

        switch try lookup(in: .dataProtection) {
        case .found(let data):
            return try decode(data)
        case .notFound:
            return try migrateLegacyAPIKeyIfPresent()
        }
    }

    static func saveAPIKey(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)

        if allowsLegacyFallback {
            try upsert(data, in: .legacy)
            return
        }

        try upsert(data, in: .dataProtection)
        try verify(data, in: .dataProtection)
        removeLegacyItemAfterVerifiedMigration()
    }

    private static func migrateLegacyAPIKeyIfPresent() throws -> String {
        switch try lookup(in: .legacy) {
        case .notFound:
            return ""
        case .found(let legacyData):
            let value = try decode(legacyData)

            try upsert(legacyData, in: .dataProtection)

            try verify(legacyData, in: .dataProtection)

            removeLegacyItemAfterVerifiedMigration()
            return value
        }
    }

    private static func loadLegacyAPIKey() throws -> String {
        switch try lookup(in: .legacy) {
        case .found(let data):
            return try decode(data)
        case .notFound:
            return ""
        }
    }

    private static func lookup(in backend: Backend) throws -> LookupResult {
        var query = baseQuery(for: backend)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw StoreError.invalidData
            }
            return .found(data)
        case errSecItemNotFound:
            return .notFound
        default:
            throw StoreError.operationFailed(operation: "Reading the API key from Keychain", status: status)
        }
    }

    private static func upsert(_ data: Data, in backend: Backend) throws {
        let query = baseQuery(for: backend)
        var updateAttributes: [String: Any] = [kSecValueData as String: data]
        if backend == .dataProtection {
            updateAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            updateAttributes as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            throw StoreError.operationFailed(operation: "Updating the API key in Keychain", status: updateStatus)
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        if backend == .dataProtection {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let retryStatus = SecItemUpdate(
                query as CFDictionary,
                updateAttributes as CFDictionary
            )
            guard retryStatus == errSecSuccess else {
                throw StoreError.operationFailed(operation: "Updating the API key in Keychain", status: retryStatus)
            }
        default:
            throw StoreError.operationFailed(operation: "Saving the API key in Keychain", status: addStatus)
        }
    }

    private static func verify(_ expectedData: Data, in backend: Backend) throws {
        guard
            case .found(let storedData) = try lookup(in: backend),
            storedData == expectedData
        else {
            throw StoreError.verificationFailed
        }
    }

    private static func removeLegacyItemAfterVerifiedMigration() {
        let status = SecItemDelete(baseQuery(for: .legacy) as CFDictionary)

        // A cleanup failure must never make a successfully copied credential look
        // missing. The protected item remains authoritative, and a future save can
        // retry cleanup without risking credential loss.
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            return
        }
    }

    private static func decode(_ data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidData
        }

        return value
    }

    private static func baseQuery(for backend: Backend) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if backend == .dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }

        return query
    }

    private static var allowsLegacyFallback: Bool {
        Bundle.main.object(forInfoDictionaryKey: legacyFallbackInfoKey) as? Bool == true
    }
}
