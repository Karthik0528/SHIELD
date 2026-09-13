import Foundation

#if canImport(CryptoKit)
import CryptoKit
import Security
#endif

#if canImport(CommonCrypto)
import CommonCrypto

/// Native CommonCrypto implementation of PBKDF2 key derivation.
public struct CommonCryptoPBKDF2: PasswordKeyDerivationProtocol {
    public init() {}
    
    public func deriveKey(passcode: String, salt: Data, iterations: Int) throws -> SymmetricKeyMaterial {
        guard let passcodeData = passcode.data(using: .utf8) else {
            throw PlatformCryptoError.keyDerivationFailed
        }
        var derivedKeyData = Data(count: 32)
        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passcodeData.withUnsafeBytes { passcodeBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passcodeBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passcodeData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard result == kCCSuccess else {
            throw PlatformCryptoError.keyDerivationFailed
        }
        return SymmetricKeyMaterial(rawBytes: derivedKeyData)
    }
}
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

public extension PlatformCryptoProtocol {
    func encrypt(data: Data, using key: SymmetricKeyMaterial) throws -> EncryptedPayload {
        try encrypt(data: data, using: key, authenticData: Data())
    }
    
    func decrypt(payload: EncryptedPayload, using key: SymmetricKeyMaterial) throws -> Data {
        try decrypt(payload: payload, using: key, authenticData: Data())
    }
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
        #if canImport(CommonCrypto)
        let defaultEngine = CommonCryptoPBKDF2()
        return try defaultEngine.deriveKey(passcode: passcode, salt: salt, iterations: iterations)
        #else
        throw PlatformCryptoError.unsupportedPlatform
        #endif
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

