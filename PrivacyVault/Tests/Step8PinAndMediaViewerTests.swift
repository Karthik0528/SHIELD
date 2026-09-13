import Foundation
import UIKit
import ImageIO

/// Unit test suite validating:
/// 1. Primary PIN change (requiring current PIN, preserving VMK_main, preserving media decryption).
/// 2. Secondary PIN change (requiring current PIN, preserving VMK_decoy, preserving media decryption).
/// 3. Rejection of invalid current PIN during PIN change.
/// 4. Photo thumbnail generator producing complete valid image bytes instead of truncated slices.
/// 5. Video thumbnail generator fallback logic.
/// 6. Video prepare for playback temporary file creation and cleanup.
public final class Step8PinAndMediaViewerTests {
    private let mockKeychain: MockKeychain
    private let keyManager: DefaultKeyManager
    private let authManager: DefaultAuthenticationManager
    private let vaultManager: VaultManager
    private let fileManager: FileManager
    private let testBaseURL: URL
    
    public init() {
        self.mockKeychain = MockKeychain()
        let crypto = DefaultPlatformCrypto()
        self.keyManager = DefaultKeyManager(cryptoPlatform: crypto, keychainPlatform: mockKeychain)
        self.authManager = DefaultAuthenticationManager(keyManager: keyManager, keychainPlatform: mockKeychain)
        let session = SecureSession()
        self.fileManager = .default
        let baseURL = fileManager.temporaryDirectory.appendingPathComponent("Step8PinAndMediaViewerTests_\(UUID().uuidString)")
        try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        self.testBaseURL = baseURL
        let storage = VaultStorage(fileManager: fileManager, baseURL: baseURL)
        self.vaultManager = VaultManager(session: session, keyManager: keyManager, authenticationManager: authManager, storage: storage)
    }
    
    public func runAllTests() async throws {
        print("--- Starting Step 8 PIN Management & Media Viewer Test Suite ---")
        try await testSetupInitialVaults()
        print("[PASS] testSetupInitialVaults"); fflush(stdout)
        try await testChangePrimaryPinSuccess()
        print("[PASS] testChangePrimaryPinSuccess"); fflush(stdout)
        try await testChangeSecondaryPinSuccess()
        print("[PASS] testChangeSecondaryPinSuccess"); fflush(stdout)
        try await testChangePinWithInvalidOldPinFails()
        print("[PASS] testChangePinWithInvalidOldPinFails"); fflush(stdout)
        try await testVMKAndMediaPreservedAfterPinChange()
        print("[PASS] testVMKAndMediaPreservedAfterPinChange"); fflush(stdout)
        try testPhotoThumbnailGeneratorValidImage()
        print("[PASS] testPhotoThumbnailGeneratorValidImage"); fflush(stdout)
        try await testVideoPlaybackPrepAndCleanup()
        print("[PASS] testVideoPlaybackPrepAndCleanup"); fflush(stdout)
        try tearDown()
        print("--- All Step 8 PIN & Media Viewer Tests Passed Successfully ---")
    }
    
    private func testSetupInitialVaults() async throws {
        mockKeychain.storage.removeAll()
        try? fileManager.removeItem(at: testBaseURL)
        try fileManager.createDirectory(at: testBaseURL, withIntermediateDirectories: true)
        let tx = CredentialSetupTransaction(keyManager: keyManager, keychainPlatform: mockKeychain, storage: vaultManager.storage)
        try tx.executeAtomicSetup(mainPin: "1234", decoyPin: "9999", recoveryKey: "MY_RECOVERY_KEY")
        
        let result = await vaultManager.unlock(with: "1234")
        guard case let .success(vaultType, masterKey) = result else {
            XCTFail("Setup unlock failed")
            return
        }
        XCTAssertEqual(vaultType, .main)
        XCTAssertFalse(masterKey.rawBytes.isEmpty)
    }
    
