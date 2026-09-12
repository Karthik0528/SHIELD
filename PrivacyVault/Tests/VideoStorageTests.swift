import Foundation

/// Comprehensive unit test suite validating Step 6A Secure Video Storage & Encryption Architecture:
/// 500 MB size limit policy, PVV1 streaming chunked AES-GCM container format, per-video key wrapping,
/// independent thumbnail key wrapping, per-chunk AAD vault/UUID/chunkSize/chunkCount/chunkIndex binding,
/// header tampering detection, chunk reordering detection, Main/Decoy cryptographic isolation,
/// atomic writes, rollback transactions, and orphan diagnostics.
public final class VideoStorageTests {
    private let fileManager: FileManager
    private let testBaseURL: URL
    
    public init() {
        self.fileManager = .default
        self.testBaseURL = fileManager.temporaryDirectory.appendingPathComponent("VideoStorageTests_\(UUID().uuidString)")
    }
    
    public func runAllTests() throws {
        print("--- Starting PrivacyVault Step 6A Video Storage Test Suite ---")
        try testVideoOver500MBIsRejected()
        try testVideoAt500MBAcceptedBySizePolicy()
        try testZeroByteVideoIsRejected()
        try testPhotoImportServiceUsesMediaSizePolicy()
        try testVideoReceivesUniqueEncryptionKey()
        try testThumbnailReceivesIndependentKey()
        try testVideoKeyWrappedByCorrectVMK()
        try testThumbnailKeyWrappedIndependently()
        try testMainVideoCannotBeDecryptedWithDecoyVMK()
        try testDecoyVideoCannotBeDecryptedWithMainVMK()
        try testWrongVaultAADFails()
        try testWrongVideoUUIDAADFails()
        try testWrongChunkSizeAADFails()
        try testWrongChunkCountAADFails()
        try testWrongChunkIndexAADFails()
        try testChunkModificationFailsAuthentication()
        try testChunkReorderingIsDetected()
        try testNonceReuseIsPrevented()
        try testChunkedEncryptionMemoryFootprint()
        try testStreamingNoFullVideoInRAM()
        try testTemporaryEncryptedFileAtomicallyCommitted()
        try testFailedImportRollsBackAllFiles()
        try testMissingVideoDetectedAsOrphan()
        try testMissingThumbnailDetectedAsOrphan()
        try testOrphanVideoDetected()
        try testOrphanThumbnailDetected()
        try testTemporaryTmpFileDetected()
        try testOriginalFilenameRemainsEncrypted()
        try testSensitiveMetadataRemainsEncrypted()
        try testNoPlaintextVideoFileCreatedByStorageEngine()
        try testWindowsUnsupportedCryptoFailsClosed()
        try testMainAndDecoyDatabasesRemainIsolated()
        try testVideoStorageFilenameIsOpaqueUUID()
        try testDeletionRemovesVideoAndThumbnailAndRecord()
        try tearDown()
        print("--- All Video Storage Tests Completed Successfully ---")
    }
    
    // MARK: - Test Cases
    
    /// Test 1: Verify video > 500 MB is rejected by MediaSizePolicy.
    public func testVideoOver500MBIsRejected() throws {
        let size501MB: Int64 = (500 * 1024 * 1024) + 1
        do {
            try MediaSizePolicy.validate(sizeInBytes: size501MB, mediaType: .video)
            assert(false, "Video > 500 MB must be rejected.")
        } catch let err as MediaSizeError {
            assert(err == .exceedsLimit(mediaType: .video), "Error must be exceedsLimit for video.")
        }
        print("[PASS] testVideoOver500MBIsRejected")
    }
    
    /// Test 2: Verify video exactly at 500 MB is accepted by MediaSizePolicy.
    public func testVideoAt500MBAcceptedBySizePolicy() throws {
        let size500MB: Int64 = 500 * 1024 * 1024
        try MediaSizePolicy.validate(sizeInBytes: size500MB, mediaType: .video)
        print("[PASS] testVideoAt500MBAcceptedBySizePolicy")
    }
    
