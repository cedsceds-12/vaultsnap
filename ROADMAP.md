# VaultSnap — roadmap & current state

> Edit this file as phases complete. Last updated: **2026-05-02** (Phases 1–11 done; 1.0 release-ready, manual QA pass owed).

## Progress snapshot

| Phase | Title | Status |
|-------|-------|--------|
| **1** | Crypto + `vault_meta` storage | **Done** |
| **2** | Setup wizard + first-run gate + real unlock | **Done** (MVP) |
| **3** | `VaultLockScope`, overlay lock, session VMK, auto-lock, biometric | **Done** |
| **4** | Live encrypted vault data | **Done** |
| **5** | Privacy / security settings (wipe, change pw, backup, etc.) | **Done** |
| **6** | Recovery unlock + reuse detection | **Done** |
| **7** | Android Autofill (strictly offline) | **Done** |
| **7.5** | Autofill hardening (parity + bug fixes) | **In progress** (PR-1, 2, 4, 5, 6, 7, 8 landed; PR-3 deferred to v1.1) |
| **8** | TOTP / Authenticator (offline) | **Done** |
| **9** | Encrypted attachments | **Done** |
| **10** | Trust polish (backup-verify, threat model, FAQ) | **Done** (README/store-listing copy deferred to Phase 11) |
| **11** | Release prep (no `INTERNET`, ProGuard, QA) | **Done** (manual QA pass owed before tagging — see `QA_CHECKLIST.md`) |

---

## Product invariants (recap)

Authoritative copy lives in `.cursor/rules/vaultsnap.mdc`. Roadmap items must respect:

- **Local-only.** No `INTERNET` in release builds. No accounts, no sync, no analytics, no ads, no remote config.
- **Sensitive material** (master password, VMK, decrypted entries, clipboard contents) **never** in logs/routes/static fields/plaintext disk/method-channel cleartext.
- **Default theme:** system; user-selected light/dark/system mode is persisted.
- **Lock = `VaultLockScope` overlay**, not a route. Single source of truth.

---

## Snapshot — what exists today

### Engine (services & models)

| File | Responsibility |
|------|----------------|
| `lib/services/crypto_service.dart` | Argon2id KDF, AES-GCM-256 wrap/unwrap, secure random, answer normalization |
| `lib/services/vault_storage.dart` | Atomic read/write of `vault_meta.json` (Flutter-free) |
| `lib/services/biometric_service.dart` | `local_auth` + `flutter_secure_storage`; enroll, authenticate, store/retrieve key |
| `lib/services/clipboard_service.dart` | Copy + 30s auto-clear timer (toggle persisted) |
| `lib/services/window_service.dart` | `FLAG_SECURE` MethodChannel (Android) |
| `lib/services/settings_storage.dart` | JSON persistence for non-secret prefs |
| `lib/services/backup_service.dart` | `.vsb` export + import (import re-encrypts under current VMK) |
| `lib/services/vault_database.dart` | sqflite `entries` v1 + CRUD |
| `lib/models/vault_meta.dart` | `VaultMeta`, `KdfParams`, `WrappedSecret`, `RecoveryMeta` |
| `lib/models/vault_entry.dart` | Cleartext metadata + encrypted payload helpers |
| `lib/models/field_spec.dart`, `password_entry.dart` | Category/field schema + enums |
| `lib/navigation/vault_root_navigator.dart` | `MaterialApp.navigatorKey` — pop to root when vault locks |

### Providers / state

- `lib/providers/vault_providers.dart` — service providers (`crypto`, `storage`, `clipboard`, `window`, `settings`, `vaultDatabase`, `vaultMeta`)
- `lib/providers/vault_setup_provider.dart` — `VaultSetupService` (create vault, verify password, change password, biometric enroll, recovery verify)
- `lib/providers/vault_repository_provider.dart` — `AsyncNotifier<List<VaultEntry>>` + decrypt for UI
- `lib/widgets/vault_lock_scope.dart` — single source of truth for lock/VMK; wall-clock-aware auto-lock; on lock, `popUntil(isFirst)` on root navigator (dismisses add/edit, entry detail, modal sheets)

### UI

- `setup_wizard_screen.dart` (3 pages), `vault_home_screen.dart` (speed-dial FAB), `entry_detail_screen.dart`, `add_edit_entry_screen.dart`, `password_generator_screen.dart` (uses `ClipboardService`), `search_screen.dart`, `settings_screen.dart`
- Theme persisted to disk after first frame; native splash follows device day/night via `values-night/colors.xml`

