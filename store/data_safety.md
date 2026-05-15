# VaultSnap — Play Console Data Safety form answers

Google Play requires every app to fill in a "Data Safety" section. The
answers below are the truth for VaultSnap and should be entered verbatim.

---

## Data collection and security

### Does your app collect or share any of the required user data types?

**No.**

VaultSnap stores all user data — including passwords, TOTP secrets, and
attachments — locally on the user's device, encrypted under a key
derived from the user's master password. Nothing is collected by the
developer, transmitted to any server, or shared with any third party.
The release build of the app does not include the `INTERNET`
permission, making network communication impossible at the OS level.

### Is all of the user data collected by your app encrypted in transit?

**N/A — VaultSnap collects no user data and transmits no data over a
network. There is no "in transit" path.**

### Do you provide a way for users to request that their data be deleted?

**Yes.**

Users can wipe the entire vault at any time via Settings → Wipe vault.
This destroys:

- The encrypted entries database
- The vault metadata file (KDF salts, wrapped VMK, recovery wrap)
- The biometric-wrapped key in the Android Keystore
- All on-disk encrypted attachment files

Uninstalling the app from Android Settings also removes all VaultSnap
data, since nothing is stored outside the app's private directory.

---

## Data types — quick reference

For every category Play asks about, the answer is the same:

| Category | Collected? | Shared? |
|---|---|---|
| Personal info | No | No |
| Financial info | No | No |
| Health & fitness | No | No |
| Messages | No | No |
| Photos & videos | No | No |
| Audio files | No | No |
| Files & docs | No | No |
| Calendar | No | No |
| Contacts | No | No |
| App activity | No | No |
| Web browsing | No | No |
| App info & performance | No | No |
| Device or other IDs | No | No |

The vault contents (passwords, attachments, TOTP secrets) are **stored
on the user's device** but are not "collected" in Play's sense — the
developer has no access to them and they never leave the device.

---

## Security practices

| Practice | Answer |
|---|---|
| Data is encrypted in transit | N/A — no network traffic |
| Users can request data deletion | Yes — Settings → Wipe vault |
| Committed to follow Play Families Policy | N/A (not a kids app) |
| Has been independently security-reviewed | No (self-reviewed; reviewers welcome) |
| Provides a way for users to manage their data | Yes — full CRUD inside the app |

---

## Permissions disclosed

Two manifest permissions, both with clear in-app justifications:

- **`USE_BIOMETRIC`** — fingerprint / face unlock for the master vault.
  Optional (vault works with master password alone). Authentication
  happens entirely in the device's secure hardware.
- **`BIND_AUTOFILL_SERVICE`** — system-only permission required to
  register VaultSnap as the user's Android Autofill provider. Cannot be
  granted by an app to itself; the user enables it from Android
  Settings → Autofill service.

No other manifest permissions are requested.
