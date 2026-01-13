import Foundation
import SwiftUI
import Combine

// MARK: - User Model

struct AppUser: Codable {
    let userId: Int
    let username: String
    let email: String
    let fullName: String?
    let inviteCode: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username, email
        case fullName = "full_name"
        case inviteCode = "invite_code"
    }
}

// MARK: - Authentication Manager

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentUser: AppUser?
    
    private let tokenKey = "woven-session-token"
    private let userKey = "woven-user-data"
    
    init() {
        print("🔐 AuthenticationManager.init()")
        clearKeychainIfFreshInstall()
        checkSession()
    }
    
    // MARK: - Fresh Install Check
    
    private func clearKeychainIfFreshInstall() {
        let hasLaunchedKey = "woven-has-launched-before"
        let hasLaunched = UserDefaults.standard.bool(forKey: hasLaunchedKey)
        print("🔐 clearKeychainIfFreshInstall() - hasLaunchedBefore: \(hasLaunched)")
        
        if !hasLaunched {
            print("🔐 Fresh install - clearing stale Keychain")
            KeychainHelper.shared.delete(key: tokenKey)
            KeychainHelper.shared.delete(key: userKey)
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        }
    }
    
    // MARK: - Session Check
    
    private func checkSession() {
        if let token = KeychainHelper.shared.read(key: tokenKey), !token.isEmpty {
            print("🔐 Found existing session token")
            loadUserFromKeychain()
            isAuthenticated = true
        } else {
            print("🔐 No session token found")
            isAuthenticated = false
        }
    }
    
    private func loadUserFromKeychain() {
        if let userString = KeychainHelper.shared.read(key: userKey),
           let userData = userString.data(using: .utf8),
           let user = try? JSONDecoder().decode(AppUser.self, from: userData) {
            currentUser = user
            print("🔐 Loaded user: \(user.username)")
        }
    }
    
    private func saveUserToKeychain(_ user: AppUser) {
        if let data = try? JSONEncoder().encode(user),
           let userString = String(data: data, encoding: .utf8) {
            KeychainHelper.shared.save(key: userKey, value: userString)
        }
    }
    
    // MARK: - Sign Up
    
    func signUp(username: String, email: String, password: String, fullName: String?) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await APIService.shared.signUp(
                username: username,
                email: email,
                password: password,
                fullName: fullName
            )
            
            // Save token
            KeychainHelper.shared.save(key: tokenKey, value: response.accessToken)
            
            // Save user
            let user = AppUser(
                userId: response.userId,
                username: response.username,
                email: response.email,
                fullName: response.fullName,
                inviteCode: response.inviteCode
            )
            currentUser = user
            saveUserToKeychain(user)
            
            isAuthenticated = true
            isLoading = false
            print("✅ Sign up successful: \(response.username)")
            
            // Register pending push token now that we're authenticated
            PushNotificationManager.shared.registerPendingTokenIfNeeded()
            
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            print("❌ Sign up failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Login
    
    func login(identifier: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await APIService.shared.login(
                identifier: identifier,
                password: password
            )
            
            // Save token
            KeychainHelper.shared.save(key: tokenKey, value: response.accessToken)
            
            // Save user
            let user = AppUser(
                userId: response.userId,
                username: response.username,
                email: response.email,
                fullName: response.fullName,
                inviteCode: response.inviteCode
            )
            currentUser = user
            saveUserToKeychain(user)
            
            isAuthenticated = true
            isLoading = false
            print("✅ Login successful: \(response.username)")
            
            // Register pending push token now that we're authenticated
            PushNotificationManager.shared.registerPendingTokenIfNeeded()
            
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            print("❌ Login failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        KeychainHelper.shared.delete(key: tokenKey)
        KeychainHelper.shared.delete(key: userKey)
        currentUser = nil
        isAuthenticated = false
        print("🔐 Signed out")
    }
    
    // MARK: - Clear Error
    
    func clearError() {
        errorMessage = nil
    }
}
