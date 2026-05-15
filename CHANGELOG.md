# Changelog

All notable changes to VaultSnap will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-15

Initial public release.

### Added

- Encrypted vault with AES-GCM-256 + Argon2id (per-entry encryption under a
  single Vault Master Key).
- Android Autofill service with biometric unlock. Per-entry website or
  Android-package linking, eTLD+1-aware domain matching, save-flow support.
- TOTP / Authenticator (RFC 6238): SHA-1 / SHA-256 / SHA-512, 6 or 8 digits,
  30 or 60 second periods. `otpauth://` URI paste import.
- Encrypted attachments (images, PDFs, recovery codes). On-device image
  viewer; non-image export via Storage Access Framework.
- Encrypted backups (`.vsb`) under a separate backup-password-derived key,
  with dry-run verify wizard that decrypts in memory without writing to
  disk.
- Recovery question path with separate KDF salt; unlocks the same VMK if
  the master password is forgotten.
- Biometric unlock backed by Android Keystore (`flutter_secure_storage`).
- Auto-lock on background and after a wall-clock-aware timer; wipes the
  master key from RAM on lock.
- In-app threat model (`Settings → How VaultSnap stores your data`),
  10-section plain-language explanation of the encryption model.
- Sensitive clipboard masking on Android 13+ via
  `ClipDescription.EXTRA_IS_SENSITIVE`.
- Verification script (`scripts/verify_release_manifest.{ps1,sh}`) that
  builds a release APK and asserts the merged `AndroidManifest.xml`
  contains no network permissions.

### Security

- Release build does **not** request the `INTERNET` permission. The
  Android OS itself blocks any network call.
- Master password is never stored — only the KDF-wrapped Vault Master
  Key, which is useless without the password.
- Autofill VMK transfer between Dart and Kotlin uses RSA-OAEP-SHA256
  (RFC 8017); plaintext key material never crosses the MethodChannel.
- R8 code shrinking, resource shrinking, and obfuscation enabled in
  release builds.
