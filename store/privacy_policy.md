# VaultSnap — Privacy Policy

_Last updated: 2026-05-02_

Google Play requires a hosted privacy-policy URL for every app. Host
this content on a GitHub Pages site, a personal blog, or any URL you
control, and paste the URL into the Play Console listing.

---

## Summary

VaultSnap does not collect, transmit, share, or sell any of your data.
Everything stays on your device. We — the developer — have no access to
your vault, ever.

## What VaultSnap stores

Locally on your device, encrypted under a key derived from your master
password using Argon2id key derivation and AES-GCM-256 authenticated
encryption:

- Login credentials (username, password, website, optional Android-app
  link)
- Authenticator (TOTP) secrets
- Cards, identities, secure notes, and any other entries you create
- Attachments you add to entries (IDs, recovery codes, scanned
  documents)

The master password itself is never stored — only a wrap of the vault
key that requires the master password (or your recovery answer) to
unlock.

## What VaultSnap transmits

**Nothing.** The release build of VaultSnap does not request the
Android `INTERNET` permission. The Android operating system blocks the
app from making any network call — TCP, UDP, DNS, anything — at the
kernel level. This is verifiable: run
`aapt dump permissions <app-release.apk>` on the published APK, or
inspect the merged `AndroidManifest.xml` in any release build.

## Permissions used

| Permission | Why |
|---|---|
| `USE_BIOMETRIC` | Optional fingerprint / face unlock for the master vault. Authentication happens in your device's secure hardware; the biometric template never leaves it. |
| `BIND_AUTOFILL_SERVICE` | Required by Android to register VaultSnap as your Autofill provider. The user enables this manually in Android Settings → Autofill service. |

No camera, microphone, location, contacts, calendar, SMS, storage, or
network permissions are used.

## Data retention

Your vault data remains on your device until **you** choose to delete
it. You can:

- Wipe the entire vault: Settings → Wipe vault (irreversible)
- Uninstall the app: Android removes all VaultSnap data automatically
  (the app stores nothing outside its private directory)

There is no "delete my account" request to send because there is no
account, no server, and no developer-held data.

## Backups

VaultSnap can export an encrypted `.vsb` backup file for you to store
yourself (e.g., on a USB drive, cloud sync of your choice, or a second
device). The backup is encrypted under a separate password you choose
at export time — independent of your master password. We have no
access to either the backup file or its password.

## Children

VaultSnap is not directed at children and does not collect any data
from anyone, regardless of age.

## Changes to this policy

This policy will be updated only if VaultSnap's data handling actually
changes. Given the local-only design, that should never happen — but
if it does, the updated policy will be posted at this URL and the
"Last updated" date will change.

## Contact

For questions about this policy or VaultSnap's privacy practices,
email: **TBD@example.com** _(replace with the developer's actual
contact email before publishing)_.
