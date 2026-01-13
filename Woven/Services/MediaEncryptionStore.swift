import Foundation

/// Stores encryption metadata (IV and tag) locally for decryption
@MainActor
final class MediaEncryptionStore {
    static let shared = MediaEncryptionStore()
    
    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "media-encryption-"
    
    private init() {}
    
    /// Store encryption metadata for a media item
    func store(mediaId: UUID, iv: Data, tag: Data) {
        let key = "\(keyPrefix)\(mediaId.uuidString)"
        let data: [String: Data] = [
            "iv": iv,
            "tag": tag
        ]
        
        // Encode to Data
        if let encoded = try? JSONEncoder().encode(data.mapValues { $0.base64EncodedString() }) {
            userDefaults.set(encoded, forKey: key)
        }
    }
    
    /// Retrieve encryption metadata for a media item
    func retrieve(mediaId: UUID) -> (iv: Data, tag: Data)? {
        let key = "\(keyPrefix)\(mediaId.uuidString)"
        
        guard let encoded = userDefaults.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: String].self, from: encoded),
              let ivString = dict["iv"],
              let tagString = dict["tag"],
              let iv = Data(base64Encoded: ivString),
              let tag = Data(base64Encoded: tagString) else {
            return nil
        }
        
        return (iv, tag)
    }
    
    /// Delete encryption metadata (when media is deleted)
    func delete(mediaId: UUID) {
        let key = "\(keyPrefix)\(mediaId.uuidString)"
        userDefaults.removeObject(forKey: key)
    }
}


