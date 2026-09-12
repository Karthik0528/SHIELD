# PrivacyVault Architecture & Design System Lock

This document defines the **locked security, storage, technology stack, and design architecture** for **PrivacyVault**.
All core security foundation modules (Steps 1 through 6B) are officially frozen and locked. No future UI or feature additions may modify, bypass, or simplify these underlying security invariants or replace the technology stack.

---

## 1. Locked Security Invariants

- **100% Local-Only Architecture**: Zero network requests (`URLSession`, `Network`), no cloud storage, no backend servers, no Firebase, no analytics, no telemetry, and no external tracking SDKs.
- **Dual-Vault Cryptographic Separation**: Main Vault (`.main`) and Decoy Vault (`.decoy`) are completely independent:
  - Separate random salt values (`Salt_main` vs `Salt_decoy`).
  - Separate Vault Master Keys (`VMK_main` vs `VMK_decoy`).
  - Separate storage namespaces (`Vaults/Main/` vs `Vaults/Decoy/`).
  - Separate database partitions.
- **No Plaintext Credential Persistence**: Plaintext PINs/passcodes exist only as short-lived local variables during key derivation. They are never written to `UserDefaults`, SQLite, disk files, or logs.
- **No PIN Direct Key Usage**: PINs are never used directly as encryption keys; key derivation (`PasswordKeyDerivationProtocol`) produces a Key Encryption Key (`KEK`), which unwraps the Vault Master Key (`VMK`).
- **Per-Media & Independent Thumbnail Keys**:
  - Each photo/video payload is encrypted with its own unique random 256-bit media key.
  - Each thumbnail payload is encrypted independently with its own unique 256-bit thumbnail key.
  - Media keys are **never** reused for thumbnails.
- **Authenticated Symmetric Encryption**: All encryption uses AES-GCM 256 with cryptographically secure random nonces and 16-byte authentication tags. No nonces are reused or hardcoded.
- **Versioned Binary Container (`PV01` / `PVV1`)**: All encrypted media and thumbnails are persisted using versioned binary formats (`PV01` for photos/thumbnails; `PVV1` for chunked videos) containing magic header, object type, vault type, object UUID, VMK-wrapped key, 12-byte nonce, 16-byte authentication tag, and ciphertext.
- **Authenticated Additional Data (AAD) Vault & Header Binding**: AAD binds container headers (`PVV1`), version, objectType, `vaultType` (`0x01` Main vs `0x02` Decoy), object UUID, chunkSize, chunkCount, and chunk index, preventing cross-vault object substitution, header metadata tampering, or chunk reordering.
- **Opaque Disk Filenames**: Disk objects are stored using opaque UUID strings (`Objects/<uuid>.bin`, `Thumbnails/<uuid>.bin`). Original filenames are never used as storage paths or disk filenames.
- **Atomic Writes & Rollback Transactions**: Disk operations write to temporary `.tmp` files and perform atomic moves prior to database commit. Failed imports automatically purge newly written `.tmp` and `.bin` files.
- **COPY Semantics**: Photo/video import and export operate strictly as copy operations. The user's original media in their Photos library is never automatically modified or deleted.
- **Windows Fail-Closed Guarantee**: Cryptographic operations fail closed (`PlatformCryptoError.unsupportedPlatform`) on platforms without native `CryptoKit` support, preventing fake encryption or accidental plaintext persistence.
- **Session Locking & Key Material Purge**: Locking a vault invalidates the active `SecureSession` and purges in-memory `VMK` handles (`cachedMasterKeys`), requiring re-authentication to load key material again.
- **MAX INDIVIDUAL MEDIA SIZE = 500 MB**: Maximum individual media size is permanently capped at 500 MB (`524_288_000` bytes). Payload size is validated via centralized `MediaSizePolicy` prior to encryption or persistence for both photos and videos.

---

## 2. Main / Decoy Isolation Architecture

```text
Main PIN                           Decoy PIN
   │                                  │
   ▼                                  ▼
KEK (Salt_main)                    KEK (Salt_decoy)
   │                                  │
   ▼                                  ▼
VMK_main                           VMK_decoy
   │                                  │
   ├── Objects/  (Vaults/Main/Objects/)   ├── Objects/  (Vaults/Decoy/Objects/)
   ├── Thumbs/   (Vaults/Main/Thumbs/)     ├── Thumbs/   (Vaults/Decoy/Thumbs/)
   └── Database/ (Vaults/Main/Database/)   └── Database/ (Vaults/Decoy/Database/)
```

---

## 3. Photo & Video Import Pipeline

