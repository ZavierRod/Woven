import PhotosUI
import SwiftUI
import UIKit

struct SoloVaultRootView: View {
    @State private var store: SoloVaultStore
    @Environment(\.scenePhase) private var scenePhase

    init(store: SoloVaultStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        ZStack {
            SoloVaultScreen(
                phase: store.phase,
                decryptedPhotos: store.decryptedPhotos,
                isCreating: store.isCreating,
                isImporting: store.isImporting,
                isUnlocking: store.isUnlocking,
                deletingPhotoIDs: store.deletingPhotoIDs,
                errorMessage: store.errorMessage,
                onCreate: { name in
                    await store.createVault(named: name)
                },
                onImport: { data in
                    await store.importPhoto(data)
                },
                onUnlock: {
                    await store.unlock()
                },
                onLock: {
                    store.lock()
                },
                onDelete: { id in
                    await store.deletePhoto(id: id)
                },
                onRetry: {
                    await store.retryLoading()
                },
                onPresentError: { message in
                    store.presentError(message)
                },
                onDismissError: {
                    store.dismissError()
                }
            )

            if scenePhase != .active {
                SoloVaultPrivacyShield()
            }
        }
        .task {
            await store.bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, !store.isUnlocking {
                store.lock()
            }
        }
    }
}

private enum SoloVaultPresentation: Identifiable {
    case createVault
    case photo(SoloVaultMediaRecord)

    var id: String {
        switch self {
        case .createVault:
            return "create-vault"
        case .photo(let record):
            return "photo-\(record.id.uuidString)"
        }
    }
}

struct SoloVaultScreen: View {
    let phase: SoloVaultPhase
    var decryptedPhotos: [UUID: Data] = [:]
    var isCreating = false
    var isImporting = false
    var isUnlocking = false
    var deletingPhotoIDs: Set<UUID> = []
    var errorMessage: String?

    var onCreate: (String) async -> Bool = { _ in false }
    var onImport: (Data) async -> Void = { _ in }
    var onUnlock: () async -> Void = {}
    var onLock: () -> Void = {}
    var onDelete: (UUID) async -> Void = { _ in }
    var onRetry: () async -> Void = {}
    var onPresentError: (String) -> Void = { _ in }
    var onDismissError: () -> Void = {}

