import Foundation

public enum ObjectType: UInt8, Codable, Sendable {
    case media = 0x01
    case thumbnail = 0x02
    case metadata = 0x03
}

public enum ObjectFormatError: Error, Equatable, Sendable {
    case invalidMagicHeader
    case unsupportedVersion
    case invalidDataLength
    case serializationFailed
    case deserializationFailed
}

/// Represents a versioned binary container (`PV01`) holding an encrypted payload, its nonce, authentication tag,
/// and VMK-wrapped per-object key.
public struct EncryptedObjectContainer: Sendable {
    public static let magicHeader = Data([0x50, 0x56, 0x30, 0x31]) // "PV01"
    public static let currentVersion: UInt8 = 1
    
    public let version: UInt8
    public let objectType: ObjectType
    public let vaultType: VaultType
    public let objectID: UUID
    
    /// Per-item encryption key wrapped by the Vault Master Key (VMK).
    public let wrappedKeyData: Data
    
    /// AES-GCM IV / Nonce (12 bytes).
    public let nonce: Data
    
    /// AES-GCM Authentication Tag (16 bytes).
    public let tag: Data
    
    /// Encrypted media or thumbnail payload.
    public let ciphertext: Data
    
    public init(
        version: UInt8 = EncryptedObjectContainer.currentVersion,
        objectType: ObjectType,
        vaultType: VaultType,
        objectID: UUID = UUID(),
        wrappedKeyData: Data,
        nonce: Data,
        tag: Data,
        ciphertext: Data
    ) {
        self.version = version
        self.objectType = objectType
        self.vaultType = vaultType
        self.objectID = objectID
        self.wrappedKeyData = wrappedKeyData
        self.nonce = nonce
        self.tag = tag
        self.ciphertext = ciphertext
    }
    
    /// Computes Authenticated Additional Data (AAD) binding for encryption context.
    public var aadData: Data {
        var data = Data()
        data.append(contentsOf: [0x50, 0x56, 0x30, 0x31]) // Magic
        data.append(version)
        data.append(objectType.rawValue)
        data.append(vaultType == .main ? 0x01 : 0x02)
        withUnsafeBytes(of: objectID.uuid) { data.append(contentsOf: $0) }
        return data
    }
    
    /// Serializes the container into a binary Data blob.
    public func encode() throws -> Data {
        var data = Data()
        data.append(EncryptedObjectContainer.magicHeader)
        data.append(version)
        data.append(objectType.rawValue)
        data.append(vaultType == .main ? 0x01 : 0x02)
        
        withUnsafeBytes(of: objectID.uuid) { data.append(contentsOf: $0) }
        
        let wrappedKeyLength = UInt16(wrappedKeyData.count)
        withUnsafeBytes(of: wrappedKeyLength.bigEndian) { data.append(contentsOf: $0) }
        data.append(wrappedKeyData)
        
        let nonceLength = UInt8(nonce.count)
        data.append(nonceLength)
        data.append(nonce)
        
        let tagLength = UInt8(tag.count)
        data.append(tagLength)
        data.append(tag)
        
        let ciphertextLength = UInt32(ciphertext.count)
        withUnsafeBytes(of: ciphertextLength.bigEndian) { data.append(contentsOf: $0) }
        data.append(ciphertext)
        
        return data
    }
    
    /// Deserializes a binary Data blob into an `EncryptedObjectContainer`.
    public static func decode(from data: Data) throws -> EncryptedObjectContainer {
        guard data.count >= 36 else {
            throw ObjectFormatError.invalidDataLength
        }
        
        let magic = data.subdata(in: 0..<4)
        guard magic == EncryptedObjectContainer.magicHeader else {
            throw ObjectFormatError.invalidMagicHeader
        }
        
        let version = data[4]
        guard version == EncryptedObjectContainer.currentVersion else {
            throw ObjectFormatError.unsupportedVersion
        }
        
        guard let objectType = ObjectType(rawValue: data[5]) else {
            throw ObjectFormatError.deserializationFailed
        }
        
        let vaultRaw = data[6]
        let vaultType: VaultType = (vaultRaw == 0x01) ? .main : .decoy
        
        let uuidData = data.subdata(in: 7..<23)
        let uuidTuple: uuid_t = uuidData.withUnsafeBytes { $0.load(as: uuid_t.self) }
        let objectID = UUID(uuid: uuidTuple)
        
        var offset = 23
        
        let wrappedKeyLen = UInt16(bigEndian: data.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self) })
        offset += 2
        
        guard data.count >= offset + Int(wrappedKeyLen) + 1 else {
            throw ObjectFormatError.invalidDataLength
        }
        let wrappedKeyData = data.subdata(in: offset..<offset+Int(wrappedKeyLen))
        offset += Int(wrappedKeyLen)
        
        let nonceLen = Int(data[offset])
        offset += 1
        
        guard data.count >= offset + nonceLen + 1 else {
            throw ObjectFormatError.invalidDataLength
        }
        let nonce = data.subdata(in: offset..<offset+nonceLen)
        offset += nonceLen
        
        let tagLen = Int(data[offset])
        offset += 1
        
        guard data.count >= offset + tagLen + 4 else {
            throw ObjectFormatError.invalidDataLength
        }
        let tag = data.subdata(in: offset..<offset+tagLen)
        offset += tagLen
        
        let cipherLen = UInt32(bigEndian: data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) })
        offset += 4
        
        guard data.count >= offset + Int(cipherLen) else {
            throw ObjectFormatError.invalidDataLength
        }
        let ciphertext = data.subdata(in: offset..<offset+Int(cipherLen))
        
        return EncryptedObjectContainer(
            version: version,
            objectType: objectType,
            vaultType: vaultType,
            objectID: objectID,
            wrappedKeyData: wrappedKeyData,
            nonce: nonce,
            tag: tag,
            ciphertext: ciphertext
        )
    }
}
