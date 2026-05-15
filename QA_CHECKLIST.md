# VaultSnap — pre-release QA checklist

Run the **full** list before tagging 1.0 and before every subsequent
release. Debug-build testing alone is not sufficient — R8 obfuscation,
release signing, and AOT compilation each introduce failure modes that
debug builds skip.

All commands assume `cd vault_snap` first.

---

## 1 · Pre-flight (automated)

- [ ] `flutter analyze` — zero issues.
- [ ] `flutter test` — all tests pass (target: 120+).
- [ ] `pwsh ./scripts/verify_release_manifest.ps1` (or `.sh`) — exits 0.
      Allowed: `USE_BIOMETRIC`, `USE_FINGERPRINT` (auto-added by `local_auth`
      for pre-API-28 biometric), `<package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
      (AndroidX-generated, scoped to our package). The script's headline
      check is "no `INTERNET`" — those three are non-network permissions
      and the script allowlists them.
- [ ] `flutter build appbundle --release` — completes; produces
      `build/app/outputs/bundle/release/app-release.aab`.
- [ ] `flutter build apk --release` — completes; produces
      `build/app/outputs/flutter-apk/app-release.apk`. (For sideload-to-device
      testing below; Play submission uses the AAB.)
- [ ] APK size sanity — `ls -lh build/app/outputs/flutter-apk/app-release.apk`
      under ~30 MB. Spike vs. previous release means R8 keep rules became
      too broad.

## 2 · Release-build smoke test (real device)

Install the **release** APK (R8 active) on a physical Android device.
Walk every step. Do not skip; release-only regressions hide here.

- [ ] **Setup wizard** — fresh install → all 5 pages render in order
      (Welcome → Password → Recovery → Biometric → Summary) → pick a
      curated recovery question → "Open vault" → land on home screen.
- [ ] **Add login entry** — fill name, username, password, website →
      save → tile appears in the Logins tab.
- [ ] **Search** — type a substring of the entry name → matching entry
      shown.
- [ ] **Autofill — same-app match** — link the entry's website to a
      browser site, lock vault, open the site in Chrome, tap the
      username field → VaultSnap suggestion appears → tap "Unlock
      VaultSnap" → biometric → fields fill.
- [ ] **Autofill — Android-app match** — link an entry to an installed
      app's package, repeat → fields fill.
- [ ] **TOTP entry** — Authenticator tab → + → "Paste otpauth:// URI"
      → fields auto-populate → save → live code matches Aegis (or your
      reference authenticator) second-by-second.
- [ ] **Image attachment** — open any login → Attachments → + → pick a
      PNG/JPG → tile appears → tap → full-screen viewer with pinch-to-zoom.
- [ ] **Non-image attachment** — pick a PDF → metadata page → "Export
      decrypted…" → SAF picker → save → open the saved file externally
      → bytes match the original.
- [ ] **Backup export** — Settings → Backup → Export → enter a backup
      password → save the `.vsb` to Downloads.
- [ ] **Backup verify — happy path** — Settings → Verify backup → pick
      the file → enter the right password → green dialog "Backup is
      valid. N entries and M documents."
- [ ] **Backup verify — wrong password** — same flow, wrong password
      → amber dialog "Wrong backup password."
- [ ] **Backup verify — corrupted** — pick a non-`.vsb` file (e.g. any
      JPG) → red dialog "Backup is corrupted or not a VaultSnap
      backup."
- [ ] **Backup verify — no DB writes** — `adb shell run-as
      com.vaultsnap.app sqlite3 databases/vault_entries.db
      "SELECT COUNT(*) FROM entries;"` before and after running
      verify → identical counts.
- [ ] **Wipe + import roundtrip** — Settings → Wipe vault → re-run
      setup → Settings → Import → pick the `.vsb` from earlier →
      every entry, TOTP secret, and attachment is restored.
- [ ] **Lock-on-background** — open any entry → press home → re-open
      → vault is locked, lock overlay shows. App icon in the recents
      thumbnail is obscured (FLAG_SECURE).
- [ ] **Lock-on-timer** — set auto-lock to 1 minute → leave foregrounded
      and idle → vault locks at the timer.
- [ ] **Threat model page** — Settings → ABOUT → "How VaultSnap stores
      your data" → all 10 sections render → text is selectable.
- [ ] **Clipboard auto-clear** — copy a password → wait 30 seconds →
      `adb shell cmd clipboard get-primary` returns empty.
- [ ] **Sensitive clipboard masking (Android 13+)** — copy a password
      → pull down the clipboard preview chip / quick-paste UI → shows
      `••••••`, not the plaintext.

## 3 · Network-isolation proof

Belt-and-braces — the missing manifest permission already makes
network calls impossible, but verify on the running release build:

- [ ] App in foreground, device on Wi-Fi.
- [ ] `adb shell ps -A | grep vaultsnap` → note the PID and UID.
- [ ] `adb shell cat /proc/net/tcp` and `/proc/net/tcp6` → no entries
      owned by VaultSnap's UID. (The `uid_owner` column is the UID
      mapped from the local-address ownership.)

## 4 · Sensitive-log proof

- [ ] `adb logcat -c` to clear, then `adb logcat -s flutter:* VaultSnapAutofill:* MainActivity:*`.
- [ ] Run a full unlock + autofill + copy + lock cycle in the app.
- [ ] Stop the logcat. Search the captured output for: any plaintext
      password, any TOTP secret, any decoded VMK byte, any backup
      password, any recovery answer. **Should match nothing.**

## 5 · User-owed items before submission

These cannot ship from the codebase alone — they need design / personal
input from the project owner.

- [ ] **Real launcher icon.** The current `mipmap-*/ic_launcher.png` is
      Flutter's default "F" icon. Replace with a VaultSnap brand mark:
      generate using `flutter_launcher_icons` package or design in
      Figma (1024×1024 PNG, then export per-density). After replacing,
      add an adaptive-icon XML at
      `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
      with `<adaptive-icon>` referencing a foreground drawable + a
      background colour. Play Console flags apps without adaptive
      icons on API 26+.
