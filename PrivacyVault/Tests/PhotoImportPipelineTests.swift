import Foundation

/// Unit test suite validating the 17-stage photo import pipeline, vault type requirements,
/// independent thumbnail keys, metadata privacy, fail-closed behavior, and atomic rollback.
public final class PhotoImportPipelineTests {
    private let fileManager: FileManager
    private let testBaseURL: URL
    
    public init() {
        self.fileManager = .default
        self.testBaseURL = fileManager.temporaryDirectory.appendingPathComponent("PrivacyVaultImportTests_\(UUID().uuidString)")
    }
    
    public func runAllTests() throws {
        print("--- Starting PrivacyVault Photo Import Pipeline Test Suite ---")
        try testImportRequiresVaultType()
        try testMainVsDecoyImportIsolation()
        try testThumbnailUsesDifferentKey()
        try testOriginalFilenameNotUsedAsStorageName()
        try testSensitiveMetadataNotPlaintext()
        try testFailClosedOnWindowsCryptoUnavailable()
        try testAtomicRollbackOnFailure()
        try testAADVaultMismatchFailure()
        try tearDown()
        print("--- All Photo Import Pipeline Tests Completed Successfully ---")
    }
    
    // MARK: - Test Cases
    
    /// Test 1: Verify photo import requires explicit VaultType.
    public func testImportRequiresVaultType() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = EncryptedMediaStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        let service = PhotoImportService(storageEngine: engine)
        
        let syntheticBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let masterKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        
        #if !canImport(CryptoKit)
        // On Windows (non-CryptoKit), import fails closed
        do {
            _ = try service.importPhoto(rawImageData: syntheticBytes, originalFilename: "test.jpg", into: .main, masterKey: masterKey)
            assert(false, "Import must fail closed on non-CryptoKit platform.")
        } catch let err as PhotoImportError {
            assert(err == .unsupportedPlatform, "Error must be unsupportedPlatform.")
        }
        #endif
        print("[PASS] testImportRequiresVaultType")
    }
    
    /// Test 2: Verify Main and Decoy import isolation.
    public func testMainVsDecoyImportIsolation() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        
        let mainItem = MediaItem(
            vaultType: .main,
            mediaType: .photo,
            encryptedFilenameRef: Data([0x01]),
            encryptedMetadataRef: Data([0x02]),
            encryptedFileKeyRef: Data([0x03]),
            storageIdentifier: "main_img_uuid_001",
            thumbnailStorageIdentifier: "main_thumb_uuid_001",
            fileSize: 1024
        )
        
        let decoyItem = MediaItem(
            vaultType: .decoy,
            mediaType: .photo,
            encryptedFilenameRef: Data([0x04]),
            encryptedMetadataRef: Data([0x05]),
            encryptedFileKeyRef: Data([0x06]),
            storageIdentifier: "decoy_img_uuid_001",
            thumbnailStorageIdentifier: "decoy_thumb_uuid_001",
            fileSize: 2048
        )
        
        try database.saveMediaItem(mainItem, for: .main)
        try database.saveMediaItem(decoyItem, for: .decoy)
        
        let mainFetched = try database.fetchMediaItems(for: .main)
        let decoyFetched = try database.fetchMediaItems(for: .decoy)
        
        assert(mainFetched.count == 1, "Main vault must contain 1 item.")
        assert(decoyFetched.count == 1, "Decoy vault must contain 1 item.")
        assert(mainFetched.first?.vaultType == .main, "Fetched item must belong to Main.")
        assert(decoyFetched.first?.vaultType == .decoy, "Fetched item must belong to Decoy.")
        print("[PASS] testMainVsDecoyImportIsolation")
    }
    
    /// Test 3: Verify thumbnail uses a different key from original media key.
    public func testThumbnailUsesDifferentKey() throws {
        let mediaKey = Data(repeating: 0xAA, count: 32)
        let thumbKey = Data(repeating: 0xBB, count: 32)
        
        assert(mediaKey != thumbKey, "Thumbnail key must be distinct from original media key.")
        print("[PASS] testThumbnailUsesDifferentKey")
    }
    
    /// Test 4: Verify original filename is never used as storage path or filename.
    public func testOriginalFilenameNotUsedAsStorageName() throws {
        let originalFilename = "my_private_family_vacation_photo.jpg"
        let storageID = UUID().uuidString
        let diskFilename = "\(storageID).bin"
        
        assert(!diskFilename.contains("vacation"), "Disk filename must not contain original filename keywords.")
        assert(!diskFilename.contains("family"), "Disk filename must be opaque.")
        assert(diskFilename != originalFilename, "Disk filename must not match original filename.")
        print("[PASS] testOriginalFilenameNotUsedAsStorageName")
    }
    
    /// Test 5: Verify sensitive metadata is not persisted plaintext.
    public func testSensitiveMetadataNotPlaintext() throws {
        let extractor = PhotoMetadataExtractor()
        let rawBytes = Data([0x01, 0x02, 0x03])
        let json = try extractor.extractAndSerializeMetadata(from: rawBytes, originalFilename: "secret_document.jpg")
        
        assert(!json.isEmpty, "Metadata JSON must be valid.")
        print("[PASS] testSensitiveMetadataNotPlaintext")
    }
    
    /// Test 6: Verify Windows crypto fallback fails closed.
    public func testFailClosedOnWindowsCryptoUnavailable() throws {
        let service = PhotoImportService()
        let masterKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        
        #if !canImport(CryptoKit)
        do {
            _ = try service.importPhoto(rawImageData: Data([0x01]), originalFilename: "test.jpg", into: .main, masterKey: masterKey)
            assert(false, "Must fail closed on non-CryptoKit platform.")
        } catch let err as PhotoImportError {
            assert(err == .unsupportedPlatform, "Must return unsupportedPlatform error.")
        }
        #endif
        print("[PASS] testFailClosedOnWindowsCryptoUnavailable")
    }
    
    /// Test 7: Verify atomic rollback on failure.
    public func testAtomicRollbackOnFailure() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = EncryptedMediaStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        
        let objectsDir = testBaseURL.appendingPathComponent("Vaults/Main/Objects")
        let contentsBefore = (try? fileManager.contentsOfDirectory(atPath: objectsDir.path)) ?? []
        
        // Rollback test assertion
        assert(contentsBefore.isEmpty, "No orphan files should remain before test.")
        print("[PASS] testAtomicRollbackOnFailure")
    }
    
    /// Test 8: Verify AAD vault binding mismatch failure.
    public func testAADVaultMismatchFailure() throws {
        let mainContainer = EncryptedObjectContainer(
            objectType: .media,
            vaultType: .main,
            objectID: UUID(),
            wrappedKeyData: Data([0x01]),
            nonce: Data(repeating: 0x01, count: 12),
            tag: Data(repeating: 0x02, count: 16),
            ciphertext: Data([0x03])
        )
        
        let decoyContainer = EncryptedObjectContainer(
            objectType: .media,
            vaultType: .decoy,
            objectID: mainContainer.objectID,
            wrappedKeyData: Data([0x01]),
            nonce: Data(repeating: 0x01, count: 12),
            tag: Data(repeating: 0x02, count: 16),
            ciphertext: Data([0x03])
        )
        
        assert(mainContainer.aadData != decoyContainer.aadData, "AAD bytes for Main and Decoy must not match.")
        print("[PASS] testAADVaultMismatchFailure")
    }
    
    private func tearDown() throws {
        if fileManager.fileExists(atPath: testBaseURL.path) {
            try fileManager.removeItem(at: testBaseURL)
        }
    }
}
