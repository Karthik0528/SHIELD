import Foundation

/// Protocol defining operations on raw encrypted media binary objects (`Objects/` directory).
public protocol FileStoreProtocol: Sendable {
    /// Saves an encrypted binary data blob into storage under a random storage identifier.
    func save(encryptedData: Data, identifier: String, vault: VaultType) throws
    
    /// Reads encrypted binary data blob given its storage identifier.
    func read(identifier: String, vault: VaultType) throws -> Data
    
    /// Deletes an encrypted binary payload file from disk.
    func delete(identifier: String, vault: VaultType) throws
    
    /// Checks existence of an object file.
    func exists(identifier: String, vault: VaultType) -> Bool
}

/// Disk persistence implementation for encrypted media files.
public final class EncryptedFileStore: FileStoreProtocol {
    private let fileManager: FileManager
    private let baseURL: URL
    
    public init(fileManager: FileManager = .default, baseURL: URL? = nil) {
        self.fileManager = fileManager
        self.baseURL = baseURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private func objectsURL(for vault: VaultType) -> URL {
        return baseURL.appendingPathComponent("\(vault.storageSubpath)/Objects", isDirectory: true)
    }
    
    public func save(encryptedData: Data, identifier: String, vault: VaultType) throws {
        let dir = objectsURL(for: vault)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(identifier).bin")
        try encryptedData.write(to: fileURL, options: .atomic)
    }
    
    public func read(identifier: String, vault: VaultType) throws -> Data {
        let fileURL = objectsURL(for: vault).appendingPathComponent("\(identifier).bin")
        return try Data(contentsOf: fileURL)
    }
    
    public func delete(identifier: String, vault: VaultType) throws {
        let fileURL = objectsURL(for: vault).appendingPathComponent("\(identifier).bin")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    
    public func exists(identifier: String, vault: VaultType) -> Bool {
        let fileURL = objectsURL(for: vault).appendingPathComponent("\(identifier).bin")
        return fileManager.fileExists(atPath: fileURL.path)
    }
}
