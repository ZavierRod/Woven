import PhotosUI
import SwiftUI
import UIKit

struct PairVaultRootView: View {
    @State private var store: PairVaultStore
    private let includesNavigationStack: Bool
    @State private var isScreenCaptureActive = false
    @Environment(\.scenePhase) private var scenePhase

    init(store: PairVaultStore, includesNavigationStack: Bool = true) {
        _store = State(initialValue: store)
        self.includesNavigationStack = includesNavigationStack
    }

    var body: some View {
        ZStack {
            PairVaultScreen(store: store, includesNavigationStack: includesNavigationStack)
            PairCaptureStateMonitor { isActive in
                isScreenCaptureActive = isActive
                if isActive { store.lock() }
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            if scenePhase != .active || isScreenCaptureActive {
                PairVaultPrivacyShield()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { store.lock() }
        }
        .onDisappear { store.lock() }
    }
}

private struct PairCaptureStateMonitor: UIViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeUIView(context: Context) -> CaptureStateView {
        CaptureStateView(onChange: onChange)
    }

    func updateUIView(_ view: CaptureStateView, context: Context) {
        view.onChange = onChange
        view.reportCurrentState()
    }

    final class CaptureStateView: UIView {
        var onChange: @MainActor (Bool) -> Void
        private var lastReportedState: Bool?

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            registerForTraitChanges([UITraitSceneCaptureState.self]) {
                (self: CaptureStateView, _: UITraitCollection) in
                self.reportCurrentState()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportCurrentState()
        }

        func reportCurrentState() {
            let isActive = traitCollection.sceneCaptureState == .active
            guard lastReportedState != isActive else { return }
            lastReportedState = isActive
            // UIViewRepresentable may ask for an update while SwiftUI is still
            // evaluating the view tree. Delivering the callback on the next main
            // queue turn prevents an observation mutation during that update.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastReportedState == isActive else { return }
                self.onChange(isActive)
            }
        }
    }
}

private enum PairSheet: Identifiable {
    case create
    case invitation(PairInvitationRecord)
    case photo(PairDecryptedMedia)

    var id: String {
        switch self {
        case .create: "create"
        case .invitation(let invitation): "invitation-\(invitation.id)"
        case .photo(let media): "photo-\(media.id)"
        }
    }
}

struct PairVaultScreen: View {
    @Bindable var store: PairVaultStore
    var includesNavigationStack = true
    @State private var sheet: PairSheet?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var mediaToDelete: PairDecryptedMedia?
    @State private var isShowingRevokeConfirmation = false

