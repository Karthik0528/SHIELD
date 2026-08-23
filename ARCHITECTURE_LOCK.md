# PrivacyVault Architecture & Design System Lock

This document defines the **locked security, storage, and design architecture** for **PrivacyVault**.
All core security foundation modules (Steps 1 through 4B) are officially frozen and locked. No future UI or feature additions may modify, bypass, or simplify these underlying security invariants.

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
- **Versioned Binary Container (`PV01`)**: All encrypted media and thumbnails are persisted using a versioned binary format containing a magic header (`PV01`), object type, vault type, object UUID, VMK-wrapped key, 12-byte nonce, 16-byte authentication tag, and ciphertext.
- **Authenticated Additional Data (AAD) Vault Binding**: AAD binds container headers to `vaultType` (`0x01` Main vs `0x02` Decoy), object UUID, object type, and format version, preventing cross-vault object substitution.
- **Opaque Disk Filenames**: Disk objects are stored using opaque UUID strings (`Objects/<uuid>.bin`, `Thumbnails/<uuid>.bin`). Original filenames are never used as storage paths or disk filenames.
- **Atomic Writes & Rollback Transactions**: Disk operations write to temporary `.tmp` files and perform atomic moves prior to database commit. Failed imports automatically purge newly written `.tmp` and `.bin` files.
- **COPY Semantics**: Photo import operates strictly as a copy operation. The user's original photo in their Photos library is never automatically modified or deleted.
- **Windows Fail-Closed Guarantee**: Cryptographic operations fail closed (`PlatformCryptoError.unsupportedPlatform`) on platforms without native `CryptoKit` support, preventing fake encryption or accidental plaintext persistence.
- **Session Locking & Key Material Purge**: Locking a vault invalidates the active `SecureSession` and purges in-memory `VMK` handles (`cachedMasterKeys`), requiring re-authentication to load key material again.

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

## 3. Photo Import Pipeline (17 Stages)

```text
1. Receive platform photo payload (rawImageData, originalFilename, vault)
   ↓
2. Validate supported image format (JPEG / PNG / HEIC)
   ↓
3. Determine resolution & size attributes
   ↓
4. Extract sensitive EXIF / GPS metadata into SensitivePhotoMetadata
   ↓
5. Generate thumbnail bytes from photo payload via ThumbnailGeneratorProtocol
   ↓
6. Serialize sensitive metadata to JSON
   ↓
7. Generate random 256-bit media key
   ↓
8. Encrypt original photo payload using AES-GCM via EncryptionEngineProtocol
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

## 4. Known Future Platform Integration Work (iOS Target)

The core architecture abstracts iOS platform components using clean protocol boundaries. The following concrete iOS implementations will be completed when deploying to macOS/Xcode:

1. **Production Password KDF**: Benchmark and connect native PBKDF2/Argon2 key derivation under `PasswordKeyDerivationProtocol`.
2. **iOS Keychain Accessibility Flags**: Configure `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on `PlatformKeychainProtocol`.
3. **Backup Exclusion (`.noBackup`)**: Set `isExcludedFromBackup = true` on local storage directories (`Vaults/Main`, `Vaults/Decoy`) to prevent inclusion in unencrypted iTunes/iCloud backups.
4. **App Switcher Privacy Overlay**: Apply a privacy blur overlay during `willResignActiveNotification` to hide sensitive screen previews when switching apps.
5. **PhotosUI / PHPicker Integration**: Connect `PHPickerViewController` / SwiftUI `PhotosPicker` under `PlatformMediaProtocol`.
6. **Hardware-Backed Biometrics**: Integrate `LAContext` Face ID / Touch ID under `PlatformBiometricsProtocol`.
7. **Real-Device Performance Testing**: Validate container encoding and AES-GCM decryption performance on physical iOS hardware.

---

## 5. Locked UI Design Language

All future application screens, components, and views MUST adhere strictly to this locked design system:

### Aesthetic Principles
- **Theme**: Dark black/navy base with deep violet/purple atmospheric accents.
- **Look & Feel**: Private, sleek, state-of-the-art security product (not a standard media gallery app).
- **Surface Styling**: Glassmorphism surfaces, translucent cards, ultra-thin subtle borders (`Color.white.opacity(0.1)`), soft ambient shadows.
- **Typography**: Clean modern typography with distinct hierarchy and high legibility.
- **Primary Actions**: Rich purple-to-violet linear gradients (`LinearGradient(colors: [Color(hex: "7C3AED"), Color(hex: "8B5CF6")], ...)`).

### Strict Design Directives
- **AVOID** generic default SwiftUI styling (e.g. standard gray Form views or default List layouts).
- **AVOID** copying Apple's system Photos app styling.
- **AVOID** excessive or rainbow color palettes. Maintain strict color discipline.
- **AVOID** visible Main/Decoy toggle buttons on lock or setup screens.
