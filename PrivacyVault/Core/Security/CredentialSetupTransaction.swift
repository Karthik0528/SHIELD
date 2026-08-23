import Foundation

public enum SetupTransactionError: Error, Equatable, Sendable {
    case invalidPinLength
    case identicalPins
    case setupFailed
}

/// Transactional setup coordinator for atomic dual-vault credential setup.
public final class CredentialSetupTransaction: Sendable {
    private let keyManager: KeyManagerProtocol
    private let keychainPlatform: PlatformKeychainProtocol
    
    public init(
        keyManager: KeyManagerProtocol,
        keychainPlatform: PlatformKeychainProtocol
    ) {
        self.keyManager = keyManager
        self.keychainPlatform = keychainPlatform
    }
    
    /// Executes atomic setup for both Main and Decoy vaults.
    /// If an error occurs during Decoy PIN setup, any stored Main vault credentials are automatically rolled back.
    public func executeAtomicSetup(mainPin: String, decoyPin: String) throws {
        // Validate PIN policy
        guard mainPin.count >= 4, decoyPin.count >= 4 else {
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
            
            keyManager.purgeKeyMaterial(for: .main)
            keyManager.purgeKeyMaterial(for: .decoy)
        }
        
        do {
            // Provision Main Vault
            _ = try keyManager.setupVaultKeys(for: .main, pin: mainPin)
            
            // Provision Decoy Vault
            _ = try keyManager.setupVaultKeys(for: .decoy, pin: decoyPin)
        } catch {
            rollback()
            throw SetupTransactionError.setupFailed
        }
    }
}
