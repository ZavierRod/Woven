import Foundation

@MainActor
protocol PairRelayAPI: Sendable {
    func developmentSession(_ account: PairDevelopmentAccount) async throws -> PairSession
    func registerDevice(session: PairSession, deviceID: String, publicKey: Data) async throws -> PairDevice
    func device(for userID: Int, session: PairSession) async throws -> PairDevice
    func createVault(
        session: PairSession,
        vaultID: String,
        creatorDeviceID: String,
        encryptedMetadata: String,
        invitationID: String,
        target: PairDevice,
        tokenHash: String,
        encryptedShareEnvelope: String,
        createdAtMS: Int64,
        expiresAtMS: Int64
    ) async throws -> PairVaultCreateResponse
    func invitations(session: PairSession) async throws -> [PairInvitationRecord]
    func acceptInvitation(id: String, token: String, session: PairSession) async throws -> PairInvitationAcceptResponse
    func vaults(session: PairSession) async throws -> [PairVaultRecord]
    func createAccessRequest(
        vaultID: String,
        requestID: String,
        requesterDeviceID: String,
        ephemeralPublicKey: Data,
        createdAtMS: Int64,
        expiresAtMS: Int64,
        session: PairSession
    ) async throws -> PairAccessRecord
    func incomingAccessRequests(session: PairSession) async throws -> [PairAccessRecord]
    func accessRequest(id: String, session: PairSession) async throws -> PairAccessRecord
    func approveAccessRequest(id: String, envelope: String, session: PairSession) async throws -> PairAccessRecord
    func denyAccessRequest(id: String, session: PairSession) async throws
    func consumeAccessRequest(id: String, session: PairSession) async throws -> PairConsumeResponse
    func cancelAccessRequest(id: String, session: PairSession) async throws
    func listMedia(vaultID: String, session: PairSession) async throws -> [PairMediaRecord]
    func downloadMedia(vaultID: String, mediaID: String, session: PairSession) async throws -> PairMediaRecord
    func uploadMedia(
        vaultID: String,
        mediaID: String,
        encryptedBlob: Data,
        encryptedMetadata: Data,
        createdAtMS: Int64,
        session: PairSession
    ) async throws -> PairMediaRecord
    func deleteMedia(vaultID: String, mediaID: String, session: PairSession) async throws
    func revokeMember(vaultID: String, userID: Int, session: PairSession) async throws
}

