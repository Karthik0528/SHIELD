# PrivacyVault

**PrivacyVault** is a personal, local-only iOS application designed for securely storing and managing encrypted photos and videos directly on your device.

## Core Guarantees & Architecture

- **100% Local-Only**: Operates completely offline. No network requests, cloud sync, or external server communication.
- **Zero Third-Party Tracking**: No analytics, telemetry, Firebase, or external SDKs.
- **Privacy-First Design**: Media remains entirely within the app's local sandbox container.
- **500 MB Maximum Per-Item Limit**: Permanent project restriction enforcing a 500 MB maximum size limit per photo or video (`MediaSizePolicy`). Larger files are rejected prior to encryption or storage.

## Encrypted Storage Architecture

- **Dual-Vault Physical Isolation**: Independent directory subpaths for Main Vault (`Vaults/Main/`) and Decoy Vault (`Vaults/Decoy/`).
- **Per-Media & Per-Thumbnail Encryption Keys**: Every photo/video is encrypted with its own unique random 256-bit media key; every thumbnail is encrypted independently with its own unique thumbnail key.
- **Master Key Wrapping**: Per-item encryption keys are wrapped using the Vault Master Key (`VMK`) and stored in encrypted form in metadata database records.
- **Versioned Binary Container (`PV01` / `PVV1`)**:
  - Photos & thumbnails use `PV01` container format.
  - Videos use `PVV1` (PrivacyVault Video Format Version 1) container format with chunked AES-GCM payload encryption.
- **Opaque Storage Identifiers**: Disk filenames use random UUIDs (`Objects/<uuid>.bin` and `Thumbnails/<uuid>.bin`). Original filenames are never used as storage paths.
- **Atomic Writes & Rollback Transactions**: Disk operations write to temporary `.tmp` files and perform atomic moves prior to database commit.
- **Windows Fail-Closed Guarantee**: Cryptographic operations fail closed (`PlatformCryptoError.unsupportedPlatform`) on platforms without native `CryptoKit` support, preventing fake encryption or accidental plaintext persistence.

## Native iOS Media Import & Export (Step 6B)

- **Native PhotosUI Integration**: Uses SwiftUI native `PhotosPicker` (`PhotosUI`) for single and multi-selection photo and video import.
- **Video File URL Streaming**: Videos stream via `FileHandle` from local file URLs directly to `VideoStorageEngine.importVideo(sourceURL:)`. Complete 500 MB video files are NEVER loaded as Data into RAM.
- **Two-Way COPY Semantics**:
  - **Import**: Photos/videos selected from iOS Photos library are encrypted into the active vault. Original Photos items remain completely untouched.
  - **Export**: Encrypted vault media items can be exported back to native iOS Photos library (`PHPhotoLibrary`). Vault media items are never modified or deleted during export.
- **Active Vault Binding**: Destination vault is derived exclusively from `vaultManager.session.activeVaultType`. No manual Main vs Decoy toggle exists on import.
- **Encrypted Video Thumbnails**: Video thumbnails generated via `AVAssetImageGenerator` are encrypted with an independent random 256-bit key wrapped by active VMK.
- **In-Memory Decryption**: Export decryption occurs strictly in RAM via `EncryptedMediaStorageEngine`. SwiftUI views never perform direct decryption, and zero persistent plaintext export files are saved in the sandbox.
- **Zero Sample Media**: The vault remains completely empty until user media import.

## Secure Video Storage Architecture (Step 6A)

