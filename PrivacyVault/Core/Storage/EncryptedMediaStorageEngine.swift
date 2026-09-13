import Foundation

public struct OrphanReport: Sendable {
    public let missingMediaFiles: [UUID]
    public let missingThumbnailFiles: [UUID]
    public let orphanedObjects: [String]
    
    public init(
        missingMediaFiles: [UUID] = [],
        missingThumbnailFiles: [UUID] = [],
        orphanedObjects: [String] = []
    ) {
        self.missingMediaFiles = missingMediaFiles
        self.missingThumbnailFiles = missingThumbnailFiles
        self.orphanedObjects = orphanedObjects
    }
}

public enum StorageEngineError: Error, Equatable, Sendable {
    case unauthenticatedVault
    case encryptionFailed
    case atomicWriteFailed
    case rollbackExecuted
    case itemNotFound
}

/// Core persistent storage engine handling per-item key derivation, AES-GCM authenticated encryption,
/// atomic file writes, transactional media import/export, and orphan diagnostics.
public final class EncryptedMediaStorageEngine: Sendable {
    private let storage: VaultStorageProtocol
    private let encryptionEngine: EncryptionEngineProtocol
    private let fileManager: FileManager
    private let baseURL: URL
    
    public init(
        storage: VaultStorageProtocol = VaultStorage(),
        encryptionEngine: EncryptionEngineProtocol = DefaultEncryptionEngine(),
        fileManager: FileManager = .default,
        baseURL: URL? = nil
    ) {
        self.storage = storage
        self.encryptionEngine = encryptionEngine
        self.fileManager = fileManager
        self.baseURL = baseURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    // MARK: - Transactional Import
    /// Encrypts and imports a new photo or video payload into the specified vault.
    public func importMedia(
        rawMediaData: Data,
        thumbnailData: Data?,
        originalFilename: String,
        rawMetadataJSON: Data,
        mediaType: MediaType,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial,
        contentFingerprint: String? = nil
    ) throws -> MediaItem {
        try storage.initializeDirectories(for: vault)
        
        let itemID = UUID()
        let storageID = UUID().uuidString
        let thumbnailStorageID = thumbnailData != nil ? UUID().uuidString : nil
        
        // 1. Encrypt Metadata & Filename using Vault Master Key (VMK)
        let filenameBytes = Data(originalFilename.utf8)
        let encryptedFilename = try encryptionEngine.encrypt(data: filenameBytes, using: masterKey)
        let serializedFilename = try JSONEncoder().encode(encryptedFilename)
        
        let encryptedMetadata = try encryptionEngine.encrypt(data: rawMetadataJSON, using: masterKey)
        let serializedMetadata = try JSONEncoder().encode(encryptedMetadata)
        
        // 2. Generate Independent Per-Media Encryption Key
        let perMediaKey = try encryptionEngine.generateRandomKey()
        let wrappedMediaKeyPayload = try encryptionEngine.wrapKey(targetKey: perMediaKey, using: masterKey)
        let serializedWrappedMediaKey = try JSONEncoder().encode(wrappedMediaKeyPayload)
        
        // Encrypt Media Data with per-media key
        let encryptedMediaPayload = try encryptionEngine.encrypt(data: rawMediaData, using: perMediaKey)
        
        let mediaContainer = EncryptedObjectContainer(
            objectType: .media,
            vaultType: vault,
            objectID: itemID,
            wrappedKeyData: serializedWrappedMediaKey,
            nonce: encryptedMediaPayload.nonce,
            tag: encryptedMediaPayload.tag,
            ciphertext: encryptedMediaPayload.ciphertext
        )
        
        // 3. Generate Independent Per-Thumbnail Encryption Key (if thumbnail present)
        var thumbnailContainerData: Data? = nil
        if let thumbData = thumbnailData {
            let perThumbKey = try encryptionEngine.generateRandomKey()
            let wrappedThumbKeyPayload = try encryptionEngine.wrapKey(targetKey: perThumbKey, using: masterKey)
            let serializedWrappedThumbKey = try JSONEncoder().encode(wrappedThumbKeyPayload)
            
            let encryptedThumbPayload = try encryptionEngine.encrypt(data: thumbData, using: perThumbKey)
            
            let thumbContainer = EncryptedObjectContainer(
                objectType: .thumbnail,
                vaultType: vault,
                objectID: itemID,
                wrappedKeyData: serializedWrappedThumbKey,
                nonce: encryptedThumbPayload.nonce,
                tag: encryptedThumbPayload.tag,
                ciphertext: encryptedThumbPayload.ciphertext
            )
            thumbnailContainerData = try thumbContainer.encode()
        }
        
        let mediaContainerData = try mediaContainer.encode()
        
        // Rollback tracking
        var createdFiles: [URL] = []
        func rollback() {
            for fileURL in createdFiles {
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        do {
            // Atomic write media object
            let objectsDir = baseURL.appendingPathComponent("\(vault.storageSubpath)/Objects", isDirectory: true)
            let tempMediaURL = objectsDir.appendingPathComponent("\(storageID).tmp")
            let finalMediaURL = objectsDir.appendingPathComponent("\(storageID).bin")
            
            try mediaContainerData.write(to: tempMediaURL, options: .atomic)
            createdFiles.append(tempMediaURL)
            
            try fileManager.moveItem(at: tempMediaURL, to: finalMediaURL)
            createdFiles.append(finalMediaURL)
            
            // Atomic write thumbnail object
            if let thumbDataBlob = thumbnailContainerData, let thumbID = thumbnailStorageID {
                let thumbsDir = baseURL.appendingPathComponent("\(vault.storageSubpath)/Thumbnails", isDirectory: true)
                let tempThumbURL = thumbsDir.appendingPathComponent("\(thumbID).tmp")
                let finalThumbURL = thumbsDir.appendingPathComponent("\(thumbID).bin")
                
                try thumbDataBlob.write(to: tempThumbURL, options: .atomic)
                createdFiles.append(tempThumbURL)
                
                try fileManager.moveItem(at: tempThumbURL, to: finalThumbURL)
                createdFiles.append(finalThumbURL)
            }
            
            // Create database record
            let mediaItem = MediaItem(
                id: itemID,
                vaultType: vault,
                mediaType: mediaType,
                encryptedFilenameRef: serializedFilename,
                encryptedMetadataRef: serializedMetadata,
                encryptedFileKeyRef: serializedWrappedMediaKey,
                storageIdentifier: storageID,
                thumbnailStorageIdentifier: thumbnailStorageID,
                fileSize: Int64(mediaContainerData.count),
                contentFingerprint: contentFingerprint
            )
            
            try storage.database.saveMediaItem(mediaItem, for: vault)
            return mediaItem
        } catch {
            rollback()
            throw StorageEngineError.atomicWriteFailed
        }
    }
    
    // MARK: - Transactional Loading & Decryption
    /// Loads and decrypts in memory the thumbnail binary container for a given media item.
    public func loadThumbnail(
        for item: MediaItem,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial
    ) throws -> Data {
        guard item.vaultType == vault else {
            throw StorageEngineError.unauthenticatedVault
        }
        guard let thumbID = item.thumbnailStorageIdentifier else {
            throw StorageEngineError.itemNotFound
        }
        guard storage.thumbnailStore.thumbnailExists(identifier: thumbID, vault: vault) else {
            throw StorageEngineError.itemNotFound
        }
        
        let encContainerData = try storage.thumbnailStore.readThumbnail(identifier: thumbID, vault: vault)
        let container = try EncryptedObjectContainer.decode(from: encContainerData)
        guard container.vaultType == vault else {
            throw StorageEngineError.unauthenticatedVault
        }
        
        let wrappedKeyPayload = try JSONDecoder().decode(WrappedKeyPayload.self, from: container.wrappedKeyData)
        let perThumbKey = try encryptionEngine.unwrapKey(wrappedPayload: wrappedKeyPayload, using: masterKey)
        let cipherPayload = EncryptedPayload(ciphertext: container.ciphertext, nonce: container.nonce, tag: container.tag)
        
        return try encryptionEngine.decrypt(payload: cipherPayload, using: perThumbKey)
    }
    
    /// Loads and decrypts in memory the full-resolution media binary container for a given media item.
    public func loadMedia(
        for item: MediaItem,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial
    ) throws -> Data {
        shieldLog("[SHIELD_MEDIA] Open requested")
        shieldLog("[SHIELD_MEDIA] Active vault = \(vault.rawValue)")
        
        guard item.vaultType == vault else {
            shieldLog("[SHIELD_MEDIA] Vault type mismatch: item=\(item.vaultType.rawValue), active=\(vault.rawValue)")
            throw StorageEngineError.unauthenticatedVault
        }
        
        let fileExists = storage.fileStore.exists(identifier: item.storageIdentifier, vault: vault)
        shieldLog("[SHIELD_MEDIA] Object located = \(fileExists)")
        guard fileExists else {
            throw StorageEngineError.itemNotFound
        }
        
        shieldLog("[SHIELD_MEDIA] VMK available = true")
        
        let encContainerData = try storage.fileStore.read(identifier: item.storageIdentifier, vault: vault)
        let container: EncryptedObjectContainer
        do {
            container = try EncryptedObjectContainer.decode(from: encContainerData)
            shieldLog("[SHIELD_MEDIA] Container parse = success")
        } catch {
            shieldLog("[SHIELD_MEDIA] Container parse = failure: \(error)")
            throw error
        }
        
        guard container.vaultType == vault else {
            shieldLog("[SHIELD_MEDIA] Container vaultType mismatch")
            throw StorageEngineError.unauthenticatedVault
        }
        
        let perMediaKey: SymmetricKeyMaterial
        do {
            let wrappedKeyPayload = try JSONDecoder().decode(WrappedKeyPayload.self, from: container.wrappedKeyData)
            perMediaKey = try encryptionEngine.unwrapKey(wrappedPayload: wrappedKeyPayload, using: masterKey)
            shieldLog("[SHIELD_MEDIA] Media key unwrap = success")
        } catch {
            shieldLog("[SHIELD_MEDIA] Media key unwrap = failure: \(error)")
            throw error
        }
        
        let cipherPayload = EncryptedPayload(ciphertext: container.ciphertext, nonce: container.nonce, tag: container.tag)
        
        do {
            let decrypted = try encryptionEngine.decrypt(payload: cipherPayload, using: perMediaKey)
            shieldLog("[SHIELD_MEDIA] Payload authentication = success")
            shieldLog("[SHIELD_MEDIA] Decryption = success")
            return decrypted
        } catch {
            shieldLog("[SHIELD_MEDIA] Payload authentication = failure: \(error)")
            shieldLog("[SHIELD_MEDIA] Decryption = failure: \(error)")
            throw error
        }
    }
    
    // MARK: - Transactional Delete
    /// Permanently deletes a media item, its binary object, thumbnail binary, and database record.
    public func deleteMedia(itemID: UUID, vault: VaultType) throws {
        let items = try storage.database.fetchMediaItems(for: vault)
        guard let item = items.first(where: { $0.id == itemID }) else {
            throw StorageEngineError.itemNotFound
        }
        
        // Remove binary files
        try storage.fileStore.delete(identifier: item.storageIdentifier, vault: vault)
        if let thumbID = item.thumbnailStorageIdentifier {
            try storage.thumbnailStore.deleteThumbnail(identifier: thumbID, vault: vault)
        }
        
        // Remove database record
        try storage.database.deleteMediaItem(id: itemID, for: vault)
    }
    
    // MARK: - Orphan Diagnostics
    /// Performs integrity check and returns orphan diagnostic report.
    public func detectOrphans(for vault: VaultType) throws -> OrphanReport {
        let items = try storage.database.fetchMediaItems(for: vault)
        var missingMedia: [UUID] = []
        var missingThumbs: [UUID] = []
        
        for item in items {
            if !storage.fileStore.exists(identifier: item.storageIdentifier, vault: vault) {
                missingMedia.append(item.id)
            }
            if let thumbID = item.thumbnailStorageIdentifier {
                if !storage.thumbnailStore.thumbnailExists(identifier: thumbID, vault: vault) {
                    missingThumbs.append(item.id)
                }
            }
        }
        
        // Check for binary files without DB records
        let objectsDir = baseURL.appendingPathComponent("\(vault.storageSubpath)/Objects", isDirectory: true)
        let fileURLs = (try? fileManager.contentsOfDirectory(at: objectsDir, includingPropertiesForKeys: nil)) ?? []
        
        let validStorageIDs = Set(items.map { "\($0.storageIdentifier).bin" })
        let orphanedFiles = fileURLs
            .filter { $0.pathExtension == "bin" && !validStorageIDs.contains($0.lastPathComponent) }
            .map { $0.lastPathComponent }
        
        return OrphanReport(
            missingMediaFiles: missingMedia,
            missingThumbnailFiles: missingThumbs,
            orphanedObjects: orphanedFiles
        )
    }
}