### Dependencies in use (approved)

`cryptography`, `encrypt`, `pointycastle`, `flutter_secure_storage`, `local_auth`, `path`, `path_provider`, `flutter_riverpod`, `sqflite`. `path_provider_android` pinned via `dependency_overrides` to avoid JNI/gradle breakage.

---

## Done — Phases 1–5 (history)

### Phase 1 — Crypto + storage foundation

- [x] `crypto_service.dart` — Argon2id, AES-GCM, secure random, answer normalization
- [x] `vault_storage.dart` — atomic `vault_meta.json` r/w
- [x] `vault_meta.dart` — JSON round-trip, wraps, recovery meta
- [x] Provider wiring + `VaultSetupService`
- [x] Unit tests: `crypto_service_test`, `vault_meta_test`, `vault_storage_test`
- [x] Encrypted entries DB → moved to Phase 4 (`vault_entries.db`)
- [x] Biometric service → moved to Phase 3
- [ ] _Optional cleanup:_ rename `vaultMetaProvider` file to snake_case

### Phase 2 — Setup wizard + first-run gate

- [x] `AppRouter` (gate: no meta → wizard, else unlock overlay)
- [x] Wizard: welcome → master password (+ strength meter) → recovery Q&A → creates `VaultMeta`
- [x] `_LockOverlay`: real password verify + `recordUnlock`
- [x] `ProviderScope` + `home: AppRouter()` in `main.dart`
- [x] Widget test: wizard path with provider override
- _Deferred (polish, see Phase 10):_ biometric step, "all set" summary, curated recovery questions.

### Phase 3 — Real lock state + auth

- [x] `VaultLockScope` (`ChangeNotifier` + `InheritedWidget`) — single source of truth
- [x] `_LockOverlay` is a `Stack` over the shell, **not** a route
- [x] Session VMK held in memory only; zeroed on `lock()` / `dispose()`
- [x] `BiometricService` (`local_auth` + `flutter_secure_storage`) — enroll, authenticate, store/retrieve
- [x] Biometric wrap in `vault_meta.json`; `_LockOverlay` button conditional on `meta.hasBiometric`
- [x] Settings biometric toggle (real enable/disable)
- [x] Auto-lock on `paused`/`inactive`/`detached` + `autoLockMinutes` timer
- [x] **Wall-clock auto-lock** on resume (Android-paused-timer fix)
- [x] Old `unlock_screen.dart` + `vault_transitions.dart` removed

### Phase 4 — Live vault data

Cleartext SQL columns for list/search; sensitive fields encrypted as a single AES-GCM blob under VMK.

- [x] `vault_database.dart` (sqflite v1) + `vaultDatabaseProvider`
- [x] `VaultEntry` — encrypt/decrypt helpers, cleartext extraction
- [x] `vaultRepositoryProvider` (`AsyncNotifier`) + CRUD + `decryptEntryPayload`
- [x] `VaultHomeScreen`, `AddEditEntryScreen`, `EntryDetailScreen`, `SearchScreen`, `EntryTile` wired
- [x] Detail screen refreshes from repo after edit (no stale `VaultEntry`)
- [x] Removed `MockVault` / `PasswordEntry` model
- [x] Unit test: `vault_entry_roundtrip_test`; widget tests use a stub repository

### Phase 5 — Privacy / security settings

- [x] Auto-lock minutes persisted via `SettingsStorage` (loaded in `VaultLockScope`)
- [x] Clipboard auto-clear + toggle persisted; used by detail + generator screens
- [x] `FLAG_SECURE` / hide in recents (`MainActivity.kt` MethodChannel)
- [x] Wipe vault (DB + meta + biometric key + lock + invalidate providers)
- [x] Change master password (re-wrap VMK; entry blobs untouched)
- [x] Encrypted backup export/import (`.vsb`); import requires unlock + re-encrypts under current VMK
- [x] Theme mode persisted; splash follows system day/night

---

## Upcoming phases

### Phase 6 — Recovery unlock + reuse detection

**Goal:** Make "Forgot password?" real, and replace the mocked `reused` flag.
**Offline:** Pure local crypto using existing `wrappedVmkRecovery` path.

