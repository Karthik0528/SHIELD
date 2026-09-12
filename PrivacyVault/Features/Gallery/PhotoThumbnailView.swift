import SwiftUI

/// Async thumbnail view component.
/// Retrieves encrypted thumbnail binary container, AES-GCM decrypts in memory using active VMK,
/// renders the thumbnail image, and releases memory references when hidden.
public struct PhotoThumbnailView: View {
    public let item: MediaItem
    public let vault: VaultType
    public let masterKey: SymmetricKeyMaterial?
    public let isSelected: Bool
    public let isSelectionMode: Bool
    public let onTap: () -> Void
    
    @State private var thumbnailImage: Image? = nil
    @State private var isLoading: Bool = true
    
    public init(
        item: MediaItem,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial?,
        isSelected: Bool,
        isSelectionMode: Bool,
        onTap: @escaping () -> Void
    ) {
        self.item = item
        self.vault = vault
        self.masterKey = masterKey
        self.isSelected = isSelected
        self.isSelectionMode = isSelectionMode
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: onTap) {
            ZStack {
                Rectangle()
                    .fill(VaultTheme.cardBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(VaultTheme.cornerRadiusSmall)
                    .overlay(
                        RoundedRectangle(cornerRadius: VaultTheme.cornerRadiusSmall)
                            .stroke(isSelected ? VaultTheme.secondaryViolet : VaultTheme.subtleBorder, lineWidth: isSelected ? 2 : 1)
                    )
                
                if let image = thumbnailImage {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                        .cornerRadius(VaultTheme.cornerRadiusSmall)
                } else if isLoading {
                    ProgressView()
                        .tint(VaultTheme.secondaryViolet)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundColor(VaultTheme.textMuted)
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
        
        let engine = EncryptedMediaStorageEngine()
        do {
            let decryptedBytes = try engine.loadThumbnail(for: item, vault: vault, masterKey: key)
            #if canImport(UIKit)
            if let uiImg = UIImage(data: decryptedBytes) {
                thumbnailImage = Image(uiImage: uiImg)
            } else {
                thumbnailImage = Image(systemName: "photo.fill")
            }
            #else
            thumbnailImage = Image(systemName: "photo.fill")
            #endif
        } catch {
            thumbnailImage = nil
        }
        isLoading = false
    }
}
