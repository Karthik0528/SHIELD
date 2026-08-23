import Foundation

/// Result of an authentication attempt at the lock screen.
public enum AuthenticationResult: Sendable {
    case success(vaultType: VaultType, masterKey: SymmetricKeyMaterial)
    case failure(AuthenticationError)
}

public enum AuthenticationError: Error, Equatable, Sendable {
    case invalidCredentials
    case biometricsNotAvailable
    case biometricsFailed
    case vaultNotInitialized
}

/// Abstract contract for authentication handling.
/// Evaluates user PIN inputs against available vaults without revealing vault presence.
public protocol AuthenticationManagerProtocol: Sendable {
    /// Indicates whether both Main and Decoy vaults have completed setup.
    var isSetupComplete: Bool { get }
    
    /// Attempts authentication given an input PIN string.
    /// Evaluates candidate PIN against Main and Decoy vault key hierarchies.
    func authenticate(with pin: String) async -> AuthenticationResult
    
    /// Checks if a specific vault has been set up.
    func isVaultSetup(vault: VaultType) -> Bool
    
    /// Executes atomic dual-vault setup for Main and Decoy vaults.
    func setupDualVaults(mainPin: String, decoyPin: String) throws
}

/// Core implementation of authentication routing for Main and Decoy vaults.
public final class DefaultAuthenticationManager: AuthenticationManagerProtocol {
    private let keyManager: KeyManagerProtocol
    private let keychainPlatform: PlatformKeychainProtocol
    
    public init(
        keyManager: KeyManagerProtocol,
        keychainPlatform: PlatformKeychainProtocol = DefaultPlatformKeychain()
    ) {
        self.keyManager = keyManager
        self.keychainPlatform = keychainPlatform
    }
    
    public var isSetupComplete: Bool {
        return isVaultSetup(vault: .main) && isVaultSetup(vault: .decoy)
    }
    
    public func authenticate(with pin: String) async -> AuthenticationResult {
        // Attempt Main Vault unlock
        if let mainVMK = try? keyManager.unlockVaultMasterKey(for: .main, pin: pin) {
            return .success(vaultType: .main, masterKey: mainVMK)
        }
        
        // Attempt Decoy Vault unlock
        if let decoyVMK = try? keyManager.unlockVaultMasterKey(for: .decoy, pin: pin) {
            return .success(vaultType: .decoy, masterKey: decoyVMK)
        }
        
        return .failure(.invalidCredentials)
    }
    
    public func isVaultSetup(vault: VaultType) -> Bool {
        return keyManager.isVaultSetup(for: vault)
    }
    
    public func setupDualVaults(mainPin: String, decoyPin: String) throws {
        let transaction = CredentialSetupTransaction(
            keyManager: keyManager,
            keychainPlatform: keychainPlatform
        )
        try transaction.executeAtomicSetup(mainPin: mainPin, decoyPin: decoyPin)
    }
}
