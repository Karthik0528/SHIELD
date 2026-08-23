import Foundation

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

/// Safe development implementation.
/// Uses in-memory storage on non-iOS environments and provides clear entry points for `SecItemAdd` / `SecItemCopyMatching` on iOS.
public final class DefaultPlatformKeychain: PlatformKeychainProtocol, @unchecked Sendable {
    private var mockStorage: [String: Data] = [:]
    private let queue = DispatchQueue(label: "com.privacyvault.mockkeychain", attributes: .concurrent)
    
    public init() {}
    
    public func save(data: Data, forKey key: String) throws {
        #if canImport(Security) && os(iOS)
        // iOS Native SecItemAdd / SecItemUpdate implementation placeholder
        #endif
        queue.async(flags: .barrier) {
            self.mockStorage[key] = data
        }
    }
    
    public func load(forKey key: String) throws -> Data? {
        #if canImport(Security) && os(iOS)
        // iOS Native SecItemCopyMatching implementation placeholder
        #endif
        return queue.sync {
            self.mockStorage[key]
        }
    }
    
    public func delete(forKey key: String) throws {
        #if canImport(Security) && os(iOS)
        // iOS Native SecItemDelete implementation placeholder
        #endif
        queue.async(flags: .barrier) {
            self.mockStorage.removeValue(forKey: key)
        }
    }
}
