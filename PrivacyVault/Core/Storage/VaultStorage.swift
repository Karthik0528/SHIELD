import Foundation

/// High-level vault storage abstraction coordinating objects, thumbnails, and metadata database for a vault domain.
public protocol VaultStorageProtocol: Sendable {
    var fileStore: FileStoreProtocol { get }
    var thumbnailStore: ThumbnailStoreProtocol { get }
    var database: DatabaseProtocol { get }
    
    /// Initializes necessary directory namespaces for the specified vault instance.
    func initializeDirectories(for vault: VaultType) throws
    
    /// Purges all storage content for a vault instance.
    func wipeStorage(for vault: VaultType) throws
    
    /// Checks whether any encrypted media, thumbnail, or database files exist on disk for the vault.
    func hasDiskVaultData(for vault: VaultType) -> Bool
}

/// Concrete implementation of vault storage coordinator.
public final class VaultStorage: VaultStorageProtocol {
    public let fileStore: FileStoreProtocol
    public let thumbnailStore: ThumbnailStoreProtocol
    public let database: DatabaseProtocol
    
    private let fileManager: FileManager
    public let baseURL: URL
    
    public init(
        fileStore: FileStoreProtocol? = nil,
        thumbnailStore: ThumbnailStoreProtocol? = nil,
        database: DatabaseProtocol? = nil,
        fileManager: FileManager = .default,
        baseURL: URL? = nil
    ) {
        let root = baseURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileManager = fileManager
        self.baseURL = root
        self.fileStore = fileStore ?? EncryptedFileStore(fileManager: fileManager, baseURL: root)
        self.thumbnailStore = thumbnailStore ?? EncryptedThumbnailStore(fileManager: fileManager, baseURL: root)
        self.database = database ?? EncryptedDatabase(fileManager: fileManager, baseURL: root)
    }
    
    public func initializeDirectories(for vault: VaultType) throws {
        let vaultRoot = baseURL.appendingPathComponent(vault.storageSubpath, isDirectory: true)
        let objectsDir = vaultRoot.appendingPathComponent("Objects", isDirectory: true)
        let thumbnailsDir = vaultRoot.appendingPathComponent("Thumbnails", isDirectory: true)
        let databaseDir = vaultRoot.appendingPathComponent("Database", isDirectory: true)
        
        try fileManager.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: databaseDir, withIntermediateDirectories: true)
    }
    
    public func wipeStorage(for vault: VaultType) throws {
        let vaultRoot = baseURL.appendingPathComponent(vault.storageSubpath, isDirectory: true)
        if fileManager.fileExists(atPath: vaultRoot.path) {
            try fileManager.removeItem(at: vaultRoot)
        }
    }
    
    public func hasDiskVaultData(for vault: VaultType) -> Bool {
        let vaultRoot = baseURL.appendingPathComponent(vault.storageSubpath, isDirectory: true)
        guard fileManager.fileExists(atPath: vaultRoot.path) else {
            return false
        }
        
        let objectsDir = vaultRoot.appendingPathComponent("Objects", isDirectory: true)
        let thumbsDir = vaultRoot.appendingPathComponent("Thumbnails", isDirectory: true)
        let dbDir = vaultRoot.appendingPathComponent("Database", isDirectory: true)
        
        if let files = try? fileManager.contentsOfDirectory(atPath: objectsDir.path), !files.isEmpty {
            return true
        }
        if let files = try? fileManager.contentsOfDirectory(atPath: thumbsDir.path), !files.isEmpty {
            return true
        }
        if let files = try? fileManager.contentsOfDirectory(atPath: dbDir.path), !files.isEmpty {
            return true
        }
        
        return false
    }
}
