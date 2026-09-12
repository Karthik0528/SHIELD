import SwiftUI

/// Reusable dark atmospheric background view for PrivacyVault screens.
public struct VaultBackground: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            VaultTheme.backgroundBase
                .ignoresSafeArea()
            
            // Atmospheric Radial Purple Glow
            RadialGradient(
                colors: [VaultTheme.glowPurple, Color.clear],
                center: .top,
                startRadius: 50,
                endRadius: 500
            )
            .ignoresSafeArea()
            .opacity(0.8)
            
            RadialGradient(
                colors: [VaultTheme.primaryPurple.opacity(0.15), Color.clear],
                center: .bottomTrailing,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()
        }
    }
}