- [ ] **License.** README has `Licence: TBD`. Pick MIT / Apache 2.0 /
      proprietary and add a top-level `LICENSE` file. Required for
      open-sourcing; not strictly required by Play Console but the
      Data Safety form asks.
- [ ] **Contact email.** Fill in `store/listing.md` (support email) and
      `store/privacy_policy.md` (contact). Play Console requires a
      monitored email.
- [ ] **Privacy policy hosting.** Upload `store/privacy_policy.md`
      content to a public URL (GitHub Pages with the markdown
      converted to HTML, or any static host) and paste that URL into
      Play Console's listing.
- [ ] **Screenshots.** Capture 2–8 screenshots from a real device with
      synthetic data (never real credentials). See `store/listing.md`
      for the recommended order.
- [ ] **Feature graphic.** 1024×500 PNG. Required by Play Console.

## 6 · Play Console submission readiness

- [ ] `store/listing.md` — short and full descriptions copy-pasted
      into the Play Console; under length limits.
- [ ] `store/data_safety.md` — every Data Safety question answered
      "No" / "N/A — local-only".
- [ ] `store/privacy_policy.md` — hosted at a public URL; that URL
      pasted into the Play Console.
- [ ] At least 2 screenshots uploaded; **synthetic data only**, never
      real credentials.
- [ ] Feature graphic uploaded (1024×500 PNG).
- [ ] Content rating questionnaire submitted (target: Everyone).
- [ ] Target API level satisfies Play's current requirement (API 34
      as of late 2024 / 2026; check the Play Console for the live
      minimum).
- [ ] AAB signed with the upload key; Play App Signing enrolment
      enabled on first upload.

## 7 · Rollback

If something ships broken:

- [ ] `git log --oneline -20` to find the commit to revert.
- [ ] `git revert <sha>` (preferred) or `git checkout -- <files>` for
      uncommitted local breakage.
- [ ] Bump `version` in `pubspec.yaml` for the fix release before
      rebuilding.
- [ ] Rerun this entire checklist for the fix release.

---

## What "broken" looks like at each stage

- **Pre-flight:** `flutter build apk --release` fails with R8 errors →
  proguard-rules.pro is too aggressive; check the error for the
  stripped class and add a keep rule.
- **Smoke test:** autofill silently does nothing → `VaultSnapAutofillService`
  was stripped or its `onFillRequest` signature was renamed; check
  `adb logcat -s VaultSnapAutofill:*` for missing-class errors.
- **Network proof:** any TCP entry → release manifest leaked
  INTERNET; rerun the verify script.
- **Log proof:** any plaintext sensitive value → a `print` /
  `debugPrint` slipped through; grep `lib/` for new log calls
  introduced since the previous release.
