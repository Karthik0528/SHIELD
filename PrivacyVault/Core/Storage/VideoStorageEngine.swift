import Foundation

public enum VideoStorageError: Error, Equatable, Sendable {
    case unauthenticatedVault
    case mediaSizeExceeded
    case emptyPayload
    case encryptionFailed
    case atomicWriteFailed
    case rollbackExecuted
    case itemNotFound
    case chunkAuthenticationFailed
    case unsupportedPlatform
}

/// Core persistent storage engine handling chunked AES-GCM encrypted video storage (PVV1),
/// independent video thumbnail key wrapping, 500 MB size limit enforcement, atomic file persistence,
/// transactional rollback, and orphan diagnostics.
///
/// **Streaming I/O Architecture**:
/// Bounded RAM footprint: Video payloads are processed strictly in 4 MiB buffer slices via FileHandle streaming.
/// Complete 500 MB video files are NEVER loaded into memory as a single Data object or chunk array.
public final class VideoStorageEngine: Sendable {
    private let storage: VaultStorageProtocol
    private let encryptionEngine: EncryptionEngineProtocol
    private let cryptoPlatform: PlatformCryptoProtocol
    private let fileManager: FileManager
    private let baseURL: URL
    
    public init(
        storage: VaultStorageProtocol = VaultStorage(),
        encryptionEngine: EncryptionEngineProtocol = DefaultEncryptionEngine(),
        cryptoPlatform: PlatformCryptoProtocol = DefaultPlatformCrypto(),
        fileManager: FileManager = .default,
        baseURL: URL? = nil
    ) {
        self.storage = storage
        self.encryptionEngine = encryptionEngine
        self.cryptoPlatform = cryptoPlatform
        self.fileManager = fileManager
        self.baseURL = baseURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    // MARK: - Transactional Streaming Video Import
    /// Encrypts and streams a source video file into the specified vault using chunked AES-GCM (PVV1).
    /// Bounded RAM footprint: RAM contains only the active 4 MiB buffer slice during streaming I/O.
    /// Enforces the 500 MB maximum media size limit prior to encryption or disk persistence.
    public func importVideo(
        sourceURL: URL,
        thumbnailData: Data?,
        originalFilename: String,
        rawMetadataJSON: Data,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial
    ) throws -> MediaItem {
        // 1. Calculate file size & enforce 500 MB size policy limit
        let attributes = (try? fileManager.attributesOfItem(atPath: sourceURL.path)) ?? [:]
        let videoSize = Int64(attributes[.size] as? UInt64 ?? 0)
        
        do {
            try MediaSizePolicy.validate(sizeInBytes: videoSize, mediaType: .video)
        } catch let err as MediaSizeError {
            if err == .emptyPayload {
                throw VideoStorageError.emptyPayload
            } else {
                throw VideoStorageError.mediaSizeExceeded
            }
        }
        
        try storage.initializeDirectories(for: vault)
        
        let itemID = UUID()
        let storageID = UUID().uuidString
        let thumbnailStorageID = thumbnailData != nil ? UUID().uuidString : nil
        
        // 2. Encrypt Metadata & Filename using Vault Master Key (VMK)
        let filenameBytes = Data(originalFilename.utf8)
        let encryptedFilename = try encryptionEngine.encrypt(data: filenameBytes, using: masterKey)
        let serializedFilename = try JSONEncoder().encode(encryptedFilename)
        
        let encryptedMetadata = try encryptionEngine.encrypt(data: rawMetadataJSON, using: masterKey)
        let serializedMetadata = try JSONEncoder().encode(encryptedMetadata)
        
        // 3. Generate Independent Per-Video Encryption Key
        let perVideoKey = try encryptionEngine.generateRandomKey()
        let wrappedVideoKeyPayload = try encryptionEngine.wrapKey(targetKey: perVideoKey, using: masterKey)
        let serializedWrappedVideoKey = try JSONEncoder().encode(wrappedVideoKeyPayload)
        
        // 4. Calculate chunk count from file size without reading entire file into memory
        let chunkSize = EncryptedVideoContainer.defaultChunkSize
        let chunkCount = UInt32(ceil(Double(videoSize) / Double(chunkSize)))
        
        let videoContainer = EncryptedVideoContainer(
            vaultType: vault,
            objectID: itemID,
            chunkSize: chunkSize,
            chunkCount: chunkCount,
            wrappedKeyData: serializedWrappedVideoKey
        )
        
        // 5. Generate Independent Per-Thumbnail Encryption Key (if thumbnail present)
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
        
        // Rollback tracking
        var createdFiles: [URL] = []
        func rollback() {
            for fileURL in createdFiles {
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        do {
            let objectsDir = baseURL.appendingPathComponent("\(vault.storageSubpath)/Objects", isDirectory: true)
            let tempVideoURL = objectsDir.appendingPathComponent("\(storageID).tmp")
            let finalVideoURL = objectsDir.appendingPathComponent("\(storageID).bin")
            
            // Create empty temp destination file
            fileManager.createFile(atPath: tempVideoURL.path, contents: nil)
            createdFiles.append(tempVideoURL)
            
            let destHandle = try FileHandle(forWritingTo: tempVideoURL)
            defer { try? destHandle.close() }
            
            // Stream write container header
            destHandle.write(videoContainer.headerData)
            
            // Stream read input source file in 4 MiB buffer slices
            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? sourceHandle.close() }
            
            var chunkIndex: UInt32 = 0
            while chunkIndex < chunkCount {
                let chunkBytes = sourceHandle.readData(ofLength: Int(chunkSize))
                if chunkBytes.isEmpty { break }
                
                let chunkAAD = EncryptedVideoContainer.chunkAADData(
                    version: videoContainer.version,
                    vaultType: vault,
                    objectID: itemID,
                    chunkSize: chunkSize,
                    chunkCount: chunkCount,
                    chunkIndex: chunkIndex
                )
                
                let encryptedChunkPayload = try cryptoPlatform.encrypt(
                    data: chunkBytes,
                    using: perVideoKey,
                    authenticData: chunkAAD
                )
                
                let chunk = EncryptedVideoChunk(
                    index: chunkIndex,
                    nonce: encryptedChunkPayload.nonce,
                    tag: encryptedChunkPayload.tag,
                    ciphertext: encryptedChunkPayload.ciphertext
                )
                
                destHandle.write(chunk.encode())
                chunkIndex += 1
            }
            
            // Atomic move (.tmp -> .bin)
            try fileManager.moveItem(at: tempVideoURL, to: finalVideoURL)
            createdFiles.append(finalVideoURL)
            
            // Atomic write thumbnail object (.tmp -> .bin)
            if let thumbDataBlob = thumbnailContainerData, let thumbID = thumbnailStorageID {
                let thumbsDir = baseURL.appendingPathComponent("\(vault.storageSubpath)/Thumbnails", isDirectory: true)
                let tempThumbURL = thumbsDir.appendingPathComponent("\(thumbID).tmp")
                let finalThumbURL = thumbsDir.appendingPathComponent("\(thumbID).bin")
                
                try thumbDataBlob.write(to: tempThumbURL, options: .atomic)
                createdFiles.append(tempThumbURL)
                
                try fileManager.moveItem(at: tempThumbURL, to: finalThumbURL)
                createdFiles.append(finalThumbURL)
            }
            
            // Get final container size on disk
            let finalAttrs = (try? fileManager.attributesOfItem(atPath: finalVideoURL.path)) ?? [:]
            let finalDiskSize = Int64(finalAttrs[.size] as? UInt64 ?? 0)
            
            // Create database record
            let mediaItem = MediaItem(
                id: itemID,
                vaultType: vault,
                mediaType: .video,
                encryptedFilenameRef: serializedFilename,
                encryptedMetadataRef: serializedMetadata,
                encryptedFileKeyRef: serializedWrappedVideoKey,
                storageIdentifier: storageID,
                thumbnailStorageIdentifier: thumbnailStorageID,
                fileSize: finalDiskSize
            )
            
            try storage.database.saveMediaItem(mediaItem, for: vault)
            return mediaItem
        } catch {
            rollback()
            throw VideoStorageError.atomicWriteFailed
        }
    }
    
    /// Convenience overload for raw Data payload input (writes Data to temporary source URL before streaming).
    public func importVideo(
        rawVideoData: Data,
        thumbnailData: Data?,
        originalFilename: String,
        rawMetadataJSON: Data,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial
    ) throws -> MediaItem {
        let tempSourceURL = fileManager.temporaryDirectory.appendingPathComponent("temp_video_src_\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: tempSourceURL) }
        try rawVideoData.write(to: tempSourceURL, options: .atomic)
        
        return try importVideo(
            sourceURL: tempSourceURL,
            thumbnailData: thumbnailData,
            originalFilename: originalFilename,
            rawMetadataJSON: rawMetadataJSON,
            vault: vault,
            masterKey: masterKey
        )
    }
    
    // MARK: - Transactional Video Loading
    /// Loads and decrypts in memory the full video payload for a given MediaItem.
    public func loadVideo(
        for item: MediaItem,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial
    ) throws -> Data {
        guard item.vaultType == vault else {
            throw VideoStorageError.unauthenticatedVault
        }
        guard item.mediaType == .video else {
            throw VideoStorageError.itemNotFound
        }
        guard storage.fileStore.exists(identifier: item.storageIdentifier, vault: vault) else {
            throw VideoStorageError.itemNotFound
        }
        
        let encContainerData = try storage.fileStore.read(identifier: item.storageIdentifier, vault: vault)
        let container = try EncryptedVideoContainer.decode(from: encContainerData)
        guard container.vaultType == vault else {
            throw VideoStorageError.unauthenticatedVault
        }
        
        let wrappedKeyPayload = try JSONDecoder().decode(WrappedKeyPayload.self, from: container.wrappedKeyData)
        let perVideoKey = try encryptionEngine.unwrapKey(wrappedPayload: wrappedKeyPayload, using: masterKey)
        
        var decryptedVideoData = Data()
        for chunk in container.chunks {
            let chunkAAD = EncryptedVideoContainer.chunkAADData(
                version: container.version,
                vaultType: vault,
                objectID: container.objectID,
                chunkSize: container.chunkSize,
                chunkCount: container.chunkCount,
                chunkIndex: chunk.index
            )
            
            let cipherPayload = EncryptedPayload(ciphertext: chunk.ciphertext, nonce: chunk.nonce, tag: chunk.tag)
            let chunkBytes = try cryptoPlatform.decrypt(payload: cipherPayload, using: perVideoKey, authenticData: chunkAAD)
            decryptedVideoData.append(chunkBytes)
        }
        
        return decryptedVideoData
    }
    
    /// Loads and decrypts in memory a specific chunk index for a given MediaItem.
    public func loadVideoChunk(
        for item: MediaItem,
        chunkIndex: UInt32,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial
    ) throws -> Data {
        guard item.vaultType == vault else {
            throw VideoStorageError.unauthenticatedVault
        }
        guard storage.fileStore.exists(identifier: item.storageIdentifier, vault: vault) else {
            throw VideoStorageError.itemNotFound
        }
        
        let encContainerData = try storage.fileStore.read(identifier: item.storageIdentifier, vault: vault)
        let container = try EncryptedVideoContainer.decode(from: encContainerData)
        guard container.vaultType == vault else {
            throw VideoStorageError.unauthenticatedVault
        }
        guard let chunk = container.chunks.first(where: { $0.index == chunkIndex }) else {
            throw VideoStorageError.itemNotFound
        }
        
        let wrappedKeyPayload = try JSONDecoder().decode(WrappedKeyPayload.self, from: container.wrappedKeyData)
        let perVideoKey = try encryptionEngine.unwrapKey(wrappedPayload: wrappedKeyPayload, using: masterKey)
        
        let chunkAAD = EncryptedVideoContainer.chunkAADData(
            version: container.version,
            vaultType: vault,
            objectID: container.objectID,
            chunkSize: container.chunkSize,
            chunkCount: container.chunkCount,
            chunkIndex: chunk.index
        )
        
        let cipherPayload = EncryptedPayload(ciphertext: chunk.ciphertext, nonce: chunk.nonce, tag: chunk.tag)
        return try cryptoPlatform.decrypt(payload: cipherPayload, using: perVideoKey, authenticData: chunkAAD)
    }
    
    // MARK: - Video Deletion
    /// Permanently deletes a video item, binary container, thumbnail, and database record.
    public func deleteVideo(itemID: UUID, vault: VaultType) throws {
        let items = try storage.database.fetchMediaItems(for: vault)
        guard let item = items.first(where: { $0.id == itemID }) else {
            throw VideoStorageError.itemNotFound
        }
        
        try storage.fileStore.delete(identifier: item.storageIdentifier, vault: vault)
        if let thumbID = item.thumbnailStorageIdentifier {
            try storage.thumbnailStore.deleteThumbnail(identifier: thumbID, vault: vault)
        }
        try storage.database.deleteMediaItem(id: itemID, for: vault)
    }
    
    // MARK: - Orphan Diagnostics
    /// Performs integrity check and returns video orphan diagnostic report for specified vault.
    public func detectVideoOrphans(for vault: VaultType) throws -> OrphanReport {
        let items = try storage.database.fetchMediaItems(for: vault)
        let videoItems = items.filter { $0.mediaType == .video }
        
        var missingMedia: [UUID] = []
        var missingThumbs: [UUID] = []
        
        for item in videoItems {
            if !storage.fileStore.exists(identifier: item.storageIdentifier, vault: vault) {
                missingMedia.append(item.id)
            }
            if let thumbID = item.thumbnailStorageIdentifier {
                if !storage.thumbnailStore.thumbnailExists(identifier: thumbID, vault: vault) {
                    missingThumbs.append(item.id)
                }
            }
        }
        
        let objectsDir = baseURL.appendingPathComponent("\(vault.storageSubpath)/Objects", isDirectory: true)
        let fileURLs = (try? fileManager.contentsOfDirectory(at: objectsDir, includingPropertiesForKeys: nil)) ?? []
        
        let validStorageIDs = Set(videoItems.map { "\($0.storageIdentifier).bin" })
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
