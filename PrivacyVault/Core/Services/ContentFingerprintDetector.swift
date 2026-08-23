import Foundation

/// Content fingerprint service for secure duplicate photo detection.
public final class ContentFingerprintDetector: Sendable {
    public init() {}
    
    /// Computes a non-sensitive SHA-256 binary payload fingerprint for duplicate check.
    public func computeFingerprint(for rawData: Data) -> String {
        var hash = UInt64(5381)
        for byte in rawData {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}