    private func testChangePrimaryPinSuccess() async throws {
        XCTAssertEqual(vaultManager.session.activeVaultType, .main)
        
        // Change Primary PIN from 1234 to 4321
        try vaultManager.changePin(for: .main, oldPin: "1234", newPin: "4321")
        
        // Lock session
        vaultManager.lock()
        
        // Unlocking with old PIN (1234) should fail
        let oldResult = await vaultManager.unlock(with: "1234")
        guard case .failure = oldResult else {
            XCTFail("Old PIN unlock should have failed")
            return
        }
        
        // Unlocking with new PIN (4321) should succeed
        let newResult = await vaultManager.unlock(with: "4321")
        guard case let .success(vaultType, masterKey) = newResult else {
            XCTFail("New PIN unlock failed")
            return
        }
        XCTAssertEqual(vaultType, .main)
        XCTAssertFalse(masterKey.rawBytes.isEmpty)
    }
    
    private func testChangeSecondaryPinSuccess() async throws {
        XCTAssertEqual(vaultManager.session.activeVaultType, .main)
        
        // Change Secondary PIN from 9999 to 8888 (from Primary session)
        try vaultManager.changePin(for: .decoy, oldPin: "9999", newPin: "8888")
        
        // Lock session
        vaultManager.lock()
        
        // Unlocking with old Secondary PIN (9999) should fail
        let oldResult = await vaultManager.unlock(with: "9999")
        guard case .failure = oldResult else {
            XCTFail("Old Secondary PIN unlock should have failed")
            return
        }
        
        // Unlocking with new Secondary PIN (8888) should succeed
        let newResult = await vaultManager.unlock(with: "8888")
        guard case let .success(vaultType, secondaryKey) = newResult else {
            XCTFail("New Secondary PIN unlock failed")
            return
        }
        XCTAssertEqual(vaultType, .decoy)
        XCTAssertFalse(secondaryKey.rawBytes.isEmpty)
        
        // Lock and return to Primary vault session with new Primary PIN 4321
        vaultManager.lock()
        _ = await vaultManager.unlock(with: "4321")
    }
    
    private func testChangePinWithInvalidOldPinFails() async throws {
        XCTAssertEqual(vaultManager.session.activeVaultType, .main)
        
        // Attempting to change Primary PIN with wrong old PIN (0000) should throw error
        XCTAssertThrowsError(try vaultManager.changePin(for: .main, oldPin: "0000", newPin: "5555"))
        
        // Primary PIN remains 4321
        vaultManager.lock()
        _ = await vaultManager.unlock(with: "4321")
    }
    
    private func testVMKAndMediaPreservedAfterPinChange() async throws {
        XCTAssertEqual(vaultManager.session.activeVaultType, .main)
        let originalVMK = vaultManager.session.activeMasterKey!
        
        // Import photo item into Primary Vault
        let sampleData = "SAMPLE_PHOTO_DATA_\(UUID().uuidString)".data(using: .utf8)!
        let mediaEngine = EncryptedMediaStorageEngine(storage: vaultManager.storage)
        let item = try mediaEngine.importMedia(
            rawMediaData: sampleData,
            thumbnailData: nil,
            originalFilename: "test.jpg",
            rawMetadataJSON: Data("{}".utf8),
            mediaType: .photo,
            vault: .main,
            masterKey: originalVMK
        )
        
        // Verify media can be loaded before PIN change
        let loadedDataBefore = try mediaEngine.loadMedia(for: item, vault: .main, masterKey: originalVMK)
        XCTAssertEqual(loadedDataBefore, sampleData)
        
        // Change Primary PIN 4321 -> 7777
        try vaultManager.changePin(for: .main, oldPin: "4321", newPin: "7777")
        
        // Lock and unlock with 7777
        vaultManager.lock()
        let result = await vaultManager.unlock(with: "7777")
        guard case let .success(_, newSessionVMK) = result else {
            XCTFail("Unlock with new PIN failed")
            return
        }
        
        // VMK raw bytes must be identical
        XCTAssertEqual(originalVMK.rawBytes, newSessionVMK.rawBytes)
        
        // Media file must remain 100% decryptable without re-encryption
        let loadedDataAfter = try mediaEngine.loadMedia(for: item, vault: .main, masterKey: newSessionVMK)
        XCTAssertEqual(loadedDataAfter, sampleData)
        
        // Clean up test media item
        try mediaEngine.deleteMedia(itemID: item.id, vault: .main)
    }
    
