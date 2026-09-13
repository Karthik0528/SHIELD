import Foundation
#if canImport(Security)
import Security
#endif

/// Platform contract abstraction for iOS Keychain Services (`Security.framework`).
public protocol PlatformKeychainProtocol: Sendable {
    func save(data: Data, forKey key: String) throws
    func load(forKey key: String) throws -> Data?
    func delete(forKey key: String) throws
}

public enum PlatformKeychainError: Error, Equatable, Sendable {
    case itemNotFound
    case unhandledError(status: Int32)
}

/// Durable platform keychain implementation backed by Apple's Security framework on iOS.
/// Persists key material (`Salt_main`, `WrappedVMK_main`, `Salt_decoy`, etc.) across app launches, restarts, and reboots.
public final class DefaultPlatformKeychain: PlatformKeychainProtocol, @unchecked Sendable {
    private let service: String
    private var mockStorage: [String: Data] = [:]
    private let queue = DispatchQueue(label: "com.privacyvault.keychain", attributes: .concurrent)
    
    public init(service: String = "com.shield.privacyvault") {
        NSLog("[SHIELD_STARTUP] DefaultPlatformKeychain.init")
        self.service = service
    }
    
    public func save(data: Data, forKey key: String) throws {
        #if canImport(Security) && os(iOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        
        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw PlatformKeychainError.unhandledError(status: addStatus)
            }
            return
        }
        
        throw PlatformKeychainError.unhandledError(status: updateStatus)
        #else
        queue.async(flags: .barrier) {
            self.mockStorage[key] = data
        }
        #endif
    }
    
    public func load(forKey key: String) throws -> Data? {
        #if canImport(Security) && os(iOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let data = dataTypeRef as? Data {
                return data
            }
            return nil
        }
        
        if status == errSecItemNotFound {
            return nil
        }
        
        throw PlatformKeychainError.unhandledError(status: status)
        #else
        return queue.sync {
            self.mockStorage[key]
        }
        #endif
    }
    
    public func delete(forKey key: String) throws {
        #if canImport(Security) && os(iOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw PlatformKeychainError.unhandledError(status: status)
        }
        #else
        queue.async(flags: .barrier) {
            self.mockStorage.removeValue(forKey: key)
        }
        #endif
    }
}
