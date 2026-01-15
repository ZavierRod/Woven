import Foundation
import CryptoKit
import Combine

// MARK: - Models

struct AccessRequest: Codable, Identifiable {
    let id: Int
    let vaultId: UUID
    let requesterId: Int
    let approverId: Int
    let status: AccessRequestStatus
    let encryptedShare: String?
    let createdAt: Date
    let expiresAt: Date
    let requesterPublicKey: String
    
    enum CodingKeys: String, CodingKey {
        case id, status
        case vaultId = "vault_id"
        case requesterId = "requester_id"
        case approverId = "approver_id"
        case encryptedShare = "encrypted_share"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case requesterPublicKey = "requester_public_key"
    }
}

enum AccessRequestStatus: String, Codable {
    case pending
    case approved
    case denied
    case expired
}

struct AccessRequestCreate: Codable {
    let vault_id: UUID
    let requester_public_key: String
}

struct AccessRequestApprove: Codable {
    let encrypted_share: String
}

// MARK: - Manager

@MainActor
final class AccessRequestManager: ObservableObject {
    static let shared = AccessRequestManager()
    
    private let decoder: JSONDecoder
    
    // Store ephemeral private keys by request/transaction ID
    // In a real app, save to Keychain or limit to one active request session
    private var currentPrivateKey: P256.KeyAgreement.PrivateKey?
    
    private init() {
        let decoder = JSONDecoder()
        // Use custom date decoding to handle Python's naive datetimes (no timezone)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 with timezone and fractional seconds
            let iso8601WithFrac = ISO8601DateFormatter()
            iso8601WithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601WithFrac.date(from: dateString) {
                return date
            }
            
            // Try ISO8601 with timezone, no fractional seconds
            let iso8601 = ISO8601DateFormatter()
            iso8601.formatOptions = [.withInternetDateTime]
            if let date = iso8601.date(from: dateString) {
                return date
            }
            
            // Try naive datetime with fractional seconds (Python's default: "2024-01-14T12:30:45.123456")
            let naiveFormatter = DateFormatter()
            naiveFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            naiveFormatter.timeZone = TimeZone(identifier: "UTC")
            if let date = naiveFormatter.date(from: dateString) {
                return date
            }
            
            // Try naive datetime without fractional seconds
            naiveFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = naiveFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
        self.decoder = decoder
    }
    
    private var baseURL: String {
        if let discoveredURL = BackendDiscoveryService.shared.discoveredURL {
            return discoveredURL
        }
        return "http://192.168.1.117:8000" // Fallback
    }
    
    private func getAuthToken() -> String? {
        KeychainHelper.shared.read(key: "woven-session-token")
    }
    
    // MARK: - Public API
    
    /// Start an access request. Generates ephemeral key pair.
    func requestAccess(for vaultId: UUID) async throws -> AccessRequest {
        // 1. Generate Ephemeral Key
        let privateKey = P256.KeyAgreement.PrivateKey()
        self.currentPrivateKey = privateKey
        
        let publicKeyData = privateKey.publicKey.x963Representation
        let publicKeyString = publicKeyData.base64EncodedString()
        
        // 2. Prepare Request
        let url = URL(string: "\(baseURL)/access-requests/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(getAuthToken() ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = AccessRequestCreate(vault_id: vaultId, requester_public_key: publicKeyString)
        request.httpBody = try JSONEncoder().encode(body)
        
        // 3. Send
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw VaultServiceError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        return try decoder.decode(AccessRequest.self, from: data)
    }
    
    /// Poll for status
    func getRequest(id: Int) async throws -> AccessRequest {
        let url = URL(string: "\(baseURL)/access-requests/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(getAuthToken() ?? "")", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw VaultServiceError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        return try decoder.decode(AccessRequest.self, from: data)
    }
    
    /// Approve a request. Encrypts the key share for the requester.
    func approveRequest(request: AccessRequest, shareOrKey: Data) async throws {
        // 1. Reconstruct Requester's Public Key
        guard let requesterKeyData = Data(base64Encoded: request.requesterPublicKey),
              let requesterKey = try? P256.KeyAgreement.PublicKey(x963Representation: requesterKeyData) else {
            throw VaultServiceError.apiError(message: "Invalid requester public key")
        }
        
        // 2. Perform Handshake (Approve Side)
        // We generate OUR ephemeral key to encrypt the data
        let myPrivateKey = P256.KeyAgreement.PrivateKey()
        let myPublicKeyData = myPrivateKey.publicKey.x963Representation
        
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: requesterKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        // 3. Encrypt the share
        // Protocol: AES.GCM.seal(payload, key: key)
        let sealedBox = try AES.GCM.seal(shareOrKey, using: symmetricKey)
        
        // 4. Construct Payload containing {MyPublicKey + Ciphertext + Nonce/Tag}
        // Since we need to send just one string, we'll JSON encode a container
        struct EncryptedPayload: Codable {
            let ephemeralPublicKey: String
            let ciphertext: String
            let nonce: String
            let tag: String
        }
        
        let payload = EncryptedPayload(
            ephemeralPublicKey: myPublicKeyData.base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) }.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString()
        )
        
        let payloadData = try JSONEncoder().encode(payload)
        let payloadString = payloadData.base64EncodedString()
        
        // 5. Send to API
        let url = URL(string: "\(baseURL)/access-requests/\(request.id)/approve")!
        var apiRequest = URLRequest(url: url)
        apiRequest.httpMethod = "POST"
        apiRequest.setValue("Bearer \(getAuthToken() ?? "")", forHTTPHeaderField: "Authorization")
        apiRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = AccessRequestApprove(encrypted_share: payloadString)
        apiRequest.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: apiRequest)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw VaultServiceError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
    }
    
    
    /// Decrypt the received share from an approved request.
    func decryptShare(from request: AccessRequest) throws -> Data {
        guard let encryptedString = request.encryptedShare,
              let payloadData = Data(base64Encoded: encryptedString),
              let currentPrivateKey = self.currentPrivateKey else {
            throw VaultServiceError.apiError(message: "Missing data or private key")
        }
        
        struct EncryptedPayload: Codable {
            let ephemeralPublicKey: String
            let ciphertext: String
            let nonce: String
            let tag: String
        }
        
        let payload = try JSONDecoder().decode(EncryptedPayload.self, from: payloadData)
        
        // 1. Reconstruct Sender's Public Key
        guard let senderKeyData = Data(base64Encoded: payload.ephemeralPublicKey),
              let senderKey = try? P256.KeyAgreement.PublicKey(x963Representation: senderKeyData) else {
            throw VaultServiceError.apiError(message: "Invalid sender public key")
        }
        
        // 2. Derive Symmetric Key
        let sharedSecret = try currentPrivateKey.sharedSecretFromKeyAgreement(with: senderKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        // 3. Decrypt
        guard let nonceData = Data(base64Encoded: payload.nonce),
              let tagData = Data(base64Encoded: payload.tag),
              let ciphertext = Data(base64Encoded: payload.ciphertext) else {
             throw VaultServiceError.apiError(message: "Invalid payload components")
        }
        
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceData), ciphertext: ciphertext, tag: tagData)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        
        return decryptedData
    }
    
    /// Deny an access request.
    func denyRequest(requestId: Int) async throws {
        let url = URL(string: "\(baseURL)/access-requests/\(requestId)/deny")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(getAuthToken() ?? "")", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw VaultServiceError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
    }
}