- **STEP 6A — TRUE STREAMING VIDEO ENCRYPTION**: Bounded FileHandle I/O reading 4 MiB buffer slices directly to encrypted output streams. Never loads full 500 MB videos into RAM.
- **MAX INDIVIDUAL MEDIA SIZE = 500 MB**: Centralized `MediaSizePolicy` enforces 500 MB limit for both photo and video imports before encryption or persistence.
- **Per-Video Key Hierarchy**: Every video receives a unique random 256-bit video key wrapped by the active vault's VMK.
- **Independent Video Thumbnail Key**: Video thumbnails are encrypted with a separate random 256-bit key wrapped by VMK.
- **Chunked AES-GCM Encryption (`PVV1`)**: Raw video payloads are processed in 4 MiB chunks. Each chunk receives a cryptographically secure random 12-byte nonce, 16-byte tag, and chunk ciphertext.
- **Authenticated Additional Data (AAD) Chunk & Header Binding**: AAD binds magic (`PVV1`), format version (`1`), object type (`0x01`), vault type (`0x01`/`0x02`), video UUID, chunkSize, chunkCount, and big-endian `chunkIndex` for every chunk. Modifying chunkSize, chunkCount, or chunk ordering causes authentication failure.
- **Main / Decoy Vault Isolation**: Videos are stored in domain-separated directories (`Vaults/Main/Objects` vs `Vaults/Decoy/Objects`). All video storage APIs explicitly require authenticated `VaultType`.
- **Atomic Writes & Rollback**: Video containers write to `.tmp` files and perform atomic moves to `.bin`. Failed imports execute complete file and database rollback.
- **Video Orphan Diagnostics**: `VideoStorageEngine.detectVideoOrphans(for:)` identifies missing video objects, missing thumbnails, orphaned binary files, and leftover `.tmp` files.

## Secure Photo Import Pipeline

- **COPY Semantics**: Photo import operates strictly as a copy operation. The user's original photo in their Photos library is never automatically modified or deleted.
- **17-Stage Pipeline**:
  1. Receive platform photo payload.
  2. Validate maximum media size limit (<= 500 MB) via `MediaSizePolicy`.
  3. Validate supported image format (JPEG/PNG/HEIC).
  4. Extract sensitive EXIF/GPS metadata into encrypted payload.
  5. Generate downscaled thumbnail bytes from actual photo payload.
  6. Serialize sensitive metadata to JSON.
  7. Generate random 256-bit media key.
  8. Encrypt original photo with AES-GCM.
  9. Generate separate random 256-bit thumbnail key.
  10. Encrypt thumbnail payload independently using AES-GCM.
  11. Wrap media key using destination vault VMK.
  12. Wrap thumbnail key using destination vault VMK.
  13. Persist binary media container (`Objects/<uuid>.bin`).
  14. Persist binary thumbnail container (`Thumbnails/<uuid>.bin`).
  15. Persist encrypted metadata payload.
  16. Commit database record.
  17. Clean up temporary plaintext references and verify.
- **Encrypted Sensitive Metadata**: Original filenames, EXIF tags, GPS coordinates, and user notes are stored strictly in encrypted form.
- **Independent Thumbnail Key**: Thumbnail payload is encrypted with its own random 256-bit key (never reuses the original media key) and stored in an opaque file (`Thumbnails/<uuid>.bin`).
- **Explicit Vault Binding**: All import APIs explicitly require `into vault: VaultType` (`.main` or `.decoy`).
- **Atomic Transaction & Rollback**: Import failures automatically remove newly created binary files (`.tmp` and `.bin`) and discard database changes.

## Project Structure

```text
PrivacyVault/
├── PrivacyVault.xcodeproj/     # Xcode Project configuration
├── PrivacyVault/
│   ├── App/                   # App lifecycle & entry point (@main)
│   ├── Core/                  # Domain models, security engines, storage & services
│   ├── Features/              # Modular feature domains (Setup, Lock, Gallery)
│   ├── Platform/              # Platform abstraction layer
│   ├── Tests/                 # Storage, import, gallery security, video & Step 6B test suites
│   ├── Views/                 # Common UI components & layouts
│   ├── Assets.xcassets/       # Colors, images, & app icons
│   ├── Preview Content/       # SwiftUI canvas preview assets
│   └── Info.plist             # iOS permissions & app metadata
└── README.md
```

## Getting Started

1. Open `PrivacyVault.xcodeproj` in Xcode 15 or later.
2. Select an iOS Simulator or connected iOS device running iOS 16.0+.
3. Build and run (`Cmd + R`).
