import SwiftUI

/// Safe Security Error screen shown when existing encrypted vault data is detected on disk,
/// but required cryptographic key material in Keychain is missing or inconsistent.
/// Fails closed to protect existing ciphertext from being overwritten by fresh setup keys.
public struct VaultIntegrityErrorView: View {
    public let reason: String
    public let onRetry: () -> Void
    
    public init(reason: String, onRetry: @escaping () -> Void = {}) {
        self.reason = reason
        self.onRetry = onRetry
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 28) {
                Spacer()
                
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Color.red)
                    .shadow(color: Color.red.opacity(0.5), radius: 16)
                
                VStack(spacing: 12) {
                    Text("Vault Security Alert")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Text("Existing Encrypted Vault Detected")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(VaultTheme.secondaryViolet)
                }
                
                GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.slash.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color.red)
                            Text("Protection Active")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(VaultTheme.textPrimary)
                        }
                        
                        Text(reason)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(VaultTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Re-evaluate Security State")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(VaultTheme.glassSurface)
                    .clipShape(RoundedRectangle(cornerRadius: VaultTheme.cornerRadiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: VaultTheme.cornerRadiusMedium)
                            .stroke(VaultTheme.subtleBorder, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
