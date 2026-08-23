import Foundation

/// Central coordinator managing session lifecycle, dual-vault authentication dispatch, and isolated vault storage.
public final class VaultManager: @unchecked Sendable {
    public let session: SecureSessionProtocol
    public let authenticationManager: AuthenticationManagerProtocol
    public let keyManager: KeyManagerProtocol
    public let storage: VaultStorageProtocol
    
    public init(
        session: SecureSessionProtocol = SecureSession(),
        keyManager: KeyManagerProtocol? = nil,
        authenticationManager: AuthenticationManagerProtocol? = nil,
        storage: VaultStorageProtocol = VaultStorage()
    ) {
        let cryptoPlatform = DefaultPlatformCrypto()
        let keychainPlatform = DefaultPlatformKeychain()
        
        let km = keyManager ?? DefaultKeyManager(cryptoPlatform: cryptoPlatform, keychainPlatform: keychainPlatform)
        let am = authenticationManager ?? DefaultAuthenticationManager(keyManager: km)
        
        self.session = session
        self.keyManager = km
        self.authenticationManager = am
        self.storage = storage
    }
    
    // MARK: - Setup
    /// Configures initial PIN credentials for either Main Vault or Decoy Vault.
    public func setupVault(type: VaultType, pin: String) throws {
        try storage.initializeDirectories(for: type)
        try authenticationManager.setupCredentials(for: type, pin: pin)
    }
    
    // MARK: - Unlock / Lock
    /// Attempts unlock with provided PIN. Routes to Main or Decoy vault transparently based on key hierarchy.
    public func unlock(with pin: String) async -> AuthenticationResult {
        let result = await authenticationManager.authenticate(with: pin)
        switch result {
        case let .success(vaultType, masterKey):
            try? storage.initializeDirectories(for: vaultType)
            session.startSession(for: vaultType, masterKey: masterKey)
        case .failure:
            break
        }
        return result
    }
    
    /// Locks the active session and purges key material from memory.
    public func lock() {
        if let activeVault = session.activeVaultType {
            keyManager.purgeKeyMaterial(for: activeVault)
        }
        session.lock()
    }
    
    /// Evaluates auto-lock timer against active vault settings.
    public func checkAutoLock() {
        guard let activeVault = session.activeVaultType else { return }
        if let settings = try? storage.database.fetchSettings(for: activeVault) {
            if session.checkAutoLock(timeout: settings.autoLockTimeout) {
                lock()
            }
        }
    }
}
