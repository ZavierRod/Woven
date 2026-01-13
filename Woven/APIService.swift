import Foundation
import UIKit

// MARK: - API Response Types

struct AuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let userId: Int
    let username: String
    let email: String
    let fullName: String?
    let inviteCode: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case userId = "user_id"
        case username, email
        case fullName = "full_name"
        case inviteCode = "invite_code"
    }
}

struct APIError: Codable {
    let detail: String
}

// MARK: - API Service

@MainActor
final class APIService {
    static let shared = APIService()
    private let fallbackURL = "http://192.168.4.45:8001" // Fallback default
    
    private init() {
        // Start discovery in background
        _ = BackendDiscoveryService.shared // Initialize discovery service
    }
    
    /// Wait for discovery to complete if it's still in progress
    private func waitForDiscoveryIfNeeded() async {
        if BackendDiscoveryService.shared.isDiscovering {
            print("⏳ Waiting for discovery to complete...")
            // Wait up to 3 seconds for discovery
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                if !BackendDiscoveryService.shared.isDiscovering {
                    print("✅ Discovery completed")
                    return
                }
            }
            print("⚠️ Discovery timeout, proceeding with available URL")
        }
    }
    
    /// Get the base URL (checks discovered URL first, falls back to default)
    private var baseURL: String {
        if let discoveredURL = BackendDiscoveryService.shared.discoveredURL {
            print("🌐 Using discovered URL: \(discoveredURL)")
            return discoveredURL
        }
        print("⚠️ Using fallback URL: \(fallbackURL) (discovery in progress: \(BackendDiscoveryService.shared.isDiscovering))")
        return fallbackURL
    }
    
    // MARK: - Sign Up
    
    func signUp(
        username: String,
        email: String,
        password: String,
        fullName: String?
    ) async throws -> AuthResponse {
        // Wait for discovery to complete if it's still in progress
        await waitForDiscoveryIfNeeded()
        
        let urlString = "\(baseURL)/auth/signup"
        print("🌐 Sign up request to: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw APIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0 // 10 second timeout
        
        var body: [String: Any] = [
            "username": username,
            "email": email,
            "password": password
        ]
        if let fullName = fullName, !fullName.isEmpty {
            body["full_name"] = fullName
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        
        if httpResponse.statusCode == 201 {
            let decoder = JSONDecoder()
            return try decoder.decode(AuthResponse.self, from: data)
        } else {
            // Try to parse error message
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIServiceError.serverError(message: apiError.detail)
            }
            throw APIServiceError.serverError(message: "Sign up failed")
        }
    }
    
    // MARK: - Login
    
    func login(identifier: String, password: String) async throws -> AuthResponse {
        // Wait for discovery to complete if it's still in progress
        await waitForDiscoveryIfNeeded()
        
        let urlString = "\(baseURL)/auth/login"
        print("🌐 Login request to: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw APIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0 // 10 second timeout
        
        let body: [String: Any] = [
            "identifier": identifier,
            "password": password
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            return try decoder.decode(AuthResponse.self, from: data)
        } else {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIServiceError.serverError(message: apiError.detail)
            }
            throw APIServiceError.serverError(message: "Login failed")
        }
    }
    // MARK: - Device Tokens
    
    func registerDeviceToken(token: String) async throws {
        // Wait for discovery to complete if it's still in progress
        await waitForDiscoveryIfNeeded()
        
        let urlString = "\(baseURL)/devices/register"
        print("🌐 Registering device token to: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw APIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add auth header if available
        // Add auth header if available
        if let token = KeychainHelper.shared.read(key: "woven-session-token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Determine environment (simple check, can be improved)
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        
        let body: [String: Any] = [
            "token": token,
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "apns_environment": env,
            "platform": "ios"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, 
              (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.serverError(message: "Failed to register device token")
        }
    }
}

// MARK: - Errors

enum APIServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(message: String)
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let message):
            return message
        case .unauthorized:
            return "Please sign in again"
        }
    }
}
