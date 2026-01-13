import Foundation

// MARK: - Vault Types

enum VaultType: String, Codable, CaseIterable {
    case solo = "solo"
    case pair = "pair"
    
    var displayName: String {
        switch self {
        case .solo: return "Solo Vault"
        case .pair: return "Pair Vault"
        }
    }
    
    var icon: String {
        switch self {
        case .solo: return "person.fill"
        case .pair: return "person.2.fill"
        }
    }
    
    var description: String {
        switch self {
        case .solo: return "A private vault just for you"
        case .pair: return "Shared with one trusted person"
        }
    }
}

enum VaultMode: String, Codable, CaseIterable {
    case normal = "normal"
    case strict = "strict"
    
    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .strict: return "Strict"
        }
    }
    
    var description: String {
        switch self {
        case .normal: return "Access anytime with Face ID"
        case .strict: return "Requires partner approval each time"
        }
    }
}

// MARK: - Vault Model

struct Vault: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: VaultType
    let mode: VaultMode
    let ownerId: Int
    let createdAt: Date
    let updatedAt: Date?
    let lastAccessedAt: Date?
    let memberCount: Int
    let mediaCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, mode
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastAccessedAt = "last_accessed_at"
        case memberCount = "member_count"
        case mediaCount = "media_count"
    }
    
    var isPairVault: Bool {
        type == .pair
    }
    
    var isStrictMode: Bool {
        mode == .strict
    }
}

// MARK: - Vault Member

struct VaultMember: Codable, Identifiable {
    let id: Int
    let userId: Int
    let user: VaultUser?
    let role: String
    let status: String
    let joinedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case user, role, status
        case joinedAt = "joined_at"
    }
    
    var isOwner: Bool {
        role == "owner"
    }
    
    var isAccepted: Bool {
        status == "accepted"
    }
    
    var isPending: Bool {
        status == "pending"
    }
}

// MARK: - Vault User (nested in member responses)

struct VaultUser: Codable {
    let id: Int
    let email: String?
    let fullName: String?
    let inviteCode: String?
    
    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case inviteCode = "invite_code"
    }
    
    var displayName: String {
        // Prefer full name, but skip empty strings
        if let name = fullName, !name.isEmpty {
            return name
        }
        // Fall back to email, extracting username if it's a private relay
        if let email = email, !email.isEmpty {
            // If it's an Apple private relay email, just show "User"
            if email.contains("privaterelay.appleid.com") {
                return "User"
            }
            // Otherwise show the part before @
            return email.components(separatedBy: "@").first ?? email
        }
        return "User"
    }
}

// MARK: - Vault Detail Response (includes members)

struct VaultDetail: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: VaultType
    let mode: VaultMode
    let ownerId: Int
    let owner: VaultUser?
    let createdAt: Date
    let updatedAt: Date?
    let lastAccessedAt: Date?
    let memberCount: Int
    let mediaCount: Int
    let members: [VaultMember]
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, mode, owner, members
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastAccessedAt = "last_accessed_at"
        case memberCount = "member_count"
        case mediaCount = "media_count"
    }
    
    /// Get the partner in a pair vault (non-owner member)
    var partner: VaultMember? {
        members.first { !$0.isOwner && $0.isAccepted }
    }
    
    /// Get pending invites
    var pendingInvites: [VaultMember] {
        members.filter { $0.isPending }
    }
}

// MARK: - Request/Response Types

struct CreateVaultRequest: Codable {
    let name: String
    let type: VaultType
    let mode: VaultMode
}

struct VaultInviteRequest: Codable {
    let inviteCode: String
    
    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
    }
}

struct VaultInviteResponse: Codable {
    let vaultId: UUID
    let invitedUserId: Int
    let status: String
    let message: String
    
    enum CodingKeys: String, CodingKey {
        case vaultId = "vault_id"
        case invitedUserId = "invited_user_id"
        case status, message
    }
}

