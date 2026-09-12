import SwiftUI

/// Reusable purple-to-violet gradient primary action button for CTAs.
public struct PrimaryGradientButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void
    
    public init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(VaultTheme.primaryGradient)
            .cornerRadius(VaultTheme.cornerRadiusMedium)
            .shadow(color: VaultTheme.primaryPurple.opacity(0.5), radius: 12, x: 0, y: 4)
        }
    }
}
