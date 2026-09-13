import SwiftUI

/// Async thumbnail view component.
/// Retrieves encrypted thumbnail binary container, AES-GCM decrypts in memory using active VMK,
/// renders the thumbnail image, and releases memory references when hidden.
public struct PhotoThumbnailView: View {
    public let item: MediaItem
    public let vault: VaultType
    public let masterKey: SymmetricKeyMaterial?
    public let storage: VaultStorageProtocol
    public let isSelected: Bool
    public let isSelectionMode: Bool
    public let onTap: () -> Void
    
    @State private var thumbnailImage: Image? = nil
    @State private var isLoading: Bool = true
    
    public init(
        item: MediaItem,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial?,
        storage: VaultStorageProtocol = VaultStorage(),
        isSelected: Bool,
        isSelectionMode: Bool,
        onTap: @escaping () -> Void
    ) {
        self.item = item
        self.vault = vault
        self.masterKey = masterKey
        self.storage = storage
        self.isSelected = isSelected
        self.isSelectionMode = isSelectionMode
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: onTap) {
            ZStack {
                Rectangle()
                    .fill(isSelected ? VaultTheme.secondaryViolet.opacity(0.2) : VaultTheme.cardBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(VaultTheme.cornerRadiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: VaultTheme.cornerRadiusMedium)
                            .stroke(
                                isSelected ? VaultTheme.accentViolet : VaultTheme.subtleBorder,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isSelected ? VaultTheme.accentViolet.opacity(0.5) : Color.clear,
                        radius: isSelected ? 6 : 0
                    )
                
                if let image = thumbnailImage {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                        .cornerRadius(VaultTheme.cornerRadiusMedium)
                } else if isLoading {
                    ProgressView()
                        .tint(VaultTheme.secondaryViolet)
                } else {
                    Image(systemName: item.mediaType == .video ? "video.fill" : "photo")
                        .font(.system(size: 20))
                        .foregroundColor(VaultTheme.textMuted)
                }
                
                // Video Play Badge Indicator
                if item.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Circle())
                                .padding(4)
                        }
                    }
                }
                
                if isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(isSelected ? VaultTheme.secondaryViolet : Color.white.opacity(0.6))
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
        }
        .scaleEffect(isSelected && !isSelectionMode ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .task {
            await loadThumbnail()
        }
        .onDisappear {
            thumbnailImage = nil
        }
    }
    
    private func loadThumbnail() async {
        guard let key = masterKey else {
            isLoading = false
            return
        }
        
        let engine = EncryptedMediaStorageEngine(storage: storage)
        var loadedSuccess = false
        
        do {
            let decryptedBytes = try engine.loadThumbnail(for: item, vault: vault, masterKey: key)
            #if canImport(UIKit)
            if let uiImg = UIImage(data: decryptedBytes) {
                thumbnailImage = Image(uiImage: uiImg)
                loadedSuccess = true
            }
            #endif
        } catch {}
        
        if !loadedSuccess {
            thumbnailImage = nil
        }
        isLoading = false
    }
}
