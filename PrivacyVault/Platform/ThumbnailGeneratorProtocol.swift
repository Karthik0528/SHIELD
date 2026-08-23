import Foundation

public enum ThumbnailGeneratorError: Error, Equatable, Sendable {
    case invalidImageData
    case generationFailed
    case unsupportedPlatform
}

/// Abstract contract for generating downscaled thumbnail image bytes from raw photo payloads.
public protocol ThumbnailGeneratorProtocol: Sendable {
    func generateThumbnail(from rawImageData: Data, maxPixelDimension: Int) throws -> Data
}

/// Development implementation for thumbnail generation.
/// Uses native image APIs when available on iOS/macOS, or safe stub on non-iOS platforms.
public final class DefaultThumbnailGenerator: ThumbnailGeneratorProtocol {
    public init() {}
    
    public func generateThumbnail(from rawImageData: Data, maxPixelDimension: Int = 320) throws -> Data {
        #if canImport(CoreGraphics) && canImport(ImageIO)
        // iOS/macOS CGImageSource thumbnail generation placeholder
        guard !rawImageData.isEmpty else {
            throw ThumbnailGeneratorError.invalidImageData
        }
        return rawImageData.prefix(1024) // Placeholder slice for native environment
        #else
        // Safe fallback stub on non-iOS platform
        guard !rawImageData.isEmpty else {
            throw ThumbnailGeneratorError.invalidImageData
        }
        return rawImageData.prefix(min(512, rawImageData.count))
        #endif
    }
}