    @State private var presentation: SoloVaultPresentation?
    @State private var photoToDelete: SoloVaultMediaRecord?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

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
            .toolbar {
                if case .unlocked = phase {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onLock) {
                            Label("Lock", systemImage: "lock.fill")
                        }
                        .accessibilityLabel("Lock Solo vault")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 50,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Add Photos", systemImage: "plus")
                        }
                        .disabled(isImporting)
                        .accessibilityLabel("Choose photos to encrypt")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $presentation) { destination in
            switch destination {
            case .createVault:
                CreateSoloVaultView(onCreate: onCreate)
            case .photo(let record):
                SoloVaultPhotoViewer(
                    record: record,
                    photoData: decryptedPhotos[record.id],
                    isDeleting: deletingPhotoIDs.contains(record.id),
                    onDelete: onDelete
                )
            }
        }
        .alert(
            "Delete encrypted photo?",
            isPresented: Binding(
                get: { photoToDelete != nil },
                set: { if !$0 { photoToDelete = nil } }
            ),
            presenting: photoToDelete
        ) { record in
            Button("Cancel", role: .cancel) {
                photoToDelete = nil
            }
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete(record.id)
                    photoToDelete = nil
                }
            }
        } message: { _ in
            Text("This permanently removes the encrypted file from this device.")
        }
        .alert(
            "Woven couldn't complete that action",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { onDismissError() } }
            )
        ) {
            Button("OK", action: onDismissError)
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importSelectedPhotos(items) }
        }
        .onChange(of: phase.isUnlocked) { _, isUnlocked in
            guard !isUnlocked else { return }
            presentation = nil
            photoToDelete = nil
            selectedPhotoItems = []
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingView
        case .noVault:
            noVaultView
        case .locked(let summary):
            lockedView(summary: summary)
        case .unlocked(let manifest):
            unlockedView(manifest: manifest)
        case .failed(let message):
            errorView(message: message)
        }
    }

    private var navigationTitle: String {
        switch phase {
        case .unlocked(let manifest):
            return manifest.name
        case .locked(let summary):
            return summary.name
        default:
            return "Woven"
        }
    }

    private var loadingView: some View {
        VStack(spacing: WovenTheme.spacing16) {
            ProgressView()
                .controlSize(.large)
                .tint(WovenTheme.accent)
            Text("Loading your vault…")
                .font(WovenTheme.subheadline())
                .foregroundStyle(WovenTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Solo vault")
    }

    private var noVaultView: some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()

            securityIcon(systemName: "lock.shield.fill")

            VStack(spacing: WovenTheme.spacing8) {
                Text("Your private space")
                    .font(WovenTheme.title2())
                    .foregroundStyle(WovenTheme.textPrimary)
                Text("Create one Solo vault. Photos are encrypted on this device before they are saved.")
                    .font(WovenTheme.subheadline())
                    .foregroundStyle(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, WovenTheme.spacing32)

            Button {
                presentation = .createVault
            } label: {
                Label("Create Solo Vault", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WovenButtonStyle(isEnabled: !isCreating))
            .disabled(isCreating)
            .padding(.horizontal, WovenTheme.spacing32)
            .accessibilityLabel("Create a Solo vault")

            Spacer()

            Label("Solo vault data stays on this device", systemImage: "iphone.and.arrow.forward.inward")
                .font(WovenTheme.caption())
                .foregroundStyle(WovenTheme.textTertiary)
                .padding(.bottom, WovenTheme.spacing20)
        }
    }

    private func lockedView(summary: SoloVaultSummary) -> some View {
        VStack(spacing: WovenTheme.spacing24) {
            Spacer()
            securityIcon(systemName: "lock.fill")

            VStack(spacing: WovenTheme.spacing8) {
                Text("Vault locked")
                    .font(WovenTheme.title2())
                    .foregroundStyle(WovenTheme.textPrimary)
                Text(photoCountText(summary.photoCount))
                    .font(WovenTheme.subheadline())
                    .foregroundStyle(WovenTheme.textSecondary)
                Text("Decrypted photos and thumbnails are hidden.")
                    .font(WovenTheme.caption())
                    .foregroundStyle(WovenTheme.textTertiary)
            }
            .multilineTextAlignment(.center)

            Button {
                Task { await onUnlock() }
            } label: {
                if isUnlocking {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Unlock Vault", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(WovenButtonStyle(isEnabled: !isUnlocking))
            .disabled(isUnlocking)
            .padding(.horizontal, WovenTheme.spacing32)
            .accessibilityLabel(isUnlocking ? "Unlocking Solo vault" : "Unlock Solo vault")

            Spacer()
        }
    }

    private func unlockedView(manifest: SoloVaultManifest) -> some View {
        Group {
            if manifest.media.isEmpty {
                VStack(spacing: WovenTheme.spacing20) {
                    Spacer()
                    securityIcon(systemName: "photo.on.rectangle.angled")
                    VStack(spacing: WovenTheme.spacing8) {
                        Text("Your vault is empty")
                            .font(WovenTheme.title2())
                            .foregroundStyle(WovenTheme.textPrimary)
                        Text("Choose one or more photos. Woven encrypts each one in memory and persists only the sealed bytes.")
                            .font(WovenTheme.subheadline())
                            .foregroundStyle(WovenTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
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
                    .buttonStyle(WovenButtonStyle(isEnabled: !isImporting))
                    .disabled(isImporting)
                    .padding(.horizontal, WovenTheme.spacing32)
                    .accessibilityLabel("Choose photos to encrypt")
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4)
                        ],
                        spacing: 4
                    ) {
                        ForEach(manifest.media.sorted(by: { $0.createdAt > $1.createdAt })) { record in
                            SoloVaultPhotoCell(
                                record: record,
                                photoData: decryptedPhotos[record.id],
                                isDeleting: deletingPhotoIDs.contains(record.id),
                                onOpen: {
                                    presentation = .photo(record)
                                },
                                onDelete: {
                                    photoToDelete = record
                                }
                            )
                        }
                    }
                    .padding(4)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isImporting {
                Label("Encrypting photos…", systemImage: "lock.rotation")
                    .font(WovenTheme.subheadline())
                    .foregroundStyle(WovenTheme.textPrimary)
                    .padding(.horizontal, WovenTheme.spacing16)
                    .padding(.vertical, WovenTheme.spacing12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, WovenTheme.spacing20)
                    .accessibilityLabel("Encrypting selected photos")
            }
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Vault unavailable", systemImage: "exclamationmark.lock.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await onRetry() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Retry loading Solo vault")
        }
    }

    private func securityIcon(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(WovenTheme.accent.opacity(0.12))
                .frame(width: 124, height: 124)
            Image(systemName: systemName)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(WovenTheme.accent)
        }
        .accessibilityHidden(true)
    }

    private func photoCountText(_ count: Int) -> String {
        count == 1 ? "1 encrypted photo" : "\(count) encrypted photos"
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
                await onImport(data)
            } catch is CancellationError {
                return
            } catch {
                unreadableCount += 1
            }
        }

        if unreadableCount > 0 {
            let noun = unreadableCount == 1 ? "photo" : "photos"
            onPresentError("\(unreadableCount) selected \(noun) could not be loaded.")
        }
    }
}

private struct SoloVaultPhotoCell: View {
    let record: SoloVaultMediaRecord
    let photoData: Data?
    let isDeleting: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    photo
                        .frame(width: proxy.size.width, height: proxy.size.width)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Encrypted photo from \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")

                Button(role: .destructive, action: onDelete) {
                    Group {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Image(systemName: "trash.fill")
                        }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.68), in: Circle())
                }
                .disabled(isDeleting)
                .padding(6)
                .accessibilityLabel("Delete encrypted photo")
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var photo: some View {
        if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
                .privacySensitive()
        } else {
            Rectangle()
                .fill(WovenTheme.cardBackground)
                .overlay {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(WovenTheme.textTertiary)
                }
        }
    }
}

