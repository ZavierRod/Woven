import Foundation
import CryptoKit

/// Manages vault encryption keys stored securely in Keychain
@MainActor
final class VaultKeyManager {
    static let shared = VaultKeyManager()
    
    private let keychain = KeychainHelper.shared
    private let encryptionService = EncryptionService.shared
    
    private init() {}
    
    /// Get or generate a vault key for a specific vault
    /// - Parameter vaultId: The UUID of the vault
    /// - Returns: The vault's encryption key
    func getOrCreateVaultKey(vaultId: UUID) throws -> SymmetricKey {
        let keyKey = "vault-key-\(vaultId.uuidString)"
        
        // Try to retrieve existing key
        if let keyData = keychain.readData(key: keyKey) {
            return encryptionService.dataToKey(keyData)
        }
        
        // Generate new key
        let newKey = encryptionService.generateKey()
        let keyData = encryptionService.keyToData(newKey)
        
        // Store in Keychain
        keychain.saveData(key: keyKey, value: keyData)
        
        return newKey
    }
    
    /// Get vault key (returns nil if not found)
    /// - Parameter vaultId: The UUID of the vault
    /// - Returns: The vault's encryption key, or nil if not found
    func getVaultKey(vaultId: UUID) -> SymmetricKey? {
        let keyKey = "vault-key-\(vaultId.uuidString)"
        
        guard let keyData = keychain.readData(key: keyKey) else {
            return nil
        }
        
        return encryptionService.dataToKey(keyData)
    }
    
    /// Delete vault key (when vault is deleted)
    /// - Parameter vaultId: The UUID of the vault
    func deleteVaultKey(vaultId: UUID) {
        let keyKey = "vault-key-\(vaultId.uuidString)"
        keychain.delete(key: keyKey)
    }
    
    /// Check if a vault key exists
    /// - Parameter vaultId: The UUID of the vault
    /// - Returns: True if key exists
    func hasVaultKey(vaultId: UUID) -> Bool {
        let keyKey = "vault-key-\(vaultId.uuidString)"
        return keychain.readData(key: keyKey) != nil
    }
}


