import Foundation

// MARK: - Media Type

enum MediaType: String, Codable {
    case photo = "photo"
    case video = "video"
}

// MARK: - Media Model

struct Media: Codable, Identifiable {
    let id: UUID
    let vaultId: UUID
    let mediaType: MediaType
    let fileName: String
    let fileSize: Int
    let uploadedById: Int
    let uploadedBy: MediaUser?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case vaultId = "vault_id"
        case mediaType = "media_type"
        case fileName = "file_name"
        case fileSize = "file_size"
        case uploadedById = "uploaded_by_id"
        case uploadedBy = "uploaded_by"
        case createdAt = "created_at"
    }
    
    var isPhoto: Bool {
        mediaType == .photo
    }
    
    var isVideo: Bool {
        mediaType == .video
    }
}

// MARK: - Media User (nested in media responses)

struct MediaUser: Codable {
    let id: Int
    let username: String?
    let email: String?
    let fullName: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username, email
        case fullName = "full_name"
    }
}

// MARK: - Media List Response

struct MediaListResponse: Codable {
    let media: [Media]
    let total: Int
}

// MARK: - Media View URL Response

struct MediaViewUrlResponse: Codable {
    let viewUrl: String
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case viewUrl = "view_url"
        case expiresIn = "expires_in"
    }
}