    var body: some View {
        Group {
            if includesNavigationStack {
                NavigationStack { screenContent }
            } else {
                screenContent
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .create:
                PairVaultCreateView(requiresPartnerInviteCode: store.requiresPartnerInviteCode) { name, inviteCode in
                    await store.createVault(named: name, partnerInviteCode: inviteCode)
                }
            case .invitation(let invitation):
                PairInvitationAcceptView(invitation: invitation) { token in
                    await store.acceptInvitation(token: token)
                }
            case .photo(let media):
                PairPhotoViewer(media: media) {
                    await store.deleteMedia(id: media.id)
                }
            }
        }
        .alert(
            "Delete encrypted photo?",
            isPresented: Binding(
                get: { mediaToDelete != nil },
                set: { if !$0 { mediaToDelete = nil } }
            ),
            presenting: mediaToDelete
        ) { media in
            Button("Cancel", role: .cancel) { mediaToDelete = nil }
            Button("Delete", role: .destructive) {
                Task {
                    await store.deleteMedia(id: media.id)
                    mediaToDelete = nil
                }
            }
        } message: { _ in
            Text("This permanently removes the encrypted blob from the Pair relay.")
        }
        .alert("Revoke Pair membership?", isPresented: $isShowingRevokeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                Task { await store.revokePartner() }
            }
        } message: {
            Text("Both members will lose access to this vault. Existing ciphertext remains opaque on the development relay.")
        }
        .alert(
            "Woven couldn’t complete that action",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.dismissError() } }
            )
        ) {
            Button("OK") { store.dismissError() }
        } message: {
            Text(store.errorMessage ?? "An unknown error occurred.")
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importSelectedPhotos(items) }
        }
        .onChange(of: store.phase) { _, newPhase in
            if case .unlocked = newPhase { return }
            if case .photo = sheet { sheet = nil }
            selectedPhotoItems = []
        }
    }

    private var screenContent: some View {
        ZStack {
            WovenTheme.background.ignoresSafeArea()
            content
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(WovenTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if WOVEN_DEVELOPMENT_AUTH
        if store.account != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button("Sign Out") { store.logout() }
                    .accessibilityLabel("Sign out of Pair development account")
            }
        }
        #endif
        if case .unlocked = store.phase {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { store.lock() } label: { Image(systemName: "lock.fill") }
                    .accessibilityLabel("Lock Pair vault")
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 50,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add Photos", systemImage: "photo.badge.plus")
                }
                .disabled(store.isImporting)
                .accessibilityLabel("Choose photos to encrypt in Pair vault")
                partnerActions
            }
        } else if store.canRevokePartner {
            ToolbarItem(placement: .topBarTrailing) { partnerActions }
        }
    }

    private var partnerActions: some View {
        Menu {
            Button("Revoke Partner", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                isShowingRevokeConfirmation = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Pair vault membership actions")
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .signedOut:
            accountSelection
        case .loading:
            loading
        case .ready:
            ready
        case .invitation(let invitation):
            invitationView(invitation)
        case .waitingForPartner(let vault):
            waitingView(vault)
        case .locked(let vault):
            lockedView(vault)
        case .unlocked(let vault, let name):
            unlockedView(vault, name: name)
        case .failed(let message):
            failed(message)
        }
    }

    private var navigationTitle: String {
        switch store.phase {
        case .unlocked(_, let name): name
        default: "Pair Vault"
        }
    }

    private var accountSelection: some View {
        #if WOVEN_DEVELOPMENT_AUTH
        ScrollView {
            VStack(spacing: WovenTheme.spacing24) {
                Spacer(minLength: 52)
                icon("person.2.badge.key.fill")
                VStack(spacing: WovenTheme.spacing8) {
                    Text("Two people. Two shares.")
                        .font(WovenTheme.title2())
                        .foregroundStyle(WovenTheme.textPrimary)
                    Text("Development Pair vaults require both registered devices. Choose a deterministic local account for this Simulator.")
                        .font(WovenTheme.subheadline())
                        .foregroundStyle(WovenTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                ForEach(PairDevelopmentAccount.allCases) { account in
                    Button {
                        Task { await store.signIn(as: account) }
                    } label: {
                        Label("Continue as \(account.displayName)", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WovenButtonStyle())
                    .accessibilityLabel("Sign in as development account \(account.displayName)")
                }
                Text("Development only · no production authentication")
                    .font(WovenTheme.caption())
                    .foregroundStyle(WovenTheme.textTertiary)
            }
            .padding(WovenTheme.spacing32)
        }
        #else
        ContentUnavailableView(
            "Authentication required",
            systemImage: "person.badge.key.fill",
            description: Text("Sign in with Apple to use Pair Vault.")
        )
        #endif
    }

    private var loading: some View {
        VStack(spacing: WovenTheme.spacing16) {
            ProgressView().controlSize(.large).tint(WovenTheme.accent)
            Text("Loading encrypted Pair state…")
                .foregroundStyle(WovenTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Pair vault")
    }

    private var ready: some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()
            icon("person.2.badge.plus")
            Text("Create a space together")
                .font(WovenTheme.title2())
                .foregroundStyle(WovenTheme.textPrimary)
            Text("Invite one person you trust. Your shared memories open only when you both agree.")
                .font(WovenTheme.subheadline())
                .foregroundStyle(WovenTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WovenTheme.spacing32)
            if let inviteCode = store.accountInviteCode {
                VStack(spacing: WovenTheme.spacing12) {
                    Text("YOUR WOVEN CODE")
                        .font(WovenTheme.caption())
                        .tracking(1.2)
                        .foregroundStyle(WovenTheme.textSecondary)
                    Text(inviteCode)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(WovenTheme.textPrimary)
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = inviteCode
                    } label: {
                        Label("Copy code", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .tint(WovenTheme.accent)
                    .accessibilityLabel("Copy your Pair account invite code")
                }
                .padding(WovenTheme.spacing16)
                .background(WovenTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
            }
            Button {
                sheet = .create
            } label: {
                Label("Create a Pair Vault", systemImage: "person.2.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WovenButtonStyle(isEnabled: !store.isWorking))
            .disabled(store.isWorking)
            .padding(.horizontal, WovenTheme.spacing32)
            .accessibilityLabel("Create a two-member Pair vault")
            Spacer()
        }
    }

    private func invitationView(_ invitation: PairInvitationRecord) -> some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()
            icon("envelope.badge.shield.half.filled")
            Text("Pair invitation received")
                .font(WovenTheme.title2())
                .foregroundStyle(WovenTheme.textPrimary)
            Text("Someone invited you to share a private space. Ask them for the one-time invitation code to join.")
                .font(WovenTheme.subheadline())
                .foregroundStyle(WovenTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WovenTheme.spacing32)
            Button {
                sheet = .invitation(invitation)
            } label: {
                Label("Join Pair Vault", systemImage: "checkmark.shield.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WovenButtonStyle(isEnabled: !store.isWorking))
            .padding(.horizontal, WovenTheme.spacing32)
            .accessibilityLabel("Accept Pair vault invitation")
            Spacer()
        }
    }

    private func waitingView(_ vault: PairVaultRecord) -> some View {
        ScrollView {
            VStack(spacing: WovenTheme.spacing24) {
                Spacer(minLength: 60)
                icon("hourglass.badge.lock")
                Text("Waiting for your partner")
                    .font(WovenTheme.title2())
                    .foregroundStyle(WovenTheme.textPrimary)
                Text("Send this one-time invitation privately to your partner. It disappears after they join.")
                    .font(WovenTheme.subheadline())
                    .foregroundStyle(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
                if let token = store.invitationToken {
                    WovenSurface {
                        VStack(spacing: WovenTheme.spacing16) {
                            Text(formattedInvitationToken(token))
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .foregroundStyle(WovenTheme.textPrimary)
                                .textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = token
                            } label: {
                                Label("Copy invitation", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(WovenTheme.accent)
                            .accessibilityLabel("Copy one-time Pair invitation")
                        }
                    }
                    .accessibilityElement(children: .contain)
                } else {
                    Text("Invitation code is unavailable on this device.")
                        .foregroundStyle(WovenTheme.textSecondary)
                }
                Button("Check invitation status") {
                    Task { try? await store.refresh() }
                }
                .accessibilityLabel("Refresh Pair invitation status")
            }
            .padding(WovenTheme.spacing32)
        }
    }

    private func lockedView(_ vault: PairVaultRecord) -> some View {
        ScrollView {
            VStack(spacing: WovenTheme.spacing24) {
                Spacer(minLength: 36)
                icon("lock.fill")
                VStack(spacing: WovenTheme.spacing8) {
                    Text("Pair vault locked")
                        .font(WovenTheme.title2())
                        .foregroundStyle(WovenTheme.textPrimary)
                    Text("Your photos stay hidden until your partner approves this opening.")
                        .font(WovenTheme.subheadline())
                        .foregroundStyle(WovenTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                accessControl(vault)

                if !store.incomingRequests.isEmpty {
                    VStack(alignment: .leading, spacing: WovenTheme.spacing12) {
                        Text("Partner requests")
                            .font(WovenTheme.headline())
                            .foregroundStyle(WovenTheme.textPrimary)
                        ForEach(store.incomingRequests) { request in
                            incomingRequest(request)
                        }
                    }
                    .padding(.top, WovenTheme.spacing16)
                }
            }
            .padding(WovenTheme.spacing32)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func accessControl(_ vault: PairVaultRecord) -> some View {
        switch store.accessPhase {
        case .none, .cancelled, .consumed:
            Button {
                Task { await store.requestAccess() }
            } label: {
                Label("Ask Partner to Open", systemImage: "person.badge.key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WovenButtonStyle(isEnabled: !store.isWorking))
            .disabled(store.isWorking || vault.status != "active")
            .accessibilityLabel("Request one-time Pair vault approval")
        case .creatingRequest:
            ProgressView("Creating bound request…").tint(WovenTheme.accent)
        case .awaitingApproval:
            VStack(spacing: WovenTheme.spacing12) {
                ProgressView().tint(WovenTheme.accent)
                Text("Waiting for partner approval")
                    .foregroundStyle(WovenTheme.textPrimary)
                Text("This request expires automatically if it is not approved.")
                    .font(WovenTheme.caption())
                    .foregroundStyle(WovenTheme.textSecondary)
                Button("Cancel request", role: .cancel) {
                    Task { await store.cancelAccessRequest() }
                }
                .accessibilityLabel("Cancel Pair access request")
            }
        case .approved:
            ProgressView("Consuming one-time approval…").tint(WovenTheme.accent)
        case .denied:
            retryableStatus(
                "Partner denied this request.",
                symbol: "xmark.shield"
            )
        case .expired:
            retryableStatus(
                "This request expired. Create a fresh request.",
                symbol: "clock.badge.exclamationmark"
            )
        case .failed(let message):
            retryableStatus(message, symbol: "exclamationmark.triangle.fill")
        }
    }

    private func retryableStatus(_ message: String, symbol: String) -> some View {
        VStack(spacing: WovenTheme.spacing12) {
            statusMessage(message, symbol: symbol)
            Button("Request Fresh Approval") {
                Task { await store.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            .tint(WovenTheme.accent)
            .disabled(store.isWorking)
            .accessibilityLabel("Request fresh Pair vault approval")
        }
    }

    private func incomingRequest(_ request: PairAccessRecord) -> some View {
        VStack(alignment: .leading, spacing: WovenTheme.spacing12) {
            Label("Your partner wants to open the vault", systemImage: "person.badge.clock.fill")
                .foregroundStyle(WovenTheme.textPrimary)
            Text("Approve only if you expect this request. Your device will authenticate you first.")
                .font(WovenTheme.caption())
                .foregroundStyle(WovenTheme.textSecondary)
            HStack {
                Button("Deny", role: .destructive) {
                    Task { await store.deny(request) }
                }
                .accessibilityLabel("Deny partner access request")
                Spacer()
                Button("Approve Opening") {
                    Task { await store.approve(request) }
                }
                .buttonStyle(.borderedProminent)
                .tint(WovenTheme.accent)
                .accessibilityLabel("Approve partner access request with device authentication")
            }
        }
        .padding()
        .background(WovenTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func unlockedView(_ vault: PairVaultRecord, name: String) -> some View {
        Group {
            if store.decryptedMedia.isEmpty {
                VStack(spacing: WovenTheme.spacing24) {
                    Spacer()
                    icon("photo.badge.plus")
                    Text("\(name) is empty")
                        .font(WovenTheme.title2())
                        .foregroundStyle(WovenTheme.textPrimary)
                    Text("Photos are encrypted in memory before only sealed bytes are uploaded.")
                        .font(WovenTheme.subheadline())
                        .foregroundStyle(WovenTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, WovenTheme.spacing32)
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 50,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose Photos", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WovenButtonStyle(isEnabled: !store.isImporting))
                    .disabled(store.isImporting)
                    .padding(.horizontal, WovenTheme.spacing32)
                    .accessibilityLabel("Choose photos to encrypt in Pair vault")
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
                        spacing: 4
                    ) {
                        ForEach(store.decryptedMedia) { media in
                            PairPhotoCell(
                                media: media,
                                isDeleting: store.deletingMediaIDs.contains(media.id),
                                open: { sheet = .photo(media) },
                                delete: { mediaToDelete = media }
                            )
                        }
                    }
                    .padding(4)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if store.isImporting {
                ProgressView("Encrypting before upload…")
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
                    .accessibilityLabel("Encrypting selected Pair photo")
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: WovenTheme.spacing20) {
            icon("exclamationmark.triangle.fill")
            Text("Pair vault unavailable")
                .font(WovenTheme.title2())
                .foregroundStyle(WovenTheme.textPrimary)
            Text(message)
                .foregroundStyle(WovenTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WovenTheme.spacing32)
            #if WOVEN_DEVELOPMENT_AUTH
            Button("Choose an account") { store.logout() }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Return to Pair account selection")
            #endif
        }
    }

    private func statusMessage(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(WovenTheme.subheadline())
            .foregroundStyle(WovenTheme.textSecondary)
            .multilineTextAlignment(.center)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 50, weight: .semibold))
            .foregroundStyle(WovenTheme.accent)
            .frame(width: 92, height: 92)
            .background(WovenTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityHidden(true)
    }

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        defer { selectedPhotoItems = [] }
        var unreadableCount = 0

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      UIImage(data: data) != nil else {
                    unreadableCount += 1
                    continue
                }
                await store.importPhoto(data)
            } catch is CancellationError {
                return
            } catch {
                unreadableCount += 1
            }
        }

        if unreadableCount > 0 {
            let noun = unreadableCount == 1 ? "photo" : "photos"
            store.errorMessage = "\(unreadableCount) selected \(noun) could not be loaded."
        }
    }

    private func formattedInvitationToken(_ token: String) -> String {
        let groups = stride(from: 0, to: token.count, by: 8).map { offset in
            let start = token.index(token.startIndex, offsetBy: offset)
            let end = token.index(start, offsetBy: min(8, token.distance(from: start, to: token.endIndex)))
            return String(token[start..<end])
        }
        return groups.enumerated().map { index, group in
            index == 4 ? "\n\(group)" : group
        }.joined(separator: " ")
    }
}

private struct PairVaultCreateView: View {
    let requiresPartnerInviteCode: Bool
    let create: (String, String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var inviteCode = ""
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name your space") {
                    TextField("Our memories", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Private Pair vault name")
                }
                if requiresPartnerInviteCode {
                    Section("Who are you sharing with?") {
                        TextField("Their Woven code", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Label(
                        "Only you and your partner can read the name or see what you add.",
                        systemImage: "lock.shield"
                    )
                }
            }
            .navigationTitle("Create Pair Vault")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        submitting = true
                        Task {
                            await create(name, requiresPartnerInviteCode ? inviteCode : nil)
                            submitting = false
                            dismiss()
                        }
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (requiresPartnerInviteCode && inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                        submitting
                    )
                    .accessibilityLabel("Create encrypted Pair vault")
                }
            }
        }
    }
}

private struct PairInvitationAcceptView: View {
    let invitation: PairInvitationRecord
    let accept: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Invitation from your partner") {
                    TextField("Paste one-time invitation", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel("Pair invitation code")
                }
                Section {
                    Label(
                        "Joining adds this device to the vault. You will still approve each opening together.",
                        systemImage: "person.2.badge.key"
                    )
                }
            }
            .navigationTitle("Join Pair Vault")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        submitting = true
                        Task {
                            await accept(token)
                            submitting = false
                            dismiss()
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
                    .accessibilityLabel("Verify and accept Pair invitation")
                }
            }
        }
    }
}

private struct PairPhotoCell: View {
    let media: PairDecryptedMedia
    let isDeleting: Bool
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: open) {
            ZStack {
                if let image = UIImage(data: media.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                    Image(systemName: "exclamationmark.triangle")
                }
                if isDeleting { ProgressView().tint(.white) }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
        .disabled(isDeleting)
        .accessibilityLabel("Open decrypted Pair photo")
    }
}

private struct PairPhotoViewer: View {
    let media: PairDecryptedMedia
    let delete: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(data: media.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Decrypted Pair vault photo")
                } else {
                    ContentUnavailableView("Unreadable image", systemImage: "exclamationmark.triangle")
                }
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await delete(); dismiss() }
                    }
                    .accessibilityLabel("Delete encrypted Pair photo")
                }
            }
        }
    }
}

private struct PairVaultPrivacyShield: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46))
                Text("Woven is protected")
                    .font(.headline)
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Woven content hidden while inactive")
    }
}

#if DEBUG
#Preview("Pair account selection") {
    PairVaultScreen(store: PairVaultStore())
}

#Preview("Pair locked") {
    PairVaultScreen(store: PairVaultStore.preview(phase: .locked(pairPreviewVault)))
}

#Preview("Pair unlocked empty") {
    PairVaultScreen(store: PairVaultStore.preview(phase: .unlocked(pairPreviewVault, name: "Pair Memories")))
}

#Preview("Pair error") {
    PairVaultScreen(store: PairVaultStore.preview(phase: .failed("The development relay is unavailable.")))
}

private let pairPreviewVault = PairVaultRecord(
    vaultID: "preview-pair-vault",
    encryptedMetadata: "sealed-preview-metadata",
    membershipVersion: 1,
    status: "active",
    createdAtMS: 0,
    members: [
        PairMember(userID: 1, deviceID: "alice-device", role: "creator", status: "active"),
        PairMember(userID: 2, deviceID: "bob-device", role: "partner", status: "active")
    ]
)
#endif