```text
1. Receive platform media payload (sourceURL, originalFilename, vault)
   ↓
2. Validate maximum media size limit (<= 500 MB) via MediaSizePolicy
   ↓
3. Validate supported media format
   ↓
4. Extract sensitive metadata into encrypted payload
   ↓
5. Generate thumbnail bytes from media payload via ThumbnailGeneratorProtocol
   ↓
6. Serialize sensitive metadata to JSON
   ↓
7. Generate random 256-bit media key (or video key)
   ↓
8. Encrypt original media payload using AES-GCM (PV01 for photo; PVV1 chunked streaming I/O for video)
   ↓
9. Generate separate random 256-bit thumbnail key (independent from media key)
   ↓
10. Encrypt thumbnail payload independently using AES-GCM
   ↓
11. Wrap media key using destination vault's Vault Master Key (VMK)
   ↓
12. Wrap thumbnail key using destination vault's VMK
   ↓
13. Persist binary media container (Objects/<uuid>.bin)
   ↓
14. Persist binary thumbnail container (Thumbnails/<uuid>.bin)
   ↓
15. Persist encrypted metadata payload
   ↓
16. Commit database record to vault database
   ↓
17. Purge in-memory plaintext references & verify persistent records
```

---

## 4. Locked Technology Stack

The technology stack for **PrivacyVault** is permanently locked across all development phases:

- **Programming Language**: Swift
- **UI Framework**: SwiftUI
- **Application Platform**: Native iOS
- **Project Structure**: Native Xcode Project (`PrivacyVault.xcodeproj`)
- **Cryptography Framework**: Apple `CryptoKit`
- **Keychain & Credential Storage**: Apple `Security` framework / Keychain
- **Biometrics Framework**: Apple `LocalAuthentication`
- **Media & Photos Integration**: Apple `Photos` / `PhotosUI` / `AVFoundation`
- **File System Storage**: iOS application sandbox, `FileManager`, `VaultStorage` & `FileStore` abstractions
- **Database Subsystem**: Existing `Database` abstraction and JSON metadata persistence (do not replace without explicit approval)
- **Application Architecture**: `Core` / `Services` / `Storage` / `Security` / `Platform` protocol-oriented architecture
- **Networking / Backend / Cloud**: NONE (100% local-only)
- **Analytics / Telemetry**: NONE

### Explicitly Prohibited Stack Changes (Without Explicit User Approval)
- React Native, Expo, Flutter, Kotlin, Android
- Web technologies (HTML/JS/CSS web apps, Electron, Ionic)
- Firebase, Supabase, Cloudflare, AWS, or any cloud database/server
- Cloud media storage or remote backups
- Third-party authentication or analytics SDKs
- Replacing SwiftUI with UIKit or another UI framework
- Replacing Apple `CryptoKit` with custom cryptography
- Replacing the locked `VaultStorage`, `EncryptedMediaStorageEngine`, or `Database` architecture

### Allowed Native Apple Framework Additions
Native Apple iOS frameworks may be introduced when required for platform features without altering the stack:
- `CryptoKit`, `Security`, `LocalAuthentication`, `Photos`, `PhotosUI`, `ImageIO`, `CoreGraphics`, `AVFoundation`, `UIKit` (where required for native iOS integration).

### Development Environment Policy (Windows)
Developing in a Windows environment must **NEVER** trigger a stack migration or framework replacement. Platform-specific iOS capabilities remain behind `Platform/` abstractions with safe fail-closed placeholders until macOS/Xcode testing.

---

## 5. Known Future Platform Integration Work (iOS Target)

The core architecture abstracts iOS platform components using clean protocol boundaries. The following concrete iOS implementations will be completed when deploying to macOS/Xcode:

