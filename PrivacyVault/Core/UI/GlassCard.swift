import SwiftUI

/// Reusable glassmorphic surface container with translucent background, subtle border, and soft shadow.
public struct GlassCard<Content: View>: View {
    private let content: Content
    private let cornerRadius: CGFloat
    
    public init(cornerRadius: CGFloat = VaultTheme.cornerRadiusMedium, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    public var body: some View {
        content
            .padding()
            .background(VaultTheme.cardBackground)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(VaultTheme.subtleBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
    }
}
