import PhotosUI
import SwiftUI
import UIKit

struct PairVaultRootView: View {
    @State private var store: PairVaultStore
    @State private var isScreenCaptureActive = false
    @Environment(\.scenePhase) private var scenePhase

    init(store: PairVaultStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        ZStack {
            PairVaultScreen(store: store)
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
    @State private var sheet: PairSheet?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var mediaToDelete: PairDecryptedMedia?
    @State private var isShowingRevokeConfirmation = false

    var body: some View {
        NavigationStack {
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
        .task(id: selectedPhoto) { await importSelectedPhoto() }
        .onChange(of: store.phase) { _, newPhase in
            if case .unlocked = newPhase { return }
            if case .photo = sheet { sheet = nil }
            selectedPhoto = nil
        }
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
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "plus")
                }
                .disabled(store.isImporting)
                .accessibilityLabel("Choose a photo to encrypt in Pair vault")
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
            Text("No Pair vault yet")
                .font(WovenTheme.title2())
                .foregroundStyle(WovenTheme.textPrimary)
            Text("Your partner must sign in once on their Simulator so Woven can register their public device key.")
                .font(WovenTheme.subheadline())
                .foregroundStyle(WovenTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WovenTheme.spacing32)
            Button {
                sheet = .create
            } label: {
                Label("Create Pair Vault", systemImage: "plus")
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
            Text("The relay has an encrypted key share addressed to this device. Ask your partner for the separate invitation code.")
                .font(WovenTheme.subheadline())
                .foregroundStyle(WovenTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WovenTheme.spacing32)
            Button {
                sheet = .invitation(invitation)
            } label: {
                Label("Accept Invitation", systemImage: "checkmark.shield.fill")
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
                Text("Share this one-time code out of band. The relay stores only its SHA-256 hash.")
                    .font(WovenTheme.subheadline())
                    .foregroundStyle(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
                if let token = store.invitationToken {
                    Text(formattedInvitationToken(token))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(WovenTheme.textPrimary)
                        .textSelection(.enabled)
                        .padding()
                        .background(WovenTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("One-time Pair invitation code \(token)")
                } else {
                    Text("Invitation code is unavailable on this device.")
                        .foregroundStyle(WovenTheme.textSecondary)
                }
                Button("Check invitation status") {
                    Task { try? await store.refresh() }
                }
                .accessibilityLabel("Refresh Pair invitation status")
                Text("Vault identifier \(vault.vaultID.prefix(8))")
                    .font(WovenTheme.caption())
                    .foregroundStyle(WovenTheme.textTertiary)
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
                    Text("No decrypted image, thumbnail, name, or reconstructed key is retained while locked.")
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
                Label("Request Partner Approval", systemImage: "person.badge.key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WovenButtonStyle(isEnabled: !store.isWorking))
            .disabled(store.isWorking || vault.status != "active")
            .accessibilityLabel("Request one-time Pair vault approval")
        case .creatingRequest:
            ProgressView("Creating bound request…").tint(WovenTheme.accent)
        case .awaitingApproval(let request):
            VStack(spacing: WovenTheme.spacing12) {
                ProgressView().tint(WovenTheme.accent)
                Text("Waiting for partner approval")
                    .foregroundStyle(WovenTheme.textPrimary)
                Text("Request \(request.requestID.prefix(8)) expires automatically.")
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
            Label("Access requested", systemImage: "person.badge.clock.fill")
                .foregroundStyle(WovenTheme.textPrimary)
            Text("Approving releases only this device’s encrypted share to request \(request.requestID.prefix(8)).")
                .font(WovenTheme.caption())
                .foregroundStyle(WovenTheme.textSecondary)
            HStack {
                Button("Deny", role: .destructive) {
                    Task { await store.deny(request) }
                }
                .accessibilityLabel("Deny partner access request")
                Spacer()
                Button("Approve with Face ID") {
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
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WovenButtonStyle(isEnabled: !store.isImporting))
                    .disabled(store.isImporting)
                    .padding(.horizontal, WovenTheme.spacing32)
                    .accessibilityLabel("Choose a photo to encrypt in Pair vault")
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

    private func importSelectedPhoto() async {
        guard let selectedPhoto else { return }
        defer { self.selectedPhoto = nil }
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                  UIImage(data: data) != nil else {
                throw PairVaultError.relay("The selected item was not a readable image.")
            }
            await store.importPhoto(data)
        } catch {
            store.errorMessage = error.localizedDescription
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
                Section("Private vault name") {
                    TextField("Shared memories", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Private Pair vault name")
                }
                if requiresPartnerInviteCode {
                    Section("Partner invite code") {
                        TextField("Invite code", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Text("The name is encrypted with the vault key; the relay receives only authenticated ciphertext.")
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
                Section("One-time invitation code") {
                    TextField("64-character code", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel("Pair invitation code")
                }
                Section {
                    Text("Acceptance decrypts and stores only your device’s share. It does not unlock the vault.")
                }
            }
            .navigationTitle("Accept Pair Invite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept") {
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
