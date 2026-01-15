import SwiftUI

struct HomeView: View {
    
    @StateObject private var viewModel = VaultViewModel()
    @StateObject private var friendsViewModel = FriendsViewModel()
    @State private var showAddFriend = false
    @State private var showCreateVault = false
    @State private var selectedSegment = 0
    @State private var appeared = false
    
    var body: some View {
        ZStack {
            // Background
            WovenTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom segmented control
                    segmentedControl
                        .padding(.horizontal, WovenTheme.spacing20)
                        .padding(.top, WovenTheme.spacing12)
                        .padding(.bottom, WovenTheme.spacing16)
                    
                    // Swipeable content
                    TabView(selection: $selectedSegment) {
                        vaultsContent
                            .tag(0)
                        
                        friendsContent
                            .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("Woven")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(WovenTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if selectedSegment == 0 {
                            showCreateVault = true
                        } else {
                            showAddFriend = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(WovenTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView(viewModel: friendsViewModel)
            }
            .sheet(isPresented: $showCreateVault) {
                CreateVaultSheet(viewModel: viewModel)
            }
            .task {
                await viewModel.fetchVaults()
                await viewModel.fetchPendingInvites()
                await friendsViewModel.loadAll()
            }
            .refreshable {
                await viewModel.fetchVaults()
                await viewModel.fetchPendingInvites()
                await friendsViewModel.loadAll()
            }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Segmented Control
    private var segmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(["Vaults", "Friends"].indices, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedSegment = index
                    }
                } label: {
                    Text(index == 0 ? "Vaults" : "Friends")
                        .font(WovenTheme.subheadline())
                        .fontWeight(selectedSegment == index ? .semibold : .regular)
                        .foregroundColor(selectedSegment == index ? WovenTheme.textPrimary : WovenTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedSegment == index
                                ? WovenTheme.surfaceElevated
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(WovenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    // MARK: - Vaults Content
    private var vaultsContent: some View {
        Group {
            if viewModel.isLoading && viewModel.vaults.isEmpty && viewModel.pendingInvites.isEmpty {
                loadingState
            } else if viewModel.vaults.isEmpty && viewModel.pendingInvites.isEmpty {
                emptyVaultsState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: WovenTheme.spacing16) {
                        // Error message if any
                        if let error = viewModel.errorMessage {
                            errorBanner(message: error)
                        }
                        
                        // Pending vault invites section
                        if !viewModel.pendingInvites.isEmpty {
                            pendingVaultInvitesSection
                        }
                        
                        // Your vaults
                        if !viewModel.vaults.isEmpty && !viewModel.pendingInvites.isEmpty {
                            HStack {
                                Text("Your Vaults")
                                    .font(WovenTheme.headline())
                                    .foregroundColor(WovenTheme.textPrimary)
                                Spacer()
                            }
                            .padding(.top, WovenTheme.spacing8)
                        }
                        
                        ForEach(Array(viewModel.vaults.enumerated()), id: \.element.id) { index, vault in
                            NavigationLink(destination: VaultDetailView(vault: vault)) {
                                VaultCard(vault: vault)
                            }
                            .buttonStyle(.plain)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8)
                                .delay(Double(index) * 0.1),
                                value: appeared
                            )
                        }
                    }
                    .padding(.horizontal, WovenTheme.spacing20)
                    .padding(.bottom, 100)
                }
                .onAppear { appeared = true }
            }
        }
    }
    
    // MARK: - Pending Vault Invites Section
    private var pendingVaultInvitesSection: some View {
        VStack(alignment: .leading, spacing: WovenTheme.spacing12) {
            HStack {
                Text("Vault Invitations")
                    .font(WovenTheme.headline())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Spacer()
                
                Text("\(viewModel.pendingInvites.count)")
                    .font(WovenTheme.caption())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "A855F7"))
                    .clipShape(Capsule())
            }
            
            ForEach(viewModel.pendingInvites) { invite in
                PendingVaultInviteCard(invite: invite, viewModel: viewModel)
            }
        }
    }
    
    // MARK: - Loading State
    private var loadingState: some View {
        VStack(spacing: WovenTheme.spacing16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(WovenTheme.accent)
            
            Text("Loading vaults...")
                .font(WovenTheme.subheadline())
                .foregroundColor(WovenTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error Banner
    private func errorBanner(message: String) -> some View {
        HStack(spacing: WovenTheme.spacing12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(WovenTheme.warning)
            
            Text(message)
                .font(WovenTheme.subheadline())
                .foregroundColor(WovenTheme.textPrimary)
            
            Spacer()
            
            Button {
                viewModel.clearMessages()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(WovenTheme.textSecondary)
            }
        }
        .padding(WovenTheme.spacing16)
        .background(WovenTheme.warning.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
    }
    
    // MARK: - Empty Vaults State
    private var emptyVaultsState: some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()
            
            // Icon with glow
            ZStack {
                Circle()
                    .fill(WovenTheme.accent.opacity(0.1))
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
                                colors: [WovenTheme.accent, WovenTheme.accent.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            
            VStack(spacing: WovenTheme.spacing8) {
                Text("Create your first vault")
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("Your private, encrypted space\nfor what matters most")
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showCreateVault = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("New Vault")
                }
            }
            .buttonStyle(WovenButtonStyle())
            .padding(.horizontal, 60)
            .padding(.top, WovenTheme.spacing8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Friends Content
    private var friendsContent: some View {
        Group {
            if friendsViewModel.isLoading && friendsViewModel.friends.isEmpty {
                VStack(spacing: WovenTheme.spacing16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(WovenTheme.accent)
                    Text("Loading friends...")
                        .font(WovenTheme.subheadline())
                        .foregroundColor(WovenTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if friendsViewModel.friends.isEmpty && friendsViewModel.pendingRequests.isEmpty && friendsViewModel.sentRequests.isEmpty {
                emptyFriendsState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: WovenTheme.spacing12) {
                        // Pending requests section
                        if !friendsViewModel.pendingRequests.isEmpty {
                            pendingRequestsSection
                        }
                        
                        // Sent requests section
                        if !friendsViewModel.sentRequests.isEmpty {
                            sentRequestsSection
                        }
                        
                        // Friends list
                        if !friendsViewModel.friends.isEmpty {
                            friendsListSection
                        }
                    }
                    .padding(.horizontal, WovenTheme.spacing20)
                    .padding(.bottom, 100)
                }
            }
        }
    }
    
    // MARK: - Pending Requests Section
    private var pendingRequestsSection: some View {
        VStack(alignment: .leading, spacing: WovenTheme.spacing12) {
            Text("Friend Requests")
                .font(WovenTheme.headline())
                .foregroundColor(WovenTheme.textPrimary)
                .padding(.top, WovenTheme.spacing8)
            
            ForEach(friendsViewModel.pendingRequests) { request in
                PendingRequestRow(request: request, viewModel: friendsViewModel)
            }
        }
    }
    
    // MARK: - Sent Requests Section
    private var sentRequestsSection: some View {
        VStack(alignment: .leading, spacing: WovenTheme.spacing12) {
            Text("Sent Requests")
                .font(WovenTheme.headline())
                .foregroundColor(WovenTheme.textPrimary)
                .padding(.top, WovenTheme.spacing8)
            
            ForEach(friendsViewModel.sentRequests) { request in
                SentRequestRow(request: request, viewModel: friendsViewModel)
            }
        }
    }
    
    // MARK: - Friends List Section
    private var friendsListSection: some View {
        VStack(alignment: .leading, spacing: WovenTheme.spacing12) {
            if !friendsViewModel.pendingRequests.isEmpty || !friendsViewModel.sentRequests.isEmpty {
                Text("Friends")
                    .font(WovenTheme.headline())
                    .foregroundColor(WovenTheme.textPrimary)
                    .padding(.top, WovenTheme.spacing8)
            }
            
            ForEach(friendsViewModel.friends) { friend in
                FriendRow(friend: friend, viewModel: friendsViewModel)
            }
        }
    }
    
    // MARK: - Empty Friends State
    private var emptyFriendsState: some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(WovenTheme.info.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                ZStack {
                    Circle()
                        .fill(WovenTheme.cardBackground)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [WovenTheme.info, WovenTheme.info.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            
            VStack(spacing: WovenTheme.spacing8) {
                Text("No friends yet")
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("Add a friend to create\na shared vault together")
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showAddFriend = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("Add Friend")
                }
            }
            .buttonStyle(WovenButtonStyle())
            .padding(.horizontal, 60)
            .padding(.top, WovenTheme.spacing8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Vault Card (Apple Wallet Style)
struct VaultCard: View {
    let vault: Vault
    @State private var isPressed = false
    
    private var cardGradient: LinearGradient {
        vault.isPairVault ? WovenTheme.sharedVaultGradient : WovenTheme.soloVaultGradient
    }
    
    private var accentColor: Color {
        vault.isPairVault ? Color(hex: "A855F7") : WovenTheme.accent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top section
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(vault.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(vault.type.displayName)
                        .font(WovenTheme.caption())
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // Vault icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: vault.type.icon)
                        .font(.system(size: 18))
                        .foregroundColor(accentColor)
                }
            }
            
            Spacer()
            
            // Bottom section
            HStack(alignment: .bottom) {
                // Status badge
                HStack(spacing: 5) {
                    Image(systemName: vault.isStrictMode ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(vault.mode.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(vault.isStrictMode ? WovenTheme.warning : WovenTheme.success)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((vault.isStrictMode ? WovenTheme.warning : WovenTheme.success).opacity(0.15))
                .clipShape(Capsule())
                
                Spacer()
                
                // Stats
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(vault.mediaCount) items")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                    
                    if let lastAccess = vault.lastAccessedAt {
                        Text(lastAccess, style: .relative)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
        }
        .padding(WovenTheme.spacing20)
        .frame(height: 160)
        .background(
            ZStack {
                cardGradient
                
                // Subtle pattern overlay
                GeometryReader { geo in
                    Path { path in
                        let width = geo.size.width
                        let height = geo.size.height
                        for i in stride(from: 0, to: width + height, by: 20) {
                            path.move(to: CGPoint(x: i, y: 0))
                            path.addLine(to: CGPoint(x: i - height, y: height))
                        }
                    }
                    .stroke(.white.opacity(0.03), lineWidth: 1)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusCard, style: .continuous))
        .shadow(color: accentColor.opacity(0.2), radius: isPressed ? 10 : 20, x: 0, y: isPressed ? 5 : 10)
    }
}

// MARK: - Pending Vault Invite Card
struct PendingVaultInviteCard: View {
    let invite: VaultDetail
    @ObservedObject var viewModel: VaultViewModel
    @State private var isProcessing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            HStack(spacing: WovenTheme.spacing16) {
                // Vault icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "A855F7"), Color(hex: "6366F1")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(invite.name)
                        .font(WovenTheme.headline())
                        .foregroundColor(WovenTheme.textPrimary)
                    
                    if let owner = invite.owner {
                        Text("From \(owner.fullName ?? "Unknown")")
                            .font(WovenTheme.caption())
                            .foregroundColor(WovenTheme.textSecondary)
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: "A855F7"))
                            .frame(width: 6, height: 6)
                        Text("Pair Vault Invitation")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "A855F7"))
                    }
                }
                
                Spacer()
            }
            .padding(WovenTheme.spacing16)
            
            // Action buttons
            HStack(spacing: WovenTheme.spacing12) {
                Button {
                    Task {
                        isProcessing = true
                        _ = await viewModel.declineInvite(vaultId: invite.id)
                        isProcessing = false
                    }
                } label: {
                    Text("Decline")
                        .font(WovenTheme.subheadline())
                        .fontWeight(.medium)
                        .foregroundColor(WovenTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(WovenTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
                }
                .disabled(isProcessing)
                
                Button {
                    Task {
                        isProcessing = true
                        _ = await viewModel.acceptInvite(vaultId: invite.id)
                        isProcessing = false
                    }
                } label: {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        Text("Accept")
                            .font(WovenTheme.subheadline())
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .background(
                    LinearGradient(
                        colors: [Color(hex: "A855F7"), Color(hex: "6366F1")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
                .disabled(isProcessing)
            }
            .padding(.horizontal, WovenTheme.spacing16)
            .padding(.bottom, WovenTheme.spacing16)
        }
        .background(WovenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous)
                .stroke(Color(hex: "A855F7").opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Friend Row
struct FriendRow: View {
    let friend: Friend
    @ObservedObject var viewModel: FriendsViewModel
    @State private var showRemoveConfirmation = false
    
    private var displayName: String {
        friend.fullName ?? friend.username
    }
    
    var body: some View {
        HStack(spacing: WovenTheme.spacing16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "3B82F6"), Color(hex: "8B5CF6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(WovenTheme.headline())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("@\(friend.username)")
                    .font(WovenTheme.caption())
                    .foregroundColor(WovenTheme.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(WovenTheme.textTertiary)
        }
        .padding(WovenTheme.spacing16)
        .background(WovenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous))
        .contextMenu {
            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Label("Remove Friend", systemImage: "person.badge.minus")
            }
        }
        .alert("Remove Friend?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.removeFriend(friend)
                }
            }
        } message: {
            Text("Are you sure you want to remove \(displayName) from your friends?")
        }
    }
}

// MARK: - Pending Request Row
struct PendingRequestRow: View {
    let request: PendingFriendRequest
    @ObservedObject var viewModel: FriendsViewModel
    
    private var displayName: String {
        request.requester?.fullName ?? request.requester?.username ?? "Unknown"
    }
    
    var body: some View {
        HStack(spacing: WovenTheme.spacing16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "F59E0B"), Color(hex: "EF4444")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(WovenTheme.headline())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("Wants to be friends")
                    .font(WovenTheme.caption())
                    .foregroundColor(WovenTheme.textSecondary)
            }
            
            Spacer()
            
            // Accept/Decline buttons
            HStack(spacing: 8) {
                Button {
                    Task {
                        await viewModel.declineRequest(request)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(WovenTheme.error)
                        .padding(10)
                        .background(WovenTheme.error.opacity(0.15))
                        .clipShape(Circle())
                }
                
                Button {
                    Task {
                        await viewModel.acceptRequest(request)
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(WovenTheme.success)
                        .padding(10)
                        .background(WovenTheme.success.opacity(0.15))
                        .clipShape(Circle())
                }
            }
        }
        .padding(WovenTheme.spacing16)
        .background(WovenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous))
    }
}

// MARK: - Sent Request Row
struct SentRequestRow: View {
    let request: PendingFriendRequest
    @ObservedObject var viewModel: FriendsViewModel
    
    private var displayName: String {
        request.requester?.username ?? request.requester?.fullName ??  "Unknown"
    }
    
    var body: some View {
        HStack(spacing: WovenTheme.spacing16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(WovenTheme.headline())
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("Request pending")
                    .font(WovenTheme.caption())
                    .foregroundColor(WovenTheme.textSecondary)
            }
            
            Spacer()
            
            // Pending indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(WovenTheme.warning)
                    .frame(width: 8, height: 8)
                Text("Pending")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(WovenTheme.warning)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(WovenTheme.warning.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(WovenTheme.spacing16)
        .background(WovenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous))
    }
}


// MARK: - Add Friend View
struct AddFriendView: View {
    @ObservedObject var viewModel: FriendsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var friendCode = ""
    @State private var showCopiedAlert = false
    @StateObject private var authManager = AuthenticationManager()

    private var inviteCode: String {
        if let inviteCode = authManager.currentUser?.inviteCode, !inviteCode.isEmpty {
            return inviteCode
        }
        return "XXXXXXXX"
    }
    
    private var formattedInviteCode: String {
        let raw = inviteCode
            .replacingOccurrences(of: "WOVEN-", with: "")
            .replacingOccurrences(of: "-", with: "")
        var padded = raw
        while padded.count < 8 { padded.append("X") }
        let first = padded.prefix(4)
        let second = padded.dropFirst(4).prefix(4)
        return "WOVEN-\(first)-\(second)"
    }
    
    private var cleanedFriendCode: String {
        friendCode
            .replacingOccurrences(of: "WOVEN-", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                WovenTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: WovenTheme.spacing32) {
                        // Your code section
                        VStack(spacing: WovenTheme.spacing16) {
                            Text("Your Invite Code")
                                .font(WovenTheme.subheadline())
                                .foregroundColor(WovenTheme.textSecondary)
                            
                            Text(formattedInviteCode)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(WovenTheme.accent)
                                .padding(.vertical, 20)
                                .padding(.horizontal, 24)
                                .background(WovenTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous))
                            
                            Button {
                                UIPasteboard.general.string = formattedInviteCode
                                showCopiedAlert = true
                            } label: {
                                Label("Copy Code", systemImage: "doc.on.doc")
                                    .font(WovenTheme.subheadline())
                                    .foregroundColor(WovenTheme.accent)
                            }
                            
                            Text("Share this code with a friend to connect")
                                .font(WovenTheme.caption())
                                .foregroundColor(WovenTheme.textTertiary)
                        }
                        .padding(.top, WovenTheme.spacing20)
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(WovenTheme.separator)
                                .frame(height: 1)
                            Text("or")
                                .font(WovenTheme.caption())
                                .foregroundColor(WovenTheme.textTertiary)
                            Rectangle()
                                .fill(WovenTheme.separator)
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 40)
                        
                        // Enter friend's code
                        VStack(spacing: WovenTheme.spacing16) {
                            Text("Enter Friend's Code")
                                .font(WovenTheme.subheadline())
                                .foregroundColor(WovenTheme.textSecondary)
                            
                            TextField("WOVEN-XXXX-XXXX", text: $friendCode)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(WovenTheme.textPrimary)
                                .multilineTextAlignment(.center)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding()
                                .background(WovenTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
                                .padding(.horizontal, WovenTheme.spacing20)
                            
                            // Error message
                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(WovenTheme.caption())
                                    .foregroundColor(WovenTheme.error)
                                    .multilineTextAlignment(.center)
                            }
                            
                            // Success message
                            if let success = viewModel.successMessage {
                                Text(success)
                                    .font(WovenTheme.caption())
                                    .foregroundColor(WovenTheme.success)
                                    .multilineTextAlignment(.center)
                            }
                            
                            Button {
                                Task {
                                    let success = await viewModel.sendFriendRequest(inviteCode: cleanedFriendCode)
                                    if success {
                                        friendCode = ""
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            dismiss()
                                        }
                                    }
                                }
                            } label: {
                                if viewModel.isProcessing {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("Add Friend")
                                }
                            }
                            .buttonStyle(WovenButtonStyle(isEnabled: !cleanedFriendCode.isEmpty && !viewModel.isProcessing))
                            .disabled(cleanedFriendCode.isEmpty || viewModel.isProcessing)
                            .padding(.horizontal, WovenTheme.spacing20)
                        }
                    }
                    .padding(.horizontal, WovenTheme.spacing20)
                }
            }
            .navigationTitle("Add Friend")
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
            .alert("Copied!", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your invite code has been copied to the clipboard.")
            }
            .onDisappear {
                viewModel.clearMessages()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Create Vault Sheet (Updated with API)
struct CreateVaultSheet: View {
    @ObservedObject var viewModel: VaultViewModel
    @StateObject private var friendsViewModel = FriendsViewModel()
    @Environment(\.dismiss) var dismiss
    
    @State private var vaultName = ""
    @State private var selectedType: VaultType = .solo
    @State private var selectedMode: VaultMode = .normal
    @State private var selectedFriendId: Int? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                WovenTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: WovenTheme.spacing24) {
                        // Vault type selection
                        VStack(spacing: WovenTheme.spacing16) {
                            Text("Choose vault type")
                                .font(WovenTheme.subheadline())
                                .foregroundColor(WovenTheme.textSecondary)
                            
                            VaultTypeOption(
                                icon: VaultType.solo.icon,
                                title: VaultType.solo.displayName,
                                description: VaultType.solo.description,
                                gradient: WovenTheme.soloVaultGradient,
                                accentColor: WovenTheme.accent,
                                isSelected: selectedType == .solo
                            ) {
                                selectedType = .solo
                                selectedFriendId = nil  // Reset friend selection when switching to solo
                            }
                            
                            VaultTypeOption(
                                icon: VaultType.pair.icon,
                                title: VaultType.pair.displayName,
                                description: VaultType.pair.description,
                                gradient: WovenTheme.sharedVaultGradient,
                                accentColor: Color(hex: "A855F7"),
                                isSelected: selectedType == .pair
                            ) {
                                selectedType = .pair
                            }
                        }
                        .padding(.top, WovenTheme.spacing12)
                        
                        // Friend selector (only for pair vaults)
                        if selectedType == .pair {
                            VStack(spacing: WovenTheme.spacing12) {
                                Text("Select friend to share with")
                                    .font(WovenTheme.subheadline())
                                    .foregroundColor(WovenTheme.textSecondary)
                                
                                if friendsViewModel.isLoading {
                                    ProgressView()
                                        .tint(WovenTheme.accent)
                                        .padding()
                                } else if friendsViewModel.friends.isEmpty {
                                    Text("No friends yet. Add a friend first!")
                                        .font(WovenTheme.caption())
                                        .foregroundColor(WovenTheme.textTertiary)
                                        .padding()
                                } else {
                                    ForEach(friendsViewModel.friends) { friend in
                                        FriendSelectionRow(
                                            friend: friend,
                                            isSelected: selectedFriendId == friend.id
                                        ) {
                                            selectedFriendId = friend.id
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Mode selection (only for pair vaults)
                        if selectedType == .pair {
                            VStack(spacing: WovenTheme.spacing12) {
                                Text("Access mode")
                                    .font(WovenTheme.subheadline())
                                    .foregroundColor(WovenTheme.textSecondary)
                                
                                HStack(spacing: WovenTheme.spacing12) {
                                    ForEach(VaultMode.allCases, id: \.self) { mode in
                                        Button {
                                            selectedMode = mode
                                        } label: {
                                            VStack(spacing: 6) {
                                                Image(systemName: mode == .normal ? "lock.open" : "lock")
                                                    .font(.system(size: 20))
                                                Text(mode.displayName)
                                                    .font(WovenTheme.caption())
                                            }
                                            .foregroundColor(selectedMode == mode ? WovenTheme.textPrimary : WovenTheme.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 16)
                                            .background(selectedMode == mode ? WovenTheme.surfaceElevated : WovenTheme.cardBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous)
                                                    .stroke(selectedMode == mode ? WovenTheme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                Text(selectedMode.description)
                                    .font(WovenTheme.caption())
                                    .foregroundColor(WovenTheme.textTertiary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // Vault name input
                        VStack(alignment: .leading, spacing: WovenTheme.spacing8) {
                            Text("Vault name")
                                .font(WovenTheme.subheadline())
                                .foregroundColor(WovenTheme.textSecondary)
                            
                            TextField("My Private Vault", text: $vaultName)
                                .font(WovenTheme.body())
                                .foregroundColor(WovenTheme.textPrimary)
                                .padding()
                                .background(WovenTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
                        }
                        
                        // Error message
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(WovenTheme.caption())
                                .foregroundColor(WovenTheme.error)
                                .multilineTextAlignment(.center)
                        }
                        
                        Spacer(minLength: 40)
                        
                        Button {
                            Task {
                                if await viewModel.createVault(name: vaultName, type: selectedType, mode: selectedMode, inviteeId: selectedFriendId) {
                                    dismiss()
                                }
                            }
                        } label: {
                            if viewModel.isCreating {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text(selectedType == .pair ? "Send Invite" : "Create Vault")
                            }
                        }
                        .buttonStyle(WovenButtonStyle(isEnabled: !vaultName.isEmpty && !viewModel.isCreating))
                        .disabled(vaultName.isEmpty || viewModel.isCreating)
                    }
                    .padding(.horizontal, WovenTheme.spacing20)
                }
            }
            .navigationTitle("New Vault")
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
            .onDisappear {
                viewModel.clearMessages()
            }
            .task {
                // Load friends when sheet appears
                await friendsViewModel.loadFriends()
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct VaultTypeOption: View {
    let icon: String
    let title: String
    let description: String
    let gradient: LinearGradient
    let accentColor: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: WovenTheme.spacing16) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(WovenTheme.headline())
                        .foregroundColor(WovenTheme.textPrimary)
                    
                    Text(description)
                        .font(WovenTheme.caption())
                        .foregroundColor(WovenTheme.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? accentColor : WovenTheme.textTertiary)
            }
            .padding(WovenTheme.spacing16)
            .background(
                isSelected ? gradient : WovenTheme.subtleGradient
            )
            .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous)
                    .stroke(isSelected ? accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friend Selection Row (for Create Vault)
struct FriendSelectionRow: View {
    let friend: Friend
    let isSelected: Bool
    let action: () -> Void
    
    private let accentColor = Color(hex: "A855F7")
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: WovenTheme.spacing16) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, Color(hex: "6366F1")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Text(String((friend.fullName ?? friend.username).prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.fullName ?? friend.username)
                        .font(WovenTheme.subheadline())
                        .foregroundColor(WovenTheme.textPrimary)
                    Text("@\(friend.username)")
                        .font(WovenTheme.caption())
                        .foregroundColor(WovenTheme.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? accentColor : WovenTheme.textTertiary)
            }
            .padding(WovenTheme.spacing12)
            .background(isSelected ? accentColor.opacity(0.1) : WovenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(isSelected ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView()
}

