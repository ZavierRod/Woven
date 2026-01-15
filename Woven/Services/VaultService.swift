import Foundation

/// Service for vault-related API calls
@MainActor
final class VaultService {
    static let shared = VaultService()
    
    private let fallbackURL = "http://192.168.1.117:8000"
    
    private init() {}
    
    /// Wait for discovery to complete if it's still in progress
    private func waitForDiscoveryIfNeeded() async {
        if BackendDiscoveryService.shared.isDiscovering {
            print("⏳ VaultService: Waiting for discovery to complete...")
            // Wait up to 3 seconds for discovery
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                if !BackendDiscoveryService.shared.isDiscovering {
                    print("✅ VaultService: Discovery completed")
                    return
                }
            }
            print("⚠️ VaultService: Discovery timeout, proceeding with available URL")
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0 // 10 second timeout
        return request
    }
    
    // MARK: - Fetch All Vaults
    
    func fetchVaults() async throws -> [Vault] {
        await waitForDiscoveryIfNeeded()
        
        let urlString = "\(baseURL)/vaults/"
        print("🌐 VaultService: Fetching vaults from: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw VaultServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url) else {
            throw VaultServiceError.unauthorized
        }
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw VaultServiceError.unauthorized
        }
        
        guard httpResponse.statusCode == 200 else {
            throw VaultServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try decoder.decode([Vault].self, from: data)
    }
    
    // MARK: - Get Vault Detail
    
    func getVault(id: UUID) async throws -> VaultDetail {
        guard let url = URL(string: "\(baseURL)/vaults/\(id.uuidString)") else {
            throw VaultServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url) else {
            throw VaultServiceError.unauthorized
        }
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw VaultServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try decoder.decode(VaultDetail.self, from: data)
    }
    
    // MARK: - Create Vault
    
    func createVault(name: String, type: VaultType, mode: VaultMode, inviteeId: Int? = nil) async throws -> Vault {
        guard let url = URL(string: "\(baseURL)/vaults/") else {
            throw VaultServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url, method: "POST") else {
            throw VaultServiceError.unauthorized
        }
        
        let body = CreateVaultRequest(name: name, type: type, mode: mode, inviteeId: inviteeId)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 201 else {
            // Try to extract error message
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw VaultServiceError.apiError(message: detail)
            }
            throw VaultServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try decoder.decode(Vault.self, from: data)
    }
    
    // MARK: - Delete Vault
    
    func deleteVault(id: UUID) async throws {
        guard let url = URL(string: "\(baseURL)/vaults/\(id.uuidString)") else {
            throw VaultServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url, method: "DELETE") else {
            throw VaultServiceError.unauthorized
        }
        request.httpMethod = "DELETE"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 204 else {
            throw VaultServiceError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Invite to Vault
    
    func inviteToVault(vaultId: UUID, inviteCode: String) async throws -> VaultInviteResponse {
        guard let url = URL(string: "\(baseURL)/vaults/\(vaultId.uuidString)/invite") else {
            throw VaultServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url, method: "POST") else {
            throw VaultServiceError.unauthorized
        }
        
        let body = VaultInviteRequest(inviteCode: inviteCode)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try to extract error message
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw VaultServiceError.apiError(message: detail)
            }
            throw VaultServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try decoder.decode(VaultInviteResponse.self, from: data)
    }
    
    // MARK: - Get Pending Invites
    
    func getPendingInvites() async throws -> [VaultDetail] {
        guard let url = URL(string: "\(baseURL)/vaults/invites/pending") else {
            throw VaultServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url) else {
            throw VaultServiceError.unauthorized
        }
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw VaultServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try decoder.decode([VaultDetail].self, from: data)
    }
    
    // MARK: - Accept Vault Invite
    
    func acceptInvite(vaultId: UUID) async throws -> Vault {
        guard let url = URL(string: "\(baseURL)/vaults/\(vaultId.uuidString)/accept") else {
            throw VaultServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url, method: "POST") else {
            throw VaultServiceError.unauthorized
        }
        request.httpMethod = "POST"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw VaultServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try decoder.decode(Vault.self, from: data)
    }
    
    // MARK: - Decline Vault Invite
    
    func declineInvite(vaultId: UUID) async throws {
        guard let url = URL(string: "\(baseURL)/vaults/\(vaultId.uuidString)/decline") else {
            throw VaultServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url, method: "POST") else {
            throw VaultServiceError.unauthorized
        }
        request.httpMethod = "POST"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 204 else {
            throw VaultServiceError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Leave Vault
    
    func leaveVault(id: UUID) async throws {
        guard let url = URL(string: "\(baseURL)/vaults/\(id.uuidString)/leave") else {
            throw VaultServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url, method: "DELETE") else {
            throw VaultServiceError.unauthorized
        }
        request.httpMethod = "DELETE"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 204 else {
            throw VaultServiceError.serverError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Error Types

enum VaultServiceError: LocalizedError {
    case invalidURL
    case unauthorized
    case invalidResponse
    case serverError(statusCode: Int)
    case apiError(message: String)
    case decodingError
    
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
        case .decodingError:
            return "Failed to process response"
        }
    }
}

