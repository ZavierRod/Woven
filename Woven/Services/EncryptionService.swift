import Foundation
import CryptoKit

/// Service for encrypting and decrypting media using AES-GCM
@MainActor
final class EncryptionService {
    static let shared = EncryptionService()
    
    private init() {}
    
    /// Encrypt data using AES-GCM
    /// - Parameters:
    ///   - data: Plaintext data to encrypt
    ///   - key: 32-byte symmetric key
    /// - Returns: Encrypted data with IV and tag appended, or nil if encryption fails
    func encrypt(data: Data, key: SymmetricKey) throws -> (encrypted: Data, iv: Data, tag: Data) {
        // Generate a random 12-byte IV (nonce) for AES-GCM
        let iv = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let nonce = try AES.GCM.Nonce(data: iv)
        
        // Encrypt with authentication tag
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        
        // ciphertext and tag are non-optional properties
        let encrypted = sealedBox.ciphertext
        let tag = sealedBox.tag
        
        return (encrypted, iv, tag)
    }
    
    /// Decrypt data using AES-GCM
    /// - Parameters:
    ///   - encrypted: Encrypted ciphertext
    ///   - key: 32-byte symmetric key
    ///   - iv: 12-byte initialization vector (nonce)
    ///   - tag: 16-byte authentication tag
    /// - Returns: Decrypted plaintext data, or nil if decryption fails
    func decrypt(encrypted: Data, key: SymmetricKey, iv: Data, tag: Data) throws -> Data {
        // Reconstruct the nonce
        let nonce = try AES.GCM.Nonce(data: iv)
        
        // Reconstruct the sealed box
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: encrypted, tag: tag)
        
        // Decrypt and verify
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        
        return decrypted
    }
    
    /// Generate a random 256-bit (32-byte) symmetric key
    func generateKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    /// Convert SymmetricKey to Data
    func keyToData(_ key: SymmetricKey) -> Data {
        return key.withUnsafeBytes { Data($0) }
    }
    
    /// Convert Data to SymmetricKey
    func dataToKey(_ data: Data) -> SymmetricKey {
        return SymmetricKey(data: data)
    }
}

enum EncryptionError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidKey
    case invalidIV
    case invalidTag
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        case .invalidKey:
            return "Invalid encryption key"
        case .invalidIV:
            return "Invalid initialization vector"
        case .invalidTag:
            return "Invalid authentication tag"
        }
    }
}