@MainActor
final class PairVaultAPIClient: PairRelayAPI, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func developmentSession(_ account: PairDevelopmentAccount) async throws -> PairSession {
        try await send(path: "/pair-v2/dev/session/\(account.rawValue)", method: "POST", token: nil, body: EmptyBody())
    }

    func registerDevice(session: PairSession, deviceID: String, publicKey: Data) async throws -> PairDevice {
        try await send(
            path: "/pair-v2/devices",
            method: "POST",
            token: session.accessToken,
            body: DeviceBody(deviceID: deviceID, agreementPublicKey: publicKey.base64EncodedString())
        )
    }

    func device(for userID: Int, session: PairSession) async throws -> PairDevice {
        try await send(path: "/pair-v2/devices/users/\(userID)", method: "GET", token: session.accessToken, body: EmptyBody())
    }

    func createVault(
        session: PairSession,
        vaultID: String,
        creatorDeviceID: String,
        encryptedMetadata: String,
        invitationID: String,
        target: PairDevice,
        tokenHash: String,
        encryptedShareEnvelope: String,
        createdAtMS: Int64,
        expiresAtMS: Int64
    ) async throws -> PairVaultCreateResponse {
        try await send(
            path: "/pair-v2/vaults",
            method: "POST",
            token: session.accessToken,
            body: VaultCreateBody(
                vaultID: vaultID,
                creatorDeviceID: creatorDeviceID,
                encryptedMetadata: encryptedMetadata,
                invitation: InvitationBody(
                    invitationID: invitationID,
                    targetUserID: target.userID,
                    targetDeviceID: target.deviceID,
                    tokenSHA256: tokenHash,
                    encryptedShareEnvelope: encryptedShareEnvelope,
                    createdAtMS: createdAtMS,
                    expiresAtMS: expiresAtMS
                )
            )
        )
    }

    func invitations(session: PairSession) async throws -> [PairInvitationRecord] {
        try await send(path: "/pair-v2/invitations", method: "GET", token: session.accessToken, body: EmptyBody())
    }

    func acceptInvitation(id: String, token: String, session: PairSession) async throws -> PairInvitationAcceptResponse {
        try await send(
            path: "/pair-v2/invitations/\(id)/accept",
            method: "POST",
            token: session.accessToken,
            body: InvitationAcceptBody(token: token)
        )
    }

    func vaults(session: PairSession) async throws -> [PairVaultRecord] {
        try await send(path: "/pair-v2/vaults", method: "GET", token: session.accessToken, body: EmptyBody())
    }

    func createAccessRequest(
        vaultID: String,
        requestID: String,
        requesterDeviceID: String,
        ephemeralPublicKey: Data,
        createdAtMS: Int64,
        expiresAtMS: Int64,
        session: PairSession
    ) async throws -> PairAccessRecord {
        try await send(
            path: "/pair-v2/vaults/\(vaultID)/access-requests",
            method: "POST",
            token: session.accessToken,
            body: AccessCreateBody(
                requestID: requestID,
                requesterDeviceID: requesterDeviceID,
                requesterEphemeralPublicKey: ephemeralPublicKey.base64EncodedString(),
                createdAtMS: createdAtMS,
                expiresAtMS: expiresAtMS
            )
        )
    }

    func incomingAccessRequests(session: PairSession) async throws -> [PairAccessRecord] {
        try await send(path: "/pair-v2/access-requests/incoming", method: "GET", token: session.accessToken, body: EmptyBody())
    }

    func accessRequest(id: String, session: PairSession) async throws -> PairAccessRecord {
        try await send(path: "/pair-v2/access-requests/\(id)", method: "GET", token: session.accessToken, body: EmptyBody())
    }

    func approveAccessRequest(id: String, envelope: String, session: PairSession) async throws -> PairAccessRecord {
        try await send(
            path: "/pair-v2/access-requests/\(id)/approve",
            method: "POST",
            token: session.accessToken,
            body: ApprovalBody(encryptedShareEnvelope: envelope)
        )
    }

    func denyAccessRequest(id: String, session: PairSession) async throws {
        let _: RelayStatus = try await send(path: "/pair-v2/access-requests/\(id)/deny", method: "POST", token: session.accessToken, body: EmptyBody())
    }

    func consumeAccessRequest(id: String, session: PairSession) async throws -> PairConsumeResponse {
        try await send(path: "/pair-v2/access-requests/\(id)/consume", method: "POST", token: session.accessToken, body: EmptyBody())
    }

    func cancelAccessRequest(id: String, session: PairSession) async throws {
        let _: RelayStatus = try await send(path: "/pair-v2/access-requests/\(id)/cancel", method: "POST", token: session.accessToken, body: EmptyBody())
    }

    func listMedia(vaultID: String, session: PairSession) async throws -> [PairMediaRecord] {
        try await send(path: "/pair-v2/vaults/\(vaultID)/media", method: "GET", token: session.accessToken, body: EmptyBody())
    }

    func downloadMedia(vaultID: String, mediaID: String, session: PairSession) async throws -> PairMediaRecord {
        try await send(path: "/pair-v2/vaults/\(vaultID)/media/\(mediaID)", method: "GET", token: session.accessToken, body: EmptyBody())
    }

    func uploadMedia(
        vaultID: String,
        mediaID: String,
        encryptedBlob: Data,
        encryptedMetadata: Data,
        createdAtMS: Int64,
        session: PairSession
    ) async throws -> PairMediaRecord {
        try await send(
            path: "/pair-v2/vaults/\(vaultID)/media",
            method: "POST",
            token: session.accessToken,
            body: MediaCreateBody(
                mediaID: mediaID,
                encryptedBlob: encryptedBlob.base64EncodedString(),
                encryptedMetadata: encryptedMetadata.base64EncodedString(),
                createdAtMS: createdAtMS
            )
        )
    }

    func deleteMedia(vaultID: String, mediaID: String, session: PairSession) async throws {
        try await sendWithoutResponse(
            path: "/pair-v2/vaults/\(vaultID)/media/\(mediaID)",
            method: "DELETE",
            token: session.accessToken
        )
    }

    func revokeMember(vaultID: String, userID: Int, session: PairSession) async throws {
        let _: RelayStatus = try await send(
            path: "/pair-v2/vaults/\(vaultID)/members/\(userID)",
            method: "DELETE",
            token: session.accessToken,
            body: EmptyBody()
        )
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        token: String?,
        body: Body
    ) async throws -> Response {
        let (data, response) = try await session.data(for: request(path: path, method: method, token: token, body: body))
        try validate(response: response, data: data)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw PairVaultError.relay("The Pair relay returned an unreadable response.")
        }
    }

    private func sendWithoutResponse(path: String, method: String, token: String?) async throws {
        let (data, response) = try await session.data(for: request(path: path, method: method, token: token, body: EmptyBody()))
        try validate(response: response, data: data)
    }

    private func request<Body: Encodable>(path: String, method: String, token: String?, body: Body) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw PairVaultError.malformedData }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if method != "GET" && method != "DELETE" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw PairVaultError.relay("The Pair relay did not return HTTP.") }
        guard 200..<300 ~= http.statusCode else {
            let detail = (try? decoder.decode(RelayProblem.self, from: data).detail) ?? "Pair relay request failed (\(http.statusCode))."
            throw PairVaultError.relay(detail)
        }
    }
}

