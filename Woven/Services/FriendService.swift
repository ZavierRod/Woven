import Foundation

@MainActor
final class FriendService {
    static let shared = FriendService()
    
    private let fallbackURL = "http://192.168.4.45:8001"
    
    private init() {}
    
    private func waitForDiscoveryIfNeeded() async {
        if BackendDiscoveryService.shared.isDiscovering {
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !BackendDiscoveryService.shared.isDiscovering {
                    return
                }
            }
        }
    }
    
    private var baseURL: String {
        if let discoveredURL = BackendDiscoveryService.shared.discoveredURL {
            return discoveredURL
        }
        return fallbackURL
    }
    
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = formatter.date(from: dateString) {
                return date
            }
            
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
        request.timeoutInterval = 10.0
        return request
    }
    
    // MARK: - Send Friend Request
    
    func sendFriendRequest(inviteCode: String) async throws -> Friendship {
        await waitForDiscoveryIfNeeded()
        
        guard let url = URL(string: "\(baseURL)/friends/request") else {
            throw FriendServiceError.invalidURL
        }
        
        guard var request = authorizedRequest(url: url, method: "POST") else {
            throw FriendServiceError.unauthorized
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = FriendRequestCreate(inviteCode: inviteCode)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 201:
            return try decoder.decode(Friendship.self, from: data)
        case 400:
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw FriendServiceError.apiError(message: detail)
            }
            throw FriendServiceError.apiError(message: "Invalid request")
        case 404:
            throw FriendServiceError.apiError(message: "User not found with that invite code")
        default:
            throw FriendServiceError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Get Friends List
    
    func getFriends() async throws -> [Friend] {
        await waitForDiscoveryIfNeeded()
        
        guard let url = URL(string: "\(baseURL)/friends/") else {
            throw FriendServiceError.invalidURL
        }
        
        guard let request = authorizedRequest(url: url) else {
            throw FriendServiceError.unauthorized
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw FriendServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        let listResponse = try decoder.decode(FriendListResponse.self, from: data)
        return listResponse.friends
    }
    
    // MARK: - Get Pending Requests
    
    func getPendingRequests() async throws -> [PendingFriendRequest] {
        await waitForDiscoveryIfNeeded()
        
        guard let url = URL(string: "\(baseURL)/friends/requests/pending") else {
            throw FriendServiceError.invalidURL
        }
        
        guard let request = authorizedRequest(url: url) else {
            throw FriendServiceError.unauthorized
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw FriendServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        let listResponse = try decoder.decode(PendingRequestsResponse.self, from: data)
        return listResponse.requests
    }
    
    // MARK: - Get Sent Requests
    
    func getSentRequests() async throws -> [PendingFriendRequest] {
        await waitForDiscoveryIfNeeded()
        
        guard let url = URL(string: "\(baseURL)/friends/requests/sent") else {
            throw FriendServiceError.invalidURL
        }
        
        guard let request = authorizedRequest(url: url) else {
            throw FriendServiceError.unauthorized
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw FriendServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        let listResponse = try decoder.decode(PendingRequestsResponse.self, from: data)
        return listResponse.requests
    }
    
    // MARK: - Accept Friend Request
    
    func acceptRequest(friendshipId: Int) async throws -> Friendship {
        await waitForDiscoveryIfNeeded()
        
        guard let url = URL(string: "\(baseURL)/friends/requests/\(friendshipId)/accept") else {
            throw FriendServiceError.invalidURL
        }
        
        guard let request = authorizedRequest(url: url, method: "POST") else {
            throw FriendServiceError.unauthorized
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try decoder.decode(Friendship.self, from: data)
        case 404:
            throw FriendServiceError.apiError(message: "Friend request not found")
        default:
            throw FriendServiceError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Decline Friend Request
    
    func declineRequest(friendshipId: Int) async throws {
        await waitForDiscoveryIfNeeded()
        
        guard let url = URL(string: "\(baseURL)/friends/requests/\(friendshipId)/decline") else {
            throw FriendServiceError.invalidURL
        }
        
        guard let request = authorizedRequest(url: url, method: "POST") else {
            throw FriendServiceError.unauthorized
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 204 else {
            throw FriendServiceError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Remove Friend
    
    func removeFriend(friendUserId: Int) async throws {
        await waitForDiscoveryIfNeeded()
        
        guard let url = URL(string: "\(baseURL)/friends/\(friendUserId)") else {
            throw FriendServiceError.invalidURL
        }
        
        guard let request = authorizedRequest(url: url, method: "DELETE") else {
            throw FriendServiceError.unauthorized
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 204 else {
            throw FriendServiceError.serverError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

enum FriendServiceError: LocalizedError {
    case invalidURL
    case unauthorized
    case invalidResponse
    case serverError(statusCode: Int)
    case apiError(message: String)
    
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
        }
    }
}
