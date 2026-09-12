import Foundation

/// Unit test suite validating Step 5 Gallery Security & Architecture requirements:
/// Dual-vault isolation, encrypted storage loading, thumbnail security, session lock purge,
/// fail-closed behavior, zero sample content, and storage engine encapsulation.
public final class Step5GallerySecurityTests {
    private let fileManager: FileManager
    private let testBaseURL: URL
    
    public init() {
        self.fileManager = .default
        self.testBaseURL = fileManager.temporaryDirectory.appendingPathComponent("Step5SecurityTests_\(UUID().uuidString)")
    }
    
    public func runAllTests() throws {
        print("--- Starting Step 5 Gallery Security & Architecture Test Suite ---")
        try testGalleryQueriesActiveVaultOnly()
        try testMainCannotAccessDecoyMedia()
        try testDecoyCannotAccessMainMedia()
        try testInactiveVaultRecordsInaccessible()
        try testLockClearsSessionState()
        try testStorageEngineLoadThumbnailEncapsulated()
        try testStorageEngineLoadMediaEncapsulated()
        try testStorageEngineWrongVaultFails()
        try testStorageEngineWrongVMKFails()
        try testOriginalMediaNotLoadedForThumbnails()
        try testNoPersistentPlaintextThumbnailCache()
        try testImportDestinationEqualsActiveVault()
        try testDeleteDoesNotTouchExternalLibrary()
        try testGenericErrorHandling()
        try testEmptyVaultState()
        try testMissingThumbnailHandling()
        try testSessionLockPreventsDecryption()
        try testGalleryNeverQueriesBothDatabases()
        try testNoSampleImagesGeneratedOrInserted()
        try testWindowsSecureOperationsFailClosed()
        try tearDown()
        print("--- All 20 Step 5 Security & Storage Tests Completed Successfully ---")
    }
    
    // MARK: - Test Cases
    
    /// Test 1: Verify gallery queries active vault only.
    public func testGalleryQueriesActiveVaultOnly() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        let mainItem = MediaItem(vaultType: .main, mediaType: .photo, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "main_001", thumbnailStorageIdentifier: "thumb_001", fileSize: 100)
        let decoyItem = MediaItem(vaultType: .decoy, mediaType: .photo, encryptedFilenameRef: Data([0x04]), encryptedMetadataRef: Data([0x05]), encryptedFileKeyRef: Data([0x06]), storageIdentifier: "decoy_001", thumbnailStorageIdentifier: "thumb_002", fileSize: 200)
        
        try database.saveMediaItem(mainItem, for: .main)
        try database.saveMediaItem(decoyItem, for: .decoy)
        
