import Foundation
import Security

enum Keychain {
    private static let service = "com.tanookistudios.bloodglucosebuddy.dexcom"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    static func save(_ password: String, for account: String) -> Bool {
        delete(account)
        var item = query(account)
        item[kSecValueData as String] = Data(password.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func password(for account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
