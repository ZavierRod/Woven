import SwiftUI

struct AccessApprovalView: View {
    let requestId: Int
    @State private var request: AccessRequest?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                ProgressView("Loading request...")
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
                Button("Close") { dismiss() }
            } else if let success = successMessage {
                ContentUnavailableView {
                    Label("Approved", systemImage: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.green)
                } description: {
                    Text(success)
                }
                Button("Done") { dismiss() }
            } else if let request = request {
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("Unlock Request")
                        .font(.title2.bold())
                    
                    VStack(spacing: 8) {
                        Text("Partner wants to open vault")
                            .foregroundStyle(.secondary)
                        
                        // In a real app, resolve User ID to Name via FriendService
                        Text("Request from User #\(request.requesterId)")
                            .font(.headline)
                        
                        Text("Vault #\(request.vaultId)")
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    if request.status != .pending {
                        Text("This request is already \(request.status.rawValue).")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 16) {
                            Button(role: .destructive) {
                                // Implement Deny
                                errorMessage = "Deny not implemented in this demo" 
                            } label: {
                                Text("Deny")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                approveRequest()
                            } label: {
                                Text("Approve")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()
            }
        }
        .task {
            await loadRequest()
        }
    }
    
    private func loadRequest() async {
        do {
            request = try await AccessRequestManager.shared.getRequest(id: requestId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func approveRequest() {
        guard let req = request else { return }
        
        Task {
            isLoading = true
            do {
                // 1. Get the Key (In Strict Mode, this is MY share, but for now we send the Full Key)
                guard let key = VaultKeyManager.shared.getVaultKey(vaultId: req.vaultId) else {
                    throw VaultServiceError.apiError(message: "Could not find key for this vault")
                }
                
                let keyData = EncryptionService.shared.keyToData(key)
                
                // 2. Approve & Encrypt
                try await AccessRequestManager.shared.approveRequest(request: req, shareOrKey: keyData)
                
                withAnimation {
                    successMessage = "Request approved! Partner can now access the vault."
                    isLoading = false
                }
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
