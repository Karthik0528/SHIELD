import SwiftUI

/// Deterministic loading view displayed while VaultManager evaluates disk & Keychain startup state.
public struct VaultLoadingView: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(VaultTheme.primaryGradient)
                    .shadow(color: VaultTheme.glowPurple, radius: 16)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: VaultTheme.secondaryViolet))
                    .scaleEffect(1.2)
            }
        }
    }
}
