<p align="center">
  <img src="assets/icon.png" alt="VaultSnap" width="128" height="128"/>
</p>

<h1 align="center">VaultSnap</h1>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"/></a>
  <a href="https://github.com/cedsceds-12/vaultsnap/actions/workflows/test.yml"><img src="https://github.com/cedsceds-12/vaultsnap/actions/workflows/test.yml/badge.svg?branch=main" alt="tests"/></a>
  <a href="https://github.com/cedsceds-12/vaultsnap/releases/latest"><img src="https://img.shields.io/github/v/release/cedsceds-12/vaultsnap?label=release" alt="Latest release"/></a>
  <a href="https://github.com/cedsceds-12/vaultsnap/releases"><img src="https://img.shields.io/github/downloads/cedsceds-12/vaultsnap/total" alt="Downloads"/></a>
  <img src="https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white" alt="Android"/>
  <img src="https://img.shields.io/badge/Flutter-3.11%2B-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
</p>

A **local-only**, offline-first password manager for Android. No cloud, no
accounts, no telemetry. Your vault never leaves the device — the release
build does not request the `INTERNET` permission, so the operating system
itself blocks any network call.

Built with Flutter and Kotlin. Material 3, Android 8.0+ (`minSdk` 26).

## Features

- **Encrypted vault** — passwords, TOTP secrets, and attachments encrypted
  with AES-GCM-256 under a Vault Master Key derived from your master
  password via Argon2id.
- **Android Autofill** — fills usernames and passwords into other apps and
  browsers. Per-entry website or Android-package linking.
- **TOTP / Authenticator** — RFC 6238 codes from `otpauth://` URIs.
  Supports SHA-1 / SHA-256 / SHA-512, 6 or 8 digits, 30 or 60 second
  periods.
- **Encrypted attachments** — store IDs, recovery codes, and scanned
  documents inside the vault. Built-in image viewer; other formats export
  through Android Storage Access Framework.
- **Biometric unlock** — fingerprint or face unlock backed by an Android
  Keystore key. Your biometric never leaves the secure hardware.
- **Encrypted backups** (`.vsb`) — encrypted under a separate
  backup-password-derived key. Verify a backup decrypts correctly before
  trusting it.
- **Recovery question** — separate key path unlocks the same VMK if you
  forget your master password.
- **Auto-lock** — wall-clock timer, locks immediately on background, wipes
  the master key from RAM.

## Threat model

The full plain-language threat model is in the app: **Settings → How
VaultSnap stores your data**. Summary:

- **Cleartext on disk:** entry names, usernames, URLs, and linked Android
  package IDs. Required so list, search, and autofill work without
  unlocking.
- **Encrypted on disk:** passwords, TOTP secrets, attachment bytes, and
  the wrapped Vault Master Key. Useless without the master password.
- **Recoverable:** if you remember the master password *or* the recovery
  answer. If you forget both, the vault is unrecoverable by design.

## Install

Download the latest signed APK from
[Releases](https://github.com/cedsceds-12/vaultsnap/releases) and sideload
on Android 8.0+.

Verify the download:

```bash
sha256sum VaultSnap-v1.0.0.apk
```

The SHA-256 hash is listed on each release page.

## Build from source

### Prerequisites

- Flutter 3.11.5 or newer
- JDK 17
- Android SDK with API 34+
- `minSdk` 26 (Android 8.0+, required by the Autofill API)

### Build

```bash
git clone https://github.com/cedsceds-12/vaultsnap.git
cd vaultsnap
flutter pub get
flutter run                   # debug
flutter build apk --release   # signed release APK
```

The release build runs through R8 (code shrinking + resource shrinking +
obfuscation). Keep rules live in `android/app/proguard-rules.pro`.

## Verify the no-network guarantee

VaultSnap's headline claim is that the release build cannot make network
calls. The repository ships a script that proves it:

```powershell
# Windows
pwsh ./scripts/verify_release_manifest.ps1
```

```bash
# Linux / macOS
./scripts/verify_release_manifest.sh
```

The script builds a release APK and asserts the merged
`AndroidManifest.xml` contains only `USE_BIOMETRIC` (plus benign
auto-added entries from `local_auth` and AndroidX). Any other permission
— especially `INTERNET`, `ACCESS_NETWORK_STATE`, `READ_*`, `WRITE_*`,
`CAMERA`, `RECORD_AUDIO` — fails the script with a non-zero exit.

Quick sanity check on a published APK:

```bash
aapt dump permissions VaultSnap-v1.0.0.apk
```

You will not find `android.permission.INTERNET`. By design.

## Project layout

```
lib/
├── screens/        Full-screen pages
├── widgets/        Reusable widgets
├── services/       Crypto, storage, autofill, clipboard, backup
├── providers/      Riverpod providers
├── models/         VaultMeta, VaultEntry, FieldSpec, EntryCategory
├── theme/          Material 3 theme
└── navigation/     Root navigator key

android/app/src/main/kotlin/com/vaultsnap/app/
                    Autofill service + RSA-OAEP bridge + MainActivity

test/               120 unit and widget tests
scripts/            verify_release_manifest.{ps1,sh}
```

## Tests

```bash
flutter analyze
flutter test
flutter test test/services/totp_service_test.dart   # one file
```

## License

MIT — see [LICENSE](LICENSE).
