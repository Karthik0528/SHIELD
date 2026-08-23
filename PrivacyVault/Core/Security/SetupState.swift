import Foundation

/// Represents the overall setup configuration state of the application.
public enum SetupState: String, Codable, Sendable, Equatable {
    /// Neither Main nor Decoy vaults have been configured.
    case unconfigured
    
    /// Setup process was interrupted or incomplete.
    case incomplete
    
    /// Both Main and Decoy vaults have been successfully configured.
    case configured
}
