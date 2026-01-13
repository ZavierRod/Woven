import Foundation

struct Friend: Codable, Identifiable {
    let id: Int
    let username: String
    let fullName: String?
    let inviteCode: String?
    let profilePictureUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username
        case fullName = "full_name"
        case inviteCode = "invite_code"
        case profilePictureUrl = "profile_picture_url"
    }
}

struct Friendship: Codable, Identifiable {
    let id: Int
    let userId: Int
    let friendId: Int
    let status: String
    let createdAt: Date
    let friend: Friend?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case friendId = "friend_id"
        case status
        case createdAt = "created_at"
        case friend
    }
}

struct PendingFriendRequest: Codable, Identifiable {
    let id: Int
    let userId: Int
    let status: String
    let createdAt: Date
    let requester: Friend?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case status
        case createdAt = "created_at"
        case requester
    }
}

struct FriendListResponse: Codable {
    let friends: [Friend]
    let total: Int
}

struct PendingRequestsResponse: Codable {
    let requests: [PendingFriendRequest]
    let total: Int
}

struct FriendRequestCreate: Codable {
    let inviteCode: String
    
    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
    }
}
