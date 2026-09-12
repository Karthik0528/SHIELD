import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

/// Modal sheet UI for securely importing photos and videos into the active vault.
/// Delegates media selection to native iOS `PhotosPicker` (`PhotosUI`) and streams video/photo payloads
/// into the authenticated vault session (`vaultManager.session.activeVaultType`).
public struct PhotoImportSheet: View {
    @ObservedObject private var vaultManager: VaultManager
    public let onImportCompleted: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = MediaImportExportService()
    
    #if canImport(PhotosUI)
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    #endif
    
    @State private var isProcessing: Bool = false
    @State private var statusMessage: String = ""
    @State private var errorMessage: String? = nil
    
    public init(vaultManager: VaultManager, onImportCompleted: @escaping () -> Void) {
        self.vaultManager = vaultManager
        self.onImportCompleted = onImportCompleted
    }
    
    private var isPlatformSupported: Bool {
        #if canImport(PhotosUI) && os(iOS)
        return true
        #else
        return false
        #endif
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 24) {
                // Header Bar
                HStack {
                    Text("Import Media")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(VaultTheme.textSecondary)
                    }
                    .disabled(isProcessing)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // Informational Glass Card
                GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                    VStack(spacing: 16) {
                        Image(systemName: isPlatformSupported ? "photo.badge.plus" : "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(VaultTheme.primaryGradient)
                            .shadow(color: VaultTheme.glowPurple, radius: 12)
                        
                        Text(isPlatformSupported ? "Select Photos & Videos" : "Platform Unavailable")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(VaultTheme.textPrimary)
                        
                        Text(isPlatformSupported
                             ? "Photos and videos selected from your device library will be encrypted using your active vault key and stored locally. Original Photos items remain untouched."
                             : "Media import relies on native iOS PhotosUI capabilities. Photos library import is available on iOS device targets.")
                            .font(.system(size: 14))
                            .foregroundColor(VaultTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(20)
                }
                .padding(.horizontal, 24)
                
                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(VaultTheme.secondaryViolet)
                        Text(statusMessage.isEmpty ? "Encrypting and storing media..." : statusMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(VaultTheme.textSecondary)
                    }
                    .padding(.horizontal, 24)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                Spacer()
                
                if isPlatformSupported {
                    #if canImport(PhotosUI)
                    PhotosPicker(
                        selection: $selectedPickerItems,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.fill.on.rectangle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(isProcessing ? "Processing..." : "Open Photos Library")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(VaultTheme.primaryGradient)
                        .cornerRadius(VaultTheme.cornerRadiusMedium)
                        .shadow(color: VaultTheme.glowPurple, radius: 10)
                    }
                    .disabled(isProcessing)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .onChange(of: selectedPickerItems) { newItems in
                        if !newItems.isEmpty {
                            Task {
                                await processSelectedPickerItems(newItems)
                            }
                        }
                    }
                    #endif
                } else {
                    GlassButton(title: "Close", action: { dismiss() })
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
        }
        .onChange(of: vaultManager.session.isAuthenticated) { isAuthenticated in
            if !isAuthenticated {
                dismiss()
            }
        }
    }
    
    #if canImport(PhotosUI)
    private func processSelectedPickerItems(_ items: [PhotosPickerItem]) async {
        guard vaultManager.session.isAuthenticated else {
            errorMessage = "Vault session expired."
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        var importedCount = 0
        var lastError: String? = nil
        
        for (index, item) in items.enumerated() {
            guard vaultManager.session.isAuthenticated else {
                errorMessage = "Import cancelled due to session lock."
                break
            }
            
            statusMessage = "Processing item \(index + 1) of \(items.count)..."
            
            do {
                // Check if video vs photo
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
                    // Video import via FileHandle streaming path
                    if let movieURL = try await item.loadTransferable(type: URL.self) {
                        _ = try await service.importVideoFile(
                            sourceURL: movieURL,
                            originalFilename: "video_\(UUID().uuidString).mp4",
                            vaultManager: vaultManager
                        )
                        importedCount += 1
                    } else {
                        lastError = "Unable to read video source payload."
                    }
                } else {
                    // Photo import via raw bytes
                    if let rawData = try await item.loadTransferable(type: Data.self) {
                        _ = try service.importPhotoBytes(
                            rawImageData: rawData,
                            originalFilename: "photo_\(UUID().uuidString).jpg",
                            vaultManager: vaultManager
                        )
                        importedCount += 1
                    } else {
                        lastError = "Unable to read photo source payload."
                    }
                }
            } catch let err as MediaImportExportError {
                lastError = err.userFacingMessage
            } catch {
                lastError = "Unable to import item."
            }
        }
        
        isProcessing = false
        selectedPickerItems = []
        
        if importedCount > 0 {
            onImportCompleted()
            dismiss()
        } else if let err = lastError {
            errorMessage = err
        }
    }
    #endif
}
