import SwiftUI

/// Fullscreen photo viewer screen.
/// Requests decrypted media bytes in memory via EncryptedMediaStorageEngine,
/// displays the photo preview, allows exporting to Photos library, and allows deletion.
/// EXIF, GPS, camera metadata, and original filenames are strictly hidden in the UI.
public struct PhotoDetailView: View {
    public let item: MediaItem
    @ObservedObject private var vaultManager: VaultManager
    public let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var exportService = MediaImportExportService()
    
    @State private var fullImage: Image? = nil
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var toastMessage: String? = nil
    @State private var isExporting: Bool = false
    
    public init(
        item: MediaItem,
        vaultManager: VaultManager,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.vaultManager = vaultManager
        self.onDelete = onDelete
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(VaultTheme.textPrimary)
                            .padding(10)
                            .background(VaultTheme.glassSurface)
                            .clipShape(Circle())
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.mediaType == .video ? "Encrypted Video" : "Encrypted Photo")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(VaultTheme.textPrimary)
                        
                        Text(formattedFileSize(item.fileSize))
                            .font(.system(size: 12))
                            .foregroundColor(VaultTheme.textSecondary)
                    }
                    .padding(.leading, 8)
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button(action: { exportItem() }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(VaultTheme.secondaryViolet)
                                .padding(10)
                                .background(VaultTheme.glassSurface)
                                .clipShape(Circle())
                        }
                        .disabled(isExporting)
                        
                        Button(action: {
                            onDelete()
                            dismiss()
                        }) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.red.opacity(0.9))
                                .padding(10)
                                .background(VaultTheme.glassSurface)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(VaultTheme.cardBackground)
                
                if let toast = toastMessage {
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(VaultTheme.accentViolet)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(VaultTheme.glassSurface)
                        .cornerRadius(20)
                        .padding(.top, 8)
                }
                
                // Photo Area
                ZStack {
                    if let image = fullImage {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(8)
                    } else if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(VaultTheme.secondaryViolet)
                            Text("Decrypting media payload...")
                                .font(.system(size: 14))
                                .foregroundColor(VaultTheme.textSecondary)
                        }
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 48))
                                .foregroundColor(Color.red.opacity(0.8))
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(VaultTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(32)
                    }
                }
            }
        }
        .task {
            await loadFullMedia()
        }
        .onDisappear {
            fullImage = nil
        }
        .onChange(of: vaultManager.session.isAuthenticated) { isAuthenticated in
            if !isAuthenticated {
                dismiss()
            }
        }
    }
    
    private func loadFullMedia() async {
        guard let masterKey = vaultManager.session.activeMasterKey,
              let vaultType = vaultManager.session.activeVaultType else {
            errorMessage = "Active session key material unavailable."
            isLoading = false
            return
        }
        
        let engine = EncryptedMediaStorageEngine(storage: vaultManager.storage)
        do {
            let decryptedMediaBytes = try engine.loadMedia(for: item, vault: vaultType, masterKey: masterKey)
            
            #if canImport(UIKit)
            if let uiImg = UIImage(data: decryptedMediaBytes) {
                fullImage = Image(uiImage: uiImg)
            } else {
                fullImage = Image(systemName: "photo.fill")
            }
            #else
            fullImage = Image(systemName: "photo.fill")
            #endif
            
            isLoading = false
        } catch {
            errorMessage = "Failed to decrypt media payload."
            isLoading = false
        }
    }
    
    private func exportItem() {
        isExporting = true
        toastMessage = "Exporting..."
        
        Task {
            do {
                try await exportService.exportMediaItem(item, vaultManager: vaultManager)
                toastMessage = "Saved to Photos."
            } catch let err as MediaImportExportError {
                toastMessage = err.userFacingMessage
            } catch {
                toastMessage = "Unable to export this media."
            }
            isExporting = false
        }
    }
    
    private func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
