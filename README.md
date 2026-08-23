# PrivacyVault

**PrivacyVault** is a personal, local-only iOS application designed for securely storing and managing encrypted photos and videos directly on your device.

## Core Guarantees & Architecture

- **100% Local-Only**: Operates completely offline. No network requests, cloud sync, or external server communication.
- **Zero Third-Party Tracking**: No analytics, telemetry, Firebase, or external SDKs.
- **Privacy-First Design**: Media remains entirely within the app's local sandbox container.

## Encrypted Storage Architecture

- **Dual-Vault Physical Isolation**: Independent directory subpaths for Main Vault (`Vaults/Main/`) and Decoy Vault (`Vaults/Decoy/`).
- **Per-Media & Per-Thumbnail Encryption Keys**: Every photo/video is encrypted with its own unique random 256-bit media key; every thumbnail is encrypted independently with its own unique thumbnail key.
- **Master Key Wrapping**: Per-item encryption keys are wrapped using the Vault Master Key (`VMK`) and stored in encrypted form in metadata database records.
- **Versioned Binary Container (`PV01`)**: Encrypted payloads are stored using a versioned binary format containing magic header (`PV01`), object type, vault type, object UUID, wrapped key, 12-byte AES-GCM nonce, 16-byte authentication tag, and ciphertext.
- **Opaque Storage Identifiers**: Disk filenames use random UUIDs (`Objects/<uuid>.bin` and `Thumbnails/<uuid>.bin`). Original filenames are never used as storage paths.
- **Atomic Writes & Rollback Transactions**: Disk operations write to temporary `.tmp` files and perform atomic moves prior to database commit.
- **Windows Fail-Closed Guarantee**: Cryptographic operations fail closed (`PlatformCryptoError.unsupportedPlatform`) on platforms without native `CryptoKit` support, preventing fake encryption or accidental plaintext persistence.

## Secure Photo Import Pipeline

- **COPY Semantics**: Photo import operates strictly as a copy operation. The user's original photo in their Photos library is never automatically modified or deleted.
- **17-Stage Pipeline**:
  1. Receive platform photo payload.
  2. Validate supported image format (JPEG/PNG/HEIC).
  3. Determine resolution & size attributes.
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
│   ├── Features/              # Modular feature domains (Setup, Lock)
│   ├── Platform/              # Platform abstraction layer
│   ├── Tests/                 # Storage engine & import test suites
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
