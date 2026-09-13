import Foundation

/// Represents a symmetric key wrapper for cryptographic key material.
/// Sensitive in-memory key material lifetime is managed by strict scope release,
/// session invalidation, and platform cryptographic abstractions.
public struct SymmetricKeyMaterial: Sendable {
    public let rawBytes: Data
    
    public init(rawBytes: Data) {
        self.rawBytes = rawBytes
    }
}

/// Abstract representation of an encrypted data payload including initialization vector / nonce and tag.
public struct EncryptedPayload: Codable, Sendable {
    public let ciphertext: Data
    public let nonce: Data
    public let tag: Data
    
    public init(ciphertext: Data, nonce: Data, tag: Data) {
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.tag = tag
    }
}

public typealias WrappedKeyPayload = EncryptedPayload


/// Contract for the cryptographic engine responsible for encrypting/decrypting media & metadata payloads.
/// Implementations must use standard, vetted symmetric encryption algorithms (AES-GCM 256 via CryptoKit).
public protocol EncryptionEngineProtocol: Sendable {
    /// Encrypts raw data bytes with a given symmetric key.
    func encrypt(data: Data, using key: SymmetricKeyMaterial) throws -> EncryptedPayload
    
    /// Decrypts an encrypted payload with a given symmetric key.
    func decrypt(payload: EncryptedPayload, using key: SymmetricKeyMaterial) throws -> Data
    
    /// Wraps (encrypts) a target key using a Key Encryption Key (KEK).
    func wrapKey(targetKey: SymmetricKeyMaterial, using kek: SymmetricKeyMaterial) throws -> EncryptedPayload
    
    /// Unwraps (decrypts) a target key using a Key Encryption Key (KEK).
    func unwrapKey(wrappedPayload: EncryptedPayload, using kek: SymmetricKeyMaterial) throws -> SymmetricKeyMaterial
    
    /// Generates cryptographically secure random bytes for new per-media keys.
    func generateRandomKey() throws -> SymmetricKeyMaterial
}

/// Core encryption engine implementation delegating to the platform cryptography provider.
public final class DefaultEncryptionEngine: EncryptionEngineProtocol {
    private let cryptoPlatform: PlatformCryptoProtocol
    
    public init(cryptoPlatform: PlatformCryptoProtocol = DefaultPlatformCrypto()) {
        self.cryptoPlatform = cryptoPlatform
    }
    
    public func encrypt(data: Data, using key: SymmetricKeyMaterial) throws -> EncryptedPayload {
        return try cryptoPlatform.encrypt(data: data, using: key)
    }
    
    public func decrypt(payload: EncryptedPayload, using key: SymmetricKeyMaterial) throws -> Data {
        return try cryptoPlatform.decrypt(payload: payload, using: key)
    }
    
    public func wrapKey(targetKey: SymmetricKeyMaterial, using kek: SymmetricKeyMaterial) throws -> EncryptedPayload {
        return try encrypt(data: targetKey.rawBytes, using: kek)
    }
    
    public func unwrapKey(wrappedPayload: EncryptedPayload, using kek: SymmetricKeyMaterial) throws -> SymmetricKeyMaterial {
        let rawBytes = try decrypt(payload: wrappedPayload, using: kek)
        return SymmetricKeyMaterial(rawBytes: rawBytes)
    }
    
    public func generateRandomKey() throws -> SymmetricKeyMaterial {
        return try cryptoPlatform.generateRandomKey()
    }
}

public enum EncryptionEngineError: Error, Equatable {
    case platformNotAvailable
    case encryptionFailed
    case decryptionFailed
    case invalidKeyLength
}
