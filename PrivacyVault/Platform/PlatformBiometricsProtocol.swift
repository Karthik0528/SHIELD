import Foundation

public enum BiometricType: String, Sendable {
    case faceID
    case touchID
    case none
}

/// Platform contract abstraction for LocalAuthentication (`LAContext`).
public protocol PlatformBiometricsProtocol: Sendable {
    func evaluateBiometrics(reason: String) async throws -> Bool
    func availableBiometricType() -> BiometricType
}

public enum BiometricsError: Error, Equatable, Sendable {
    case notAvailable
    case userCancelled
    case authenticationFailed
}

/// Development placeholder for non-iOS environment.
public final class DefaultPlatformBiometrics: PlatformBiometricsProtocol {
    public init() {}
    
    public func evaluateBiometrics(reason: String) async throws -> Bool {
        #if canImport(LocalAuthentication) && os(iOS)
        // iOS LAContext evaluatePolicy implementation placeholder
        throw BiometricsError.notAvailable
        #else
        throw BiometricsError.notAvailable
        #endif
    }
    
    public func availableBiometricType() -> BiometricType {
        #if canImport(LocalAuthentication) && os(iOS)
        // iOS LAContext biometryType evaluation
        return .none
        #else
        return .none
        #endif
    }
}