- [x] Unlock → "Forgot password?" → recovery screen (question text from `meta.recovery.question`)
- [x] In-memory rate-limit / exponential backoff on wrong answers
- [x] On correct answer → prompt new master password → re-wrap VMK for password path; biometric/recovery wraps untouched
- [x] Real reuse detection: hash decrypted password fields locally; flip `reused` column on add/update/unlock
- [x] Surface reuse/weak health filters in `_SecuritySummaryCard` (no tap-hint copy)
- [x] Tests: recovery happy-path + wrong answer + backoff; reuse/security helpers

### Phase 7 — Android Autofill (strictly offline)

**Goal:** Suggest VaultSnap entries inside other apps' login fields. The single biggest reason users tolerate big password apps.
**Offline guarantee:** No network. Host matching mirrors Dart `autofill_matching` (subdomain rules); optional linked **Android package IDs** per login; bundled **browser package** set to prefer web-domain signals (no Digital Asset Links fetch).
**Permissions:** `BIND_AUTOFILL_SERVICE` on the service (system-only); **no** `QUERY_ALL_PACKAGES`. Launcher `<queries>` for the app-picker only.
**VMK bridge:** RSA-OAEP (SHA-256, Keystore private key) — VMK never crosses MethodChannel in plaintext. Session cleared on vault lock / scope dispose. Dart encryption uses **RFC 8017** OAEP (matches `Cipher` on Android); `package:encrypt` OAEP is PKCS #1 v2.0 and must not be used for this bridge.
**minSdk:** 26 (Autofill API).

- [x] `VaultSnapAutofillService` (Kotlin) — `FillResponse`, username/password detection, SQLite read + AES-GCM decrypt matching Dart payloads
- [x] MethodChannel `com.vaultsnap.app/autofill` — PEM export, wrapped VMK session, clear, launchable-app list, open system autofill settings
- [x] **Lock-aware:** no VMK session → dataset with authentication → `MainActivity`; unlocked + matches → datasets; unlocked + no match → no fill UI
- [x] Settings → **Android autofill** tile → `ACTION_REQUEST_SET_AUTOFILL_SERVICE`
- [x] DB v2: `android_packages` column; login form field + optional app picker; payload encrypt excludes `android_packages` (column-only cleartext for matching)
- [x] DB v3: legacy `app` category rows → `login`
- [x] Autofill: fill username and/or password when only one autofill id is present; launcher-app picker includes PNG icons
- [x] `VaultLockScope` sync/clear session on unlock/lock/dispose
- [x] Tests: `autofill_matching_test`; `rsa_oaep_sha256_roundtrip_test` (RFC 8017 VMK wrap matches Keystore RSA-OAEP); manual checklist below

**Manual device checklist (Phase 7):**

1. Settings → Android autofill → set VaultSnap as provider.
2. Create login with **Website** and/or **Android app** link; unlock vault.
3. Open target app/site login form → VaultSnap datasets appear; pick one → fields fill.
4. Lock vault → autofill shows **Unlock VaultSnap**; tap → returns to app.
5. `adb` optional: verify no cleartext VMK in logcat during normal use.

### Phase 7.5 — Autofill hardening (parity + bug fixes)

**Goal:** Bring VaultSnap autofill to Bitwarden / 1Password / Dashlane parity. Triggered by user feedback that "autofill isn't working properly". Plan in `~/.claude/plans/ok-so-now-we-adaptive-aurora.md`.

