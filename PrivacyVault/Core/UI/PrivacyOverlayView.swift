import SwiftUI

/// Privacy blur overlay view displayed when the app moves to background or becomes inactive.
/// Prevents sensitive vault contents from appearing in the iOS app switcher snapshot.
public struct PrivacyOverlayView: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(VaultTheme.primaryGradient)
                        .shadow(color: VaultTheme.glowPurple, radius: 12)
                    
                    Text("SHIELD Protected")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Text("Vault contents are secured.")
                        .font(.system(size: 14))
                        .foregroundColor(VaultTheme.textSecondary)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 32)
        }
    }
}
