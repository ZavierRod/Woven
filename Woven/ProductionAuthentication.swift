import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import SwiftUI

private struct ProductionSessionResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let userID: Int
    let username: String
    let email: String
    let fullName: String?
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case userID = "user_id"
        case username, email
        case fullName = "full_name"
        case inviteCode = "invite_code"
    }

    var pairSession: PairSession {
        PairSession(
            accessToken: accessToken,
            tokenType: tokenType,
            userID: userID,
            username: username,
            email: email,
            fullName: fullName,
            inviteCode: inviteCode
        )
    }
}

@Observable
@MainActor
final class ProductionAuthenticationStore {
    private(set) var session: PairSession?
    private(set) var isWorking = false
    var errorMessage: String?

    private let configuration: AppConfiguration
    private let urlSession: URLSession
    private let refreshKey = "production.refresh-token"

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCache = nil
        sessionConfiguration.timeoutIntervalForRequest = 20
        urlSession = URLSession(configuration: sessionConfiguration)
    }

    func restore() async {
        guard session == nil, let refreshToken = KeychainHelper.shared.read(key: refreshKey) else { return }
        await exchange(path: "/auth/refresh", body: ["refresh_token": refreshToken])
    }

    func signIn(identityToken: Data, nonce: String, fullName: String?) async {
        guard let token = String(data: identityToken, encoding: .utf8) else {
            errorMessage = "Apple returned an unreadable credential."
            return
        }
        await exchange(
            path: "/auth/apple",
            body: [
                "identity_token": token,
                "nonce": nonce,
                "full_name": fullName ?? "",
            ]
        )
    }

    func signOut() async {
        let refreshToken = KeychainHelper.shared.read(key: refreshKey)
        clearLocalSession()
        guard let refreshToken else { return }
        _ = try? await request(path: "/auth/logout", body: ["refresh_token": refreshToken])
    }

    private func exchange(path: String, body: [String: String]) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let data = try await request(path: path, body: body)
            let response = try JSONDecoder().decode(ProductionSessionResponse.self, from: data)
            KeychainHelper.shared.save(key: refreshKey, value: response.refreshToken)
            session = response.pairSession
        } catch {
            clearLocalSession()
            errorMessage = error.localizedDescription
        }
    }

    private func request(path: String, body: [String: String]) async throws -> Data {
        guard let url = URL(string: path, relativeTo: configuration.apiBaseURL) else {
            throw AppConfigurationError.invalid("The configured API URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw AppConfigurationError.invalid("Authentication failed. Please try again.")
        }
        return data
    }

    private func clearLocalSession() {
        KeychainHelper.shared.delete(key: refreshKey)
        session = nil
    }
}

struct ProductionSignInView: View {
    @Bindable var store: ProductionAuthenticationStore
    @State private var rawNonce = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54))
                .foregroundStyle(WovenTheme.accent)
            Text("Sign in to Woven")
                .font(.title.bold())
            Text("Your Apple identity authenticates your account. Vault keys remain only on your devices.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            SignInWithAppleButton(.signIn) { request in
                do {
                    rawNonce = try Self.randomNonce()
                    request.nonce = Self.sha256(rawNonce)
                    request.requestedScopes = [.fullName, .email]
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            } onCompletion: { result in
                guard case .success(let authorization) = result,
                      let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let identityToken = credential.identityToken,
                      !rawNonce.isEmpty else {
                    store.errorMessage = "Sign in with Apple was cancelled or failed."
                    return
                }
                let fullName = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
                let nonce = rawNonce
                rawNonce = ""
                Task { await store.signIn(identityToken: identityToken, nonce: nonce, fullName: fullName) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .disabled(store.isWorking)
            if store.isWorking { ProgressView() }
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .preferredColorScheme(.dark)
    }

    private static func randomNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw AppConfigurationError.invalid("Secure random generation failed.")
        }
        return Data(bytes).base64EncodedString()
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ConfigurationErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Woven is not configured",
            systemImage: "exclamationmark.shield.fill",
            description: Text(message)
        )
        .preferredColorScheme(.dark)
    }
}
