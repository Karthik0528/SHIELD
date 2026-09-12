import Foundation

#if canImport(CryptoKit)
import CryptoKit
import Security
#endif

/// Abstract contract for Password-based Key Derivation Functions (e.g. PBKDF2, Argon2).
public protocol PasswordKeyDerivationProtocol: Sendable {
    func deriveKey(passcode: String, salt: Data, iterations: Int) throws -> SymmetricKeyMaterial
}

/// Platform contract abstraction for symmetric cryptography.
public protocol PlatformCryptoProtocol: Sendable {
    func generateSalt() throws -> Data
    func generateRandomKey() throws -> SymmetricKeyMaterial
    func deriveKey(passcode: String, salt: Data, iterations: Int) throws -> SymmetricKeyMaterial
    func encrypt(data: Data, using key: SymmetricKeyMaterial, authenticData: Data) throws -> EncryptedPayload
    func decrypt(payload: EncryptedPayload, using key: SymmetricKeyMaterial, authenticData: Data) throws -> Data
}

public enum PlatformCryptoError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidKeyLength
}

/// Platform crypto implementation.
/// Uses Apple's CryptoKit on supported platforms. On unsupported platforms (such as Windows development),
/// it FAILS CLOSED by throwing `unsupportedPlatform` to prevent accidental plaintext exposure or fake security.
public final class DefaultPlatformCrypto: PlatformCryptoProtocol {
    private let kdfEngine: PasswordKeyDerivationProtocol?
    
    public init(kdfEngine: PasswordKeyDerivationProtocol? = nil) {
        self.kdfEngine = kdfEngine
    }
    
    public func generateSalt() throws -> Data {
        #if canImport(CryptoKit)
        var bytes = Data(count: 32)
        let result = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw PlatformCryptoError.encryptionFailed
        }
        return bytes
        #else
        throw PlatformCryptoError.unsupportedPlatform
        #endif
    }
    
    public func generateRandomKey() throws -> SymmetricKeyMaterial {
        #if canImport(CryptoKit)
        let key = SymmetricKey(size: .bits256)
        let rawData = key.withUnsafeBytes { Data($0) }
        return SymmetricKeyMaterial(rawBytes: rawData)
        #else
        throw PlatformCryptoError.unsupportedPlatform
        #endif
    }
    
    public func deriveKey(passcode: String, salt: Data, iterations: Int) throws -> SymmetricKeyMaterial {
        if let kdfEngine = kdfEngine {
            return try kdfEngine.deriveKey(passcode: passcode, salt: salt, iterations: iterations)
        }
        throw PlatformCryptoError.unsupportedPlatform
    }
    
    public func encrypt(data: Data, using key: SymmetricKeyMaterial, authenticData: Data = Data()) throws -> EncryptedPayload {
        #if canImport(CryptoKit)
        guard key.rawBytes.count == 32 else {
            throw PlatformCryptoError.invalidKeyLength
        }
        let symKey = SymmetricKey(data: key.rawBytes)
        do {
            let sealedBox = authenticData.isEmpty
                ? try AES.GCM.seal(data, using: symKey)
                : try AES.GCM.seal(data, using: symKey, authenticating: authenticData)
            let nonceData = Data(sealedBox.nonce)
            return EncryptedPayload(ciphertext: sealedBox.ciphertext, nonce: nonceData, tag: sealedBox.tag)
        } catch {
            throw PlatformCryptoError.encryptionFailed
        }
        #else
        throw PlatformCryptoError.unsupportedPlatform
        #endif
    }
    
    public func decrypt(payload: EncryptedPayload, using key: SymmetricKeyMaterial, authenticData: Data = Data()) throws -> Data {
        #if canImport(CryptoKit)
        guard key.rawBytes.count == 32 else {
            throw PlatformCryptoError.invalidKeyLength
        }
        let symKey = SymmetricKey(data: key.rawBytes)
        do {
            let nonce = try AES.GCM.Nonce(data: payload.nonce)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: payload.ciphertext, tag: payload.tag)
            return authenticData.isEmpty
                ? try AES.GCM.open(sealedBox, using: symKey)
                : try AES.GCM.open(sealedBox, using: symKey, authenticating: authenticData)
        } catch {
            throw PlatformCryptoError.decryptionFailed
        }
        #else
        throw PlatformCryptoError.unsupportedPlatform
        #endif
    }
}
