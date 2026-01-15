import Foundation
import CryptoKit

/// Service for media-related API calls with encryption
@MainActor
final class MediaService {
    static let shared = MediaService()
    
    private let fallbackURL = "http://192.168.1.117:8000"
    private let encryptionService = EncryptionService.shared
    private let keyManager = VaultKeyManager.shared
    private let encryptionStore = MediaEncryptionStore.shared
    
    private init() {}
    
    /// Wait for discovery to complete if it's still in progress
    private func waitForDiscoveryIfNeeded() async {
        if BackendDiscoveryService.shared.isDiscovering {
            // Wait up to 3 seconds for discovery
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                if !BackendDiscoveryService.shared.isDiscovering {
                    return
                }
            }
        }
    }
    
    /// Get the base URL (checks discovered URL first, falls back to default)
    private var baseURL: String {
        if let discoveredURL = BackendDiscoveryService.shared.discoveredURL {
            return discoveredURL
        }
        return fallbackURL
    }
    
    // MARK: - JSON Decoder with Date Handling
    
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try with fractional seconds first
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }
    
    // MARK: - Get Auth Token
    
    private func getAuthToken() -> String? {
        KeychainHelper.shared.read(key: "woven-session-token")
    }
    
    private func authorizedRequest(url: URL, method: String = "GET") -> URLRequest? {
        guard let token = getAuthToken() else {
            print("❌ No auth token available")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10.0 // 10 second timeout
        return request
    }
    
    // MARK: - Upload Media
    
    /// Upload encrypted media to a vault
    /// - Parameters:
    ///   - vaultId: The vault ID
    ///   - mediaType: Photo or video
    ///   - originalData: The original unencrypted media data
    ///   - fileName: Original file name
    /// - Returns: The created Media object
    func uploadMedia(
        vaultId: UUID,
        mediaType: MediaType,
        originalData: Data,
        fileName: String
    ) async throws -> Media {
        await waitForDiscoveryIfNeeded()
        // Get or create vault key
        let vaultKey = try keyManager.getOrCreateVaultKey(vaultId: vaultId)
        
        // Encrypt the media
        let (encrypted, iv, tag) = try encryptionService.encrypt(data: originalData, key: vaultKey)
        
        // Prepare multipart form data
        guard let url = URL(string: "\(baseURL)/media/") else {
            throw MediaServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url, method: "POST") else {
            throw MediaServiceError.unauthorized
        }
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add form fields
        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"vault_id\"\r\n\r\n")
        append("\(vaultId.uuidString)\r\n")
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file_name\"\r\n\r\n")
        append("\(fileName)\r\n")
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file_size\"\r\n\r\n")
        append("\(encrypted.count)\r\n")
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"media_type\"\r\n\r\n")
        append("\(mediaType.rawValue)\r\n")
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"encryption_iv\"\r\n\r\n")
        append("\(iv.base64EncodedString())\r\n")
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"encryption_tag\"\r\n\r\n")
        append("\(tag.base64EncodedString())\r\n")
        
        // Add file
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(encrypted)
        
        append("\r\n--\(boundary)--\r\n")
        
        request.httpBody = body
        
        // Upload
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 201 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw MediaServiceError.apiError(message: detail)
            }
            throw MediaServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        let media = try decoder.decode(Media.self, from: data)
        
        // Store encryption metadata locally for decryption
        encryptionStore.store(mediaId: media.id, iv: iv, tag: tag)
        
        return media
    }
    
    // MARK: - List Media
    
    /// Get all media in a vault
    func listMedia(vaultId: UUID) async throws -> [Media] {
        await waitForDiscoveryIfNeeded()
        
        guard let url = URL(string: "\(baseURL)/media/vault/\(vaultId.uuidString)") else {
            throw MediaServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url) else {
            throw MediaServiceError.unauthorized
        }
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw MediaServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        let listResponse = try decoder.decode(MediaListResponse.self, from: data)
        return listResponse.media
    }
    
    // MARK: - Download and Decrypt Media
    
    /// Download and decrypt media
    /// - Parameter media: The media object (contains vaultId)
    /// - Returns: Decrypted media data
    func downloadAndDecryptMedia(media: Media) async throws -> Data {
        await waitForDiscoveryIfNeeded()
        
        // Download encrypted data
        guard let url = URL(string: "\(baseURL)/media/\(media.id.uuidString)/view") else {
            throw MediaServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url) else {
            throw MediaServiceError.unauthorized
        }
        request.httpMethod = "GET"
        
        let (encryptedData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw MediaServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        // Get vault key
        guard let vaultKey = keyManager.getVaultKey(vaultId: media.vaultId) else {
            throw MediaServiceError.missingKey
        }
        
        // Get encryption metadata from local store
        guard let (iv, tag) = encryptionStore.retrieve(mediaId: media.id) else {
            throw MediaServiceError.missingMetadata
        }
        
        // Decrypt
        do {
            let decrypted = try encryptionService.decrypt(
                encrypted: encryptedData,
                key: vaultKey,
                iv: iv,
                tag: tag
            )
            return decrypted
        } catch {
            throw MediaServiceError.decryptionFailed
        }
    }
    
    // MARK: - Delete Media
    
    func deleteMedia(mediaId: UUID) async throws {
        await waitForDiscoveryIfNeeded()
        
        guard let url = URL(string: "\(baseURL)/media/\(mediaId.uuidString)") else {
            throw MediaServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url, method: "DELETE") else {
            throw MediaServiceError.unauthorized
        }
        request.httpMethod = "DELETE"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 204 else {
            throw MediaServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        // Delete local encryption metadata
        encryptionStore.delete(mediaId: mediaId)
    }
}

// MARK: - Error Types

enum MediaServiceError: LocalizedError {
    case invalidURL
    case unauthorized
    case invalidResponse
    case serverError(statusCode: Int)
    case apiError(message: String)
    case missingKey
    case missingMetadata
    case encryptionFailed
    case decryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .unauthorized:
            return "Please sign in again"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code):
            return "Server error (\(code))"
        case .apiError(let message):
            return message
        case .missingKey:
            return "Vault key not found"
        case .missingMetadata:
            return "Encryption metadata not found"
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        }
    }
}

