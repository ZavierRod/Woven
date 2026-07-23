import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import GoogleSignInSwift
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

    var googleSignInConfigured: Bool {
        configuration.googleSignInConfigured
    }

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

    func signInWithGoogle() async {
        guard !isWorking else { return }
        guard let clientID = configuration.googleIOSClientID,
              let serverClientID = configuration.googleServerClientID else {
            errorMessage = "Sign in with Google is not configured for this build."
            return
        }
        guard let presentingViewController = Self.presentingViewController() else {
            errorMessage = "Woven could not present Google sign-in."
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: clientID,
                serverClientID: serverClientID
            )
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController
            )
            guard let idToken = result.user.idToken?.tokenString, !idToken.isEmpty else {
                throw AppConfigurationError.invalid("Google did not return a verifiable identity.")
            }
            let data = try await request(path: "/auth/google", body: ["id_token": idToken])
            let response = try JSONDecoder().decode(ProductionSessionResponse.self, from: data)
            KeychainHelper.shared.save(key: refreshKey, value: response.refreshToken)
            session = response.pairSession
        } catch {
            if (error as NSError).code == GIDSignInError.canceled.rawValue {
                errorMessage = "Sign in with Google was cancelled."
            } else {
                errorMessage = "Sign in with Google failed. Please try again."
            }
        }
    }

    func signOut() async {
        let refreshToken = KeychainHelper.shared.read(key: refreshKey)
        clearLocalSession()
        GIDSignIn.sharedInstance.signOut()
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

    private static func presentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var presented = root
        while let next = presented?.presentedViewController {
            presented = next
        }
        return presented
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
            Text("Your Apple or Google identity authenticates your account. Vault keys remain only on your devices.")
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
            if store.googleSignInConfigured {
                HStack {
                    Divider()
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                }
                GoogleSignInButton {
                    Task { await store.signInWithGoogle() }
                }
                .frame(height: 50)
                .disabled(store.isWorking)
                .accessibilityLabel("Sign in with Google")
            }
            if store.isWorking { ProgressView() }
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
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