- [x] **PR-1** Two-engine refactor — split parser/engine/matcher/presentation into `android/.../autofill/` subpackages. Mirrors Bitwarden's NativeApp + WebDomain split. Field-detection bug fixes K-3 (IME), K-4 (contentDescription), K-5 (current-password vs new-password), K-12 (walk every FillContext), K-13 (filter `IMPORTANT_FOR_AUTOFILL_NO` and non-focusable nodes).
- [x] **PR-2** PSL-aware eTLD+1 + port-aware matching (D-1, D-2). Vendored 200-entry curated suffix list at `lib/services/public_suffix_list.dart` + Kotlin mirror. K-11 browser-without-webDomain fallback **deferred** — too fragile without device testing.
- [ ] **PR-3** HMAC `android_packages` migration — **deferred** (documented in `lib/services/vault_database.dart`). Needs CryptoService HKDF/HMAC, schema v3→v4, blob re-encryption with VMK, Kotlin matcher rewrite. Cleartext column remains a known privacy gap.
- [x] **PR-4** Dataset icons (K-10) + manifest cleanup. Layout now LinearLayout w/ icon + label. `supportsInlineSuggestions="true"` removed from manifest until inline plumbing actually emits Slice content (K-9 deferred).
- [x] **PR-5** `onSaveRequest` + deferred-save queue (K-1). `SaveResponseBuilder` attaches `SaveInfo` w/ `FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE` to every fill response. `DeferredSaveQueue` persists payloads under Android Keystore AES-GCM-256 (never plaintext on disk). Dart consumes via new `AutofillSessionService.consumePendingSaves()` — UI banner wiring is the next small change.
- [x] **PR-6** Crypto/memory/race fixes — K-2 (AES-GCM `decryptAndUse` lambda zeroes plaintext on return), K-7 (`AtomicReference` state machine in `AutofillAuthActivity` replaces volatile flag race), K-8 (timeout 120s → 30s), D-4 (RSA-OAEP intermediate buffer zeroing). K-17 doesn't apply to current code; D-3 deferred.
- [x] **PR-7** Logging + null-safety + own-UI hardening — K-6 covered by `EntryRepository` null-safe cursor reads, K-16 covered by `AutofillDispatcher` skip-with-reason logs. **K-14 landed**: every master-password / recovery-answer / backup-password field across `vault_lock_scope.dart`, `setup_wizard_screen.dart`, and `settings_screen.dart` now sets `autofillHints: const <String>[]` (Flutter's documented "disable autofill" signal — sets `IMPORTANT_FOR_AUTOFILL_NO` on the underlying Android view) so a different installed autofill service can't see, suggest into, or log VaultSnap's keystone credentials. K-18 (always-show unlock affordance) **deferred** — UX-only edge case, low priority.
- [x] **PR-8** "Actually works on a real device" fixes — discovered when device-testing PR-1..6 against `com.facebook.katana`. Three blocker bugs:
  - **MGF-1 digest mismatch** (`INCOMPATIBLE_MGF_DIGEST` from keystore2). Android Keystore RSA-OAEP only authorizes SHA-1 for MGF1 by default; `setMgf1Digests` was added in API 34 only and is unreliable below that. Switched both sides to RFC 8017's SHA-256 OAEP digest + MGF1-SHA-1 (still secure — security rests on the OAEP digest, not MGF1). Bumped key alias to `_v3` and added cleanup of legacy v1/v2 keys. Files: `AutofillRsa.kt`, `lib/services/rsa_oaep_sha256_pkcs1.dart`, `test/services/rsa_oaep_sha256_roundtrip_test.dart`.
  - **Auto-lock racing the autofill flow.** `moveTaskToBack(true)` after unlock triggered `AppLifecycleState.paused`, which (with `autoLockMinutes == 0`) fired `_controller.lock()` → cleared `AutofillSessionHolder` → `AutofillAuthActivity` saw `vmk == null` → timed out. Fix: `autofillStartSession` now returns whether it minimized; Dart arms `_suppressNextBackgroundLock` (5s expiry) and `VaultLockScope.didChangeAppLifecycleState` consumes it on the next pause. Files: `MainActivity.kt`, `lib/services/autofill_session_service.dart`, `lib/widgets/vault_lock_scope.dart`.
  - **Single-match auto-fill UX.** Returning `FillResponse` from auth always made Android show the suggestion picker again. Now: if exactly 1 entry matches we return a `Dataset` (Android applies it directly, fields populate on return to caller); 2+ matches still return `FillResponse` so the user can pick. Files: `DatasetBuilder.kt` (new `buildSingleDataset`), `AutofillAuthActivity.kt` (`tryComplete` branches on `matches.size`).
  - Logging fleshed out across the pipeline (`fill_request`, `fill_parsed`, `auth_open_vault`, `session_started minimize=…`, `auth_ok type=…`) so failures are diagnosable from `adb logcat -s VaultSnapAutofill:I`.

**Manual device checklist** (in addition to Phase 7's):
1. eTLD+1 — store entry for `example.co.uk`; autofill on `login.example.co.uk` site → match works.
2. Save flow — sign up for a new account in a 3rd-party app → save prompt appears → accept → check that the queue has a payload (`adb shell run-as com.vaultsnap.app cat shared_prefs/vaultsnap_save_queue.xml` should show ciphertext, never plaintext).
3. 30s auth timeout — open autofill prompt with vault locked, wait — should cancel after 30s, not 2 min.
4. Memory — `adb logcat -s VaultSnapAutofill:*` after a fill — `decrypt_skip` / `auth_ok` lines visible, no plaintext password material.
5. End-to-end app autofill (PR-8) — link an entry to `com.facebook.katana` (or any installed app), lock vault, open the linked app's login screen, tap field, tap "Unlock VaultSnap", unlock. **Expect:** VaultSnap auto-minimizes; calling app comes forward with username + password already filled (no extra tap). `auth_ok ... type=Dataset` in logs. Repeat with `autoLockMinutes` set to **0** (lock immediately) — must still work (suppression flag).
6. Multi-account picker (PR-8) — link **two** entries to the same package, repeat step 5. **Expect:** suggestion picker appears with both labels; tap one → fills. `auth_ok ... type=FillResponse` in logs.

### Phase 8 — TOTP / Authenticator (offline)

**Plan:** `~/.claude/plans/1-idk-just-make-snoopy-pebble.md`. Decisions locked: (1a) **new `EntryCategory.totp`** + dedicated bottom-nav Authenticator tab; (2iii) **`otpauth://` URI paste path** in v1, QR scan deferred to v1.1 (avoids `mobile_scanner` dep + `CAMERA` permission ask). No new dependency required — `pointycastle` already in scope provides HMAC-SHA1/256/512.

**Note:** Legacy `totp` JSON sub-field on login entries is preserved (readable on the login detail screen) but not auto-migrated. Users can copy the secret into a new TOTP entry; auto-migration ships only if real users hit it.

- [x] Decision: TOTP as new `EntryCategory.totp` (matches Google Authenticator / Aegis mental model; ships with its own bottom-nav tab and matches the user's "make a new tab for authenticator" direction)
- [x] `lib/services/totp_service.dart` — RFC 6238 generator (HMAC-SHA1/256/512), RFC 4648 base32 decoder, `otpauth://` URI parser, `secondsRemaining` / `progress` helpers
- [x] `lib/screens/authenticator_screen.dart` — live code list with single shared `Ticker`; per-tile period ring via `CustomPaint`; FAB → `AddEditEntryScreen(initialCategory: totp)`; tap-to-copy via `ClipboardService` + `VaultToast`
- [x] `lib/screens/home_shell.dart` — 4th nav destination "Auth" (`Icons.shield_moon_outlined` / `Icons.shield_moon`); lazy-mounts via `_visited` gate
- [x] `lib/screens/add_edit_entry_screen.dart` — "Paste otpauth:// URI" card above the field list when category is TOTP; auto-fills issuer/account/secret/algorithm/digits/period from clipboard
- [x] `lib/screens/entry_detail_screen.dart` — `_TotpHeroCard` at the top of TOTP entries: gradient hero with 36sp tabular code, 56dp period ring, copy button
- [x] `lib/models/password_entry.dart` — `EntryCategory.totp('Authenticator', shield_moon, cyan-500)`
- [x] `lib/models/field_spec.dart` — TOTP field schema (name, issuer, account, secret, algorithm, digits, period, notes)
- [x] `lib/models/vault_entry.dart` — `cleartextFromFields` derives `username` from issuer (or account); `strengthFromFields` returns good
- [x] Backup `.vsb` covers TOTP secrets (encrypted JSON payload — same path as login fields)
- [x] Tests: `test/services/totp_service_test.dart` (RFC 6238 Appendix B vectors × SHA1/256/512, parser edge cases, RFC 4648 base32 vectors — 31 cases); `test/models/vault_entry_totp_test.dart` (cleartext + roundtrip — 6 cases)

**Manual checklist:**
1. Copy a known-good `otpauth://` URI from another authenticator (e.g. Aegis, andOTP) → in VaultSnap go to Authenticator tab → tap + → tap "Paste otpauth:// URI" → fields auto-fill → save → entry appears with a live 6/8-digit code that matches the source authenticator second-by-second.
2. SHA-256 / SHA-512 / 8-digit / 60s-period URIs — same flow → codes match.
3. Lock vault from any tab → Authenticator tab is replaced by `_LockOverlay`. Unlock → codes resume immediately.
4. Backup roundtrip — Settings → Export → Import on a clean vault → TOTP entries (and their codes) survive.
5. `flutter run --release` + `adb logcat` → no `secret=…` or `code=…` leakage.

### Phase 9 — Encrypted attachments

**Plan:** `~/.claude/plans/now-do-the-phase-humming-snail.md`. One new dependency added: `file_picker: ^8.0.0` (platform document picker — no INTERNET, no extra runtime permissions). Dev-only `sqflite_common_ffi: ^2.3.5` so backup-roundtrip tests can stand up a real DB without a Flutter binding.

**Goal:** Store IDs, passport scans, recovery codes as files inside the vault. Real-life upsell vs "password list" apps.
**Offline:** Bytes encrypted under VMK; never leave device.

- [x] Schema v4: `attachments` table (id, entry_id, name, mime, nonce, mac, blob_size, created_at) + per-file ciphertext under `<docs>/vault_attachments/<id>.bin`. No FK constraint — sqflite has `foreign_keys` off by default; repository handles cascade-on-entry-delete manually.
- [x] `lib/services/attachment_service.dart` — encrypt/decrypt under VMK, runs on `Isolate.run` for blobs ≥1 MiB so the UI thread doesn't drop frames during a large encrypt. Soft warning at >25 MiB; no hard cap. Uses `DartAesGcm` (pure Dart, isolate-safe).
- [x] `lib/models/attachment.dart` — `VaultAttachment` model with cleartext metadata + binary `nonce` / `mac`; SQL row roundtrip helpers.
- [x] CRUD on `VaultRepository`: `addAttachment`, `decryptAttachment`, `deleteAttachment`, `attachmentsFor(entryId)`. `deleteEntry` / `deleteEntries` now cascade-delete attachment rows AND on-disk files.
- [x] Backup `.vsb` v2 — JSON `version` bumped to 2, new `attachments` array. Each attachment's blob is decrypted under VMK at export, re-encrypted under the backup-password-derived key alongside its metadata. Import re-encrypts under the current VMK and re-writes per-file ciphertext. v1 backups still import (no `attachments` field).
- [x] UI: `EntryDetailScreen` gained an `_AttachmentsSection` sliver — list of `AttachmentTile`s (mime icon + name + size), `+ Add attachment` button via `FilePicker.platform.pickFiles(withData: true)`, long-press to delete. New `AttachmentViewerScreen` shows full-screen `Image.memory` + `InteractiveViewer` for images, or a metadata card with a warned "Export decrypted…" button (routes through the existing `WindowService.saveBytes` SAF channel) for non-images.
- [x] Wipe vault: `_wipeVault` now also calls `attachmentService.wipeAll()` — recursively clears `<docs>/vault_attachments/`. Best-effort try/catch so a missing dir / partial wipe doesn't fail the rest of the wipe.
- [x] Tests: `test/services/attachment_service_test.dart` (1 KB + 5 MB roundtrip via isolate, MAC tamper rejection, wrong-VMK rejection, file lifecycle); `test/models/attachment_test.dart` (DB row roundtrip + mime getters); `test/services/backup_v2_roundtrip_test.dart` (entries+attachments survive export→wipe→import, including different-VMK migration); `test/services/backup_v1_compat_test.dart` (synthesised v1 JSON still imports, wrong-password returns null without crash). 113 tests total — was 100.

**Deferred to v1.1** (out of scope for Phase 9):
- In-app PDF preview (`pdfx`).
- Camera capture (would need `image_picker` + `CAMERA` permission).
- Chunked-frame encryption for files >100 MB (single-frame AES-GCM holds the whole ciphertext in memory for MAC verification).
- Per-file thumbnails on the list tile.

**Manual checklist (Phase 9):**
1. Open any login → Attachments → + → pick a PNG/JPG → tile appears. Tap → full-screen viewer with pinch-to-zoom.
2. Same for a PDF → metadata page → "Export decrypted…" → confirm warning → SAF picker → save → open externally → bytes match the original.
3. Lock vault → reopen entry → Attachments section is hidden (lock-scope unmounts the subtree).
4. Delete an entry that has attachments → confirm `<docs>/vault_attachments/` no longer holds those `.bin` files (`adb shell run-as com.vaultsnap.app ls files/vault_attachments/`).
5. Backup roundtrip with attachments — Settings → Export → wipe → setup → Import → entries AND attachments survive byte-identical.
6. Soft warning — attach a 30 MB file → toast warns but the operation completes.
7. Wipe vault → confirm `<docs>/vault_attachments/` directory is gone.

### Phase 10 — Trust polish

**Plan:** `~/.claude/plans/ok-now-lets-now-sorted-ullman.md`. No new dependencies — pure UI + a small refactor of `backup_service.dart` to share the crypto path between import and a new dry-run verify.

**Goal:** Earn the price tag. Make security legible.

- [x] In-app **"How VaultSnap stores your data"** ([threat_model_screen.dart](vault_snap/lib/screens/threat_model_screen.dart)) — 10 plain-language Q&A sections covering where passwords live, how the master password is handled, what's encrypted vs. searchable, recovery, lock-on-background scrub, no-INTERNET guarantee, biometric mechanics, backups, and what an attacker with an unlocked phone vs. file-system access can see. Selectable text. Reachable from Settings → ABOUT.
- [x] **Backup verify** — Settings → "Verify backup" → dry-run import that decrypts the entries payload + every attachment blob (validates every MAC) but does NOT touch the DB or the on-disk attachments dir. Reports counts + version on success, distinguishes wrong-password (amber dialog) from corrupted-backup (red dialog). Refactored `backup_service.dart` to share the crypto path: extracted `_decryptAndValidate(...)` is called by both `importFromBytes` and the new `verifyBytes`.
- [x] Wizard polish — Setup wizard expanded from 3 → 5 pages: Welcome → Password → Recovery → **Biometric** → **Summary**. Recovery question now uses a curated dropdown (9 personal/non-publicly-findable presets + "Custom question…" fallback). Biometric page asynchronously checks `BiometricService.isAvailable()`, renders a spinner while resolving, then either a toggle (capable) or an "unavailable on this device" info card. Summary page lists every setup decision with check/dash marks and commits via "Open vault" — vault creation moved from the Recovery page to the Summary's button so the summary screen actually summarises *before* committing.
- [ ] README + store-listing copy — **deferred to Phase 11** (release prep). Copy will evolve as the rest of pre-release polish lands; locking it in now wastes work.

**Manual checklist (Phase 10):**
1. Settings → ABOUT → "How VaultSnap stores your data" → page opens, all sections render, text is selectable.
2. Settings → "Verify backup" — happy path: pick a real `.vsb`, enter the right password → green "Backup is valid. N entries and M documents." dialog.
3. Verify — wrong password: same flow, wrong password → amber "Wrong backup password" dialog.
4. Verify — corrupted: pick any non-`.vsb` file (or a tampered one) → red "Backup is corrupted" dialog.
5. Verify — no DB writes: count entries before via `adb shell run-as com.vaultsnap.app sqlite3 ...`, run verify, count again. Same number.
6. Setup wizard — fresh install: 5-page indicator visible, dropdown shows 9 presets + Custom, biometric page on capable device shows toggle, on non-capable device shows info card, Summary page lists all four checks with appropriate marks.
7. Summary "Open vault" → vault is created and unlocked, biometric is enrolled if requested.

### Phase 11 — Release prep

**Plan:** `~/.claude/plans/ok-now-lets-now-sorted-ullman.md`. No new dependencies — pure config + docs. Targets Play Store as the primary distribution channel.

- [x] Release manifest verification — `scripts/verify_release_manifest.{ps1,sh}` runs `flutter build apk --release`, parses the merged manifest, and asserts only `USE_BIOMETRIC` is present. Exits non-zero if `INTERNET` (or anything else) leaks in. Manifests themselves were already correctly split — debug requests `INTERNET` for hot reload, main + release do not.
- [x] R8 / ProGuard — `android/app/build.gradle.kts` now sets `isMinifyEnabled = true`, `isShrinkResources = true`, and `proguardFiles(...)` for the `release` build type. `android/app/proguard-rules.pro` keeps `MainActivity`, `VaultSnapAutofillService`, `AutofillAuthActivity`, and the `com.vaultsnap.app.autofill.**` subpackage; strips `Log.v/d/i` in release. Pure-Dart deps (`cryptography`, `pointycastle`, `encrypt`) compile to AOT and are out of R8's scope; Flutter plugins ship their own `consumer-rules.pro` inside their AARs — no app-level keep rules needed for `sqflite` / `local_auth` etc.
- [x] Upload-key signing — `build.gradle.kts` reads `android/keystore.properties` when present and falls back to debug signing otherwise (so contributors without a keystore can still `flutter run --release`). `android/keystore.properties.example` documents the contract; `keystore.properties` and `upload-keystore.jks` are gitignored. Default release artifact is now AAB (`flutter build appbundle --release`) — Play Store requires it.
- [x] README rewrite — replaced the Flutter starter boilerplate with a real README (project pitch, threat-model summary, build/run/release commands, `verify_release_manifest` instructions, signing setup, project layout, contributing pointer to `CLAUDE.md`).
- [x] Store-listing copy — `store/listing.md` (app name, short + full description under length limits, category, keywords, screenshot plan), `store/data_safety.md` (every Data Safety question answered "No" / "N/A — local-only" with justifications), `store/privacy_policy.md` (short, hostable, contact-email placeholder).
- [x] QA checklist — `QA_CHECKLIST.md` consolidates every per-phase manual checklist into a single pre-release pass. Includes release-build-only smoke test, network-isolation proof via `/proc/net/tcp`, sensitive-log proof via logcat, Play Console submission readiness, and rollback steps.
- [ ] **Final manual QA pass** — owed before tagging 1.0. Walk every step of `QA_CHECKLIST.md` on a physical Android device with the release APK installed.

**What's left for the user:**
1. **Real launcher icon** — `mipmap-*/ic_launcher.png` is still Flutter's default. Generate a VaultSnap brand mark (recommend `flutter_launcher_icons` package) and add adaptive-icon XML at `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` so API 26+ devices render correctly.
2. Generate `upload-keystore.jks` with `keytool` (one-time; see README "Signing for release").
3. Pick a licence (TBD line in README) and a contact email (TBD lines in `store/privacy_policy.md` and `store/listing.md`).
4. Capture screenshots from a real device with synthetic data only.
5. Walk `QA_CHECKLIST.md` end-to-end on a release-built APK.
6. Host the privacy policy somewhere public (GitHub Pages is fine) and paste that URL into the Play Console.
7. Build AAB (`flutter build appbundle --release`), upload to Play Console, enrol in Play App Signing on first upload.

**Pre-1.0 polish landed alongside Phase 11:**

- `lib/main.dart` — `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and a `runZonedGuarded` outer wrapper so release-build crashes log a redacted sentinel instead of disappearing silently. Logs the runtime type only, never the message or stack — those can include thrown VMK / master-password material.
- Redacted `toString()` on `VaultMeta`, `VaultEntry`, `WrappedSecret`, `RecoveryMeta` — defaults dump every field, including base64 ciphertext, into any log line or exception trace that prints them.
- iOS `Info.plist` — `CFBundleDisplayName` / `CFBundleName` corrected from `Test App` / `test_app` to `VaultSnap` / `vault_snap`.

**Known v1.0 limitations (deferred to v1.1+):**

- **Recovery backoff is in-memory only** ([recovery_backoff_controller.dart](vault_snap/lib/services/recovery_backoff_controller.dart)). Caps at 30s after 5 wrong answers but resets on app restart — a determined attacker can rapid-restart to bypass throttling. Not a crypto break (answer is salted+Argon2id), but UX-hostile. Persist to SQLite or harden to permanent lockout in v1.1.
- **No tablet / foldable layout adaptation.** Single-column phone layout used everywhere; large screens stretch awkwardly. Wrap entry list in `LayoutBuilder` and switch to multi-column above 600dp width in v1.1.
- **No Material You / dynamic-color support.** Hardcoded seed colour. Integrate `dynamic_color` package + Settings toggle in v1.1.
- **English-only.** No `flutter_localizations` / `intl` integration. Document in store listing; add localisation in v1.1+.
- **Accessibility coverage is partial** (~36 tooltips, 1 explicit `Semantics()` widget). Walk every interactive surface and add `Semantics(button: true, label: …)` + `tooltip:` in v1.1.
- **No release-mode automated smoke test.** Only `flutter test` (debug mode) runs in CI. Manual QA on the release APK is the contract — see QA_CHECKLIST.md.

---

## Crypto model — envelope encryption

- **VMK** (256-bit random) wrapped by:
  - master-password-derived key (Argon2id)
  - recovery-answer-derived key (separate salt, normalization version)
  - optional biometric path (random key in keystore via `flutter_secure_storage`)
- `vault_meta.json` holds wraps + KDF params + recovery question text (**not** the answer).
- Entry payloads: per-entry field map → AES-GCM under VMK (`VaultEntry.encryptFieldMap`). HKDF child keys remain optional future hardening.

---

## App tree (current)

```text
VaultSnapApp
 └── ProviderScope
      └── MaterialApp
           └── AppRouter         ← same role as the spec's SetupGate
                ├── meta == null → SetupWizardScreen
                └── else        → VaultLockScope
                                   ├── HomeShell
                                   └── _LockOverlay (Stack overlay, not a route)
```

---

## Notes for editors

- When a checkbox completes, change `[ ]` → `[x]` and (optionally) add a one-line "Done YYYY-MM-DD".
- Keep **product invariants** in `.cursor/rules/vaultsnap.mdc` authoritative — this file follows them, not the other way around.
- Bug fixes still need tests per project rules; this file is not a substitute for tests.
- Any phase that *might* introduce a new dependency or permission requires asking before implementation (per the workspace rule).
