import Foundation

/// Auto-lock timeout choices.
public enum AutoLockTimeout: Int, Codable, Sendable {
    case immediately = 0
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case never = -1
}

/// Settings configuration bound to a specific vault domain instance.
public struct VaultSettings: Codable, Sendable {
    /// Authoritative PIN length required for setup, confirmation, and unlock UI.
    public static let standardPinLength: Int = 4
    
    public let vaultType: VaultType
    public var autoLockTimeout: AutoLockTimeout
    public var isBiometricEnabled: Bool
    public var isConfigured: Bool
    
    public init(
        vaultType: VaultType,
        autoLockTimeout: AutoLockTimeout = .thirtySeconds,
        isBiometricEnabled: Bool = false,
        isConfigured: Bool = false
    ) {
        self.vaultType = vaultType
        self.autoLockTimeout = autoLockTimeout
        self.isBiometricEnabled = isBiometricEnabled
        self.isConfigured = isConfigured
    }
}

