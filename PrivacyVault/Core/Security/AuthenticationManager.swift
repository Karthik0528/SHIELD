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
    
    /// Count of consecutive failed authentication attempts.
    var failedAttempts: Int { get }
    
    /// Attempts authentication given an input PIN string.
    /// Evaluates candidate PIN against Main and Decoy vault key hierarchies.
    func authenticate(with pin: String) async -> AuthenticationResult
    
    /// Checks if a specific vault has been set up.
    func isVaultSetup(vault: VaultType) -> Bool
    
    /// Executes atomic dual-vault setup for Main and Decoy vaults with optional recovery key.
    func setupDualVaults(mainPin: String, decoyPin: String, recoveryKey: String) throws
    
    /// Authorizes Primary PIN replacement using a valid recovery key.
    func recoverPrimaryPin(recoveryKey: String, newPin: String) async -> AuthenticationResult
    
    /// Re-wraps Primary Vault Master Key with a new recovery key from active session.
    func changeRecoveryKey(newRecoveryKey: String) throws
    
    /// Re-wraps Primary or Secondary Vault Master Key with a new PIN using active key hierarchy.
    func changePin(for vault: VaultType, oldPin: String, newPin: String) throws
    
    /// Resets failed attempt counter manually when needed.
    func resetFailedAttempts()
}

/// Core implementation of authentication routing for Main and Decoy vaults.
public final class DefaultAuthenticationManager: AuthenticationManagerProtocol, @unchecked Sendable {
    private let keyManager: KeyManagerProtocol
    private let keychainPlatform: PlatformKeychainProtocol
    private let lockQueue = DispatchQueue(label: "com.privacyvault.authenticationmanager", attributes: .concurrent)
    private var _failedAttempts: Int = 0
    
    public init(
        keyManager: KeyManagerProtocol,
        keychainPlatform: PlatformKeychainProtocol = DefaultPlatformKeychain()
    ) {
        NSLog("[SHIELD_STARTUP] DefaultAuthenticationManager.init")
        self.keyManager = keyManager
        self.keychainPlatform = keychainPlatform
    }
    
    public var isSetupComplete: Bool {
        return isVaultSetup(vault: .main) && isVaultSetup(vault: .decoy)
    }
    
    public var failedAttempts: Int {
        lockQueue.sync { _failedAttempts }
    }
    
    public func resetFailedAttempts() {
        lockQueue.sync(flags: .barrier) {
            self._failedAttempts = 0
        }
    }
    
    public func authenticate(with pin: String) async -> AuthenticationResult {
        // Attempt Main Vault unlock
        if let mainVMK = try? keyManager.unlockVaultMasterKey(for: .main, pin: pin) {
            resetFailedAttempts()
            return .success(vaultType: .main, masterKey: mainVMK)
        }
        
        // Attempt Decoy Vault unlock
        if let decoyVMK = try? keyManager.unlockVaultMasterKey(for: .decoy, pin: pin) {
            resetFailedAttempts()
            return .success(vaultType: .decoy, masterKey: decoyVMK)
        }
        
        lockQueue.sync(flags: .barrier) {
            self._failedAttempts += 1
        }
        
        return .failure(.invalidCredentials)
    }
    
    public func isVaultSetup(vault: VaultType) -> Bool {
        return keyManager.isVaultSetup(for: vault)
    }
    
    public func setupDualVaults(mainPin: String, decoyPin: String, recoveryKey: String = "") throws {
        let transaction = CredentialSetupTransaction(
            keyManager: keyManager,
            keychainPlatform: keychainPlatform
        )
        try transaction.executeAtomicSetup(mainPin: mainPin, decoyPin: decoyPin, recoveryKey: recoveryKey)
    }
    
    public func recoverPrimaryPin(recoveryKey: String, newPin: String) async -> AuthenticationResult {
        do {
            let vmk = try keyManager.replacePrimaryPinWithRecovery(recoveryKey: recoveryKey, newPin: newPin)
            resetFailedAttempts()
            return .success(vaultType: .main, masterKey: vmk)
        } catch {
            return .failure(.invalidCredentials)
        }
    }
    
    public func changeRecoveryKey(newRecoveryKey: String) throws {
        try keyManager.changeRecoveryKey(newRecoveryKey: newRecoveryKey)
    }
    
    public func changePin(for vault: VaultType, oldPin: String, newPin: String) throws {
        guard oldPin.count == VaultSettings.standardPinLength,
              newPin.count == VaultSettings.standardPinLength else {
            throw AuthenticationError.invalidCredentials
        }
        do {
            try keyManager.rewrapMasterKey(for: vault, oldPin: oldPin, newPin: newPin)
        } catch {
            throw AuthenticationError.invalidCredentials
        }
    }
}
