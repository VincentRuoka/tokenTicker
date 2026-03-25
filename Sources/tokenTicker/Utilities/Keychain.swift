// Sources/tokenTicker/Utilities/Keychain.swift
import Foundation
import Security

enum Keychain {
    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.tokenticker",
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.tokenticker",
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.tokenticker",
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// Key constants
extension Keychain {
    static let openRouterAPIKey = "tokenTicker.openRouter.apiKey"
    static let claudeAccessToken = "tokenTicker.claude.accessToken"
    static let claudeRefreshToken = "tokenTicker.claude.refreshToken"
    static let claudeExpiresAt = "tokenTicker.claude.expiresAt"
    static let claudeCodeVerifier = "tokenTicker.claude.codeVerifier"
}
