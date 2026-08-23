import Foundation

/// Represents an encrypted album collection record inside the vault metadata database.
public struct Album: Identifiable, Codable, Sendable {
    public let id: UUID
    public let vaultType: VaultType
    
    /// Encrypted payload containing the album display title.
    public let encryptedName: Data
    
    /// Album creation date.
    public let createdDate: Date
    
    public init(
        id: UUID = UUID(),
        vaultType: VaultType,
        encryptedName: Data,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.vaultType = vaultType
        self.encryptedName = encryptedName
        self.createdDate = createdDate
    }
}
