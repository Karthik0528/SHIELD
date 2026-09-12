import SwiftUI

/// Empty state component displayed when the authenticated vault contains no media items.
public struct EmptyVaultView: View {
    public let onAddPhotos: () -> Void
    
    public init(onAddPhotos: @escaping () -> Void) {
        self.onAddPhotos = onAddPhotos
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 56))
                        .foregroundStyle(VaultTheme.primaryGradient)
                        .shadow(color: VaultTheme.glowPurple, radius: 12)
                    
                    Text("Your Vault is Empty")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Text("Add your photos to keep them encrypted and protected on this device.")
                        .font(.system(size: 14))
                        .foregroundColor(VaultTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    
                    PrimaryGradientButton(title: "Add Photos", systemImage: "plus") {
                        onAddPhotos()
                    }
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
}
