import Foundation

/// Database errors.
public enum DatabaseError: Error, Equatable {
    case itemNotFound
    case recordCorrupted
    case storageFailed
}

/// Abstract contract for metadata database persistence per vault domain (`Database/` subpath).
public protocol DatabaseProtocol: Sendable {
    // MARK: - MediaItems
    func fetchMediaItems(for vault: VaultType) throws -> [MediaItem]
    func saveMediaItem(_ item: MediaItem, for vault: VaultType) throws
    func deleteMediaItem(id: UUID, for vault: VaultType) throws
    
    // MARK: - Albums
    func fetchAlbums(for vault: VaultType) throws -> [Album]
    func saveAlbum(_ album: Album, for vault: VaultType) throws
    func deleteAlbum(id: UUID, for vault: VaultType) throws
    
    // MARK: - VaultSettings
    func fetchSettings(for vault: VaultType) throws -> VaultSettings
    func saveSettings(_ settings: VaultSettings, for vault: VaultType) throws
}

/// Disk persistence implementation storing JSON-encoded metadata tables in `Vaults/<VaultType>/Database/`.
public final class EncryptedDatabase: DatabaseProtocol {
    private let fileManager: FileManager
    private let baseURL: URL
    
    public init(fileManager: FileManager = .default, baseURL: URL? = nil) {
        self.fileManager = fileManager
        self.baseURL = baseURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private func databaseURL(for vault: VaultType) -> URL {
        return baseURL.appendingPathComponent("\(vault.storageSubpath)/Database", isDirectory: true)
    }
    
    // MARK: - MediaItems
    public func fetchMediaItems(for vault: VaultType) throws -> [MediaItem] {
        let fileURL = databaseURL(for: vault).appendingPathComponent("media_items.json")
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([MediaItem].self, from: data)
    }
    
    public func saveMediaItem(_ item: MediaItem, for vault: VaultType) throws {
        var items = try fetchMediaItems(for: vault)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        let dir = databaseURL(for: vault)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(items)
        try data.write(to: dir.appendingPathComponent("media_items.json"), options: .atomic)
    }
    
    public func deleteMediaItem(id: UUID, for vault: VaultType) throws {
        var items = try fetchMediaItems(for: vault)
        items.removeAll(where: { $0.id == id })
        let dir = databaseURL(for: vault)
        let data = try JSONEncoder().encode(items)
        try data.write(to: dir.appendingPathComponent("media_items.json"), options: .atomic)
    }
    
    // MARK: - Albums
    public func fetchAlbums(for vault: VaultType) throws -> [Album] {
        let fileURL = databaseURL(for: vault).appendingPathComponent("albums.json")
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([Album].self, from: data)
    }
    
    public func saveAlbum(_ album: Album, for vault: VaultType) throws {
        var albums = try fetchAlbums(for: vault)
        if let index = albums.firstIndex(where: { $0.id == album.id }) {
            albums[index] = album
        } else {
            albums.append(album)
        }
        let dir = databaseURL(for: vault)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(albums)
        try data.write(to: dir.appendingPathComponent("albums.json"), options: .atomic)
    }
    
    public func deleteAlbum(id: UUID, for vault: VaultType) throws {
        var albums = try fetchAlbums(for: vault)
        albums.removeAll(where: { $0.id == id })
        let dir = databaseURL(for: vault)
        let data = try JSONEncoder().encode(albums)
        try data.write(to: dir.appendingPathComponent("albums.json"), options: .atomic)
    }
    
    // MARK: - VaultSettings
    public func fetchSettings(for vault: VaultType) throws -> VaultSettings {
        let fileURL = databaseURL(for: vault).appendingPathComponent("settings.json")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return VaultSettings(vaultType: vault)
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(VaultSettings.self, from: data)
    }
    
    public func saveSettings(_ settings: VaultSettings, for vault: VaultType) throws {
        let dir = databaseURL(for: vault)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: dir.appendingPathComponent("settings.json"), options: .atomic)
    }
}