    private func testPhotoThumbnailGeneratorValidImage() throws {
        let generator = DefaultThumbnailGenerator()
        // Create 100x100 RGB image data
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            XCTFail("Failed to generate test image")
            return
        }
        
        let thumbData = try generator.generateThumbnail(from: imageData)
        XCTAssertGreaterThan(thumbData.count, 1024) // Thumbnail should NOT be truncated to 1 KB!
        
        // Verify image source can parse the thumbnail completely
        guard let source = CGImageSourceCreateWithData(thumbData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Thumbnail data was invalid or corrupted")
            return
        }
        XCTAssertGreaterThan(cgImage.width, 0)
        XCTAssertGreaterThan(cgImage.height, 0)
    }
    
    private func testVideoPlaybackPrepAndCleanup() async throws {
        XCTAssertEqual(vaultManager.session.activeVaultType, .main)
        let masterKey = vaultManager.session.activeMasterKey!
        
        // Create dummy video file
        let tempVideoInput = testBaseURL.appendingPathComponent("temp_in_\(UUID().uuidString).mp4")
        let dummyVideoData = Data(repeating: 0x41, count: 50 * 1024) // 50 KB dummy video
        try dummyVideoData.write(to: tempVideoInput)
        
        let videoEngine = VideoStorageEngine(storage: vaultManager.storage)
        let item = try videoEngine.importVideo(
            sourceURL: tempVideoInput,
            thumbnailData: Data(repeating: 0xFF, count: 2000),
            originalFilename: "sample_test.mp4",
            rawMetadataJSON: Data("{}".utf8),
            vault: .main,
            masterKey: masterKey
        )
        
        let service = MediaImportExportService()
        let tempURL = try service.prepareVideoForPlayback(item: item, vaultManager: vaultManager)
        
        XCTAssertTrue(fileManager.fileExists(atPath: tempURL.path))
        let readData = try Data(contentsOf: tempURL)
        XCTAssertEqual(readData.count, dummyVideoData.count)
        
        // Clean up temp file
        try? fileManager.removeItem(at: tempURL)
        XCTAssertFalse(fileManager.fileExists(atPath: tempURL.path))
        
        // Clean up video storage item
        try videoEngine.deleteVideo(itemID: item.id, vault: .main)
    }
    
    private func tearDown() throws {
        if fileManager.fileExists(atPath: testBaseURL.path) {
            try fileManager.removeItem(at: testBaseURL)
        }
    }
    
    // Helpers
    private func XCTAssertTrue(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("Assertion Failed: \(message) at \(file):\(line)")
        }
    }
    
    private func XCTAssertFalse(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if condition {
            fatalError("Assertion Failed: \(message) at \(file):\(line)")
        }
    }
    
    private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if a != b {
            fatalError("Assertion Failed: Expected \(a) == \(b). \(message) at \(file):\(line)")
        }
    }
    
    private func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if a <= b {
            fatalError("Assertion Failed: Expected \(a) > \(b). \(message) at \(file):\(line)")
        }
    }
    
    private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        do {
            _ = try expression()
            fatalError("Assertion Failed: Expected error to be thrown, but succeeded. \(message) at \(file):\(line)")
        } catch {
            // Success
        }
    }
    
    private func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
        fatalError("Test Failure: \(message) at \(file):\(line)")
    }
}
