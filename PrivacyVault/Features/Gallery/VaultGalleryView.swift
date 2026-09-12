import SwiftUI

/// Main Gallery screen displayed when a vault session is active and authenticated.
/// Handles encrypted media grid rendering, toolbar operations, multi-selection management,
/// full-screen detail viewing, secure photo/video import triggers, and export actions.
public struct VaultGalleryView: View {
    @ObservedObject private var vaultManager: VaultManager
    @StateObject private var viewModel: VaultGalleryViewModel
    @StateObject private var selectionMode = PhotoSelectionMode()
    
    public init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
        self._viewModel = StateObject(wrappedValue: VaultGalleryViewModel(vaultManager: vaultManager))
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 0) {
                // Top Header Toolbar
                GalleryToolbar(
                    isSelectionMode: selectionMode.isSelectionMode,
                    selectedCount: selectionMode.selectedIDs.count,
                    onAddPhotos: {
                        vaultManager.session.recordActivity()
                        viewModel.isImportSheetPresented = true
                    },
                    onToggleSelection: {
                        vaultManager.session.recordActivity()
                        selectionMode.toggleSelectionMode()
                    },
                    onDeleteSelected: {
                        vaultManager.session.recordActivity()
                        viewModel.deleteItems(ids: selectionMode.selectedIDs)
                        selectionMode.clearSelection()
                    },
                    onExportSelected: {
                        vaultManager.session.recordActivity()
                        viewModel.exportItems(ids: selectionMode.selectedIDs)
                        selectionMode.clearSelection()
                    },
                    onLock: {
                        vaultManager.lock()
                    }
                )
                
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(VaultTheme.secondaryViolet)
                    Spacer()
                } else if viewModel.mediaItems.isEmpty {
                    EmptyVaultView {
                        vaultManager.session.recordActivity()
                        viewModel.isImportSheetPresented = true
                    }
                } else {
                    // Encrypted Photo Grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(viewModel.mediaItems) { item in
                                PhotoThumbnailView(
                                    item: item,
                                    vault: viewModel.activeVault,
                                    masterKey: viewModel.masterKey,
                                    isSelected: selectionMode.selectedIDs.contains(item.id),
                                    isSelectionMode: selectionMode.isSelectionMode,
                                    onTap: {
                                        vaultManager.session.recordActivity()
                                        if selectionMode.isSelectionMode {
                                            selectionMode.toggleSelect(id: item.id)
                                        } else {
                                            viewModel.selectedDetailItem = item
                                        }
                                    }
                                )
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
        .onAppear {
            vaultManager.session.recordActivity()
            viewModel.fetchMediaItems()
        }
        .sheet(isPresented: $viewModel.isImportSheetPresented) {
            PhotoImportSheet(vaultManager: vaultManager) {
                viewModel.fetchMediaItems()
            }
        }
        .fullScreenCover(item: $viewModel.selectedDetailItem) { item in
            PhotoDetailView(
                item: item,
                vaultManager: vaultManager,
                onDelete: {
                    viewModel.deleteItem(item)
                    viewModel.selectedDetailItem = nil
                }
            )
        }
    }
}

/// View model managing media item fetching, storage engine operations, multi-select export, and presentation states.
public final class VaultGalleryViewModel: ObservableObject, @unchecked Sendable {
    @Published public var mediaItems: [MediaItem] = []
    @Published public var isLoading: Bool = false
    @Published public var isImportSheetPresented: Bool = false
    @Published public var selectedDetailItem: MediaItem? = nil
    
    private let vaultManager: VaultManager
    private let storageEngine: EncryptedMediaStorageEngine
    private let importExportService: MediaImportExportService
    
    public init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
        self.storageEngine = EncryptedMediaStorageEngine(storage: vaultManager.storage)
        self.importExportService = MediaImportExportService()
    }
    
    public var activeVault: VaultType {
        return vaultManager.session.activeVaultType ?? .main
    }
    
    public var masterKey: SymmetricKeyMaterial? {
        return vaultManager.session.activeMasterKey
    }
    
    @MainActor
    public func fetchMediaItems() {
        guard let vault = vaultManager.session.activeVaultType else { return }
        isLoading = true
        do {
            mediaItems = try vaultManager.storage.database.fetchMediaItems(for: vault)
        } catch {
            mediaItems = []
        }
        isLoading = false
    }
    
    @MainActor
    public func deleteItem(_ item: MediaItem) {
        guard let vault = vaultManager.session.activeVaultType else { return }
        try? storageEngine.deleteMedia(itemID: item.id, vault: vault)
        fetchMediaItems()
    }
    
    @MainActor
    public func deleteItems(ids: Set<UUID>) {
        guard let vault = vaultManager.session.activeVaultType else { return }
        for id in ids {
            try? storageEngine.deleteMedia(itemID: id, vault: vault)
        }
        fetchMediaItems()
    }
    
    @MainActor
    public func exportItems(ids: Set<UUID>) {
        guard vaultManager.session.isAuthenticated else { return }
        let selectedItems = mediaItems.filter { ids.contains($0.id) }
        Task {
            _ = try? await importExportService.exportMultipleItems(selectedItems, vaultManager: vaultManager)
        }
    }
}
