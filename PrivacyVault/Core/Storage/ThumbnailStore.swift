import Foundation

/// Protocol defining operations on raw encrypted thumbnail binary objects (`Thumbnails/` directory).
public protocol ThumbnailStoreProtocol: Sendable {
    /// Saves an encrypted thumbnail blob into storage under a random thumbnail storage identifier.
    func saveThumbnail(encryptedData: Data, identifier: String, vault: VaultType) throws
    
    /// Reads encrypted thumbnail data blob given its identifier.
    func readThumbnail(identifier: String, vault: VaultType) throws -> Data
    
    /// Deletes an encrypted thumbnail binary file from disk.
    func deleteThumbnail(identifier: String, vault: VaultType) throws
    
    /// Checks existence of a thumbnail file.
    func thumbnailExists(identifier: String, vault: VaultType) -> Bool
}

/// Disk persistence implementation for encrypted thumbnail files.
public final class EncryptedThumbnailStore: ThumbnailStoreProtocol {
    private let fileManager: FileManager
    private let baseURL: URL
    
    public init(fileManager: FileManager = .default, baseURL: URL? = nil) {
        self.fileManager = fileManager
        self.baseURL = baseURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private func thumbnailsURL(for vault: VaultType) -> URL {
        return baseURL.appendingPathComponent("\(vault.storageSubpath)/Thumbnails", isDirectory: true)
    }
    
    public func saveThumbnail(encryptedData: Data, identifier: String, vault: VaultType) throws {
        let dir = thumbnailsURL(for: vault)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(identifier).bin")
        try encryptedData.write(to: fileURL, options: .atomic)
    }
    
    public func readThumbnail(identifier: String, vault: VaultType) throws -> Data {
        let fileURL = thumbnailsURL(for: vault).appendingPathComponent("\(identifier).bin")
        return try Data(contentsOf: fileURL)
    }
    
    public func deleteThumbnail(identifier: String, vault: VaultType) throws {
        let fileURL = thumbnailsURL(for: vault).appendingPathComponent("\(identifier).bin")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    
    public func thumbnailExists(identifier: String, vault: VaultType) -> Bool {
        let fileURL = thumbnailsURL(for: vault).appendingPathComponent("\(identifier).bin")
        return fileManager.fileExists(atPath: fileURL.path)
    }
}
