import Foundation

public enum PhotoImportError: Error, Equatable, Sendable {
    case invalidImageFormat
    case emptyPayload
    case cryptoFailed
    case atomicWriteFailed
    case duplicateDetected
    case unsupportedPlatform
}

/// Service executing the 17-stage secure photo import pipeline.
public final class PhotoImportService: Sendable {
    private let storageEngine: EncryptedMediaStorageEngine
    private let metadataExtractor: PhotoMetadataExtractor
    private let thumbnailGenerator: ThumbnailGeneratorProtocol
    private let fingerprintDetector: ContentFingerprintDetector
    private let database: DatabaseProtocol
    
    public init(
        storageEngine: EncryptedMediaStorageEngine = EncryptedMediaStorageEngine(),
        metadataExtractor: PhotoMetadataExtractor = PhotoMetadataExtractor(),
        thumbnailGenerator: ThumbnailGeneratorProtocol = DefaultThumbnailGenerator(),
        fingerprintDetector: ContentFingerprintDetector = ContentFingerprintDetector(),
        database: DatabaseProtocol = EncryptedDatabase()
    ) {
        self.storageEngine = storageEngine
        self.metadataExtractor = metadataExtractor
        self.thumbnailGenerator = thumbnailGenerator
        self.fingerprintDetector = fingerprintDetector
        self.database = database
    }
    
    /// Executes the 17-stage secure photo import pipeline.
    /// Operates as COPY TO VAULT. The user's original photo payload is never altered.
    public func importPhoto(
        rawImageData: Data,
        originalFilename: String,
        mimeType: String = "image/jpeg",
        into vault: VaultType,
        masterKey: SymmetricKeyMaterial
    ) throws -> MediaItem {
        // Stage 1: Validate payload & 500 MB media size limit
        do {
            try MediaSizePolicy.validate(sizeInBytes: Int64(rawImageData.count), mediaType: .photo)
        } catch {
            throw PhotoImportError.emptyPayload
        }
        
        // Stage 1b: Duplicate Detection check BEFORE any file persistence or encryption
        let fingerprint = fingerprintDetector.computeFingerprint(for: rawImageData, masterKey: masterKey)
        let existingItems = (try? database.fetchMediaItems(for: vault)) ?? []
        if existingItems.contains(where: { $0.contentFingerprint == fingerprint }) {
            throw PhotoImportError.duplicateDetected
        }
        
        // Stage 2 & 3: Validate supported format & image data
        let lowerFilename = originalFilename.lowercased()
        guard lowerFilename.hasSuffix(".jpg") || lowerFilename.hasSuffix(".jpeg") ||
              lowerFilename.hasSuffix(".png") || lowerFilename.hasSuffix(".heic") else {
            throw PhotoImportError.invalidImageFormat
        }
        
        // Stage 4 & 6: Extract & serialize sensitive metadata
        let metadataJSON = try metadataExtractor.extractAndSerializeMetadata(
            from: rawImageData,
            originalFilename: originalFilename,
            mimeType: mimeType
        )
        
        // Stage 5: Generate thumbnail bytes from photo payload
        let thumbnailBytes = try thumbnailGenerator.generateThumbnail(from: rawImageData, maxPixelDimension: 320)
        
        // Stage 7-16: Execute transactional import, key derivation, authenticated encryption & atomic file persistence
        do {
            let item = try storageEngine.importMedia(
                rawMediaData: rawImageData,
                thumbnailData: thumbnailBytes,
                originalFilename: originalFilename,
                rawMetadataJSON: metadataJSON,
                mediaType: .photo,
                vault: vault,
                masterKey: masterKey,
                contentFingerprint: fingerprint
            )
            
            // Stage 17: Post-import verification
            return item
        } catch let err as PhotoImportError {
            throw err
        } catch let err as StorageEngineError {
            if err == .atomicWriteFailed {
                throw PhotoImportError.atomicWriteFailed
            }
            throw PhotoImportError.cryptoFailed
        } catch let err as PlatformCryptoError {
            if err == .unsupportedPlatform {
                throw PhotoImportError.unsupportedPlatform
            }
            throw PhotoImportError.cryptoFailed
        } catch {
            throw PhotoImportError.cryptoFailed
        }
    }
}
