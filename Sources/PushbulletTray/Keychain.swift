import Foundation
import Security

/// Generic-password items under the same service and account names the Electron
/// version (keytar) used, so an existing token carries over.
enum Keychain {
    enum Account: String {
        case accessToken, e2eePassword
    }

    private static let service = "Pushbullet Tray"

    private static func query(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    static func get(_ account: Account) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String, for account: Account) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var query = query(account)
        query[kSecValueData as String] = data
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: Account) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
