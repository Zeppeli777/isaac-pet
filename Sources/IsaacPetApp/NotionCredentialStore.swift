import Foundation
import Security

enum NotionCredentialError: LocalizedError {
    case emptyToken
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyToken:
            return "Notion 访问令牌不能为空。"
        case let .keychain(status):
            return "无法访问 macOS 钥匙串（错误 \(status)）。"
        }
    }
}

@MainActor
final class NotionCredentialStore {
    private let service = "com.fanmade.isaacpet.notion"
    private let account = "access-token"

    func loadToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw NotionCredentialError.keychain(status)
        }
        return token
    }

    func saveToken(_ rawToken: String) throws {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw NotionCredentialError.emptyToken }
        let data = Data(token.utf8)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NotionCredentialError.keychain(updateStatus)
        }

        var attributes = identity
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NotionCredentialError.keychain(addStatus)
        }
    }

    func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NotionCredentialError.keychain(status)
        }
    }
}