1. **Production Password KDF**: Benchmark and connect native PBKDF2/Argon2 key derivation under `PasswordKeyDerivationProtocol`.
2. **iOS Keychain Accessibility Flags**: Configure `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on `PlatformKeychainProtocol`.
3. **Backup Exclusion (`.noBackup`)**: Set `isExcludedFromBackup = true` on local storage directories (`Vaults/Main`, `Vaults/Decoy`) to prevent inclusion in unencrypted iTunes/iCloud backups.
4. **App Switcher Privacy Overlay**: Apply a privacy blur overlay during `willResignActiveNotification` to hide sensitive screen previews when switching apps.
5. **PhotosUI / PHPicker Integration**: Connect `PHPickerViewController` / SwiftUI `PhotosPicker` under `PlatformMediaProtocol`.
6. **Hardware-Backed Biometrics**: Integrate `LAContext` Face ID / Touch ID under `PlatformBiometricsProtocol`.
7. **AVFoundation Video Playback**: Streaming decryption pipeline for native iOS AVFoundation video player integration.
8. **Real-Device Performance Testing**: Validate container encoding and AES-GCM decryption performance on physical iOS hardware.

---

## 6. Locked UI Design Language

All future application screens, components, and views MUST adhere strictly to this locked design system:

### Aesthetic Principles
- **Theme**: Dark black/navy base with deep violet/purple atmospheric accents.
- **Look & Feel**: Private, sleek, state-of-the-art security product (not a standard media gallery app).
- **Surface Styling**: Glassmorphism surfaces, translucent cards, ultra-thin subtle borders (`Color.white.opacity(0.1)`), soft ambient shadows.
- **Typography**: Clean modern typography with distinct hierarchy and high legibility.
- **Primary Actions**: Rich purple-to-violet linear gradients (`LinearGradient(colors: [Color(hex: "7C3AED"), Color(hex: "8B5CF6")], ...)`).

---

## 7. Step 5 — Secure Photo Gallery Lock

**Status**: **APPROVED / LOCKED**

---

## 8. Step 6A — Secure Video Storage Architecture Lock

**Status**: **APPROVED / LOCKED**

---

## 9. Step 6B — Native iOS Photo & Video Import & Export Integration Lock

**Status**: **APPROVED / LOCKED**

> [!IMPORTANT]
> Real iOS validation is still pending and must be performed later on macOS + Xcode + real iPhone.

### Step 6B Locked Invariants & Integration Specification
1. **Native PhotosPicker Integration**: Native SwiftUI `PhotosPicker` (`PhotosUI`) for single and multi-selection of photos and videos.
2. **One-Click Add Media Workflow**: Toolbar and empty gallery view trigger native iOS Photos library picker directly.
3. **One-Click Single-Item Export**: Single media detail viewer provides one-click export back to native iOS Photos library.
4. **Multi-Selection Export**: Multi-select gallery mode supports exporting all selected items to native iOS Photos library in a single action.
5. **Session-Bound Vault Target**: Destination vault for import and active media for export are derived strictly from `vaultManager.session.activeVaultType`. No manual Main vs Decoy UI picker exists.
6. **Main and Decoy Vault Physical Isolation**: Main Vault imports to `Vaults/Main/`; Decoy Vault imports to `Vaults/Decoy/`. Zero cross-vault access.
7. **Permanent 500 MB Size Limit**: Centralized `MediaSizePolicy` caps individual photo and video size at 500 MB (`524_288_000` bytes). Rejection occurs before encryption or persistence.
8. **Import COPY Semantics**: Photo and video imports encrypt copies into the active vault. User original Photos library media is NEVER modified or deleted.
9. **Export COPY Semantics**: Exporting media to native iOS Photos library saves a copy and NEVER modifies or deletes encrypted vault items.
10. **Video Bounded Streaming Encryption**: Video import streams 4 MiB buffer slices via `FileHandle` directly into encrypted `.tmp` files.
11. **Video Bounded Streaming Decryption**: Video export streams chunked 4 MiB AES-GCM decryption via `StreamingVideoExportService` directly into temporary export files.
12. **Zero Full-Video Data Materialization**: Complete 500 MB video payloads are NEVER materialized as a single `Data` object in RAM during import or export.
13. **PVV1 Chunk AAD Integrity**: AAD binds magic (`PVV1`), version (`1`), objectType (`0x01`), vaultType (`0x01`/`0x02`), video UUID (16 bytes), `chunkSize`, `chunkCount`, and `chunkIndex`.
14. **Sandbox Protected Temporary Export Files**: Temporary export files exist strictly inside `FileManager.default.temporaryDirectory` outside `Vaults/Main` and `Vaults/Decoy`.
15. **Automatic Temporary File Cleanup**: Temporary export files are purged via `defer` blocks on success, failure, cancellation, or session lock.
16. **Session Invalidation Abort**: Unauthenticated sessions or vault locks immediately terminate import and export tasks and purge temporary files.
17. **100% Local-Only Architecture**: Zero network calls, zero cloud APIs, zero CloudKit, zero Firebase, zero Supabase, zero analytics/tracking SDKs.
18. **Step 6A Frozen Files Untouched**: All 6 Step 6A files (`MediaSizePolicy.swift`, `EncryptedVideoContainer.swift`, `VideoStorageEngine.swift`, `PhotoImportService.swift`, `PlatformCryptoProtocol.swift`, `VideoStorageTests.swift`) remain 100% UNTOUCHED.
19. **Pending macOS/Xcode XCTest Execution**: Native XCTest suite execution remains pending until macOS + Xcode environment is available.
20. **Verified Unit Test Registration**: Total registered tests: 116 tests across 5 test suites (116 statically verified via `verify_tests.py`, 0 executed on Windows host).
