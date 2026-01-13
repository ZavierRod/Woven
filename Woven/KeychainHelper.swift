import Foundation
import Security

final class KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "com.woven.app"
    
    private init() {}
    
    func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        saveData(key: key, value: data)
    }
    
    func read(key: String) -> String? {
        guard let data = readData(key: key),
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }
    
    /// Save binary data to Keychain
    func saveData(key: String, value: Data) {
        // Delete existing item first
        delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    /// Read binary data from Keychain
    func readData(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        return data
    }
    
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

