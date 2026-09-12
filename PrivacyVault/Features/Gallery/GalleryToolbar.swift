import SwiftUI

/// Glass header toolbar for the Gallery screen.
/// Contains title, Add Photos, Select, Export, Delete, and Lock actions.
public struct GalleryToolbar: View {
    public let isSelectionMode: Bool
    public let selectedCount: Int
    public let onAddPhotos: () -> Void
    public let onToggleSelection: () -> Void
    public let onDeleteSelected: () -> Void
    public let onExportSelected: () -> Void
    public let onLock: () -> Void
    
    public init(
        isSelectionMode: Bool,
        selectedCount: Int,
        onAddPhotos: @escaping () -> Void,
        onToggleSelection: @escaping () -> Void,
        onDeleteSelected: @escaping () -> Void,
        onExportSelected: @escaping () -> Void,
        onLock: @escaping () -> Void
    ) {
        self.isSelectionMode = isSelectionMode
        self.selectedCount = selectedCount
        self.onAddPhotos = onAddPhotos
        self.onToggleSelection = onToggleSelection
        self.onDeleteSelected = onDeleteSelected
        self.onExportSelected = onExportSelected
        self.onLock = onLock
    }
    
    public var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(VaultTheme.primaryGradient)
                
                Text(isSelectionMode ? "\(selectedCount) Selected" : "Privacy Vault")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(VaultTheme.textPrimary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                if isSelectionMode {
                    if selectedCount > 0 {
                        Button(action: onExportSelected) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(VaultTheme.secondaryViolet)
                                .padding(8)
                                .background(VaultTheme.glassSurface)
                                .clipShape(Circle())
                        }
                        
                        Button(action: onDeleteSelected) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.red.opacity(0.9))
                                .padding(8)
                                .background(VaultTheme.glassSurface)
                                .clipShape(Circle())
                        }
                    }
                    
                    GlassButton(title: "Done", action: onToggleSelection)
                } else {
                    Button(action: onAddPhotos) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(VaultTheme.primaryGradient)
                            .clipShape(Circle())
                            .shadow(color: VaultTheme.glowPurple, radius: 8)
                    }
                    
                    GlassButton(title: "Select", action: onToggleSelection)
                    
                    Button(action: onLock) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(VaultTheme.textSecondary)
                            .padding(10)
                            .background(VaultTheme.glassSurface)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(VaultTheme.subtleBorder, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(VaultTheme.cardBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(VaultTheme.subtleBorder),
            alignment: .bottom
        )
    }
}
