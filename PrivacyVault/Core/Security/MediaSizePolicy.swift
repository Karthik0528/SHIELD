import Foundation

public enum MediaSizeError: Error, Equatable, Sendable {
    case emptyPayload
    case exceedsLimit(mediaType: MediaType)
    
    public var title: String {
        switch self {
        case .emptyPayload:
            return "Unable to import media"
        case .exceedsLimit(let type):
            return type == .video ? "Video size not supported" : "Media too large"
        }
    }
    
    public var userFacingMessage: String {
        switch self {
        case .emptyPayload:
            return "Media payload is empty."
        case .exceedsLimit(let type):
            return type == .video
                ? "This video exceeds the 500 MB limit."
                : "Photos and videos larger than 500 MB aren't supported."
        }
    }
}

/// Centralized policy validator enforcing maximum individual media size limits (500 MB).
public struct MediaSizePolicy: Sendable {
    /// Permanent project maximum individual media size limit: 500 MB (524,288,000 bytes).
    public static let maxMediaSizeBytes: Int64 = 500 * 1024 * 1024
    
    public init() {}
    
    /// Validates media payload size against the 500 MB limit before encryption or disk persistence.
    public static func validate(sizeInBytes: Int64, mediaType: MediaType) throws {
        guard sizeInBytes > 0 else {
            throw MediaSizeError.emptyPayload
        }
        guard sizeInBytes <= maxMediaSizeBytes else {
            throw MediaSizeError.exceedsLimit(mediaType: mediaType)
        }
    }
}
