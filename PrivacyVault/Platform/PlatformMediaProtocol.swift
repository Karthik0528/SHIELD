import Foundation

public struct UnencryptedMediaImportPayload: Sendable {
    public let filename: String
    public let mediaType: MediaType
    public let rawBytes: Data
    public let thumbnailBytes: Data?
}

/// Platform contract abstraction for Photos / PhotosUI iOS integration.
public protocol PlatformMediaProtocol: Sendable {
    func requestPhotoLibraryPermission() async -> Bool
    func exportMedia(data: Data, filename: String, type: MediaType) async throws -> Bool
}

public enum PlatformMediaError: Error, Equatable, Sendable {
    case permissionDenied
    case exportFailed
}

/// Development placeholder for non-iOS environment.
public final class DefaultPlatformMedia: PlatformMediaProtocol {
    public init() {}
    
    public func requestPhotoLibraryPermission() async -> Bool {
        #if canImport(Photos) && os(iOS)
        // PHPhotoLibrary requestAuthorization placeholder
        return false
        #else
        return false
        #endif
    }
    
    public func exportMedia(data: Data, filename: String, type: MediaType) async throws -> Bool {
        #if canImport(Photos) && os(iOS)
        // PHPhotoLibrary export placeholder
        throw PlatformMediaError.exportFailed
        #else
        throw PlatformMediaError.exportFailed
        #endif
    }
}
