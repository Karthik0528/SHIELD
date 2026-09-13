import Foundation
#if canImport(Photos)
import Photos
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

public enum MediaImportExportError: Error, Equatable, Sendable {
    case unauthenticatedVault
    case mediaSizeExceeded(mediaType: MediaType)
    case duplicateDetected
    case invalidMediaFormat
    case importCancelled
    case importFailed
    case exportFailed
    case permissionDenied
    case unsupportedPlatform
    
    public var userFacingMessage: String {
        switch self {
        case .duplicateDetected:
            return "Photo already exists in SHIELD."
        case .mediaSizeExceeded(let mediaType):
            return mediaType == .video
                ? "Video size not supported. This video exceeds the 500 MB limit."
                : "Photo size not supported. This photo exceeds the 500 MB limit."
        case .unauthenticatedVault:
            return "Vault session expired. Please unlock vault."
        case .importCancelled:
            return "Import cancelled."
        case .permissionDenied:
            return "Photos library access permission required."
        default:
            return "Unable to process request."
        }
    }
}

/// Centralized service connecting native iOS Photos / PhotosUI import and export
/// to the frozen secure photo and video storage engines.
///
/// **Key Invariants**:
/// 1. Import/Export strictly uses COPY semantics. User original Photos library media is NEVER modified or deleted.
/// 2. Active vault is derived exclusively from `vaultManager.session.activeVaultType`.
/// 3. Centralized 500 MB `MediaSizePolicy` is enforced prior to encryption or disk persistence.
/// 4. Videos use file URL streaming paths without loading complete videos into memory.
/// 5. Zero persistent plaintext export files are saved inside PrivacyVault sandbox.
public final class MediaImportExportService: ObservableObject, @unchecked Sendable {
    private let videoEngine: VideoStorageEngine
    private let photoService: PhotoImportService
    private let storageEngine: EncryptedMediaStorageEngine
    
    @Published public var importProgress: Double = 0.0
    @Published public var importStatusMessage: String = ""
    @Published public var isProcessing: Bool = false
    
    public init(
        videoEngine: VideoStorageEngine = VideoStorageEngine(),
        photoService: PhotoImportService = PhotoImportService(),
        storageEngine: EncryptedMediaStorageEngine = EncryptedMediaStorageEngine()
    ) {
        self.videoEngine = videoEngine
        self.photoService = photoService
        self.storageEngine = storageEngine
    }
    
