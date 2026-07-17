import CryptoKit
import Foundation
import Security

protocol PairSecretStore: Sendable {
    func identityPrivateKey(accountID: Int, cryptography: PairVaultCryptography) throws -> Data
    func signingPrivateKey(accountID: Int, cryptography: PairVaultCryptography) throws -> Data
    func saveShare(_ share: Data, vaultID: String, accountID: Int) throws
    func share(vaultID: String, accountID: Int) throws -> Data
    func deleteShare(vaultID: String, accountID: Int)
    func saveInvitationToken(_ token: String, vaultID: String, accountID: Int) throws
    func invitationToken(vaultID: String, accountID: Int) throws -> String?
    func deleteInvitationToken(vaultID: String, accountID: Int)
}

final class PairVaultKeychain: PairSecretStore, @unchecked Sendable {
    private let service = "com.woven.app.pair-v2"

    func identityPrivateKey(accountID: Int, cryptography: PairVaultCryptography) throws -> Data {
        let key = "identity.\(accountID)"
        if let existing = try read(key) { return existing }
        let created = cryptography.generateIdentityPrivateKey()
        try save(created, key: key)
        return created
    }

    func signingPrivateKey(accountID: Int, cryptography: PairVaultCryptography) throws -> Data {
        let key = "signing.\(accountID)"
        if let existing = try read(key) { return existing }
        let created = cryptography.generateSigningPrivateKey()
        try save(created, key: key)
        return created
    }

    func saveShare(_ share: Data, vaultID: String, accountID: Int) throws {
        guard share.count == PairVaultCryptography.keyByteCount else { throw PairVaultError.invalidKeyLength }
        try save(share, key: shareKey(vaultID: vaultID, accountID: accountID))
    }

    func share(vaultID: String, accountID: Int) throws -> Data {
        guard let value = try read(shareKey(vaultID: vaultID, accountID: accountID)) else {
            throw PairVaultError.missingLocalShare
        }
        return value
    }

    func deleteShare(vaultID: String, accountID: Int) {
        delete(shareKey(vaultID: vaultID, accountID: accountID))
    }

    func saveInvitationToken(_ token: String, vaultID: String, accountID: Int) throws {
        try save(Data(token.utf8), key: "invitation.\(accountID).\(vaultID)")
    }

    func invitationToken(vaultID: String, accountID: Int) throws -> String? {
        guard let data = try read("invitation.\(accountID).\(vaultID)") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteInvitationToken(vaultID: String, accountID: Int) {
        delete("invitation.\(accountID).\(vaultID)")
    }

    private func shareKey(vaultID: String, accountID: Int) -> String {
        "share.\(accountID).\(vaultID)"
    }

    private func save(_ data: Data, key: String) throws {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PairVaultError.relay("Keychain write failed (\(status)).")
        }
    }

    private func read(_ key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PairVaultError.relay("Keychain read failed (\(status)).")
        }
        return data
    }

    private func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
