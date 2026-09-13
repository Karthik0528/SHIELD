import Foundation

/// Defines the category of stored media.
public enum MediaType: String, Codable, Sendable {
    case photo
    case video
}

/// Represents an encrypted media item record inside the vault metadata database.
///
/// **Operational (Plaintext) Attributes**:
/// - `id`: Opaque stable UUID.
/// - `vaultType`: Domain partition (`.main` or `.decoy`).
/// - `mediaType`: `.photo` or `.video` for rendering classification.
/// - `storageIdentifier`: Opaque UUID string referencing binary object under `Objects/`.
/// - `thumbnailStorageIdentifier`: Opaque UUID string referencing binary thumbnail under `Thumbnails/`.
/// - `fileSize`, `createdDate`, `modifiedDate`, `formatVersion`: Non-sensitive operational metadata.
///
/// **Encrypted Attributes**:
/// - `encryptedFilenameRef`: Encrypted original filename payload.
/// - `encryptedMetadataRef`: Encrypted EXIF, location/GPS, duration, and user description payload.
/// - `encryptedFileKeyRef`: Per-item 256-bit media key wrapped with the Vault Master Key (`VMK`).
public struct MediaItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let vaultType: VaultType
    public let mediaType: MediaType
    
    /// Encrypted payload containing original filename string.
    public let encryptedFilenameRef: Data
    
    /// Encrypted payload containing EXIF data, GPS location, resolution, and descriptions.
    public let encryptedMetadataRef: Data
    
    /// Encrypted per-item file encryption key payload (wrapped with Vault Master Key).
    public let encryptedFileKeyRef: Data
    
    /// Storage identifier for raw binary payload (`Vaults/<VaultType>/Objects/<storageIdentifier>.bin`).
    public let storageIdentifier: String
    
    /// Storage identifier for thumbnail binary payload (`Vaults/<VaultType>/Thumbnails/<thumbnailStorageIdentifier>.bin`).
    public let thumbnailStorageIdentifier: String?
    
    /// File size of encrypted binary object in bytes.
    public let fileSize: Int64
    
    /// Container format version.
    public let formatVersion: UInt8
    
    /// Item creation timestamp.
    public let createdDate: Date
    
    /// Item last modification timestamp.
    public let modifiedDate: Date
    
    /// Vault-scoped HMAC-SHA256 fingerprint for exact duplicate content checking.
    public let contentFingerprint: String?
    
    public init(
        id: UUID = UUID(),
        vaultType: VaultType,
        mediaType: MediaType,
        encryptedFilenameRef: Data,
        encryptedMetadataRef: Data,
        encryptedFileKeyRef: Data,
        storageIdentifier: String,
        thumbnailStorageIdentifier: String?,
        fileSize: Int64,
        formatVersion: UInt8 = 1,
        createdDate: Date = Date(),
        modifiedDate: Date = Date(),
        contentFingerprint: String? = nil
    ) {
        self.id = id
        self.vaultType = vaultType
        self.mediaType = mediaType
        self.encryptedFilenameRef = encryptedFilenameRef
        self.encryptedMetadataRef = encryptedMetadataRef
        self.encryptedFileKeyRef = encryptedFileKeyRef
        self.storageIdentifier = storageIdentifier
        self.thumbnailStorageIdentifier = thumbnailStorageIdentifier
        self.fileSize = fileSize
        self.formatVersion = formatVersion
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.contentFingerprint = contentFingerprint
    }
}
