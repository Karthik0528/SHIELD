import Foundation
import Combine

public enum VaultStartupState: Equatable, Sendable {
    case loading
    case uninitialized
    case ready
    case vaultIntegrityError(reason: String)
}

/// Central coordinator managing session lifecycle, dual-vault authentication dispatch, and isolated vault storage.
public final class VaultManager: ObservableObject, @unchecked Sendable {
    public let session: SecureSessionProtocol
    public let authenticationManager: AuthenticationManagerProtocol
    public let keyManager: KeyManagerProtocol
    public let storage: VaultStorageProtocol
    
    @Published public private(set) var startupState: VaultStartupState = .loading
    
    public init(
        session: SecureSessionProtocol = SecureSession(),
        keyManager: KeyManagerProtocol? = nil,
        authenticationManager: AuthenticationManagerProtocol? = nil,
        storage: VaultStorageProtocol? = nil,
        fileManager: FileManager = .default,
        baseURL: URL? = nil
    ) {
        shieldLog("[SHIELD_STARTUP] VaultManager init BEGIN")
        let cryptoPlatform = DefaultPlatformCrypto()
        let keychainPlatform = DefaultPlatformKeychain()
        
        let km = keyManager ?? DefaultKeyManager(cryptoPlatform: cryptoPlatform, keychainPlatform: keychainPlatform)
        shieldLog("[SHIELD_STARTUP] KeyManager init complete")
        
        let am = authenticationManager ?? DefaultAuthenticationManager(keyManager: km, keychainPlatform: keychainPlatform)
        shieldLog("[SHIELD_STARTUP] AuthenticationManager init complete")
        
        let st = storage ?? VaultStorage(fileManager: fileManager, baseURL: baseURL)
        shieldLog("[SHIELD_STARTUP] Storage init complete")
        
        self.session = session
        self.keyManager = km
        self.authenticationManager = am
        self.storage = st
        
        shieldLog("[SHIELD_STARTUP] VaultManager init END")
        evaluateStartupState()
    }
    
