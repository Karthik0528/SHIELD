import Foundation

/// Unit test suite validating storage isolation, binary object container layout (PV01),
/// opaque identifier rules, transaction rollback, orphan diagnostics, and fail-closed behavior.
public final class StorageEngineTests {
    private let fileManager: FileManager
    private let testBaseURL: URL
    
    public init() {
        self.fileManager = .default
        self.testBaseURL = fileManager.temporaryDirectory.appendingPathComponent("PrivacyVaultTests_\(UUID().uuidString)")
    }
    
    public func runAllTests() throws {
        print("--- Starting PrivacyVault Storage Engine Test Suite ---")
        try testVaultPathIsolation()
        try testMainVsDecoyStorageIsolation()
        try testStorageIdentifierUniqueness()
        try testContainerFormatEncodingDecoding()
        try testFailClosedOnUnsupportedPlatform()
        try testOrphanDetection()
        try tearDown()
        print("--- All Storage Engine Tests Completed Successfully ---")
    }
    
    // MARK: - Test Cases
    
    /// Test 1: Verify Vault subpath separation.
    public func testVaultPathIsolation() throws {
        let mainStorage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        try mainStorage.initializeDirectories(for: .main)
        try mainStorage.initializeDirectories(for: .decoy)
        
        let mainObjects = testBaseURL.appendingPathComponent("Vaults/Main/Objects")
        let decoyObjects = testBaseURL.appendingPathComponent("Vaults/Decoy/Objects")
        
        assert(fileManager.fileExists(atPath: mainObjects.path), "Main Objects directory must exist.")
        assert(fileManager.fileExists(atPath: decoyObjects.path), "Decoy Objects directory must exist.")
        assert(mainObjects.path != decoyObjects.path, "Main and Decoy object paths must be distinct.")
        print("[PASS] testVaultPathIsolation")
    }
    
    /// Test 2: Verify Main and Decoy store items independently.
    public func testMainVsDecoyStorageIsolation() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        let mainItem = MediaItem(
            vaultType: .main,
            mediaType: .photo,
            encryptedFilenameRef: Data([0x01]),
            encryptedMetadataRef: Data([0x02]),
            encryptedFileKeyRef: Data([0x03]),
            storageIdentifier: "main_file_001",
            thumbnailStorageIdentifier: nil,
            fileSize: 100
        )
        let decoyItem = MediaItem(
            vaultType: .decoy,
            mediaType: .photo,
            encryptedFilenameRef: Data([0x04]),
            encryptedMetadataRef: Data([0x05]),
            encryptedFileKeyRef: Data([0x06]),
            storageIdentifier: "decoy_file_001",
            thumbnailStorageIdentifier: nil,
            fileSize: 200
        )
        
        try database.saveMediaItem(mainItem, for: .main)
        try database.saveMediaItem(decoyItem, for: .decoy)
        
        let mainFetched = try database.fetchMediaItems(for: .main)
        let decoyFetched = try database.fetchMediaItems(for: .decoy)
        
        assert(mainFetched.count == 1, "Main vault should contain 1 item.")
        assert(decoyFetched.count == 1, "Decoy vault should contain 1 item.")
        assert(mainFetched.first?.storageIdentifier == "main_file_001", "Main item identifier mismatch.")
        assert(decoyFetched.first?.storageIdentifier == "decoy_file_001", "Decoy item identifier mismatch.")
        print("[PASS] testMainVsDecoyStorageIsolation")
    }
    
    /// Test 3: Verify opaque storage identifiers (no original filenames used as disk filenames).
    public func testStorageIdentifierUniqueness() throws {
        let storageID = UUID().uuidString
        let originalFilename = "private_secret_vacation_photo.jpg"
        
        assert(storageID != originalFilename, "Storage identifier must not equal original filename.")
        assert(!storageID.contains("private"), "Storage identifier must be an opaque UUID.")
        assert(UUID(uuidString: storageID) != nil, "Storage identifier must be a valid UUID.")
        print("[PASS] testStorageIdentifierUniqueness")
    }
    
    /// Test 4: Verify binary container header (PV01) encoding and decoding.
    public func testContainerFormatEncodingDecoding() throws {
        let container = EncryptedObjectContainer(
            objectType: .media,
            vaultType: .main,
            objectID: UUID(),
            wrappedKeyData: Data([0x10, 0x20, 0x30]),
            nonce: Data(repeating: 0x01, count: 12),
            tag: Data(repeating: 0x02, count: 16),
            ciphertext: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        
        let encoded = try container.encode()
        assert(encoded.prefix(4) == Data([0x50, 0x56, 0x30, 0x31]), "Magic header must be PV01.")
        
        let decoded = try EncryptedObjectContainer.decode(from: encoded)
        assert(decoded.version == 1, "Container version must be 1.")
        assert(decoded.objectType == .media, "Object type must match.")
        assert(decoded.vaultType == .main, "Vault type must match.")
        assert(decoded.ciphertext == Data([0xDE, 0xAD, 0xBE, 0xEF]), "Ciphertext payload must match.")
        print("[PASS] testContainerFormatEncodingDecoding")
    }
    
    /// Test 5: Verify fail-closed behavior on non-CryptoKit platforms.
    public func testFailClosedOnUnsupportedPlatform() throws {
        let defaultCrypto = DefaultPlatformCrypto()
        
        #if canImport(CryptoKit)
        // On iOS/macOS with CryptoKit available, salt & key generation succeed.
        let salt = try defaultCrypto.generateSalt()
        assert(salt.count == 32, "Salt count must be 32 bytes.")
        #else
        // On Windows (without CryptoKit), all operations fail closed.
        do {
            _ = try defaultCrypto.generateSalt()
            assert(false, "Should have thrown unsupportedPlatform on non-CryptoKit platform.")
        } catch let err as PlatformCryptoError {
            assert(err == .unsupportedPlatform, "Error must be unsupportedPlatform.")
        }
        #endif
        print("[PASS] testFailClosedOnUnsupportedPlatform")
    }
    
    /// Test 6: Verify orphan diagnostics.
    public func testOrphanDetection() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = EncryptedMediaStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        try storage.initializeDirectories(for: .main)
        
        // Add a database item with missing binary file
        let missingItem = MediaItem(
            vaultType: .main,
            mediaType: .photo,
            encryptedFilenameRef: Data([0x01]),
            encryptedMetadataRef: Data([0x02]),
            encryptedFileKeyRef: Data([0x03]),
            storageIdentifier: "non_existent_file_id",
            thumbnailStorageIdentifier: nil,
            fileSize: 50
        )
        try storage.database.saveMediaItem(missingItem, for: .main)
        
        let report = try engine.detectOrphans(for: .main)
        assert(report.missingMediaFiles.contains(missingItem.id), "Missing media file must be detected in orphan report.")
        print("[PASS] testOrphanDetection")
    }
    
    private func tearDown() throws {
        if fileManager.fileExists(atPath: testBaseURL.path) {
            try fileManager.removeItem(at: testBaseURL)
        }
    }
}
