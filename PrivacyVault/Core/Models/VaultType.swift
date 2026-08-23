import Foundation

/// Represents the two cryptographically isolated vault domains.
public enum VaultType: String, Codable, CaseIterable, Identifiable, Sendable {
    case main
    case decoy
    
    public var id: String { rawValue }
    
    /// Storage directory subpath for this vault instance.
    public var storageSubpath: String {
        switch self {
        case .main:
            return "Vaults/Main"
        case .decoy:
            return "Vaults/Decoy"
        }
    }
    
    /// Descriptive title for logging / debugging (without exposing sensitivity).
    public var debugName: String {
        switch self {
        case .main:
            return "Main Vault Domain"
        case .decoy:
            return "Decoy Vault Domain"
        }
    }
}