private struct CreateSoloVaultView: View {
    let onCreate: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = "Solo Vault"
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Vault name") {
                    TextField("Solo Vault", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Solo vault name")
                }

                Section {
                    Label("A random 256-bit key is stored in this device's Keychain.", systemImage: "key.fill")
                    Label("Photos are sealed with AES-GCM authenticated encryption.", systemImage: "lock.shield.fill")
                    Label("Only encrypted files are written to Woven's storage.", systemImage: "internaldrive.fill")
                } header: {
                    Text("Local security")
                }
            }
            .navigationTitle("New Solo Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    .accessibilityLabel(isSubmitting ? "Creating Solo vault" : "Create Solo vault")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        if await onCreate(name) {
            dismiss()
        } else {
            isSubmitting = false
        }
    }
}

private struct SoloVaultPhotoViewer: View {
    let record: SoloVaultMediaRecord
    let photoData: Data?
    let isDeleting: Bool
    let onDelete: (UUID) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .privacySensitive()
                        .accessibilityLabel("Decrypted vault photo")
                } else {
                    ContentUnavailableView(
                        "Vault locked",
                        systemImage: "lock.fill",
                        description: Text("The decrypted photo is no longer available.")
                    )
                }
            }
            .navigationTitle("Encrypted Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .disabled(photoData == nil || isDeleting)
                    .accessibilityLabel("Delete encrypted photo")
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Delete encrypted photo?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete(record.id)
                    dismiss()
                }
            }
        } message: {
            Text("This permanently removes the encrypted file from this device.")
        }
    }
}

private struct SoloVaultPrivacyShield: View {
    var body: some View {
        ZStack {
            WovenTheme.background.ignoresSafeArea()
            VStack(spacing: WovenTheme.spacing16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(WovenTheme.accent)
                Text("Woven is locked")
                    .font(WovenTheme.title2())
                    .foregroundStyle(WovenTheme.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Woven is locked")
    }
}

private let previewVaultID = UUID(uuidString: "B19B1174-9A79-489E-8C4F-7C13F7C7F6A1")!
private let previewPhotoID = UUID(uuidString: "251B8B9B-7E8E-4C75-9788-F9171598DE73")!
private let previewRecord = SoloVaultMediaRecord(
    id: previewPhotoID,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    encryptedFileName: "preview.woven",
    encryptedByteCount: 256
)
private let previewManifest = SoloVaultManifest(
    id: previewVaultID,
    name: "Solo Vault",
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    media: [previewRecord]
)

@MainActor
private func makePreviewPhotoData() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600))
    return renderer.pngData { context in
        UIColor(red: 0.12, green: 0.08, blue: 0.22, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
        let image = UIImage(systemName: "sparkles")?.withTintColor(.systemPurple, renderingMode: .alwaysOriginal)
        image?.draw(in: CGRect(x: 200, y: 200, width: 200, height: 200))
    }
}

#Preview("Loading") {
    SoloVaultScreen(phase: .loading)
}

#Preview("No Vault") {
    SoloVaultScreen(phase: .noVault)
}

#Preview("Locked") {
    SoloVaultScreen(phase: .locked(previewManifest.summary))
}

#Preview("Unlocked") {
    SoloVaultScreen(
        phase: .unlocked(previewManifest),
        decryptedPhotos: [previewPhotoID: makePreviewPhotoData()]
    )
}

#Preview("Empty") {
    SoloVaultScreen(
        phase: .unlocked(
            SoloVaultManifest(
                id: previewVaultID,
                name: "Solo Vault",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
    )
}

#Preview("Error") {
    SoloVaultScreen(phase: .failed("The local vault data could not be opened."))
}
