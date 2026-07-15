import Foundation

nonisolated struct SoloVaultManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    var name: String
    let createdAt: Date
    var media: [SoloVaultMediaRecord]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: UUID,
        name: String,
        createdAt: Date,
        media: [SoloVaultMediaRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.media = media
    }

    var summary: SoloVaultSummary {
        SoloVaultSummary(id: id, name: name, photoCount: media.count)
    }
}

nonisolated struct SoloVaultMediaRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let encryptedFileName: String
    let encryptedByteCount: Int
}

nonisolated struct SoloVaultSummary: Equatable, Sendable {
    let id: UUID
    let name: String
    let photoCount: Int
}

nonisolated enum SoloVaultPhase: Equatable, Sendable {
    case loading
    case noVault
    case locked(SoloVaultSummary)
    case unlocked(SoloVaultManifest)
    case failed(String)

    var isUnlocked: Bool {
        if case .unlocked = self {
            return true
        }
        return false
    }
}

nonisolated enum SoloVaultError: LocalizedError, Equatable {
    case authenticationUnavailable
    case authenticationFailed
    case invalidKey
    case encryptionFailed
    case authenticationTagMismatch
    case vaultAlreadyExists
    case vaultNotFound
    case mediaNotFound
    case unsupportedSchema
    case corruptStorage

    var errorDescription: String? {
        switch self {
        case .authenticationUnavailable:
            return "Device authentication is not available. Set a device passcode and try again."
        case .authenticationFailed:
            return "Woven could not verify your identity."
        case .invalidKey:
            return "The vault encryption key is unavailable or invalid."
        case .encryptionFailed:
            return "Woven could not encrypt this photo."
        case .authenticationTagMismatch:
            return "This encrypted photo failed its integrity check."
        case .vaultAlreadyExists:
            return "A Solo vault already exists on this device."
        case .vaultNotFound:
            return "The Solo vault could not be found."
        case .mediaNotFound:
            return "The encrypted photo could not be found."
        case .unsupportedSchema:
            return "This vault was created by an unsupported version of Woven."
        case .corruptStorage:
            return "The local vault data is incomplete or damaged."
        }
    }
}
