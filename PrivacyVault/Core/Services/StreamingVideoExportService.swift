import Foundation

public enum StreamingExportError: Error, Equatable, Sendable {
    case unauthenticatedVault
    case itemNotFound
    case invalidContainerHeader
    case authenticationFailed
    case exportFailed
    case cancellation
}

/// Service executing chunked streaming AES-GCM video decryption into protected temporary sandbox export files.
///
/// **Bounded Memory Guarantee**:
/// At no point does a 500 MB video exist in RAM as a single Data object or chunk array.
/// Reads 4 MiB encrypted chunks from disk via FileHandle, authenticates and decrypts each chunk
/// in memory, writes plaintext chunk directly to destination FileHandle, and releases chunk memory.
public final class StreamingVideoExportService: Sendable {
    private let fileManager: FileManager
    private let cryptoPlatform: PlatformCryptoProtocol
    private let encryptionEngine: EncryptionEngineProtocol
    private let baseURL: URL
    
    public init(
        fileManager: FileManager = .default,
        cryptoPlatform: PlatformCryptoProtocol = DefaultPlatformCrypto(),
        encryptionEngine: EncryptionEngineProtocol = DefaultEncryptionEngine(),
        baseURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.cryptoPlatform = cryptoPlatform
        self.encryptionEngine = encryptionEngine
        self.baseURL = baseURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    /// Streams chunked AES-GCM decryption of a vault video item to a temporary destination export URL.
    /// RAM footprint is strictly bounded to the active 4 MiB chunk slice during decryption.
    public func exportVideoToTempFile(
        for item: MediaItem,
        vault: VaultType,
        masterKey: SymmetricKeyMaterial,
        destinationURL: URL
    ) throws {
        guard item.vaultType == vault else {
            throw StreamingExportError.unauthenticatedVault
        }
        guard item.mediaType == .video else {
            throw StreamingExportError.itemNotFound
        }
        
        let containerPath = baseURL
            .appendingPathComponent("\(vault.storageSubpath)/Objects/\(item.storageIdentifier).bin").path
        
        guard fileManager.fileExists(atPath: containerPath) else {
            throw StreamingExportError.itemNotFound
        }
        
        let containerURL = URL(fileURLWithPath: containerPath)
        let sourceHandle = try FileHandle(forReadingFrom: containerURL)
        defer { try? sourceHandle.close() }
        
        // 1. Read binary header prefix (magic 4 + ver 1 + obj 1 + vault 1 + uuid 16 + chunkSize 4 + chunkCount 4 + wrappedKeyLen 2 = 33 bytes)
        let headerPrefix = sourceHandle.readData(ofLength: 33)
        guard headerPrefix.count == 33 else {
            throw StreamingExportError.invalidContainerHeader
        }
        
        let magic = headerPrefix.subdata(in: 0..<4)
        guard magic == EncryptedVideoContainer.magicHeader else {
            throw StreamingExportError.invalidContainerHeader
        }
        
        let version = headerPrefix[4]
        guard version == EncryptedVideoContainer.currentVersion else {
            throw StreamingExportError.invalidContainerHeader
        }
        
        let vaultRaw = headerPrefix[6]
        let headerVault: VaultType = (vaultRaw == 0x01) ? .main : .decoy
        guard headerVault == vault else {
            throw StreamingExportError.unauthenticatedVault
        }
        
        let uuidData = headerPrefix.subdata(in: 7..<23)
        let uuidTuple: uuid_t = uuidData.withUnsafeBytes { $0.load(as: uuid_t.self) }
        let objectID = UUID(uuid: uuidTuple)
        
        let chunkSize = UInt32(bigEndian: headerPrefix.subdata(in: 23..<27).withUnsafeBytes { $0.load(as: UInt32.self) })
        let chunkCount = UInt32(bigEndian: headerPrefix.subdata(in: 27..<31).withUnsafeBytes { $0.load(as: UInt32.self) })
        let wrappedKeyLen = Int(UInt16(bigEndian: headerPrefix.subdata(in: 31..<33).withUnsafeBytes { $0.load(as: UInt16.self) }))
        
        let wrappedKeyData = sourceHandle.readData(ofLength: wrappedKeyLen)
        guard wrappedKeyData.count == wrappedKeyLen else {
            throw StreamingExportError.invalidContainerHeader
        }
        
        // 2. Unwrap per-video key using active vault VMK
        let wrappedKeyPayload: WrappedKeyPayload
        do {
            wrappedKeyPayload = try JSONDecoder().decode(WrappedKeyPayload.self, from: wrappedKeyData)
        } catch {
            throw StreamingExportError.invalidContainerHeader
        }
        
        let perVideoKey: SymmetricKeyMaterial
        do {
            perVideoKey = try encryptionEngine.unwrapKey(wrappedPayload: wrappedKeyPayload, using: masterKey)
        } catch {
            throw StreamingExportError.authenticationFailed
        }
        
        // 3. Create empty destination temporary plaintext export file
        fileManager.createFile(atPath: destinationURL.path, contents: nil)
        let destHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? destHandle.close() }
        
        // 4. Stream read and decrypt encrypted chunks sequentially
        var chunkIndex: UInt32 = 0
        while chunkIndex < chunkCount {
            let nonceLenData = sourceHandle.readData(ofLength: 1)
            if nonceLenData.isEmpty { break }
            let nonceLen = Int(nonceLenData[0])
            
            let nonce = sourceHandle.readData(ofLength: nonceLen)
            guard nonce.count == nonceLen else {
                throw StreamingExportError.invalidContainerHeader
            }
            
            let tagLenData = sourceHandle.readData(ofLength: 1)
            guard !tagLenData.isEmpty else {
                throw StreamingExportError.invalidContainerHeader
            }
            let tagLen = Int(tagLenData[0])
            
            let tag = sourceHandle.readData(ofLength: tagLen)
            guard tag.count == tagLen else {
                throw StreamingExportError.invalidContainerHeader
            }
            
            let cipherLenData = sourceHandle.readData(ofLength: 4)
            guard cipherLenData.count == 4 else {
                throw StreamingExportError.invalidContainerHeader
            }
            let cipherLen = Int(UInt32(bigEndian: cipherLenData.withUnsafeBytes { $0.load(as: UInt32.self) }))
            
            let ciphertext = sourceHandle.readData(ofLength: cipherLen)
            guard ciphertext.count == cipherLen else {
                throw StreamingExportError.invalidContainerHeader
            }
            
            // Reconstruct exact AAD: PVV1 + version + objectType + vaultType + objectID + chunkSize + chunkCount + chunkIndex
            let chunkAAD = EncryptedVideoContainer.chunkAADData(
                version: version,
                vaultType: vault,
                objectID: objectID,
                chunkSize: chunkSize,
                chunkCount: chunkCount,
                chunkIndex: chunkIndex
            )
            
            let cipherPayload = EncryptedPayload(ciphertext: ciphertext, nonce: nonce, tag: tag)
            let plaintextChunk: Data
            do {
                plaintextChunk = try cryptoPlatform.decrypt(payload: cipherPayload, using: perVideoKey, authenticData: chunkAAD)
            } catch {
                throw StreamingExportError.authenticationFailed
            }
            
            // Stream write decrypted plaintext chunk directly to temporary export file
            destHandle.write(plaintextChunk)
            chunkIndex += 1
        }
    }
}