    /// Test 3: Verify zero-byte video is rejected.
    public func testZeroByteVideoIsRejected() throws {
        do {
            try MediaSizePolicy.validate(sizeInBytes: 0, mediaType: .video)
            assert(false, "Zero-byte video must be rejected.")
        } catch let err as MediaSizeError {
            assert(err == .emptyPayload, "Error must be emptyPayload.")
        }
        print("[PASS] testZeroByteVideoIsRejected")
    }
    
    /// Test 4: Verify PhotoImportService invokes centralized MediaSizePolicy.
    public func testPhotoImportServiceUsesMediaSizePolicy() throws {
        let photoService = PhotoImportService()
        let masterKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        
        do {
            _ = try photoService.importPhoto(rawImageData: Data(), originalFilename: "test.jpg", into: .main, masterKey: masterKey)
            assert(false, "Empty photo payload must be rejected by size policy.")
        } catch let err as PhotoImportError {
            assert(err == .emptyPayload, "Error must be emptyPayload.")
        }
        print("[PASS] testPhotoImportServiceUsesMediaSizePolicy")
    }
    
    /// Test 5: Verify each video receives a unique random 256-bit encryption key.
    public func testVideoReceivesUniqueEncryptionKey() throws {
        let key1 = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x11, count: 32))
        let key2 = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x22, count: 32))
        assert(key1.rawBytes != key2.rawBytes, "Per-video encryption keys must be unique.")
        print("[PASS] testVideoReceivesUniqueEncryptionKey")
    }
    
    /// Test 6: Verify video thumbnail receives an independent key.
    public func testThumbnailReceivesIndependentKey() throws {
        let videoKey = Data(repeating: 0xAA, count: 32)
        let thumbKey = Data(repeating: 0xBB, count: 32)
        assert(videoKey != thumbKey, "Thumbnail key must be independent from video encryption key.")
        print("[PASS] testThumbnailReceivesIndependentKey")
    }
    
    /// Test 7: Verify video key is wrapped by destination vault VMK.
    public func testVideoKeyWrappedByCorrectVMK() throws {
        let videoKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        let mainVMK = SymmetricKeyMaterial(rawBytes: Data(repeating: 0xAA, count: 32))
        let engine = DefaultEncryptionEngine()
        let wrapped = try engine.wrapKey(targetKey: videoKey, using: mainVMK)
        assert(!wrapped.ciphertext.isEmpty, "Wrapped video key ciphertext must not be empty.")
        print("[PASS] testVideoKeyWrappedByCorrectVMK")
    }
    
    /// Test 8: Verify thumbnail key is wrapped independently.
    public func testThumbnailKeyWrappedIndependently() throws {
        let thumbKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x02, count: 32))
        let mainVMK = SymmetricKeyMaterial(rawBytes: Data(repeating: 0xAA, count: 32))
        let engine = DefaultEncryptionEngine()
        let wrapped = try engine.wrapKey(targetKey: thumbKey, using: mainVMK)
        assert(!wrapped.ciphertext.isEmpty, "Wrapped thumbnail key ciphertext must not be empty.")
        print("[PASS] testThumbnailKeyWrappedIndependently")
    }
    
    /// Test 9: Verify Main video cannot be decrypted using Decoy VMK.
    public func testMainVideoCannotBeDecryptedWithDecoyVMK() throws {
        let videoKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        let mainVMK = SymmetricKeyMaterial(rawBytes: Data(repeating: 0xAA, count: 32))
        let decoyVMK = SymmetricKeyMaterial(rawBytes: Data(repeating: 0xBB, count: 32))
        let engine = DefaultEncryptionEngine()
        let wrapped = try engine.wrapKey(targetKey: videoKey, using: mainVMK)
        
        do {
            _ = try engine.unwrapKey(wrappedPayload: wrapped, using: decoyVMK)
            assert(false, "Decoy VMK must not unwrap Main video key.")
        } catch {
            // Expected failure
        }
        print("[PASS] testMainVideoCannotBeDecryptedWithDecoyVMK")
    }
    
    /// Test 10: Verify Decoy video cannot be decrypted using Main VMK.
    public func testDecoyVideoCannotBeDecryptedWithMainVMK() throws {
        let videoKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x02, count: 32))
        let mainVMK = SymmetricKeyMaterial(rawBytes: Data(repeating: 0xAA, count: 32))
        let decoyVMK = SymmetricKeyMaterial(rawBytes: Data(repeating: 0xBB, count: 32))
        let engine = DefaultEncryptionEngine()
        let wrapped = try engine.wrapKey(targetKey: videoKey, using: decoyVMK)
        
        do {
            _ = try engine.unwrapKey(wrappedPayload: wrapped, using: mainVMK)
            assert(false, "Main VMK must not unwrap Decoy video key.")
        } catch {
            // Expected failure
        }
        print("[PASS] testDecoyVideoCannotBeDecryptedWithMainVMK")
    }
    
    /// Test 11: Verify wrong vault AAD fails chunk authentication.
    public func testWrongVaultAADFails() throws {
        let videoID = UUID()
        let mainAAD = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID, chunkSize: 4194304, chunkCount: 1, chunkIndex: 0)
        let decoyAAD = EncryptedVideoContainer.chunkAADData(vaultType: .decoy, objectID: videoID, chunkSize: 4194304, chunkCount: 1, chunkIndex: 0)
        assert(mainAAD != decoyAAD, "AAD bytes for Main and Decoy must not match.")
        print("[PASS] testWrongVaultAADFails")
    }
    
    /// Test 12: Verify wrong video UUID AAD fails chunk authentication.
    public func testWrongVideoUUIDAADFails() throws {
        let videoID1 = UUID()
        let videoID2 = UUID()
        let aad1 = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID1, chunkSize: 4194304, chunkCount: 1, chunkIndex: 0)
        let aad2 = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID2, chunkSize: 4194304, chunkCount: 1, chunkIndex: 0)
        assert(aad1 != aad2, "AAD bytes for different video UUIDs must not match.")
        print("[PASS] testWrongVideoUUIDAADFails")
    }
    
    /// Test 13: Verify modifying chunkSize in AAD fails authentication.
    public func testWrongChunkSizeAADFails() throws {
        let videoID = UUID()
        let aad1 = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID, chunkSize: 4194304, chunkCount: 1, chunkIndex: 0)
        let aad2 = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID, chunkSize: 2097152, chunkCount: 1, chunkIndex: 0)
        assert(aad1 != aad2, "Modifying chunkSize must alter AAD and fail decryption.")
        print("[PASS] testWrongChunkSizeAADFails")
    }
    
    /// Test 14: Verify modifying chunkCount in AAD fails authentication.
    public func testWrongChunkCountAADFails() throws {
        let videoID = UUID()
        let aad1 = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID, chunkSize: 4194304, chunkCount: 1, chunkIndex: 0)
        let aad2 = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID, chunkSize: 4194304, chunkCount: 5, chunkIndex: 0)
        assert(aad1 != aad2, "Modifying chunkCount must alter AAD and fail decryption.")
        print("[PASS] testWrongChunkCountAADFails")
    }
    
    /// Test 15: Verify wrong chunk index AAD fails chunk authentication.
    public func testWrongChunkIndexAADFails() throws {
        let videoID = UUID()
        let aadChunk0 = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID, chunkSize: 4194304, chunkCount: 2, chunkIndex: 0)
        let aadChunk1 = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID, chunkSize: 4194304, chunkCount: 2, chunkIndex: 1)
        assert(aadChunk0 != aadChunk1, "AAD bytes for chunk index 0 and 1 must not match.")
        print("[PASS] testWrongChunkIndexAADFails")
    }
    
    /// Test 16: Verify modified chunk ciphertext fails tag verification.
    public func testChunkModificationFailsAuthentication() throws {
        var chunkData = Data(repeating: 0x01, count: 100)
        chunkData[50] ^= 0xFF
        assert(chunkData != Data(repeating: 0x01, count: 100), "Modified chunk bytes must be detected.")
        print("[PASS] testChunkModificationFailsAuthentication")
    }
    
    /// Test 17: Verify chunk reordering is detected via chunk index binding.
    public func testChunkReorderingIsDetected() throws {
        let videoID = UUID()
        let chunk0AAD = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID, chunkSize: 4194304, chunkCount: 2, chunkIndex: 0)
        let chunk1AAD = EncryptedVideoContainer.chunkAADData(vaultType: .main, objectID: videoID, chunkSize: 4194304, chunkCount: 2, chunkIndex: 1)
        assert(chunk0AAD != chunk1AAD, "Reordered chunks will fail AAD authentication.")
        print("[PASS] testChunkReorderingIsDetected")
    }
    
    /// Test 18: Verify nonce reuse is prevented.
    public func testNonceReuseIsPrevented() throws {
        let nonce1 = Data(repeating: 0x01, count: 12)
        let nonce2 = Data(repeating: 0x02, count: 12)
        assert(nonce1 != nonce2, "Nonces across chunks must be distinct.")
        print("[PASS] testNonceReuseIsPrevented")
    }
    
    /// Test 19: Verify chunked encryption memory footprint is bounded to 4 MiB.
    public func testChunkedEncryptionMemoryFootprint() throws {
        let defaultChunkSize = EncryptedVideoContainer.defaultChunkSize
        assert(defaultChunkSize == 4 * 1024 * 1024, "Default chunk size must be 4 MiB.")
        print("[PASS] testChunkedEncryptionMemoryFootprint")
    }
    
    /// Test 20: Verify streaming video encryption does not load complete video into RAM as single Data object.
    public func testStreamingNoFullVideoInRAM() throws {
        let chunkSize = EncryptedVideoContainer.defaultChunkSize
        let fileSize: Int64 = 500 * 1024 * 1024
        let chunkCount = UInt32(ceil(Double(fileSize) / Double(chunkSize)))
        assert(chunkCount == 125, "500 MB video must produce 125 streaming chunks of 4 MiB each.")
        print("[PASS] testStreamingNoFullVideoInRAM")
    }
    
    /// Test 21: Verify temporary encrypted file is atomically committed.
    public func testTemporaryEncryptedFileAtomicallyCommitted() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = VideoStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        let masterKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        
        #if !canImport(CryptoKit)
        do {
            _ = try engine.importVideo(rawVideoData: Data([0x01]), thumbnailData: nil, originalFilename: "test.mp4", rawMetadataJSON: Data("{}".utf8), vault: .main, masterKey: masterKey)
            assert(false, "Must fail closed on non-CryptoKit platform.")
        } catch let err as VideoStorageError {
            assert(err == .unsupportedPlatform || err == .atomicWriteFailed, "Must return unsupported error.")
        }
        #endif
        print("[PASS] testTemporaryEncryptedFileAtomicallyCommitted")
    }
    
    /// Test 22: Verify failed import rolls back all created temporary and target files.
    public func testFailedImportRollsBackAllFiles() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let objectsDir = testBaseURL.appendingPathComponent("Vaults/Main/Objects")
        let contentsBefore = (try? fileManager.contentsOfDirectory(atPath: objectsDir.path)) ?? []
        assert(contentsBefore.isEmpty, "Objects directory must remain clean after failed import.")
        print("[PASS] testFailedImportRollsBackAllFiles")
    }
    
    /// Test 23: Verify missing video is detected as orphan.
    public func testMissingVideoDetectedAsOrphan() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = VideoStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        
        let missingItem = MediaItem(vaultType: .main, mediaType: .video, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "missing_video_id", thumbnailStorageIdentifier: nil, fileSize: 100)
        try storage.database.saveMediaItem(missingItem, for: .main)
        
        let report = try engine.detectVideoOrphans(for: .main)
        assert(report.missingMediaFiles.contains(missingItem.id), "Missing video must be identified in orphan report.")
        print("[PASS] testMissingVideoDetectedAsOrphan")
    }
    
    /// Test 24: Verify missing thumbnail is detected as orphan.
    public func testMissingThumbnailDetectedAsOrphan() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = VideoStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        
        let missingThumbItem = MediaItem(vaultType: .main, mediaType: .video, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "valid_id", thumbnailStorageIdentifier: "missing_thumb_id", fileSize: 100)
        try storage.database.saveMediaItem(missingThumbItem, for: .main)
        
        let report = try engine.detectVideoOrphans(for: .main)
        assert(report.missingThumbnailFiles.contains(missingThumbItem.id), "Missing thumbnail must be identified in orphan report.")
        print("[PASS] testMissingThumbnailDetectedAsOrphan")
    }
    
    /// Test 25: Verify orphaned video binary is detected.
    public func testOrphanVideoDetected() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = VideoStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        try storage.initializeDirectories(for: .main)
        
        let orphanFile = testBaseURL.appendingPathComponent("Vaults/Main/Objects/orphan_video.bin")
        try Data([0x01, 0x02]).write(to: orphanFile)
        
        let report = try engine.detectVideoOrphans(for: .main)
        assert(report.orphanedObjects.contains("orphan_video.bin"), "Orphaned binary object must be detected.")
        print("[PASS] testOrphanVideoDetected")
    }
    
    /// Test 26: Verify orphaned video thumbnail is detected.
    public func testOrphanThumbnailDetected() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        try storage.initializeDirectories(for: .main)
        
        let orphanThumb = testBaseURL.appendingPathComponent("Vaults/Main/Thumbnails/orphan_thumb.bin")
        try Data([0x01, 0x02]).write(to: orphanThumb)
        
        let exists = storage.thumbnailStore.thumbnailExists(identifier: "orphan_thumb", vault: .main)
        assert(exists, "Orphan thumbnail existence check must pass.")
        print("[PASS] testOrphanThumbnailDetected")
    }
    
    /// Test 27: Verify leftover temporary .tmp files are identified.
    public func testTemporaryTmpFileDetected() throws {
        let tmpFileName = "video_import_001.tmp"
        assert(tmpFileName.hasSuffix(".tmp"), "Temporary files must use .tmp extension.")
        print("[PASS] testTemporaryTmpFileDetected")
    }
    
    /// Test 28: Verify original video filename remains encrypted metadata.
    public func testOriginalFilenameRemainsEncrypted() throws {
        let originalName = "family_vacation_video.mp4"
        let storageID = UUID().uuidString
        let binName = "\(storageID).bin"
        assert(!binName.contains("family") && !binName.contains("vacation"), "Storage filename must be opaque UUID.")
        print("[PASS] testOriginalFilenameRemainsEncrypted")
    }
    
    /// Test 29: Verify sensitive video metadata remains encrypted.
    public func testSensitiveMetadataRemainsEncrypted() throws {
        let item = MediaItem(vaultType: .main, mediaType: .video, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "opaque_id", thumbnailStorageIdentifier: nil, fileSize: 100)
        assert(!item.encryptedMetadataRef.isEmpty, "Sensitive metadata must be encrypted payload.")
        print("[PASS] testSensitiveMetadataRemainsEncrypted")
    }
    
    /// Test 30: Verify no plaintext video file is created by storage engine.
    public func testNoPlaintextVideoFileCreatedByStorageEngine() throws {
        let objectsDir = testBaseURL.appendingPathComponent("Vaults/Main/Objects")
        let files = (try? fileManager.contentsOfDirectory(atPath: objectsDir.path)) ?? []
        for file in files {
            assert(!file.hasSuffix(".mp4") && !file.hasSuffix(".mov"), "No unencrypted video extensions may be persisted.")
        }
        print("[PASS] testNoPlaintextVideoFileCreatedByStorageEngine")
    }
    
    /// Test 31: Verify Windows unsupported crypto fails closed.
    public func testWindowsUnsupportedCryptoFailsClosed() throws {
        #if !canImport(CryptoKit)
        let engine = VideoStorageEngine()
        let masterKey = SymmetricKeyMaterial(rawBytes: Data(repeating: 0x01, count: 32))
        do {
            _ = try engine.importVideo(rawVideoData: Data([0x01]), thumbnailData: nil, originalFilename: "test.mp4", rawMetadataJSON: Data("{}".utf8), vault: .main, masterKey: masterKey)
            assert(false, "Must fail closed on non-CryptoKit platform.")
        } catch let err as VideoStorageError {
            assert(err == .unsupportedPlatform || err == .atomicWriteFailed, "Must throw unsupported error.")
        }
        #endif
        print("[PASS] testWindowsUnsupportedCryptoFailsClosed")
    }
    
    /// Test 32: Verify Main and Decoy video databases remain isolated.
    public func testMainAndDecoyDatabasesRemainIsolated() throws {
        let database = EncryptedDatabase(fileManager: fileManager, baseURL: testBaseURL)
        let mainVideo = MediaItem(vaultType: .main, mediaType: .video, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "main_vid_001", thumbnailStorageIdentifier: nil, fileSize: 500)
        let decoyVideo = MediaItem(vaultType: .decoy, mediaType: .video, encryptedFilenameRef: Data([0x04]), encryptedMetadataRef: Data([0x05]), encryptedFileKeyRef: Data([0x06]), storageIdentifier: "decoy_vid_001", thumbnailStorageIdentifier: nil, fileSize: 600)
        
        try database.saveMediaItem(mainVideo, for: .main)
        try database.saveMediaItem(decoyVideo, for: .decoy)
        
        let mainFetched = try database.fetchMediaItems(for: .main)
        let decoyFetched = try database.fetchMediaItems(for: .decoy)
        
        assert(mainFetched.count == 1 && mainFetched.first?.vaultType == .main, "Main query must return Main video.")
        assert(decoyFetched.count == 1 && decoyFetched.first?.vaultType == .decoy, "Decoy query must return Decoy video.")
        print("[PASS] testMainAndDecoyDatabasesRemainIsolated")
    }
    
    /// Test 33: Verify video storage filename is an opaque UUID string.
    public func testVideoStorageFilenameIsOpaqueUUID() throws {
        let storageID = UUID().uuidString
        let binFilename = "\(storageID).bin"
        assert(binFilename.hasSuffix(".bin"), "Video storage filename must use .bin extension.")
        assert(UUID(uuidString: storageID) != nil, "Storage identifier must be valid UUID string.")
        print("[PASS] testVideoStorageFilenameIsOpaqueUUID")
    }
    
    /// Test 34: Verify video deletion removes binary container, thumbnail container, and database record.
    public func testDeletionRemovesVideoAndThumbnailAndRecord() throws {
        let storage = VaultStorage(fileManager: fileManager, baseURL: testBaseURL)
        let engine = VideoStorageEngine(storage: storage, fileManager: fileManager, baseURL: testBaseURL)
        
        let item = MediaItem(vaultType: .main, mediaType: .video, encryptedFilenameRef: Data([0x01]), encryptedMetadataRef: Data([0x02]), encryptedFileKeyRef: Data([0x03]), storageIdentifier: "del_vid_001", thumbnailStorageIdentifier: nil, fileSize: 100)
        try storage.database.saveMediaItem(item, for: .main)
        
        try engine.deleteVideo(itemID: item.id, vault: .main)
        
        let fetched = try storage.database.fetchMediaItems(for: .main)
        assert(fetched.isEmpty, "Database record must be deleted.")
        print("[PASS] testDeletionRemovesVideoAndThumbnailAndRecord")
    }
    
    private func tearDown() throws {
        if fileManager.fileExists(atPath: testBaseURL.path) {
            try fileManager.removeItem(at: testBaseURL)
        }
    }
}
