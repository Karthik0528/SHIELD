import SwiftUI
#if canImport(AVKit)
import AVKit
#endif

public enum GallerySection: String, CaseIterable, Identifiable {
    case photos = "Photos"
    case videos = "Videos"
    public var id: String { rawValue }
}

/// Secure Paging Media Detail Viewer & Gallery.
/// Supports separate Photos and Videos browsing modes, mode-specific thumbnail strip navigation,
/// explicit branching between encrypted photo and video streaming pathways, export/delete actions,
/// and automatic temporary file cleanup on item change, mode switch, view dismissal, or session lock.
public struct PhotoDetailView: View {
    public let initialItem: MediaItem
    public let mediaItems: [MediaItem]
    @ObservedObject private var vaultManager: VaultManager
    public let onDelete: (MediaItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var exportService = MediaImportExportService()
    
    @State private var selectedMode: GallerySection
    @State private var selectedPhotoID: UUID?
    @State private var selectedVideoID: UUID?
    
    @State private var currentImage: Image? = nil
    @State private var videoPlayer: AVPlayer? = nil
    @State private var tempVideoURL: URL? = nil
    
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var toastMessage: String? = nil
    @State private var isExporting: Bool = false
    
    public init(
        item: MediaItem,
        mediaItems: [MediaItem] = [],
        vaultManager: VaultManager,
        onDelete: @escaping (MediaItem) -> Void
    ) {
        self.initialItem = item
        let list = mediaItems.isEmpty ? [item] : mediaItems
        self.mediaItems = list
        self.vaultManager = vaultManager
        self.onDelete = onDelete
        
        let initialPhotos = list.filter { $0.mediaType == .photo }
        let initialVideos = list.filter { $0.mediaType == .video }
        
        if item.mediaType == .video {
            self._selectedMode = State(initialValue: .videos)
            self._selectedVideoID = State(initialValue: item.id)
            self._selectedPhotoID = State(initialValue: initialPhotos.first?.id)
        } else {
            if !initialPhotos.isEmpty {
                self._selectedMode = State(initialValue: .photos)
                self._selectedPhotoID = State(initialValue: item.id)
                self._selectedVideoID = State(initialValue: initialVideos.first?.id)
            } else {
                self._selectedMode = State(initialValue: .videos)
                self._selectedVideoID = State(initialValue: initialVideos.first?.id)
                self._selectedPhotoID = State(initialValue: nil)
            }
        }
    }
    
    public var photos: [MediaItem] {
        mediaItems.filter { $0.mediaType == .photo }
    }
    
    public var videos: [MediaItem] {
        mediaItems.filter { $0.mediaType == .video }
    }
    
    public var selectedItem: MediaItem? {
        switch selectedMode {
        case .photos:
            guard let id = selectedPhotoID else { return photos.first }
            return photos.first(where: { $0.id == id }) ?? photos.first
        case .videos:
            guard let id = selectedVideoID else { return videos.first }
            return videos.first(where: { $0.id == id }) ?? videos.first
        }
    }
    
    private var activeTaskID: String {
        switch selectedMode {
        case .photos:
            return "photo_\(selectedPhotoID?.uuidString ?? "none")"
        case .videos:
            return "video_\(selectedVideoID?.uuidString ?? "none")"
        }
    }
    
    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.05, blue: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Sleek Header Bar with Photos/Videos Mode Switcher
                HStack {
                    Button(action: { dismissAndCleanup() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(VaultTheme.textPrimary)
                            .padding(10)
                            .background(VaultTheme.glassSurface)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Mode Switcher Control
                    if !photos.isEmpty && !videos.isEmpty {
                        HStack(spacing: 4) {
                            Button(action: {
                                if selectedMode != .photos {
                                    cleanupActiveMedia()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedMode = .photos
                                        if selectedPhotoID == nil || !photos.contains(where: { $0.id == selectedPhotoID }) {
                                            selectedPhotoID = photos.first?.id
                                        }
                                    }
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 12))
                                    Text("Photos (\(photos.count))")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(selectedMode == .photos ? VaultTheme.textPrimary : VaultTheme.textSecondary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 14)
                                .background(selectedMode == .photos ? VaultTheme.secondaryViolet.opacity(0.35) : Color.clear)
                                .clipShape(Capsule())
                            }
                            
                            Button(action: {
                                if selectedMode != .videos {
                                    cleanupActiveMedia()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedMode = .videos
                                        if selectedVideoID == nil || !videos.contains(where: { $0.id == selectedVideoID }) {
                                            selectedVideoID = videos.first?.id
                                        }
                                    }
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.tv.fill")
                                        .font(.system(size: 12))
                                    Text("Videos (\(videos.count))")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(selectedMode == .videos ? VaultTheme.textPrimary : VaultTheme.textSecondary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 14)
                                .background(selectedMode == .videos ? VaultTheme.secondaryViolet.opacity(0.35) : Color.clear)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(4)
                        .background(VaultTheme.glassSurface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(VaultTheme.subtleBorder, lineWidth: 1))
                    } else if !photos.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.fill")
                                .foregroundColor(VaultTheme.secondaryViolet)
                            Text("Photos (\(photos.count))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(VaultTheme.textPrimary)
                        }
                    } else if !videos.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "play.tv.fill")
                                .foregroundColor(VaultTheme.secondaryViolet)
                            Text("Videos (\(videos.count))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(VaultTheme.textPrimary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: { exportSelectedItem() }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(VaultTheme.secondaryViolet)
                                .padding(10)
                                .background(VaultTheme.glassSurface)
                                .clipShape(Circle())
                        }
                        .disabled(isExporting || selectedItem == nil)
                        
                        Button(action: { deleteSelectedItem() }) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color.red.opacity(0.85))
                                .padding(10)
                                .background(VaultTheme.glassSurface)
                                .clipShape(Circle())
                        }
                        .disabled(selectedItem == nil)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(VaultTheme.glassSurface)
                
                if let toast = toastMessage {
                    Text(toast)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(VaultTheme.accentViolet)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(VaultTheme.glassSurface)
                        .cornerRadius(20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Paging Canvas (Photos mode OR Videos mode)
                if selectedMode == .photos {
                    if let currentID = selectedPhotoID {
                        let binding = Binding<UUID>(
                            get: { selectedPhotoID ?? currentID },
                            set: { selectedPhotoID = $0 }
                        )
                        TabView(selection: binding) {
                            ForEach(photos) { item in
                                ZStack {
                                    if item.id == selectedPhotoID {
                                        if let img = currentImage {
                                            img.resizable()
                                               .scaledToFit()
                                               .frame(maxWidth: .infinity, maxHeight: .infinity)
                                               .padding(12)
                                        } else if isLoading {
                                            loadingView(text: "Decrypting photo payload...")
                                        } else if let error = errorMessage {
                                            errorView(text: error)
                                        }
                                    } else {
                                        Color.clear
                                    }
                                }
                                .tag(item.id)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    } else {
                        Spacer()
                        Text("No Photos Available")
                            .font(.system(size: 14))
                            .foregroundColor(VaultTheme.textMuted)
                        Spacer()
                    }
                } else {
                    if let currentID = selectedVideoID {
                        let binding = Binding<UUID>(
                            get: { selectedVideoID ?? currentID },
                            set: { selectedVideoID = $0 }
                        )
                        TabView(selection: binding) {
                            ForEach(videos) { item in
                                ZStack {
                                    if item.id == selectedVideoID {
                                        #if canImport(AVKit)
                                        if let player = videoPlayer {
                                            VideoPlayer(player: player)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .cornerRadius(16)
                                                .padding(12)
                                                .onAppear { player.play() }
                                                .onDisappear { player.pause() }
                                        } else if isLoading {
                                            loadingView(text: "Streaming encrypted video...")
                                        } else if let error = errorMessage {
                                            errorView(text: error)
                                        }
                                        #else
                                        errorView(text: "Video playback unavailable on this platform.")
                                        #endif
                                    } else {
                                        Color.clear
                                    }
                                }
                                .tag(item.id)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    } else {
                        Spacer()
                        Text("No Videos Available")
                            .font(.system(size: 14))
                            .foregroundColor(VaultTheme.textMuted)
                        Spacer()
                    }
                }
                
                // Bottom Thumbnail Strip & Position Control Container
                VStack(spacing: 8) {
                    if selectedMode == .photos {
                        if photos.count > 1 {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(photos) { item in
                                            let isSelected = (item.id == selectedPhotoID)
                                            PhotoThumbnailView(
                                                item: item,
                                                vault: vaultManager.session.activeVaultType ?? .main,
                                                masterKey: vaultManager.session.activeMasterKey,
                                                storage: vaultManager.storage,
                                                isSelected: isSelected,
                                                isSelectionMode: false
                                            ) {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    selectedPhotoID = item.id
                                                }
                                            }
                                            .frame(width: 60, height: 60)
                                            .id(item.id)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                }
                                .onChange(of: selectedPhotoID) { newID in
                                    if let id = newID {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            proxy.scrollTo(id, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
                        
                        if !photos.isEmpty {
                            let currentIndex = (photos.firstIndex(where: { $0.id == selectedPhotoID }) ?? 0) + 1
                            Text("\(currentIndex) of \(photos.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(VaultTheme.textSecondary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 14)
                                .background(VaultTheme.glassSurface)
                                .clipShape(Capsule())
                                .padding(.bottom, 12)
                        }
                    } else {
                        if videos.count > 1 {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(videos) { item in
                                            let isSelected = (item.id == selectedVideoID)
                                            PhotoThumbnailView(
                                                item: item,
                                                vault: vaultManager.session.activeVaultType ?? .main,
                                                masterKey: vaultManager.session.activeMasterKey,
                                                storage: vaultManager.storage,
                                                isSelected: isSelected,
                                                isSelectionMode: false
                                            ) {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    selectedVideoID = item.id
                                                }
                                            }
                                            .frame(width: 60, height: 60)
                                            .id(item.id)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                }
                                .onChange(of: selectedVideoID) { newID in
                                    if let id = newID {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            proxy.scrollTo(id, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
                        
                        if !videos.isEmpty {
                            let currentIndex = (videos.firstIndex(where: { $0.id == selectedVideoID }) ?? 0) + 1
                            Text("\(currentIndex) of \(videos.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(VaultTheme.textSecondary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 14)
                                .background(VaultTheme.glassSurface)
                                .clipShape(Capsule())
                                .padding(.bottom, 12)
                        }
                    }
                }
                .background(
                    VaultTheme.cardBackground.opacity(0.85)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .task(id: activeTaskID) {
            if let item = selectedItem {
                await loadMediaItem(item)
            }
        }
        .onDisappear {
            cleanupActiveMedia()
        }
        .onChange(of: vaultManager.session.isAuthenticated) { isAuthenticated in
            if !isAuthenticated {
                dismissAndCleanup()
            }
        }
        .onChange(of: vaultManager.session.activeVaultType) { _ in
            dismissAndCleanup()
        }
    }
    
    @ViewBuilder
    private func loadingView(text: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(VaultTheme.secondaryViolet)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(VaultTheme.textSecondary)
        }
    }
    
    @ViewBuilder
    private func errorView(text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(Color.red.opacity(0.8))
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(VaultTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
    
    private func loadMediaItem(_ item: MediaItem) async {
        cleanupActiveMedia()
        isLoading = true
        errorMessage = nil
        
        guard let masterKey = vaultManager.session.activeMasterKey,
              let vaultType = vaultManager.session.activeVaultType else {
            errorMessage = "Active session key material unavailable."
            isLoading = false
            return
        }
        
        if item.mediaType == .photo {
            let engine = EncryptedMediaStorageEngine(storage: vaultManager.storage)
            do {
                let decryptedBytes = try engine.loadMedia(for: item, vault: vaultType, masterKey: masterKey)
                #if canImport(UIKit)
                if let uiImg = UIImage(data: decryptedBytes) {
                    currentImage = Image(uiImage: uiImg)
                } else {
                    currentImage = Image(systemName: "photo.fill")
                }
                #else
                currentImage = Image(systemName: "photo.fill")
                #endif
                isLoading = false
            } catch {
                errorMessage = "Failed to decrypt media payload."
                isLoading = false
            }
        } else {
            let service = MediaImportExportService(videoEngine: VideoStorageEngine(storage: vaultManager.storage))
            do {
                let playbackURL = try service.prepareVideoForPlayback(item: item, vaultManager: vaultManager)
                tempVideoURL = playbackURL
                #if canImport(AVKit)
                videoPlayer = AVPlayer(url: playbackURL)
                #endif
                isLoading = false
            } catch {
                errorMessage = "Failed to stream encrypted video."
                isLoading = false
            }
        }
    }
    
    private func cleanupActiveMedia() {
        #if canImport(AVKit)
        videoPlayer?.pause()
        videoPlayer = nil
        #endif
        currentImage = nil
        
        if let tempURL = tempVideoURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempVideoURL = nil
        }
    }
    
    private func dismissAndCleanup() {
        cleanupActiveMedia()
        dismiss()
    }
    
    private func exportSelectedItem() {
        guard let itemToExport = selectedItem else { return }
        isExporting = true
        toastMessage = "Exporting..."
        
        Task {
            do {
                try await exportService.exportMediaItem(itemToExport, vaultManager: vaultManager)
                toastMessage = "Saved to Photos."
            } catch let err as MediaImportExportError {
                toastMessage = err.userFacingMessage
            } catch {
                toastMessage = "Unable to export this media."
            }
            isExporting = false
        }
    }
    
    private func deleteSelectedItem() {
        guard let itemToDelete = selectedItem else { return }
        onDelete(itemToDelete)
        
        if itemToDelete.mediaType == .photo {
            let remaining = photos.filter { $0.id != itemToDelete.id }
            if let next = remaining.first {
                selectedPhotoID = next.id
            } else if !videos.isEmpty {
                selectedMode = .videos
                selectedVideoID = videos.first?.id
            } else {
                dismissAndCleanup()
            }
        } else {
            let remaining = videos.filter { $0.id != itemToDelete.id }
            if let next = remaining.first {
                selectedVideoID = next.id
            } else if !photos.isEmpty {
                selectedMode = .photos
                selectedPhotoID = photos.first?.id
            } else {
                dismissAndCleanup()
            }
        }
    }
}
