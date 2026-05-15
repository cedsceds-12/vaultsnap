# VaultSnap

A **local-only**, offline-first password manager for Android. No cloud, no
accounts, no telemetry, no analytics. Your vault never leaves the device —
the release build doesn't even request the `INTERNET` permission, so the
operating system itself blocks any network call.

Built with Flutter / Kotlin. Android-first, iOS-capable.

## Features

- **Encrypted vault** — entries' sensitive fields (passwords, TOTP secrets,
  attachments) are encrypted under a 256-bit AES-GCM key derived from your
  master password (Argon2id).
- **Android Autofill** — fills usernames/passwords into other apps and
  browsers. The autofill service is local-only and supports per-entry
  Android-package or website links.
- **TOTP / Authenticator** — RFC 6238 codes from `otpauth://` URIs. SHA-1 /
  SHA-256 / SHA-512, 6 / 8 digits, 30 / 60 second periods.
- **Encrypted attachments** — store IDs, recovery codes, passport scans
  inside the vault. Image preview built in; other formats export through
  Android's Storage Access Framework.
- **Biometric unlock** — fingerprint / face unlock backed by an Android
  Keystore key. Your biometric never leaves the secure hardware.
- **Encrypted backups** (`.vsb`) — re-encrypted under a separate
  backup-password-derived key. Verify a backup decrypts correctly *before*
  you trust it (Settings → Verify backup).
- **Recovery question** — separate KDF salt unlocks the same VMK if you
  forget your master password.
- **Auto-lock** — wall-clock-aware timer, locks immediately when the app
  goes to the background, scrubs the VMK from RAM.

## Threat model (short version)

The full plain-language threat model is in the app: Settings → "How
VaultSnap stores your data". Three-bullet summary:

- **Cleartext on disk:** entry names, usernames, URLs, and linked Android
  package IDs. Required so list / search / autofill work without unlocking.
- **Encrypted on disk:** passwords, TOTP secrets, attachment bytes, the
  KDF-wrapped VMK. Useless without the master password.
- **Recoverable:** if you remember the master password OR the recovery
  answer. If you forget both, the vault is unrecoverable — by design.

## Build

### Prerequisites

- Flutter 3.11.5 or newer (`flutter --version`)
- JDK 17
- Android SDK with API 34+ (set via Android Studio's SDK Manager)
- `minSdk` is 26 (Android 8.0 — required by the Autofill API)

### Run debug

```bash
cd vault_snap
flutter pub get
flutter run
```

### Build release

Play Store submissions ship as Android App Bundle (`.aab`):

```bash
cd vault_snap
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

For sideloading or local QA you can also build an APK:

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

The release build runs through R8 (code shrinking + resource shrinking +
obfuscation). Keep rules live in `android/app/proguard-rules.pro`.

### Verifying the release build is offline

VaultSnap's headline guarantee is that the release build cannot make
network calls. Verify before every release:

```powershell
# Windows / PowerShell
pwsh ./scripts/verify_release_manifest.ps1
```

```bash
# macOS / Linux
./scripts/verify_release_manifest.sh
```

The script builds a release APK and parses the merged
`AndroidManifest.xml` for `<uses-permission>` entries. The allowlist:

- `android.permission.USE_BIOMETRIC` — declared by VaultSnap.
- `android.permission.USE_FINGERPRINT` — auto-added by the `local_auth`
  plugin for the pre-API-28 fingerprint API. Biometric only.
- `<package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` —
  AndroidX-generated, scoped to our own package, gates internal
  broadcast receivers.

Anything else — especially `INTERNET`, `ACCESS_NETWORK_STATE`,
`READ_*`, `WRITE_*`, `CAMERA`, `RECORD_AUDIO` — fails the script
with a non-zero exit.

Belt-and-braces sanity check on a built APK:

```bash
aapt dump permissions build/app/outputs/flutter-apk/app-release.apk
```

## Signing for release

Release builds use the upload-key path when `android/keystore.properties`
exists, and fall back to the debug key otherwise (so contributors can
`flutter run --release` without a keystore).

### One-time setup

```bash
# Generate the upload keystore. Run from the repo root.
keytool -genkey -v \
        -keystore vault_snap/android/upload-keystore.jks \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -alias upload
```

Copy the template:

```bash
cp vault_snap/android/keystore.properties.example \
   vault_snap/android/keystore.properties
```

Fill in the real values:

```properties
storeFile=../upload-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=upload
keyPassword=YOUR_KEY_PASSWORD
```

Both `keystore.properties` and `*.jks` are gitignored. **Never** commit
either. Lose either and you lose the ability to push updates to your Play
Store listing — back them up offline.

After uploading the first AAB to Play Console, enrol in **Play App
Signing**. Google then re-signs with the actual app-signing key on their
side; your upload key only signs uploads to Google.

## Project layout

```
vault_snap/
├── lib/
│   ├── screens/        Full-screen pages
│   ├── widgets/        Reusable widgets (lock scope, entry tile, sheets)
│   ├── services/       Crypto, storage, autofill, clipboard, backup, etc.
│   ├── providers/      Riverpod providers
│   ├── models/         VaultMeta, VaultEntry, FieldSpec, EntryCategory
│   ├── theme/          Material 3 theme — only place hex literals live
│   └── navigation/     Root navigator key (pop-to-root on lock)
├── android/
│   └── app/src/main/kotlin/com/vaultsnap/app/
│                       Autofill service + RSA-OAEP bridge + MainActivity
├── test/               Dart tests (unit + widget). 120 tests at last count.
├── scripts/            verify_release_manifest.{ps1,sh}
├── store/              Play Store listing copy + privacy policy + Data Safety
├── ROADMAP.md          Phase-by-phase progress
├── QA_CHECKLIST.md     Pre-release manual test pass
└── pubspec.yaml
```

## Tests

```bash
cd vault_snap
flutter test              # all tests (~120)
flutter test test/services/totp_service_test.dart   # single file
flutter analyze           # lint pass
```

## Contributing

Read [`CLAUDE.md`](../CLAUDE.md) at the repo root for the full conventions
(state-management split, no-network invariant, sensitive-logging rules,
testing requirements, end-of-turn checklist). The cursor mirror lives at
`.cursor/rules/vaultsnap.mdc`.

## Licence

TBD — pick before tagging 1.0.
