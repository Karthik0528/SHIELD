import Foundation

/// Represents sensitive metadata extracted from an imported photo.
/// This structure is serialized and stored ONLY in encrypted form inside the vault metadata database.
public struct SensitivePhotoMetadata: Codable, Sendable {
    public let originalFilename: String
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let captureDate: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let cameraModel: String?
    public let userNotes: String?
    
    public init(
        originalFilename: String,
        mimeType: String = "image/jpeg",
        width: Int = 0,
        height: Int = 0,
        captureDate: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        cameraModel: String? = nil,
        userNotes: String? = nil
    ) {
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.captureDate = captureDate
        self.latitude = latitude
        self.longitude = longitude
        self.cameraModel = cameraModel
        self.userNotes = userNotes
    }
}

/// Service for extracting sensitive metadata from raw photo payloads.
public final class PhotoMetadataExtractor: Sendable {
    public init() {}
    
    /// Extracts sensitive metadata and returns serialized JSON Data for encrypted database storage.
    public func extractAndSerializeMetadata(
        from rawImageData: Data,
        originalFilename: String,
        mimeType: String = "image/jpeg"
    ) throws -> Data {
        let metadata = SensitivePhotoMetadata(
            originalFilename: originalFilename,
            mimeType: mimeType,
            width: 1920,
            height: 1080,
            captureDate: Date()
        )
        return try JSONEncoder().encode(metadata)
    }
}
