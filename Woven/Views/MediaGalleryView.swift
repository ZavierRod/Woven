import SwiftUI
import Combine

struct MediaGalleryView: View {
    let vaultId: UUID
    @StateObject private var viewModel = MediaViewModel()
    @State private var mediaToDelete: Media?
    private var showDeleteConfirmation: Bool {
        mediaToDelete != nil
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.media.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(WovenTheme.accent)
                    Text("Loading media...")
                        .font(WovenTheme.subheadline())
                        .foregroundColor(WovenTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else if viewModel.media.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(WovenTheme.accent.opacity(0.1))
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
                                        colors: [WovenTheme.accent, WovenTheme.accent.opacity(0.6)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                    
                    VStack(spacing: 8) {
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
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(viewModel.media) { media in
                        MediaThumbnailView(media: media)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let index = viewModel.media.firstIndex(where: { $0.id == media.id }) {
                                    viewModel.selectedMediaIndex = index
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    mediaToDelete = media
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.selectedMediaIndex != nil },
            set: { if !$0 { viewModel.selectedMediaIndex = nil } }
        )) {
            if let startIndex = viewModel.selectedMediaIndex {
                MediaPagerView(
                    mediaItems: viewModel.media,
                    startIndex: startIndex,
                    onDelete: { deletedMedia in
                        Task {
                            await viewModel.deleteMedia(deletedMedia)
                        }
                    }
                )
            }
        }
        .alert("Delete Media?", isPresented: Binding(
            get: { mediaToDelete != nil },
            set: { if !$0 { mediaToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                mediaToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let media = mediaToDelete {
                    Task {
                        await viewModel.deleteMedia(media)
                        mediaToDelete = nil
                    }
                }
            }
        } message: {
            if let media = mediaToDelete {
                Text("This will permanently delete \"\(media.fileName)\" from this vault.")
            }
        }
        .task {
            await viewModel.loadMedia(vaultId: vaultId)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MediaUploaded"))) { _ in
            Task {
                await viewModel.loadMedia(vaultId: vaultId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MediaDeleted"))) { _ in
            Task {
                await viewModel.loadMedia(vaultId: vaultId)
            }
        }
    }
}

// MARK: - Media Thumbnail

struct MediaThumbnailView: View {
    let media: Media
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if isLoading {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WovenTheme.cardBackground)
                        .overlay {
                            ProgressView()
                                .tint(WovenTheme.textSecondary)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WovenTheme.cardBackground)
                        .overlay {
                            Image(systemName: media.isPhoto ? "photo" : "video")
                                .font(.system(size: 24))
                                .foregroundColor(WovenTheme.textTertiary)
                        }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        do {
            let decryptedData = try await MediaService.shared.downloadAndDecryptMedia(media: media)
            
            if media.isPhoto {
                if let image = UIImage(data: decryptedData) {
                    await MainActor.run {
                        self.thumbnail = image
                        self.isLoading = false
                    }
                }
            } else {
                // For videos, we'd need to extract a frame - for now show placeholder
                await MainActor.run {
                    self.isLoading = false
                }
            }
        } catch {
            print("Failed to load thumbnail: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Media Detail View

struct MediaDetailView: View {
    let media: Media
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                WovenTheme.background.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(WovenTheme.accent)
                } else if let image = image {
                    ZoomableImageView(image: image)
                        .background(WovenTheme.background)
                } else if let error = error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(WovenTheme.error)
                        Text("Failed to load media")
                            .font(WovenTheme.headline())
                            .foregroundColor(WovenTheme.textPrimary)
                        Text(error.localizedDescription)
                            .font(WovenTheme.subheadline())
                            .foregroundColor(WovenTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    // Fallback state - should not normally occur
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(WovenTheme.accent)
                        Text("Loading...")
                            .font(WovenTheme.subheadline())
                            .foregroundColor(WovenTheme.textSecondary)
                    }
                }
            }
            .navigationTitle(media.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WovenTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(WovenTheme.accent)
                }
                
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .alert("Delete Media?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await deleteMedia()
                }
            }
        } message: {
            Text("This will permanently delete \"\(media.fileName)\" from this vault. This cannot be undone.")
        }
        .task {
            await loadMedia()
        }
        .preferredColorScheme(.dark)
    }
    
    private func loadMedia() async {
        isLoading = true
        error = nil
        
        do {
            print("📥 Starting to download and decrypt media: \(media.fileName)")
            let decryptedData = try await MediaService.shared.downloadAndDecryptMedia(media: media)
            print("✅ Downloaded and decrypted \(decryptedData.count) bytes")
            
            if media.isPhoto {
                guard let loadedImage = UIImage(data: decryptedData) else {
                    print("❌ Failed to create UIImage from decrypted data")
                    throw NSError(domain: "MediaDetailView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data. Data size: \(decryptedData.count) bytes"])
                }
                
                print("✅ Successfully created UIImage")
                await MainActor.run {
                    self.image = loadedImage
                    self.isLoading = false
                }
            } else {
                // Video playback would go here
                throw NSError(domain: "MediaDetailView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Video playback not yet implemented"])
            }
        } catch {
            print("❌ Error loading media: \(error)")
            await MainActor.run {
                self.error = error
                self.isLoading = false
                self.image = nil
            }
        }
    }
    
    private func deleteMedia() async {
        isDeleting = true
        defer { isDeleting = false }
        
        do {
            try await MediaService.shared.deleteMedia(mediaId: media.id)
            // Notify gallery to refresh
            NotificationCenter.default.post(name: NSNotification.Name("MediaDeleted"), object: nil)
            // Dismiss the detail view
            dismiss()
        } catch {
            self.error = error
            print("Failed to delete media: \(error)")
        }
    }
}

// MARK: - Media Pager View (Swipeable Gallery)

struct MediaPagerView: View {
    let mediaItems: [Media]
    let startIndex: Int
    let onDelete: (Media) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showDeleteConfirmation = false
    