    // MARK: - Import Video from Local Source File URL
    /// Encrypts and imports a video source file URL into the active vault using chunked streaming (PVV1).
    public func importVideoFile(
        sourceURL: URL,
        originalFilename: String,
        vaultManager: VaultManager
    ) async throws -> MediaItem {
        guard let vault = vaultManager.session.activeVaultType,
              let masterKey = vaultManager.session.activeMasterKey else {
            throw MediaImportExportError.unauthenticatedVault
        }
        
        let attributes = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)) ?? [:]
        let fileSize = Int64(attributes[.size] as? UInt64 ?? 0)
        
        // 1. Enforce 500 MB size limit
        do {
            try MediaSizePolicy.validate(sizeInBytes: fileSize, mediaType: .video)
        } catch {
            throw MediaImportExportError.mediaSizeExceeded(mediaType: .video)
        }
        
        // 2. Extract metadata & generate thumbnail via AVFoundation
        var thumbnailBytes: Data? = nil
        var metadataJSON = Data("{}".utf8)
        
        #if canImport(AVFoundation)
        let asset = AVAsset(url: sourceURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 320, height: 320)
        
        if let cgImage = try? imageGenerator.copyCGImage(at: .zero, actualTime: nil) {
            #if canImport(UIKit)
            let uiImage = UIImage(cgImage: cgImage)
            thumbnailBytes = uiImage.jpegData(compressionQuality: 0.7)
            #endif
        }
        
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let metadataDict: [String: Any] = [
            "duration": durationSeconds,
            "filename": originalFilename,
            "createdDate": ISO8601DateFormatter().string(from: Date())
        ]
        metadataJSON = (try? JSONSerialization.data(withJSONObject: metadataDict)) ?? Data("{}".utf8)
        #endif
        
        // 3. Execute streaming encryption into vault
        let item = try videoEngine.importVideo(
            sourceURL: sourceURL,
            thumbnailData: thumbnailBytes,
            originalFilename: originalFilename,
            rawMetadataJSON: metadataJSON,
            vault: vault,
            masterKey: masterKey
        )
        
        vaultManager.session.recordActivity()
        return item
    }
    
    // MARK: - Import Photo from Raw Data
    /// Encrypts and imports raw photo bytes into the active vault via 17-stage PhotoImportService.
    public func importPhotoBytes(
        rawImageData: Data,
        originalFilename: String,
        vaultManager: VaultManager
    ) throws -> MediaItem {
        guard let vault = vaultManager.session.activeVaultType,
              let masterKey = vaultManager.session.activeMasterKey else {
            throw MediaImportExportError.unauthenticatedVault
        }
        
        // 1. Enforce 500 MB size limit
        do {
            try MediaSizePolicy.validate(sizeInBytes: Int64(rawImageData.count), mediaType: .photo)
        } catch {
            throw MediaImportExportError.mediaSizeExceeded(mediaType: .photo)
        }
        
        // 2. Execute photo import pipeline
        do {
            let item = try photoService.importPhoto(
                rawImageData: rawImageData,
                originalFilename: originalFilename,
                into: vault,
                masterKey: masterKey
            )
            
            vaultManager.session.recordActivity()
            return item
        } catch PhotoImportError.duplicateDetected {
            throw MediaImportExportError.duplicateDetected
        } catch {
            throw MediaImportExportError.importFailed
        }
    }
    
    // MARK: - Export Single Item to iOS Photos Library
    /// Decrypts a vault media item using chunked streaming for videos and exports a copy to the native iOS Photos library.
    /// Strictly COPY semantics: Encrypted vault media item is NEVER modified or deleted.
    public func exportMediaItem(
        _ item: MediaItem,
        vaultManager: VaultManager
    ) async throws {
        guard let vault = vaultManager.session.activeVaultType,
              let masterKey = vaultManager.session.activeMasterKey,
              item.vaultType == vault else {
            throw MediaImportExportError.unauthenticatedVault
        }
        
        vaultManager.session.recordActivity()
        
        if item.mediaType == .photo {
            let decryptedData = try storageEngine.loadMedia(for: item, vault: vault, masterKey: masterKey)
            
            #if canImport(Photos) && canImport(UIKit)
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                throw MediaImportExportError.permissionDenied
            }
            
            if let image = UIImage(data: decryptedData) {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } else {
                throw MediaImportExportError.exportFailed
            }
            #else
            throw MediaImportExportError.unsupportedPlatform
            #endif
        } else {
            #if canImport(Photos)
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                throw MediaImportExportError.permissionDenied
            }
            
            let tempDir = FileManager.default.temporaryDirectory
            let tempExportURL = tempDir.appendingPathComponent("export_vid_\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: tempExportURL) }
            
            let streamingExportService = StreamingVideoExportService()
            do {
                try streamingExportService.exportVideoToTempFile(
                    for: item,
                    vault: vault,
                    masterKey: masterKey,
                    destinationURL: tempExportURL
                )
            } catch {
                throw MediaImportExportError.exportFailed
            }
            
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempExportURL)
            }
            #else
            throw MediaImportExportError.unsupportedPlatform
            #endif
        }
    }
    
    // MARK: - Export Multiple Items to iOS Photos Library
    /// Exports multiple selected vault media items to the native iOS Photos library item by item.
    public func exportMultipleItems(
        _ items: [MediaItem],
        vaultManager: VaultManager
    ) async throws -> Int {
        var exportedCount = 0
        for item in items {
            do {
                try await exportMediaItem(item, vaultManager: vaultManager)
                exportedCount += 1
            } catch {
                // Multi-select export skips failed item and continues
            }
        }
        return exportedCount
    }
}
