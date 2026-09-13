import SwiftUI

public struct WelcomeSetupView: View {
    public let onContinue: () -> Void
    
    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 32) {
                Spacer()
                
                Image(systemName: "shield.checkered")
                    .font(.system(size: 64))
                    .foregroundStyle(VaultTheme.primaryGradient)
                    .shadow(color: VaultTheme.glowPurple, radius: 16)
                
                VStack(spacing: 8) {
                    Text("SHIELD")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Text("Your private media stays protected on this device.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(VaultTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureRow(
                            icon: "iphone.radiowaves.left.and.right.slash",
                            title: "100% Local Privacy",
                            description: "Operates offline. Your media never leaves this device."
                        )
                        
                        FeatureRow(
                            icon: "lock.doc.fill",
                            title: "Encrypted Storage",
                            description: "Photos and thumbnails are encrypted before persistence."
                        )
                        
                        FeatureRow(
                            icon: "key.fill",
                            title: "Dual Vault Protection",
                            description: "Supports a Primary Vault and a secondary Decoy Vault."
                        )
                    }
                    .padding(8)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                PrimaryGradientButton(title: "Get Started", systemImage: "arrow.right") {
                    onContinue()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(VaultTheme.secondaryViolet)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VaultTheme.textPrimary)
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(VaultTheme.textSecondary)
            }
        }
    }
}
