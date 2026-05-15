# VaultSnap — Play Store listing copy

Submission-ready copy for the Google Play Console. Keep claims accurate —
Play rejects misleading descriptions and "no telemetry" promises that
turn out to be false.

---

## App name

**VaultSnap**

## Short description (≤ 80 characters)

```
Local, offline password manager. No cloud, no accounts, no telemetry.
```

(67 / 80)

## Full description (≤ 4000 characters)

```
VaultSnap is a password manager that runs entirely on your phone.

No cloud sync. No account to create. No analytics. No ads. No telemetry.
The release build does not request the INTERNET permission, so the
operating system itself blocks any network call — by design.

WHAT VAULTSNAP STORES
• Logins — username, password, website, optional Android-app link
• Authenticator codes — paste any otpauth:// URI; supports SHA-1, SHA-256,
  SHA-512, 6 or 8 digits, 30 or 60 second periods
• Cards, identities, and secure notes
• Encrypted attachments — IDs, passport scans, recovery code sheets

HOW IT'S PROTECTED
• Sensitive fields are encrypted with AES-GCM-256 under a Vault Master
  Key (VMK) derived from your master password using Argon2id
• The master password is never stored — only the wrapped VMK, which is
  useless without it
• Optional biometric unlock backed by the Android Keystore — your
  fingerprint or face never leaves the secure hardware
• Recovery question with a separate KDF salt for the "I forgot my master
  password" path

ANDROID AUTOFILL
VaultSnap fills usernames and passwords into other apps and browsers
through the Android Autofill API. Match by website domain (eTLD+1 aware,
port-aware) or by linking an entry to a specific Android package.

ENCRYPTED BACKUPS
Export the vault to a .vsb file encrypted under a separate
backup-password-derived key. Use "Verify backup" before you trust it —
the wizard decrypts every entry and attachment in memory and reports the
counts without writing anything to disk.

WHAT YOU SEE WHEN YOU LOCK
The Vault Master Key is wiped from memory. The app's icon is hidden in
the recents thumbnail. Auto-lock fires on background and after the timer
you choose.

THREAT MODEL
A plain-language threat model lives inside the app: Settings → "How
VaultSnap stores your data". It explains exactly what's encrypted, what
isn't (entry names and usernames stay in cleartext SQL columns so
search and autofill work), and what an attacker with file-system access
or an unlocked phone can see.

WHO IT'S FOR
People who don't want a third party — even a well-meaning one —
holding their passwords. People on slow networks, in air-gapped
environments, or who don't trust cloud breaches not to happen to them.
People who want a password manager that works on a flight without
mobile data.

PERMISSIONS
• USE_BIOMETRIC — fingerprint / face unlock
• BIND_AUTOFILL_SERVICE — system-bound autofill (no app can request this)
• No INTERNET. No storage permission. No camera. No location.

This is version 1.0.
```

(2127 / 4000)

## Application category

**Tools.** (Productivity is the alternative; "Tools" is more honest for a
password manager — Play's own examples list 1Password and Bitwarden
under Tools.)

## Tags / search keywords

`password manager`, `offline`, `local`, `autofill`, `TOTP`,
`authenticator`, `encrypted backup`, `no cloud`

## Content rating

Target: **Everyone**. Submit the IARC questionnaire honestly — VaultSnap
collects no user data, has no user-generated content, no in-app
purchases, no ads, no online interactions.

## Contact / support

- Support email: TBD (user fills in)
- Website: TBD (optional — can be a single-page GitHub Pages site)

## Screenshots required by Play

Need at least 2, up to 8. Recommended order:

1. Vault home screen with a few example entries (use synthetic data)
2. Entry detail showing reveal-password + copy
3. Authenticator tab with live TOTP codes + period rings
4. Add/edit entry — login category
5. Search results
6. Settings → "How VaultSnap stores your data"
7. Backup verify success dialog
8. Setup wizard summary page (✓ marks for each step)

Capture from a Pixel-class device at native resolution. **Use synthetic
data only — never your real credentials.**

## Feature graphic

1024 × 500 PNG. Suggested: VaultSnap wordmark + tagline "Local. Offline.
Yours." on a Material 3 surface gradient. Match the in-app theme.

## Promo video

Optional. Skip for v1.0.
