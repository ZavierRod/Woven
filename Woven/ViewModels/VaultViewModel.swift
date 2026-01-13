import Foundation
import SwiftUI
import Combine

/// ViewModel for managing vault state
@MainActor
class VaultViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var vaults: [Vault] = []
    @Published var selectedVault: VaultDetail?
    @Published var pendingInvites: [VaultDetail] = []
    
    @Published var isLoading = false
    @Published var isCreating = false
    @Published var isDeleting = false
    
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    // MARK: - Private
    
    private let service = VaultService.shared
    
    // MARK: - Fetch Vaults
    
    func fetchVaults() async {
        isLoading = true
        errorMessage = nil
        
        do {
            vaults = try await service.fetchVaults()
            print("✅ Fetched \(vaults.count) vaults")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to fetch vaults: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Get Vault Detail
    
    func getVaultDetail(id: UUID) async {
        isLoading = true
        errorMessage = nil
        
        do {
            selectedVault = try await service.getVault(id: id)
            print("✅ Fetched vault detail: \(selectedVault?.name ?? "nil")")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to get vault: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Create Vault
    
    func createVault(name: String, type: VaultType, mode: VaultMode) async -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a vault name"
            return false
        }
        
        isCreating = true
        errorMessage = nil
        
        do {
            let newVault = try await service.createVault(name: name, type: type, mode: mode)
            vaults.insert(newVault, at: 0) // Add to top of list
            successMessage = "Vault created!"
            print("✅ Created vault: \(newVault.name)")
            isCreating = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to create vault: \(error)")
            isCreating = false
            return false
        }
    }
    
    // MARK: - Delete Vault
    
    func deleteVault(id: UUID) async -> Bool {
        isDeleting = true
        errorMessage = nil
        
        do {
            try await service.deleteVault(id: id)
            vaults.removeAll { $0.id == id }
            successMessage = "Vault deleted"
            print("✅ Deleted vault: \(id)")
            isDeleting = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to delete vault: \(error)")
            isDeleting = false
            return false
        }
    }
    
    // MARK: - Invite to Vault
    
    func inviteToVault(vaultId: UUID, inviteCode: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await service.inviteToVault(vaultId: vaultId, inviteCode: inviteCode)
            successMessage = response.message
            // Refresh vault detail to show pending invite
            await getVaultDetail(id: vaultId)
            print("✅ Invited user to vault")
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to invite: \(error)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Fetch Pending Invites
    
    func fetchPendingInvites() async {
        do {
            pendingInvites = try await service.getPendingInvites()
            print("✅ Fetched \(pendingInvites.count) pending invites")
        } catch {
            print("❌ Failed to fetch pending invites: \(error)")
        }
    }
    
    // MARK: - Accept Invite
    
    func acceptInvite(vaultId: UUID) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let vault = try await service.acceptInvite(vaultId: vaultId)
            pendingInvites.removeAll { $0.id == vaultId }
            vaults.insert(vault, at: 0)
            successMessage = "Joined vault!"
            print("✅ Accepted invite to vault: \(vault.name)")
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to accept invite: \(error)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Decline Invite
    
    func declineInvite(vaultId: UUID) async -> Bool {
        isLoading = true
        
        do {
            try await service.declineInvite(vaultId: vaultId)
            pendingInvites.removeAll { $0.id == vaultId }
            print("✅ Declined invite")
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to decline invite: \(error)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Leave Vault
    
    func leaveVault(id: UUID) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            try await service.leaveVault(id: id)
            vaults.removeAll { $0.id == id }
            successMessage = "Left vault"
            print("✅ Left vault")
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to leave vault: \(error)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Helpers
    
    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
    
    func clearSelectedVault() {
        selectedVault = nil
    }
}