    init(mediaItems: [Media], startIndex: Int, onDelete: @escaping (Media) -> Void) {
        self.mediaItems = mediaItems
        self.startIndex = startIndex
        self.onDelete = onDelete
        self._currentIndex = State(initialValue: startIndex)
    }
    
    private var currentMedia: Media? {
        guard currentIndex >= 0 && currentIndex < mediaItems.count else { return nil }
        return mediaItems[currentIndex]
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                TabView(selection: $currentIndex) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, media in
                        MediaPageItemView(media: media)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.5), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("\(currentIndex + 1) of \(mediaItems.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .alert("Delete Photo?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let media = currentMedia {
                    onDelete(media)
                    // If we deleted the last item, dismiss
                    if mediaItems.count <= 1 {
                        dismiss()
                    } else if currentIndex >= mediaItems.count - 1 {
                        // Move to previous if we deleted the last one
                        currentIndex = max(0, currentIndex - 1)
                    }
                }
            }
        } message: {
            if let media = currentMedia {
                Text("This will permanently delete \"\(media.fileName)\".")
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Single Page Item View

struct MediaPageItemView: View {
    let media: Media
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        ZStack {
            Color.black
            
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let image = image {
                ZoomableImageView(image: image)
            } else if error != nil {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text("Failed to load")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .task {
            await loadMedia()
        }
    }
    
    private func loadMedia() async {
        guard media.isPhoto else {
            await MainActor.run {
                self.error = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Video not supported"])
                self.isLoading = false
            }
            return
        }
        
        do {
            let decryptedData = try await MediaService.shared.downloadAndDecryptMedia(media: media)
            if let loadedImage = UIImage(data: decryptedData) {
                await MainActor.run {
                    self.image = loadedImage
                    self.isLoading = false
                }
            } else {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}

// MARK: - Media ViewModel

@MainActor
class MediaViewModel: ObservableObject {
    @Published var media: [Media] = []
    @Published var isLoading = false
    @Published var selectedMediaIndex: Int?
    @Published var deleteError: Error?
    
    var isShowingDetail: Bool {
        selectedMediaIndex != nil
    }
    
    func loadMedia(vaultId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            media = try await MediaService.shared.listMedia(vaultId: vaultId)
        } catch {
            print("Failed to load media: \(error)")
        }
    }
    
    func deleteMedia(_ media: Media) async {
        do {
            try await MediaService.shared.deleteMedia(mediaId: media.id)
            // Remove from local array immediately for better UX
            self.media.removeAll { $0.id == media.id }
            // Also post notification to refresh other views
            NotificationCenter.default.post(name: NSNotification.Name("MediaDeleted"), object: nil)
        } catch {
            deleteError = error
            print("Failed to delete media: \(error)")
        }
    }
}

