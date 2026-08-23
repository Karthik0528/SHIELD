import SwiftUI

public struct WelcomeSetupView: View {
    public let onContinue: () -> Void
    
    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundColor(.accentColor)
            
            Text("Welcome to PrivacyVault")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "iphone.radiowaves.left.and.right.slash",
                    title: "100% Local Privacy",
                    description: "Operates completely offline. Your media never leaves this device."
                )
                
                FeatureRow(
                    icon: "key.fill",
                    title: "Dual Vault Protection",
                    description: "Supports a Main Vault and a secondary Decoy Vault, each unlocked with a distinct PIN."
                )
                
                FeatureRow(
                    icon: "lock.doc.fill",
                    title: "Encrypted Storage",
                    description: "Photos and metadata are securely encrypted before being stored on disk."
                )
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
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
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeSetupView(onContinue: {})
}