private struct EmptyBody: Codable, Sendable {}
private struct RelayProblem: Codable { let detail: String }
private struct RelayStatus: Codable { let status: String }

private struct DeviceBody: Codable {
    let deviceID: String
    let agreementPublicKey: String
    enum CodingKeys: String, CodingKey { case deviceID = "device_id"; case agreementPublicKey = "agreement_public_key" }
}

private struct VaultCreateBody: Codable {
    let vaultID: String
    let creatorDeviceID: String
    let encryptedMetadata: String
    let invitation: InvitationBody
    enum CodingKeys: String, CodingKey {
        case vaultID = "vault_id"
        case creatorDeviceID = "creator_device_id"
        case encryptedMetadata = "encrypted_metadata"
        case invitation
    }
}

private struct InvitationBody: Codable {
    let invitationID: String
    let targetUserID: Int
    let targetDeviceID: String
    let tokenSHA256: String
    let encryptedShareEnvelope: String
    let createdAtMS: Int64
    let expiresAtMS: Int64
    enum CodingKeys: String, CodingKey {
        case invitationID = "invitation_id"
        case targetUserID = "target_user_id"
        case targetDeviceID = "target_device_id"
        case tokenSHA256 = "token_sha256"
        case encryptedShareEnvelope = "encrypted_share_envelope"
        case createdAtMS = "created_at_ms"
        case expiresAtMS = "expires_at_ms"
    }
}

private struct InvitationAcceptBody: Codable { let token: String }

private struct AccessCreateBody: Codable {
    let requestID: String
    let requesterDeviceID: String
    let requesterEphemeralPublicKey: String
    let createdAtMS: Int64
    let expiresAtMS: Int64
    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case requesterDeviceID = "requester_device_id"
        case requesterEphemeralPublicKey = "requester_ephemeral_public_key"
        case createdAtMS = "created_at_ms"
        case expiresAtMS = "expires_at_ms"
    }
}

private struct ApprovalBody: Codable {
    let encryptedShareEnvelope: String
    enum CodingKeys: String, CodingKey { case encryptedShareEnvelope = "encrypted_share_envelope" }
}

private struct MediaCreateBody: Codable {
    let mediaID: String
    let encryptedBlob: String
    let encryptedMetadata: String
    let createdAtMS: Int64
    enum CodingKeys: String, CodingKey {
        case mediaID = "media_id"
        case encryptedBlob = "encrypted_blob"
        case encryptedMetadata = "encrypted_metadata"
        case createdAtMS = "created_at_ms"
    }
}
