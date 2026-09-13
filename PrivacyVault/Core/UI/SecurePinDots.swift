import SwiftUI

/// Animated PIN dot indicator component used in LockScreenView and setup screens.
public struct SecurePinDots: View {
    private let count: Int
    private let maxCount: Int
    
    public init(count: Int, maxCount: Int = VaultSettings.standardPinLength) {
        self.count = count
        self.maxCount = maxCount
    }
    
    public var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<maxCount, id: \.self) { index in
                Circle()
                    .fill(index < count ? VaultTheme.secondaryViolet : Color.white.opacity(0.15))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(index < count ? VaultTheme.secondaryViolet : Color.white.opacity(0.3), lineWidth: 1.5)
                    )
                    .shadow(color: index < count ? VaultTheme.glowPurple : Color.clear, radius: 8, x: 0, y: 0)
                    .scaleEffect(index < count ? 1.15 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: count)
            }
        }
    }
}
