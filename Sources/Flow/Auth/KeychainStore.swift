import Foundation
import Security

/// Stores and retrieves OAuth tokens from the macOS Keychain.
///
/// Uses the Security framework directly (no third-party keyring crate).
/// Tokens are stored with service="ai.flow.app" and account="chatgpt_tokens".
final class KeychainStore {
    static let shared = KeychainStore()
    private let service = "ai.flow.app"

    private init() {}

    // MARK: - Token Storage

    struct AuthTokens: Codable {
        let accessToken: String
        let refreshToken: String
        let idToken: String?
        let expiresAt: Date
        let email: String?
        let plan: String?

        var isExpired: Bool {
            Date() > expiresAt.addingTimeInterval(-60) // 60s buffer
        }
    }

    func saveTokens(_ tokens: AuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "chatgpt_tokens",
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        let addQuery: [String: Any] = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]) { _, new in new }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadTokens() -> AuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "chatgpt_tokens",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    func deleteTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "chatgpt_tokens",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed (status: \(s))"
        case .loadFailed(let s): return "Keychain load failed (status: \(s))"
        }
    }
}
