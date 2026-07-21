import Foundation

#if WOVEN_DEVELOPMENT_AUTH
enum PairDevelopmentAccount: String, CaseIterable, Codable, Identifiable, Sendable {
    case alice
    case bob

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var partner: Self { self == .alice ? .bob : .alice }
}
#endif

struct PairSession: Codable, Equatable, Sendable {
    let accessToken: String
    let tokenType: String
    let userID: Int
    let username: String
    let email: String
    let fullName: String?
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case userID = "user_id"
        case username, email
        case fullName = "full_name"
        case inviteCode = "invite_code"
    }
}

struct PairAccountLookup: Codable, Sendable {
    let userID: Int
    let username: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
    }
}

struct PairDevice: Codable, Equatable, Sendable {
    let deviceID: String
    let userID: Int
    let agreementPublicKey: String
    let signingPublicKey: String
    let createdAtMS: Int64
    let revoked: Bool

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case userID = "user_id"
        case agreementPublicKey = "agreement_public_key"
        case signingPublicKey = "signing_public_key"
        case createdAtMS = "created_at_ms"
        case revoked
    }
}

struct PairMember: Codable, Equatable, Sendable {
    let userID: Int
    let deviceID: String
    let role: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceID = "device_id"
        case role, status
    }
}

struct PairVaultRecord: Codable, Equatable, Identifiable, Sendable {
    let vaultID: String
    let encryptedMetadata: String
    let membershipVersion: Int
    let status: String
    let createdAtMS: Int64
    let members: [PairMember]

    var id: String { vaultID }

    enum CodingKeys: String, CodingKey {
        case vaultID = "vault_id"
        case encryptedMetadata = "encrypted_metadata"
        case membershipVersion = "membership_version"
        case status
        case createdAtMS = "created_at_ms"
        case members
    }
}

struct PairInvitationContext: Codable, Equatable, Sendable {
    let protocolName: String
    let purpose: String
    let vaultID: String
    let invitationID: String
    let membershipVersion: Int
    let creatorAccountID: Int
    let creatorDeviceID: String
    let targetAccountID: Int
    let targetDeviceID: String
    let createdAtMS: Int64
    let expiresAtMS: Int64

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case purpose
        case vaultID = "vault_id"
        case invitationID = "invitation_id"
        case membershipVersion = "membership_version"
        case creatorAccountID = "creator_account_id"
        case creatorDeviceID = "creator_device_id"
        case targetAccountID = "target_account_id"
        case targetDeviceID = "target_device_id"
        case createdAtMS = "created_at_ms"
        case expiresAtMS = "expires_at_ms"
    }
}

struct PairInvitationRecord: Codable, Equatable, Identifiable, Sendable {
    let invitationID: String
    let vaultID: String
    let status: String
    let context: PairInvitationContext
    let encryptedShareEnvelope: String?

    var id: String { invitationID }

    enum CodingKeys: String, CodingKey {
        case invitationID = "invitation_id"
        case vaultID = "vault_id"
        case status, context
        case encryptedShareEnvelope = "encrypted_share_envelope"
    }
}

struct PairAccessContext: Codable, Equatable, Sendable {
    let protocolName: String
    let purpose: String
    let vaultID: String
    let requestID: String
    let membershipVersion: Int
    let requesterAccountID: Int
    let requesterDeviceID: String
    let requesterEphemeralPublicKey: String
    let approverAccountID: Int
    let approverDeviceID: String
    let createdAtMS: Int64
    let expiresAtMS: Int64

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case purpose
        case vaultID = "vault_id"
        case requestID = "request_id"
        case membershipVersion = "membership_version"
        case requesterAccountID = "requester_account_id"
        case requesterDeviceID = "requester_device_id"
        case requesterEphemeralPublicKey = "requester_ephemeral_public_key"
        case approverAccountID = "approver_account_id"
        case approverDeviceID = "approver_device_id"
        case createdAtMS = "created_at_ms"
        case expiresAtMS = "expires_at_ms"
    }
}

enum PairAccessStatus: String, Codable, Sendable {
    case pending
    case approved
    case denied
    case expired
    case cancelled
    case consumed
}

struct PairAccessRecord: Codable, Equatable, Identifiable, Sendable {
    let requestID: String
    let vaultID: String
    let status: PairAccessStatus
    let context: PairAccessContext
    let encryptedShareEnvelope: String?

    var id: String { requestID }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case vaultID = "vault_id"
        case status, context
        case encryptedShareEnvelope = "encrypted_share_envelope"
    }
}

struct PairMediaRecord: Codable, Equatable, Identifiable, Sendable {
    let mediaID: String
    let vaultID: String
    let encryptedBlob: String?
    let encryptedMetadata: String
    let createdAtMS: Int64

    var id: String { mediaID }

    enum CodingKeys: String, CodingKey {
        case mediaID = "media_id"
        case vaultID = "vault_id"
        case encryptedBlob = "encrypted_blob"
        case encryptedMetadata = "encrypted_metadata"
        case createdAtMS = "created_at_ms"
    }
}

struct PairVaultCreateResponse: Codable, Sendable {
    let vault: PairVaultRecord
    let invitation: PairInvitationRecord
}

struct PairInvitationAcceptResponse: Codable, Sendable {
    let vault: PairVaultRecord
    let invitation: PairInvitationRecord
}

struct PairConsumeResponse: Codable, Sendable {
    let status: String
    let context: PairAccessContext
    let encryptedShareEnvelope: String

    enum CodingKeys: String, CodingKey {
        case status, context
        case encryptedShareEnvelope = "encrypted_share_envelope"
    }
}

struct PairVaultPrivateMetadata: Codable, Equatable, Sendable {
    let name: String
}

struct PairMediaPrivateMetadata: Codable, Equatable, Sendable {
    let mediaID: String
    let createdAtMS: Int64
    let mediaType: String
}

struct PairDecryptedMedia: Identifiable, Equatable, Sendable {
    let id: String
    let createdAtMS: Int64
    let imageData: Data
}

enum PairVaultScreenPhase: Equatable, Sendable {
    case signedOut
    case loading
    case ready
    case invitation(PairInvitationRecord)
    case waitingForPartner(PairVaultRecord)
    case locked(PairVaultRecord)
    case unlocked(PairVaultRecord, name: String)
    case failed(String)
}

enum PairAccessPhase: Equatable, Sendable {
    case none
    case creatingRequest
    case awaitingApproval(PairAccessRecord)
    case approved
    case denied
    case expired
    case cancelled
    case consumed
    case failed(String)
}

enum PairVaultError: LocalizedError, Equatable {
    case malformedData
    case invalidKeyLength
    case missingLocalShare
    case missingInvitationEnvelope
    case contextMismatch
    case relay(String)
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .malformedData: "The encrypted Pair data is malformed."
        case .invalidKeyLength: "Pair key material has an invalid length."
        case .missingLocalShare: "This device no longer has its Pair key share."
        case .missingInvitationEnvelope: "The invitation is missing its encrypted key share."
        case .contextMismatch: "The approval context did not match the request."
        case .relay(let message): message
        case .authenticationFailed: "Device-owner authentication was not completed."
        }
    }
}