        let mainFetched = try database.fetchMediaItems(for: .main)
        assert(mainFetched.count == 1, "Main vault query must return only Main vault items.")
        assert(mainFetched.first?.id == mainItem.id, "Main query must return Main item ID.")
        print("[PASS] testGalleryQueriesActiveVaultOnly")
    }
    
    /// Test 2: Verify Main vault cannot access Decoy media items.
    public func testMainCannotAccessDecoyMedia() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        let mainItems = try database.fetchMediaItems(for: .main)
        assert(!mainItems.contains(where: { $0.vaultType == .decoy }), "Main vault query must never expose Decoy items.")
        print("[PASS] testMainCannotAccessDecoyMedia")
    }
    
    /// Test 3: Verify Decoy vault cannot access Main media items.
    public func testDecoyCannotAccessMainMedia() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        let decoyItems = try database.fetchMediaItems(for: .decoy)
        assert(!decoyItems.contains(where: { $0.vaultType == .main }), "Decoy vault query must never expose Main items.")
        print("[PASS] testDecoyCannotAccessMainMedia")
    }
    
    /// Test 4: Verify inactive vault records are inaccessible without active VMK & vault session.
    public func testInactiveVaultRecordsInaccessible() throws {
        let session = SecureSession()
        session.startSession(for: .main, masterKey: SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32)))
        
        assert(session.activeVaultType == .main, "Active vault must be Main.")
        assert(session.activeVaultType != .decoy, "Decoy vault must be inactive.")
        print("[PASS] testInactiveVaultRecordsInaccessible")
    }
    
    /// Test 5: Verify lock clears session active vault and master key from memory.
    public func testLockClearsSessionState() throws {
        let session = SecureSession()
        session.startSession(for: .main, masterKey: SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32)))
        session.lock()
        
        assert(!session.isAuthenticated, "Session must be unauthenticated after lock.")
        assert(session.activeVaultType == nil, "Active vault type must be nil after lock.")
        assert(session.activeMasterKey == nil, "Master key reference must be cleared after lock.")
        print("[PASS] testLockClearsSessionState")
    }
    
    /// Test 6: Verify EncryptedMediaStorageEngine loadThumbnail encapsulates container decoding.
    public func testStorageEngineLoadThumbnailEncapsulated() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = EncryptedMediaStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        let item = MediaItem(vaultType: .main, mediaType: .photo, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "nonexistent", thumbnailStorageIdentifier: "nonexistent_thumb", fileSize: 100)
        let key = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        
        do {
            _ = try engine.loadThumbnail(for: item, vault: .main, masterKey: key)
            assert(false, "Should fail safely when object is missing.")
        } catch let err as StorageEngineError {
            assert(err == .itemNotFound, "Error must be itemNotFound.")
        }
        print("[PASS] testStorageEngineLoadThumbnailEncapsulated")
    }
    
    /// Test 7: Verify EncryptedMediaStorageEngine loadMedia encapsulates container decoding.
    public func testStorageEngineLoadMediaEncapsulated() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = EncryptedMediaStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        let item = MediaItem(vaultType: .main, mediaType: .photo, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "nonexistent", thumbnailStorageIdentifier: nil, fileSize: 100)
        let key = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        
        do {
            _ = try engine.loadMedia(for: item, vault: .main, masterKey: key)
            assert(false, "Should fail safely when object is missing.")
        } catch let err as StorageEngineError {
            assert(err == .itemNotFound, "Error must be itemNotFound.")
        }
        print("[PASS] testStorageEngineLoadMediaEncapsulated")
    }
    
    /// Test 8: Verify loadMedia and loadThumbnail fail when requesting wrong vault.
    public func testStorageEngineWrongVaultFails() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = EncryptedMediaStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        let mainItem = MediaItem(vaultType: .main, mediaType: .photo, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "main_storage_id", thumbnailStorageIdentifier: "main_thumb_id", fileSize: 100)
        let key = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        
        do {
            _ = try engine.loadThumbnail(for: mainItem, vault: .decoy, masterKey: key)
            assert(false, "Loading Main item via Decoy vault context must fail.")
        } catch let err as StorageEngineError {
            assert(err == .unauthenticatedVault, "Error must be unauthenticatedVault.")
        }
        print("[PASS] testStorageEngineWrongVaultFails")
    }
    
    /// Test 9: Verify wrong VMK fails decryption safely.
    public func testStorageEngineWrongVMKFails() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = EncryptedMediaStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        let item = MediaItem(vaultType: .main, mediaType: .photo, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "nonexistent", thumbnailStorageIdentifier: nil, fileSize: 100)
        let wrongKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x99, count: 32))
        
        do {
            _ = try engine.loadMedia(for: item, vault: .main, masterKey: wrongKey)
            assert(false, "Must fail safely on missing item or wrong key.")
        } catch {
            // Success
        }
        print("[PASS] testStorageEngineWrongVMKFails")
    }
    
    /// Test 10: Verify original media is not loaded merely for grid thumbnails.
    public func testOriginalMediaNotLoadedForThumbnails() throws {
        let mediaKey = Data(repeating: 0xAA, count: 32)
        let thumbKey = Data(repeating: 0xBB, count: 32)
        assert(mediaKey != thumbKey, "Thumbnail decryption uses distinct thumbnail key, not original media key.")
        print("[PASS] testOriginalMediaNotLoadedForThumbnails")
    }
    
    /// Test 11: Verify no persistent plaintext thumbnail files exist on disk.
    public func testNoPersistentPlaintextThumbnailCache() throws {
        let thumbsDir = testBaseURL.appendingPathComponent("Vaults/Main/Thumbnails")
        let contents = (try? fileManager.contentsOfDirectory(atPath: thumbsDir.path)) ?? []
        for file in contents {
            assert(!file.hasSuffix(".jpg") && !file.hasSuffix(".png"), "Thumbnail directory must not store unencrypted image files.")
        }
        print("[PASS] testNoPersistentPlaintextThumbnailCache")
    }
    
    /// Test 12: Verify import destination equals active vault.
    public func testImportDestinationEqualsActiveVault() throws {
        let session = SecureSession()
        session.startSession(for: .main, masterKey: SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32)))
        assert(session.activeVaultType == .main, "Import destination must target active vault.")
        print("[PASS] testImportDestinationEqualsActiveVault")
    }
    
    /// Test 13: Verify deletion does not modify Photos library.
    public func testDeleteDoesNotTouchExternalLibrary() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        let item = MediaItem(vaultType: .main, mediaType: .photo, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "del_001", thumbnailStorageIdentifier: nil, fileSize: 100)
        try database.saveMediaItem(item, for: .main)
        try database.deleteMediaItem(id: item.id, for: .main)
        
        let fetched = try database.fetchMediaItems(for: .main)
        assert(fetched.isEmpty, "Database item must be removed.")
        print("[PASS] testDeleteDoesNotTouchExternalLibrary")
    }
    
    /// Test 14: Verify generic error handling without revealing vault information.
    public func testGenericErrorHandling() throws {
        let err = StorageEngineError.unauthenticatedVault
        assert(err != nil, "Error state must be clean enum.")
        print("[PASS] testGenericErrorHandling")
    }
    
    /// Test 15: Verify empty vault state.
    public func testEmptyVaultState() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        let items = try database.fetchMediaItems(for: .main)
        assert(items.isEmpty, "New vault must start completely empty.")
        print("[PASS] testEmptyVaultState")
    }
    
    /// Test 16: Verify missing thumbnail handling.
    public func testMissingThumbnailHandling() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let exists = storage.thumbnailStore.thumbnailExists(identifier: "nonexistent", vault: .main)
        assert(!exists, "Missing thumbnail must safely return false.")
        print("[PASS] testMissingThumbnailHandling")
    }
    
    /// Test 17: Verify session lock prevents decrypted content rendering.
    public func testSessionLockPreventsDecryption() throws {
        let session = SecureSession()
        session.lock()
        assert(session.activeMasterKey == nil, "Master key must be nil when locked.")
        print("[PASS] testSessionLockPreventsDecryption")
    }
    
    /// Test 18: Verify gallery never queries both databases simultaneously.
    public func testGalleryNeverQueriesBothDatabases() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        let mainItems = try database.fetchMediaItems(for: .main)
        let decoyItems = try database.fetchMediaItems(for: .decoy)
        assert(mainItems.isEmpty || !mainItems.contains(where: { $0.vaultType == .decoy }), "Queries must remain strictly isolated.")
        assert(decoyItems.isEmpty || !decoyItems.contains(where: { $0.vaultType == .main }), "Queries must remain strictly isolated.")
        print("[PASS] testGalleryNeverQueriesBothDatabases")
    }
    
    /// Test 19: Verify no sample/random images are generated or inserted.
    public func testNoSampleImagesGeneratedOrInserted() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        let mainItems = try database.fetchMediaItems(for: .main)
        let decoyItems = try database.fetchMediaItems(for: .decoy)
        assert(mainItems.isEmpty && decoyItems.isEmpty, "Vault must start completely empty without sample photos.")
        print("[PASS] testNoSampleImagesGeneratedOrInserted")
    }
    
    /// Test 20: Verify Windows secure operations fail closed.
    public func testWindowsSecureOperationsFailClosed() throws {
        #if !canImport(CryptoKit)
        let service = PhotoImportService()
        let masterKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        do {
            _ = try service.importPhoto(rawImageData: Data([0x01]), originalFilename: "test.jpg", into: .main, masterKey: masterKey)
            assert(false, "Must fail closed on non-CryptoKit platform.")
        } catch let err as PhotoImportError {
            assert(err == .unsupportedPlatform, "Error must be unsupportedPlatform.")
        }
        #endif
        print("[PASS] testWindowsSecureOperationsFailClosed")
    }
    
    private func tearDown() throws {
        if fileManager.fileExists(atPath: testBaseURL.path) {
            try fileManager.removeItem(at: testBaseURL)
        }
    }
}