    /// Evaluates Keychain setup against disk storage state to determine deterministic startup state.
    public func evaluateStartupState() {
        shieldLog("[SHIELD_STARTUP] Startup evaluation BEGIN")
        let mainKeySetup = keyManager.isVaultSetup(for: .main)
        let decoyKeySetup = keyManager.isVaultSetup(for: .decoy)
        let isKeysComplete = mainKeySetup && decoyKeySetup
        shieldLog("[SHIELD_STARTUP] Keychain state checked: mainKeySetup=\(mainKeySetup), decoyKeySetup=\(decoyKeySetup), complete=\(isKeysComplete)")
        
        let mainDiskData = storage.hasDiskVaultData(for: .main)
        let decoyDiskData = storage.hasDiskVaultData(for: .decoy)
        let hasAnyDiskData = mainDiskData || decoyDiskData
        shieldLog("[SHIELD_STARTUP] Disk state checked: mainDiskData=\(mainDiskData), decoyDiskData=\(decoyDiskData), hasAnyDiskData=\(hasAnyDiskData)")
        
        let newState: VaultStartupState
        if isKeysComplete {
            newState = .ready
        } else if hasAnyDiskData || mainKeySetup || decoyKeySetup {
            newState = .vaultIntegrityError(
                reason: "Existing encrypted vault data or partial key state was detected on this device, but required cryptographic credentials in Keychain are missing or incomplete. SHIELD has locked down to prevent overwriting existing encrypted media."
            )
        } else {
            newState = .uninitialized
        }
        
        shieldLog("[SHIELD_STARTUP] Startup evaluation END: \(newState)")
        
        self.startupState = newState
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Setup
    /// Configures initial PIN credentials for either Main Vault or Decoy Vault.
    public func setupVault(type: VaultType, pin: String) throws {
        try storage.initializeDirectories(for: type)
        _ = try keyManager.setupVaultKeys(for: type, pin: pin)
    }
    
    // MARK: - Unlock / Lock
    /// Attempts unlock with provided PIN. Routes to Main or Decoy vault transparently based on key hierarchy.
    public func unlock(with pin: String) async -> AuthenticationResult {
        let result = await authenticationManager.authenticate(with: pin)
        switch result {
        case let .success(vaultType, masterKey):
            try? storage.initializeDirectories(for: vaultType)
            session.startSession(for: vaultType, masterKey: masterKey)
            await MainActor.run {
                NSLog("[SHIELD_LOG] Credential verification succeeded, session established for vault")
                self.objectWillChange.send()
            }
        case .failure:
            await MainActor.run {
                NSLog("[SHIELD_LOG] Credential verification failed")
            }
        }
        return result
    }
    
    /// Locks the active session and purges key material from memory.
    public func lock() {
        if let activeVault = session.activeVaultType {
            keyManager.purgeKeyMaterial(for: activeVault)
        }
        session.lock()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
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
    
    // MARK: - Recovery
    /// Recovers Primary PIN using Recovery Key and starts session upon success.
    public func recoverPrimaryPin(recoveryKey: String, newPin: String) async -> AuthenticationResult {
        let result = await authenticationManager.recoverPrimaryPin(recoveryKey: recoveryKey, newPin: newPin)
        switch result {
        case let .success(vaultType, masterKey):
            try? storage.initializeDirectories(for: vaultType)
            session.startSession(for: vaultType, masterKey: masterKey)
            await MainActor.run {
                self.objectWillChange.send()
            }
        case .failure:
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
        return result
    }
    
    /// Re-wraps active Primary Vault Master Key with a new recovery key.
    public func changeRecoveryKey(newRecoveryKey: String) throws {
        try authenticationManager.changeRecoveryKey(newRecoveryKey: newRecoveryKey)
    }
    
    /// Re-wraps specified vault master key with a new 4-digit PIN using active key hierarchy.
    public func changePin(for vault: VaultType, oldPin: String, newPin: String) throws {
        try authenticationManager.changePin(for: vault, oldPin: oldPin, newPin: newPin)
    }
    
    // MARK: - Emergency Switch
    /// Immediately transitions from Primary Vault to Secondary Vault without requesting Secondary PIN.
    /// Performs an authenticated session transition using Primary VMK to unwrap Secondary VMK.
    @MainActor
    @discardableResult
    public func switchToSecondaryVault() -> Bool {
        shieldLog("[SHIELD_SWITCH] Button tapped")
        shieldLog("[SHIELD_SWITCH] switchToSecondaryVault BEGIN")
        let primarySessionPresent = (session.activeVaultType == .main) && (session.activeMasterKey != nil)
        shieldLog("[SHIELD_SWITCH] Primary session present = \(primarySessionPresent)")
        
        guard session.activeVaultType == .main,
              let primaryVMK = session.activeMasterKey else {
            shieldLog("[SHIELD_SWITCH] Primary session missing, aborting switch")
            shieldLog("[SHIELD_SWITCH] switchToSecondaryVault END")
            return false
        }
        
        do {
            let decoyVMK = try keyManager.unlockDecoyMasterKeyWithSwitch(primaryVMK: primaryVMK)
            shieldLog("[SHIELD_SWITCH] VMK_decoy unwrap = success")
            try? storage.initializeDirectories(for: .decoy)
            
            // Atomically invalidate Primary key material and start Secondary session
            keyManager.purgeKeyMaterial(for: .main)
            session.lock()
            shieldLog("[SHIELD_SWITCH] Primary session invalidated")
            
            session.startSession(for: .decoy, masterKey: decoyVMK)
            shieldLog("[SHIELD_SWITCH] Secondary session started")
            shieldLog("[SHIELD_SWITCH] activeVaultType = \(session.activeVaultType?.rawValue ?? "nil")")
            
            shieldLog("[SHIELD_SWITCH] switchToSecondaryVault END")
            self.objectWillChange.send()
            return true
        } catch {
            shieldLog("[SHIELD_SWITCH] VMK_decoy unwrap = failure: \(error)")
            shieldLog("[SHIELD_SWITCH] switchToSecondaryVault END")
            return false
        }
    }
}
