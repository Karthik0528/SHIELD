import Foundation

/// Encrypted video chunk structure.
public struct EncryptedVideoChunk: Sendable {
    public let index: UInt32
    public let nonce: Data
    public let tag: Data
    public let ciphertext: Data
    
    public init(index: UInt32, nonce: Data, tag: Data, ciphertext: Data) {
        self.index = index
        self.nonce = nonce
        self.tag = tag
        self.ciphertext = ciphertext
    }
    
    /// Encodes a single encrypted chunk into binary Data bytes.
    public func encode() -> Data {
        var data = Data()
        let nonceLen = UInt8(nonce.count)
        data.append(nonceLen)
        data.append(nonce)
        
        let tagLen = UInt8(tag.count)
        data.append(tagLen)
        data.append(tag)
        
        let cipherLen = UInt32(ciphertext.count)
        withUnsafeBytes(of: cipherLen.bigEndian) { data.append(contentsOf: $0) }
        data.append(ciphertext)
        return data
    }
}

/// Versioned binary container (`PVV1`) holding chunked AES-GCM encrypted video data,
/// per-chunk authenticated additional data (AAD) binding, nonces, tags, and VMK-wrapped per-video key.
public struct EncryptedVideoContainer: Sendable {
    public static let magicHeader = Data([0x50, 0x56, 0x56, 0x31]) // "PVV1"
    public static let currentVersion: UInt8 = 1
    public static let defaultChunkSize: UInt32 = 4 * 1024 * 1024 // 4 MiB
    
    public let version: UInt8
    public let objectType: ObjectType
    public let vaultType: VaultType
    public let objectID: UUID
    public let chunkSize: UInt32
    public let chunkCount: UInt32
    public let wrappedKeyData: Data
    public let chunks: [EncryptedVideoChunk]
    
    public init(
        version: UInt8 = EncryptedVideoContainer.currentVersion,
        vaultType: VaultType,
        objectID: UUID = UUID(),
        chunkSize: UInt32 = EncryptedVideoContainer.defaultChunkSize,
        chunkCount: UInt32,
        wrappedKeyData: Data,
        chunks: [EncryptedVideoChunk] = []
    ) {
        self.version = version
        self.objectType = .media
        self.vaultType = vaultType
        self.objectID = objectID
        self.chunkSize = chunkSize
        self.chunkCount = chunkCount
        self.wrappedKeyData = wrappedKeyData
        self.chunks = chunks
    }
    
    /// Computes Authenticated Additional Data (AAD) binding for chunk index `chunkIndex`.
    /// Authenticates magic ("PVV1"), version (1), objectType (media 0x01), vaultType (0x01/0x02), objectID (UUID), chunkSize, chunkCount, and chunkIndex.
    public static func chunkAADData(
        version: UInt8 = EncryptedVideoContainer.currentVersion,
        vaultType: VaultType,
        objectID: UUID,
        chunkSize: UInt32,
        chunkCount: UInt32,
        chunkIndex: UInt32
    ) -> Data {
        var data = Data()
        data.append(EncryptedVideoContainer.magicHeader)
        data.append(version)
        data.append(ObjectType.media.rawValue)
        data.append(vaultType == .main ? 0x01 : 0x02)
        withUnsafeBytes(of: objectID.uuid) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: chunkSize.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: chunkCount.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: chunkIndex.bigEndian) { data.append(contentsOf: $0) }
        return data
    }
    
    /// Returns binary header Data blob (magic, version, objectType, vaultType, objectID, chunkSize, chunkCount, wrappedKeyLen, wrappedKeyData).
    public var headerData: Data {
        var data = Data()
        data.append(EncryptedVideoContainer.magicHeader)
        data.append(version)
        data.append(ObjectType.media.rawValue)
        data.append(vaultType == .main ? 0x01 : 0x02)
        withUnsafeBytes(of: objectID.uuid) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: chunkSize.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: chunkCount.bigEndian) { data.append(contentsOf: $0) }
        
        let wrappedKeyLen = UInt16(wrappedKeyData.count)
        withUnsafeBytes(of: wrappedKeyLen.bigEndian) { data.append(contentsOf: $0) }
        data.append(wrappedKeyData)
        return data
    }
    
    /// Encodes container header and all encrypted chunks into a binary Data blob.
    public func encode() throws -> Data {
        var data = headerData
        for chunk in chunks {
            data.append(chunk.encode())
        }
        return data
    }
    
    /// Deserializes a binary Data blob into an `EncryptedVideoContainer`.
    public static func decode(from data: Data) throws -> EncryptedVideoContainer {
        guard data.count >= 33 else {
            throw ObjectFormatError.invalidDataLength
        }
        
        let magic = data.subdata(in: 0..<4)
        guard magic == EncryptedVideoContainer.magicHeader else {
            throw ObjectFormatError.invalidMagicHeader
        }
        
        let version = data[4]
        guard version == EncryptedVideoContainer.currentVersion else {
            throw ObjectFormatError.unsupportedVersion
        }
        
        let vaultRaw = data[6]
        let vaultType: VaultType = (vaultRaw == 0x01) ? .main : .decoy
        
        let uuidData = data.subdata(in: 7..<23)
        let uuidTuple: uuid_t = uuidData.withUnsafeBytes { $0.load(as: uuid_t.self) }
        let objectID = UUID(uuid: uuidTuple)
        
        let chunkSize = UInt32(bigEndian: data.subdata(in: 23..<27).withUnsafeBytes { $0.load(as: UInt32.self) })
        let chunkCount = UInt32(bigEndian: data.subdata(in: 27..<31).withUnsafeBytes { $0.load(as: UInt32.self) })
        
        let wrappedKeyLen = UInt16(bigEndian: data.subdata(in: 31..<33).withUnsafeBytes { $0.load(as: UInt16.self) })
        var offset = 33
        
        guard data.count >= offset + Int(wrappedKeyLen) else {
            throw ObjectFormatError.invalidDataLength
        }
        let wrappedKeyData = data.subdata(in: offset..<offset+Int(wrappedKeyLen))
        offset += Int(wrappedKeyLen)
        
        var chunks: [EncryptedVideoChunk] = []
        for i in 0..<chunkCount {
            guard data.count >= offset + 1 else {
                throw ObjectFormatError.invalidDataLength
            }
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
            offset += Int(cipherLen)
            
            chunks.append(EncryptedVideoChunk(index: i, nonce: nonce, tag: tag, ciphertext: ciphertext))
        }
        
        return EncryptedVideoContainer(
            version: version,
            vaultType: vaultType,
            objectID: objectID,
            chunkSize: chunkSize,
            chunkCount: chunkCount,
            wrappedKeyData: wrappedKeyData,
            chunks: chunks
        )
    }
}
