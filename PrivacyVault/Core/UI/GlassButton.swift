import SwiftUI

/// Reusable glassmorphic button component for secondary actions and toolbars.
public struct GlassButton: View {
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
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(VaultTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(VaultTheme.glassSurface)
            .cornerRadius(VaultTheme.cornerRadiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: VaultTheme.cornerRadiusMedium)
                    .stroke(VaultTheme.subtleBorder, lineWidth: 1)
            )
        }
    }
}
