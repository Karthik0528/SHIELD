import Foundation

public enum SetupTransactionError: Error, Equatable, Sendable {
    case invalidPinLength
    case identicalPins
    case setupFailed
    case vaultAlreadyInitialized
}

/// Transactional setup coordinator for atomic dual-vault credential setup.
public final class CredentialSetupTransaction: Sendable {
    private let keyManager: KeyManagerProtocol
    private let keychainPlatform: PlatformKeychainProtocol
    
    private let storage: VaultStorageProtocol
    
    public init(
        keyManager: KeyManagerProtocol,
        keychainPlatform: PlatformKeychainProtocol,
        storage: VaultStorageProtocol = VaultStorage()
    ) {
        self.keyManager = keyManager
        self.keychainPlatform = keychainPlatform
        self.storage = storage
    }
    
    /// Executes atomic setup for both Main and Decoy vaults, including recovery key wrapping.
    /// If an error occurs, any stored credentials are automatically rolled back.
    public func executeAtomicSetup(mainPin: String, decoyPin: String, recoveryKey: String = "") throws {
        // Refuse re-initialization if existing vault credential state OR disk media data is present
        if keyManager.isVaultSetup(for: .main) || keyManager.isVaultSetup(for: .decoy) || storage.hasDiskVaultData(for: .main) || storage.hasDiskVaultData(for: .decoy) {
            throw SetupTransactionError.vaultAlreadyInitialized
        }
        
        // Validate PIN policy
        guard mainPin.count == VaultSettings.standardPinLength, decoyPin.count == VaultSettings.standardPinLength else {
            throw SetupTransactionError.invalidPinLength
        }
        guard mainPin != decoyPin else {
            throw SetupTransactionError.identicalPins
        }
        
        // Rollback handler
        func rollback() {
            try? keychainPlatform.delete(forKey: "Salt_main")
            try? keychainPlatform.delete(forKey: "WrappedVMK_main")
            try? keychainPlatform.delete(forKey: "WrappedVMKNonce_main")
            try? keychainPlatform.delete(forKey: "WrappedVMKTag_main")
            
            try? keychainPlatform.delete(forKey: "Salt_decoy")
            try? keychainPlatform.delete(forKey: "WrappedVMK_decoy")
            try? keychainPlatform.delete(forKey: "WrappedVMKNonce_decoy")
            try? keychainPlatform.delete(forKey: "WrappedVMKTag_decoy")
            
            try? keychainPlatform.delete(forKey: "Salt_recovery")
            try? keychainPlatform.delete(forKey: "WrappedVMK_recovery")
            try? keychainPlatform.delete(forKey: "WrappedVMKNonce_recovery")
            try? keychainPlatform.delete(forKey: "WrappedVMKTag_recovery")
            
            try? keychainPlatform.delete(forKey: "WrappedVMK_switch")
            try? keychainPlatform.delete(forKey: "WrappedVMKNonce_switch")
            try? keychainPlatform.delete(forKey: "WrappedVMKTag_switch")
            
            keyManager.purgeKeyMaterial(for: .main)
            keyManager.purgeKeyMaterial(for: .decoy)
        }
        
        do {
            // Provision Main Vault
            _ = try keyManager.setupVaultKeys(for: .main, pin: mainPin)
            guard let mainVMK = keyManager.getActiveMasterKey(for: .main) else {
                throw SetupTransactionError.setupFailed
            }
            
            // Provision Recovery Key wrapping for Main VMK if provided
            if !recoveryKey.isEmpty {
                try keyManager.setupRecoveryKey(for: mainVMK, recoveryKey: recoveryKey)
            }
            
            // Provision Decoy Vault
            _ = try keyManager.setupVaultKeys(for: .decoy, pin: decoyPin)
            guard let decoyVMK = keyManager.getActiveMasterKey(for: .decoy) else {
                throw SetupTransactionError.setupFailed
            }
            
            // Provision Emergency Switch wrapping (Decoy VMK encrypted under Main VMK)
            try keyManager.setupSwitchKey(primaryVMK: mainVMK, decoyVMK: decoyVMK)
        } catch {
            rollback()
            throw SetupTransactionError.setupFailed
        }
    }
}
