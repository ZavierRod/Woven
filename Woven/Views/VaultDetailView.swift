import SwiftUI
import PhotosUI
import LocalAuthentication

struct VaultDetailView: View {
    let vault: Vault
    @StateObject private var viewModel = VaultViewModel()
    @StateObject private var localAuth = LocalAuthenticationManager()
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDeleteConfirmation = false
    @State private var showInviteSheet = false
    @State private var showSettings = false
    @State private var appeared = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var uploadError: Error?
    @State private var uploadProgress: (current: Int, total: Int)?
    
    // Strict Mode State
    @State private var isStrictUnlocked = false
    @State private var activeRequestId: Int?
    @State private var requestStatus: AccessRequestStatus?
    @State private var showApprovalSent = false
    
    private var accentColor: Color {
        vault.isPairVault ? Color(hex: "A855F7") : WovenTheme.accent
    }
    
    var body: some View {
        ZStack {
            WovenTheme.background.ignoresSafeArea()
            
            if !localAuth.isUnlocked {
                // Lock screen overlay
                vaultLockScreen
            } else if vault.isStrictMode && !isStrictUnlocked {
                strictLockScreen
            } else {
                // Unlocked content
                ScrollView(showsIndicators: false) {
                VStack(spacing: WovenTheme.spacing24) {
                    // Vault Header Card
                    headerCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                    
                    // Members Section (for pair vaults)
                    if vault.isPairVault {
                        membersSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                    }
                    
                    // Media Grid
                    MediaGalleryView(vaultId: vault.id)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                }
                .padding(.horizontal, WovenTheme.spacing20)
                .padding(.top, WovenTheme.spacing16)
                .padding(.bottom, 120)
                }
            }
            
            // Floating Add Media Button
            VStack {
                Spacer()
                
                if isUploading {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(.black)
                        if let progress = uploadProgress {
                            Text("Uploading \(progress.current)/\(progress.total)...")
                                .font(WovenTheme.headline())
                                .foregroundColor(.black)
                        } else {
                            Text("Uploading...")
                                .font(WovenTheme.headline())
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(WovenTheme.cardBackground)
                    .clipShape(Capsule())
                    .padding(.bottom, 30)
                } else {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: nil,
                        matching: .any(of: [.images, .videos])
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                            Text("Add Media")
                                .font(WovenTheme.headline())
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: accentColor.opacity(0.4), radius: 15, x: 0, y: 8)
                    }
                    .padding(.bottom, 30)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
                    .onChange(of: selectedPhotoItems) { oldValue, newValue in
                        Task {
                            if !newValue.isEmpty {
                                await handleBatchMediaSelection(newValue)
                            }
                        }
                    }
                }
                }
        }
        .navigationTitle(vault.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(WovenTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if vault.isPairVault && vault.memberCount < 2 {
                        Button {
                            showInviteSheet = true
                        } label: {
                            Label("Invite Partner", systemImage: "person.badge.plus")
                        }
                    }
                    
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Vault", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(WovenTheme.textSecondary)
                }
            }
        }
        .alert("Delete Vault?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.deleteVault(id: vault.id) {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This will permanently delete all photos and videos in this vault. This cannot be undone.")
        }
        .sheet(isPresented: $showInviteSheet) {
            InvitePartnerSheet(vaultId: vault.id)
        }
        .onAppear {
            // Require Face ID authentication when entering vault
            Task {
                await localAuth.authenticate()
            }
            
            if localAuth.isUnlocked {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    appeared = true
                }
                Task {
                    await viewModel.getVaultDetail(id: vault.id)
                }
            }
        }
        .onChange(of: localAuth.isUnlocked) { oldValue, newValue in
            if newValue {
                // User successfully authenticated, load vault content
                Task {
                    await viewModel.getVaultDetail(id: vault.id)
                }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    appeared = true
                }
            } else {
                // Lock the vault if authentication is lost
                appeared = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MediaDeleted"))) { _ in
            if localAuth.isUnlocked {
                Task {
                    await viewModel.getVaultDetail(id: vault.id)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: WovenTheme.spacing16) {
            // Icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: vault.type.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Vault Info
            VStack(spacing: WovenTheme.spacing8) {
                HStack(spacing: 8) {
                    Text(vault.type.displayName)
                        .font(WovenTheme.caption())
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    
                    if vault.isStrictMode {
                        Text("Strict")
                            .font(WovenTheme.caption())
                            .foregroundColor(WovenTheme.warning)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(WovenTheme.warning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                
                Text("\(vault.mediaCount) item\(vault.mediaCount == 1 ? "" : "s")")
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
            }
            
            // Stats Row
            HStack(spacing: WovenTheme.spacing32) {
                statItem(value: "\(vault.memberCount)", label: "Members")
                
                Divider()
                    .frame(height: 30)
                    .background(WovenTheme.separator)
                
                statItem(value: "\(vault.mediaCount)", label: "Photos")
                
                Divider()
                    .frame(height: 30)
                    .background(WovenTheme.separator)
                
                statItem(value: formattedDate(vault.createdAt), label: "Created")
            }
            .padding(.top, WovenTheme.spacing8)
        }
        .padding(WovenTheme.spacing24)
        .frame(maxWidth: .infinity)
        .background(WovenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusCard, style: .continuous))
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(WovenTheme.textPrimary)
            
            Text(label)
                .font(WovenTheme.caption())
                .foregroundColor(WovenTheme.textTertiary)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    // MARK: - Members Section
    
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: WovenTheme.spacing12) {
            HStack {
                Text("Members")
                    .font(WovenTheme.headline())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Spacer()
                
                if vault.memberCount < 2 {
                    Button {
                        showInviteSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Invite")
                        }
                        .font(WovenTheme.caption())
                        .foregroundColor(accentColor)
                    }
                }
            }
            
            if let detail = viewModel.selectedVault {
                ForEach(detail.members, id: \.id) { member in
                    memberRow(member: member)
                }
            } else {
                // Loading state
                HStack {
                    ProgressView()
                        .tint(WovenTheme.textSecondary)
                    Text("Loading members...")
                        .font(WovenTheme.subheadline())
                        .foregroundColor(WovenTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .padding(WovenTheme.spacing20)
        .background(WovenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous))
    }
    
    private func memberRow(member: VaultMember) -> some View {
        HStack(spacing: WovenTheme.spacing12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        member.isOwner
                            ? LinearGradient(colors: [WovenTheme.accent, WovenTheme.accent.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color(hex: "A855F7"), Color(hex: "A855F7").opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 40, height: 40)
                
                Text(String(member.user?.displayName.prefix(1) ?? "?"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(member.user?.displayName ?? "Unknown")
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text(member.isOwner ? "Owner" : member.isPending ? "Pending" : "Member")
                    .font(WovenTheme.caption())
                    .foregroundColor(member.isPending ? WovenTheme.warning : WovenTheme.textTertiary)
            }
            
            Spacer()
            
            if member.isOwner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12))
                    .foregroundColor(WovenTheme.accent)
            }
        }
        .padding(.vertical, WovenTheme.spacing8)
    }
    
    // MARK: - Media Section
    
    private var mediaSection: some View {
        VStack(spacing: WovenTheme.spacing16) {
            emptyMediaState
        }
    }
    
    // MARK: - Upload Media
    
    private func uploadMedia(data: Data, fileName: String, mediaType: MediaType) async {
        isUploading = true
        uploadError = nil
        
        do {
            let uploadedMedia = try await MediaService.shared.uploadMedia(
                vaultId: vault.id,
                mediaType: mediaType,
                originalData: data,
                fileName: fileName
            )
            
            // Refresh vault detail to update media count
            await viewModel.getVaultDetail(id: vault.id)
            
            // Notify MediaGalleryView to refresh
            NotificationCenter.default.post(name: NSNotification.Name("MediaUploaded"), object: nil)
            
            print("✅ Successfully uploaded media: \(uploadedMedia.fileName)")
        } catch {
            uploadError = error
            print("❌ Failed to upload media: \(error)")
        }
        
        isUploading = false
    }
    
    private var emptyMediaState: some View {
        VStack(spacing: WovenTheme.spacing20) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                    .blur(radius: 15)
                
                ZStack {
                    Circle()
                        .fill(WovenTheme.cardBackground)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            
            VStack(spacing: WovenTheme.spacing8) {
                Text("No memories yet")
                    .font(WovenTheme.headline())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("Add your first photo or video\nto this vault")
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Strict Lock Screen
    
    private var strictLockScreen: some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(WovenTheme.cardBackground)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "shield.check.fill")
                    .font(.system(size: 40))
                    .foregroundColor(requestStatus == .approved ? .green : WovenTheme.warning)
            }
            
            VStack(spacing: WovenTheme.spacing8) {
                Text("Strict Vault")
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text(statusMessage)
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if requestStatus == .pending {
                ProgressView()
                    .tint(WovenTheme.accent)
                    .scaleEffect(1.2)
            } else {
                Button {
                    Task {
                        await requestAccess()
                    }
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text(activeRequestId != nil ? "Request Again" : "Request Access")
                    }
                    .font(WovenTheme.headline())
                    .foregroundColor(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [WovenTheme.warning, WovenTheme.warning.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            // Security: Whenever we leave this view, lock it again if strict
            if vault.isStrictMode {
                 // In a real app, delete key from keychain to be truly strict
                 // VaultKeyManager.shared.deleteVaultKey(vaultId: vault.id)
            }
        }
    }
    
    private var statusMessage: String {
        guard let status = requestStatus else {
            return "Partner approval required to open this vault."
        }
        switch status {
        case .pending:
            return "Waiting for partner approval...\nRequest #\(activeRequestId ?? 0)"
        case .approved:
            return "Approved! Unlocking..."
        case .denied:
            return "Request was denied."
        case .expired:
            return "Request expired. Try again."
        }
    }
    
    private func requestAccess() async {
        do {
            let req = try await AccessRequestManager.shared.requestAccess(for: vault.id)
            activeRequestId = req.id
            requestStatus = .pending
            
            // Start Polling
            startPolling(requestId: req.id)
            
        } catch {
            print("Request failed: \(error)")
        }
    }
    
    private func startPolling(requestId: Int) {
        Task {
            while requestStatus == .pending {
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000) // 2 sec
                if activeRequestId != requestId { break } // Cancelled
                
                do {
                    let req = try await AccessRequestManager.shared.getRequest(id: requestId)
                    if req.status != .pending {
                        requestStatus = req.status
                        if req.status == .approved {
                            try await unlockStrictVault(request: req)
                        }
                        break
                    }
                } catch {
                    print("Poll error: \(error)")
                }
            }
        }
    }
    
    private func unlockStrictVault(request: AccessRequest) async throws {
        // 1. Decrypt Key
        let keyData = try AccessRequestManager.shared.decryptShare(from: request)
        
        // 2. Save Key to Keychain (Temporary/Session)
        KeychainHelper.shared.saveData(key: "vault-key-\(vault.id.uuidString)", value: keyData)
        
        // 3. Unlock UI
        withAnimation {
            isStrictUnlocked = true
        }
    }
    
    // MARK: - Vault Lock Screen
    
    private var vaultLockScreen: some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()
            
            // Lock icon
            ZStack {
                Circle()
                    .fill(WovenTheme.cardBackground)
                    .frame(width: 100, height: 100)
                
                Image(systemName: biometryIcon)
                    .font(.system(size: 40))
                    .foregroundColor(accentColor)
            }
            
            VStack(spacing: WovenTheme.spacing8) {
                Text("Unlock Vault")
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("Use \(localAuth.biometryName) to access\n\(vault.name)")
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                Task {
                    await localAuth.authenticate()
                }
            } label: {
                Text("Unlock with \(localAuth.biometryName)")
                    .font(WovenTheme.headline())
                    .foregroundColor(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            
            if let error = localAuth.authError {
                Text(error)
                    .font(WovenTheme.caption())
                    .foregroundColor(WovenTheme.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Biometry Icon
    
    private var biometryIcon: String {
        switch localAuth.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.fill"
        @unknown default:
            return "lock.fill"
        }
    }
    
    // MARK: - Handle Batch Media Selection
    
    private func handleBatchMediaSelection(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        
        isUploading = true
        uploadProgress = (0, items.count)
        uploadError = nil
        
        var successCount = 0
        var failCount = 0
        
        for (index, item) in items.enumerated() {
            // Update progress
            uploadProgress = (index, items.count)
            
            // Check supported content types to determine if it's an image or video
            guard let firstContentType = item.supportedContentTypes.first else {
                failCount += 1
                continue
            }
            
            // Generate filename based on timestamp and content type
            let timestamp = Int(Date().timeIntervalSince1970)
            let uniqueId = UUID().uuidString.prefix(8)
            
            if firstContentType.conforms(to: .image) {
                // It's an image
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let fileName = "photo_\(timestamp)_\(uniqueId).jpg"
                    do {
                        let uploadedMedia = try await MediaService.shared.uploadMedia(
                            vaultId: vault.id,
                            mediaType: .photo,
                            originalData: data,
                            fileName: fileName
                        )
                        successCount += 1
                        print("✅ Uploaded \(index + 1)/\(items.count): \(uploadedMedia.fileName)")
                    } catch {
                        failCount += 1
                        print("❌ Failed to upload \(index + 1)/\(items.count): \(error)")
                    }
                } else {
                    failCount += 1
                }
            } else if firstContentType.conforms(to: .movie) || firstContentType.conforms(to: .video) {
                // It's a video
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let fileName = "video_\(timestamp)_\(uniqueId).mov"
                    do {
                        let uploadedMedia = try await MediaService.shared.uploadMedia(
                            vaultId: vault.id,
                            mediaType: .video,
                            originalData: data,
                            fileName: fileName
                        )
                        successCount += 1
                        print("✅ Uploaded \(index + 1)/\(items.count): \(uploadedMedia.fileName)")
                    } catch {
                        failCount += 1
                        print("❌ Failed to upload \(index + 1)/\(items.count): \(error)")
                    }
                } else {
                    failCount += 1
                }
            } else {
                failCount += 1
            }
        }
        
        // Final progress update
        uploadProgress = (items.count, items.count)
        
        // Refresh vault detail and notify gallery
        await viewModel.getVaultDetail(id: vault.id)
        NotificationCenter.default.post(name: NSNotification.Name("MediaUploaded"), object: nil)
        
        // Clear selection
        selectedPhotoItems = []
        
        // Show completion message
        if failCount > 0 {
            uploadError = NSError(
                domain: "VaultDetailView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Uploaded \(successCount) item(s), \(failCount) failed"]
            )
        } else {
            print("✅ Successfully uploaded all \(successCount) item(s)")
        }
        
        isUploading = false
        uploadProgress = nil
    }
}

// MARK: - Invite Partner Sheet

struct InvitePartnerSheet: View {
    let vaultId: UUID
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vaultViewModel = VaultViewModel()
    @StateObject private var friendsViewModel = FriendsViewModel()
    
    @State private var selectedFriend: Friend?
    @State private var isInviting = false
    @State private var showConfirmation = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                WovenTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: WovenTheme.spacing8) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "A855F7").opacity(0.15))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 24))
                                .foregroundColor(Color(hex: "A855F7"))
                        }
                        
                        Text("Select a friend to invite")
                            .font(WovenTheme.subheadline())
                            .foregroundColor(WovenTheme.textSecondary)
                    }
                    .padding(.top, WovenTheme.spacing16)
                    .padding(.bottom, WovenTheme.spacing20)
                    
                    // Error message
                    if let error = vaultViewModel.errorMessage {
                        Text(error)
                            .font(WovenTheme.caption())
                            .foregroundColor(WovenTheme.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.bottom, WovenTheme.spacing8)
                    }
                    
                    // Friends list
                    if friendsViewModel.isLoading {
                        Spacer()
                        ProgressView()
                            .tint(WovenTheme.accent)
                        Text("Loading friends...")
                            .font(WovenTheme.caption())
                            .foregroundColor(WovenTheme.textSecondary)
                            .padding(.top, WovenTheme.spacing8)
                        Spacer()
                    } else if friendsViewModel.friends.isEmpty {
                        Spacer()
                        VStack(spacing: WovenTheme.spacing12) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 40))
                                .foregroundColor(WovenTheme.textTertiary)
                            Text("No friends yet")
                                .font(WovenTheme.headline())
                                .foregroundColor(WovenTheme.textSecondary)
                            Text("Add friends first to invite them to your vault")
                                .font(WovenTheme.caption())
                                .foregroundColor(WovenTheme.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, WovenTheme.spacing32)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: WovenTheme.spacing8) {
                                ForEach(friendsViewModel.friends) { friend in
                                    FriendSelectRow(
                                        friend: friend,
                                        isSelected: selectedFriend?.id == friend.id
                                    ) {
                                        selectedFriend = friend
                                        showConfirmation = true
                                    }
                                }
                            }
                            .padding(.horizontal, WovenTheme.spacing16)
                            .padding(.bottom, WovenTheme.spacing20)
                        }
                    }
                }
            }
            .navigationTitle("Invite Partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WovenTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(WovenTheme.accent)
                }
            }
            .task {
                await friendsViewModel.loadFriends()
            }
            .alert("Invite \(selectedFriend?.fullName ?? selectedFriend?.username ?? "friend")?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {
                    selectedFriend = nil
                }
                Button("Send Invite") {
                    Task {
                        await sendInvite()
                    }
                }
            } message: {
                Text("They will receive an invitation to join this vault.")
            }
            .overlay {
                if isInviting {
                    ZStack {
                        Color.black.opacity(0.5)
                        VStack(spacing: WovenTheme.spacing12) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                            Text("Sending invite...")
                                .font(WovenTheme.subheadline())
                                .foregroundColor(.white)
                        }
                        .padding(WovenTheme.spacing24)
                        .background(WovenTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium))
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
    
    private func sendInvite() async {
        guard let friend = selectedFriend, let inviteCode = friend.inviteCode else {
            vaultViewModel.errorMessage = "Unable to invite this friend"
            return
        }
        
        isInviting = true
        if await vaultViewModel.inviteToVault(vaultId: vaultId, inviteCode: inviteCode) {
            dismiss()
        }
        isInviting = false
        selectedFriend = nil
    }
}

// MARK: - Friend Select Row
struct FriendSelectRow: View {
    let friend: Friend
    let isSelected: Bool
    let onTap: () -> Void
    
    private var displayName: String {
        friend.fullName ?? friend.username
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: WovenTheme.spacing12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "A855F7"), Color(hex: "6366F1")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Text(String(displayName.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(WovenTheme.headline())
                        .foregroundColor(WovenTheme.textPrimary)
                    
                    Text("@\(friend.username)")
                        .font(WovenTheme.caption())
                        .foregroundColor(WovenTheme.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: "A855F7"))
            }
            .padding(WovenTheme.spacing12)
            .background(isSelected ? Color(hex: "A855F7").opacity(0.1) : WovenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        VaultDetailView(vault: Vault(
            id: UUID(),
            name: "Our Memories",
            type: .pair,
            mode: .normal,
            ownerId: 1,
            createdAt: Date(),
            updatedAt: nil,
            lastAccessedAt: nil,
            memberCount: 1,
            mediaCount: 0
        ))
    }
}

