import SwiftUI

/// Centralized design system tokens for PrivacyVault.
/// Establishes the locked dark navy/black base and deep purple/violet glassmorphism visual language.
public enum VaultTheme {
    // MARK: - Color Palette
    public static let backgroundBase = Color(hex: "07080E")
    public static let backgroundSecondary = Color(hex: "0B0D17")
    public static let cardBackground = Color(hex: "121526").opacity(0.65)
    public static let glassSurface = Color.white.opacity(0.06)
    
    // Accents & Gradients
    public static let primaryPurple = Color(hex: "7C3AED")
    public static let secondaryViolet = Color(hex: "8B5CF6")
    public static let glowPurple = Color(hex: "A855F7").opacity(0.35)
    public static let subtleBorder = Color.white.opacity(0.12)
    public static let activeBorder = Color(hex: "8B5CF6").opacity(0.6)
    
    // Text Colors
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.7)
    public static let textMuted = Color.white.opacity(0.45)
    
    // Primary Button Gradient
    public static let primaryGradient = LinearGradient(
        colors: [Color(hex: "7C3AED"), Color(hex: "8B5CF6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let glassGradient = LinearGradient(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // MARK: - Layout Tokens
    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 16
    public static let cornerRadiusLarge: CGFloat = 24
}

// MARK: - Color Hex Extension Helper
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xff0000) >> 16) / 255
            let g = Double((hexNumber & 0x00ff00) >> 8) / 255
            let b = Double(hexNumber & 0x0000ff) / 255
            self.init(red: r, green: g, blue: b)
            return
        }
        self.init(red: 0, green: 0, blue: 0)
    }
}
