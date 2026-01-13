import Foundation
import Combine

@MainActor
class FriendsViewModel: ObservableObject {
    @Published var friends: [Friend] = []
    @Published var pendingRequests: [PendingFriendRequest] = []
    @Published var sentRequests: [PendingFriendRequest] = []
    @Published var isLoading = false
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    private let friendService = FriendService.shared
    
    // MARK: - Load Data
    
    func loadFriends() async {
        isLoading = true
        errorMessage = nil
        
        do {
            friends = try await friendService.getFriends()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to load friends: \(error)")
        }
        
        isLoading = false
    }
    
    func loadPendingRequests() async {
        do {
            pendingRequests = try await friendService.getPendingRequests()
        } catch {
            print("❌ Failed to load pending requests: \(error)")
        }
    }
    
    func loadSentRequests() async {
        do {
            sentRequests = try await friendService.getSentRequests()
        } catch {
            print("❌ Failed to load sent requests: \(error)")
        }
    }
    
    func loadAll() async {
        isLoading = true
        errorMessage = nil
        
        async let friendsTask: () = loadFriends()
        async let pendingTask: () = loadPendingRequests()
        async let sentTask: () = loadSentRequests()
        
        _ = await (friendsTask, pendingTask, sentTask)
        
        isLoading = false
    }
    
    // MARK: - Send Friend Request
    
    func sendFriendRequest(inviteCode: String) async -> Bool {
        isProcessing = true
        errorMessage = nil
        successMessage = nil
        
        do {
            let friendship = try await friendService.sendFriendRequest(inviteCode: inviteCode)
            successMessage = "Friend request sent to \(friendship.friend?.username ?? "user")!"
            await loadSentRequests()
            isProcessing = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to send friend request: \(error)")
            isProcessing = false
            return false
        }
    }
    
    // MARK: - Accept Request
    
    func acceptRequest(_ request: PendingFriendRequest) async {
        isProcessing = true
        errorMessage = nil
        
        do {
            _ = try await friendService.acceptRequest(friendshipId: request.id)
            pendingRequests.removeAll { $0.id == request.id }
            await loadFriends()
            successMessage = "You are now friends with \(request.requester?.username ?? "user")!"
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to accept request: \(error)")
        }
        
        isProcessing = false
    }
    
    // MARK: - Decline Request
    
    func declineRequest(_ request: PendingFriendRequest) async {
        isProcessing = true
        errorMessage = nil
        
        do {
            try await friendService.declineRequest(friendshipId: request.id)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to decline request: \(error)")
        }
        
        isProcessing = false
    }
    
    // MARK: - Remove Friend
    
    func removeFriend(_ friend: Friend) async {
        isProcessing = true
        errorMessage = nil
        
        do {
            try await friendService.removeFriend(friendUserId: friend.id)
            friends.removeAll { $0.id == friend.id }
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to remove friend: \(error)")
        }
        
        isProcessing = false
    }
    
    // MARK: - Clear Messages
    
    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

