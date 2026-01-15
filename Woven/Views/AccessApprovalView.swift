import SwiftUI

struct AccessApprovalView: View {
    let requestId: Int
    @State private var request: AccessRequest?
    @State private var vaultName: String?
    @State private var requesterName: String?
    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            WovenTheme.background.ignoresSafeArea()
            
            VStack(spacing: 20) {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error: error)
                } else if let success = successMessage {
                    successView(message: success)
                } else if let request = request {
                    approvalView(request: request)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRequest()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: WovenTheme.spacing16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(WovenTheme.accent)
            
            Text("Loading request...")
                .font(WovenTheme.subheadline())
                .foregroundColor(WovenTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    private func errorView(error: String) -> some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(WovenTheme.error.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                ZStack {
                    Circle()
                        .fill(WovenTheme.cardBackground)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(WovenTheme.error)
                }
            }
            
            VStack(spacing: WovenTheme.spacing8) {
                Text("Error")
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text(error)
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                dismiss()
            } label: {
                Text("Close")
            }
            .buttonStyle(WovenButtonStyle())
            .padding(.top, WovenTheme.spacing8)
            
            Spacer()
        }
    }
    
    // MARK: - Success View
    private func successView(message: String) -> some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(WovenTheme.success.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                ZStack {
                    Circle()
                        .fill(WovenTheme.cardBackground)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(WovenTheme.success)
                }
            }
            
            VStack(spacing: WovenTheme.spacing8) {
                Text("Approved")
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text(message)
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .buttonStyle(WovenButtonStyle())
            .padding(.top, WovenTheme.spacing8)
            
            Spacer()
        }
    }
    
    // MARK: - Approval View
    private func approvalView(request: AccessRequest) -> some View {
        VStack(spacing: WovenTheme.spacing32) {
            Spacer()
            
            // Icon with glow
            ZStack {
                Circle()
                    .fill(Color(hex: "A855F7").opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                ZStack {
                    Circle()
                        .fill(WovenTheme.cardBackground)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "A855F7"), Color(hex: "6366F1")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            
            VStack(spacing: WovenTheme.spacing16) {
                Text("Unlock Request")
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                VStack(spacing: WovenTheme.spacing12) {
                    // Request info card
                    VStack(spacing: WovenTheme.spacing8) {
                        HStack {
                            Text("From:")
                                .font(WovenTheme.caption())
                                .foregroundColor(WovenTheme.textSecondary)
                            Spacer()
                            Text(requesterName ?? "Unknown")
                                .font(WovenTheme.subheadline())
                                .fontWeight(.medium)
                                .foregroundColor(WovenTheme.textPrimary)
                        }
                        
                        Divider()
                            .background(WovenTheme.textTertiary)
                        
                        HStack {
                            Text("Vault:")
                                .font(WovenTheme.caption())
                                .foregroundColor(WovenTheme.textSecondary)
                            Spacer()
                            Text(vaultName ?? "Loading...")
                                .font(WovenTheme.subheadline())
                                .fontWeight(.medium)
                                .foregroundColor(WovenTheme.textPrimary)
                        }
                    }
                    .padding(WovenTheme.spacing16)
                    .background(WovenTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
                    
                    if request.status != .pending {
                        Text("This request is already \(request.status.rawValue)")
                            .font(WovenTheme.caption())
                            .foregroundColor(WovenTheme.textSecondary)
                            .padding(.top, WovenTheme.spacing8)
                    }
                }
            }
            
            if request.status == .pending {
                VStack(spacing: WovenTheme.spacing12) {
                    // Approve button
                    Button {
                        approveRequest()
                    } label: {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Approve Access")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WovenButtonStyle())
                    .disabled(isProcessing)
                    
                    // Deny button
                    Button {
                        denyRequest()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                            Text("Deny")
                        }
                        .font(WovenTheme.subheadline())
                        .fontWeight(.semibold)
                        .foregroundColor(WovenTheme.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(WovenTheme.error.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
                    }
                    .disabled(isProcessing)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Load Request
    private func loadRequest() async {
        do {
            // Load the access request
            request = try await AccessRequestManager.shared.getRequest(id: requestId)
            
            // Load vault details
            if let vaultId = request?.vaultId {
                let vaultDetail = try? await VaultService.shared.getVault(id: vaultId)
                await MainActor.run {
                    vaultName = vaultDetail?.name
                }
            }
            
            // Load requester details
            if let requesterId = request?.requesterId {
                let friends = try? await FriendService.shared.getFriends()
                let requester = friends?.first { $0.id == requesterId }
                await MainActor.run {
                    requesterName = requester?.fullName ?? requester?.username
                }
            }
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    // MARK: - Approve Request
    private func approveRequest() {
        guard let req = request else { return }
        
        Task {
            isProcessing = true
            do {
                // 1. Get the vault key (in strict mode, this should be the user's share)
                guard let key = VaultKeyManager.shared.getVaultKey(vaultId: req.vaultId) else {
                    throw VaultServiceError.apiError(message: "Could not find key for this vault")
                }
                
                let keyData = EncryptionService.shared.keyToData(key)
                
                // 2. Approve & Encrypt the key share
                try await AccessRequestManager.shared.approveRequest(request: req, shareOrKey: keyData)
                
                await MainActor.run {
                    withAnimation {
                        successMessage = "Access approved! Your partner can now open the vault."
                        isProcessing = false
                    }
                }
                
                // Auto-dismiss after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
    
    // MARK: - Deny Request
    private func denyRequest() {
        guard let req = request else { return }
        
        Task {
            isProcessing = true
            do {
                try await AccessRequestManager.shared.denyRequest(requestId: req.id)
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}
