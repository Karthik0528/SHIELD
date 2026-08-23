import Foundation

/// Defines Key Derivation Function (KDF) parameters.
public struct KDFParameters: Sendable {
    public let salt: Data
    public let iterations: Int
    
    public init(salt: Data, iterations: Int = 100_000) {
        self.salt = salt
        self.iterations = iterations
    }
}

/// Abstract contract for managing the key hierarchy across Main and Decoy vaults.
/// Key Hierarchy:
///   User PIN -> KDF (with Salt) -> Key Encryption Key (KEK) -> Unwraps Vault Master Key (VMK) -> Unwraps Per-Media Keys
public protocol KeyManagerProtocol: Sendable {
    /// Checks if credential metadata (salt) exists for a vault domain.
    func isVaultSetup(for vault: VaultType) -> Bool
    
    /// Derives a Key Encryption Key (KEK) from a PIN and KDF parameters.
    func deriveKEK(from pin: String, parameters: KDFParameters) throws -> SymmetricKeyMaterial
    
    /// Provisions initial Vault Master Key (VMK) and KEK wrapping for a newly setup vault domain.
    func setupVaultKeys(for vault: VaultType, pin: String) throws -> KDFParameters
    
    /// Unwraps and loads the Vault Master Key (VMK) into memory for an authenticated session.
    func unlockVaultMasterKey(for vault: VaultType, pin: String) throws -> SymmetricKeyMaterial
    
    /// Returns cached in-memory Vault Master Key if vault is unlocked.
    func getActiveMasterKey(for vault: VaultType) -> SymmetricKeyMaterial?
    
    /// Re-wraps the existing Vault Master Key with a new KEK derived from a new PIN.
    /// Enables PIN changes without decrypting or re-encrypting media payloads.
    func rewrapMasterKey(for vault: VaultType, oldPin: String, newPin: String) throws
    
    /// Clears any cached in-memory key material for a given vault domain when locked.
    /// Does NOT delete persistent wrapped keys from Keychain storage.
    func purgeKeyMaterial(for vault: VaultType)
}

public enum KeyManagerError: Error, Equatable, Sendable {
    case invalidPIN
    case vaultNotConfigured
    case keyDerivationFailed
    case keychainAccessError
    case missingSalt
}

/// Core implementation of KeyManager.
public final class DefaultKeyManager: KeyManagerProtocol, @unchecked Sendable {
    private let cryptoPlatform: PlatformCryptoProtocol
    private let keychainPlatform: PlatformKeychainProtocol
    private let queue = DispatchQueue(label: "com.privacyvault.keymanager", attributes: .concurrent)
    
    private var cachedMasterKeys: [VaultType: SymmetricKeyMaterial] = [:]
    
    public init(
        cryptoPlatform: PlatformCryptoProtocol,
        keychainPlatform: PlatformKeychainProtocol
    ) {
        self.cryptoPlatform = cryptoPlatform
        self.keychainPlatform = keychainPlatform
    }
    
    public func isVaultSetup(for vault: VaultType) -> Bool {
        guard let saltData = try? keychainPlatform.load(forKey: "Salt_\(vault.rawValue)") else {
            return false
        }
        return !saltData.isEmpty
    }
    
    public func deriveKEK(from pin: String, parameters: KDFParameters) throws -> SymmetricKeyMaterial {
        return try cryptoPlatform.deriveKey(passcode: pin, salt: parameters.salt, iterations: parameters.iterations)
    }
    
    public func setupVaultKeys(for vault: VaultType, pin: String) throws -> KDFParameters {
        let salt = try cryptoPlatform.generateSalt()
        let parameters = KDFParameters(salt: salt)
        let kek = try deriveKEK(from: pin, parameters: parameters)
        
        let vmk = try cryptoPlatform.generateRandomKey()
        let wrappedVMK = try cryptoPlatform.encrypt(data: vmk.rawBytes, using: kek)
        
        // Save salt and wrapped VMK payload securely in Keychain per vault instance
        try keychainPlatform.save(data: parameters.salt, forKey: "Salt_\(vault.rawValue)")
        try keychainPlatform.save(data: wrappedVMK.ciphertext, forKey: "WrappedVMK_\(vault.rawValue)")
        try keychainPlatform.save(data: wrappedVMK.nonce, forKey: "WrappedVMKNonce_\(vault.rawValue)")
        try keychainPlatform.save(data: wrappedVMK.tag, forKey: "WrappedVMKTag_\(vault.rawValue)")
        
        return parameters
    }
    
    public func unlockVaultMasterKey(for vault: VaultType, pin: String) throws -> SymmetricKeyMaterial {
        guard let salt = try keychainPlatform.load(forKey: "Salt_\(vault.rawValue)"),
              let ciphertext = try keychainPlatform.load(forKey: "WrappedVMK_\(vault.rawValue)"),
              let nonce = try keychainPlatform.load(forKey: "WrappedVMKNonce_\(vault.rawValue)"),
              let tag = try keychainPlatform.load(forKey: "WrappedVMKTag_\(vault.rawValue)") else {
            throw KeyManagerError.vaultNotConfigured
        }
        
        let parameters = KDFParameters(salt: salt)
        let kek = try deriveKEK(from: pin, parameters: parameters)
        let wrappedPayload = EncryptedPayload(ciphertext: ciphertext, nonce: nonce, tag: tag)
        
        let vmkData = try cryptoPlatform.decrypt(payload: wrappedPayload, using: kek)
        let masterKey = SymmetricKeyMaterial(rawBytes: vmkData)
        
        queue.async(flags: .barrier) {
            self.cachedMasterKeys[vault] = masterKey
        }
        
        return masterKey
    }
    
    public func getActiveMasterKey(for vault: VaultType) -> SymmetricKeyMaterial? {
        return queue.sync {
            self.cachedMasterKeys[vault]
        }
    }
    
    public func rewrapMasterKey(for vault: VaultType, oldPin: String, newPin: String) throws {
        let vmk = try unlockVaultMasterKey(for: vault, pin: oldPin)
        
        let newSalt = try cryptoPlatform.generateSalt()
        let newParams = KDFParameters(salt: newSalt)
        let newKEK = try deriveKEK(from: newPin, parameters: newParams)
        
        let newWrappedVMK = try cryptoPlatform.encrypt(data: vmk.rawBytes, using: newKEK)
        
        try keychainPlatform.save(data: newParams.salt, forKey: "Salt_\(vault.rawValue)")
        try keychainPlatform.save(data: newWrappedVMK.ciphertext, forKey: "WrappedVMK_\(vault.rawValue)")
        try keychainPlatform.save(data: newWrappedVMK.nonce, forKey: "WrappedVMKNonce_\(vault.rawValue)")
        try keychainPlatform.save(data: newWrappedVMK.tag, forKey: "WrappedVMKTag_\(vault.rawValue)")
        
        queue.async(flags: .barrier) {
            self.cachedMasterKeys[vault] = vmk
        }
    }
    
    public func purgeKeyMaterial(for vault: VaultType) {
        queue.async(flags: .barrier) {
            self.cachedMasterKeys.removeValue(forKey: vault)
        }
    }
}
