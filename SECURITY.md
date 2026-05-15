# Security policy

VaultSnap is a password manager. Security is the product. If you find a
vulnerability, please report it responsibly using the process below.

## Supported versions

| Version | Supported          |
|---------|--------------------|
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |

The latest minor release of the 1.x line receives security fixes. Older
versions do not.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Use GitHub's private vulnerability reporting:

1. Go to https://github.com/cedsceds-12/vaultsnap/security/advisories/new
2. Fill in the form with a clear description, reproduction steps, and
   impact assessment
3. Submit

Reports stay private between you and the maintainer until a fix ships.

## What to include

- VaultSnap version (Settings -> About, or the release tag)
- Android version and device model
- Clear reproduction steps
- Expected vs. actual behavior
- Impact: what data or capability is exposed
- Proof of concept if applicable (sanitize any real credentials first)

## Response timeline

- **Acknowledgement:** within 7 days
- **Initial assessment:** within 14 days
- **Patch availability:** target 30 days for high/critical, best-effort
  for medium/low

VaultSnap is maintained by a single developer; please be patient.

## Scope

### In scope

- Cryptographic flaws in the vault encryption, KDF parameters, backup
  format, or RSA-OAEP MethodChannel bridge
- Vault Master Key recovery without the master password or recovery
  answer
- Plaintext leakage of passwords, TOTP secrets, attachment bytes, or
  the VMK (logs, clipboard beyond intended scope, MethodChannel,
  generated files, route arguments, static fields)
- Autofill leakage: filling credentials into apps or sites the entry was
  not linked to; missing biometric prompt on a locked vault
- Network traffic from the release build (release APK must request no
  `INTERNET` permission and must not emit any socket)
- Bypassing auto-lock, biometric unlock, or recovery-question backoff
- Backup file (`.vsb`) tampering not detected by MAC verification
- R8 / ProGuard config gaps that strip security-relevant code

### Out of scope

- Issues that require root, ADB shell with elevated privileges, or a
  custom recovery / unlocked bootloader
- Physical-access attacks on an unlocked phone (the lock-on-background
  timer + biometric prompt are the only defenses by design)
- Side-channel attacks requiring specialized hardware
- Vulnerabilities in third-party Flutter / Android dependencies (please
  report those upstream)
- Social engineering of the user
- Self-XSS or other issues that require the attacker to already be the
  user
- Anything documented as a known limitation in
  `lib/screens/threat_model_screen.dart`

## Disclosure

When a fix is ready, a coordinated disclosure date will be agreed with
the reporter. A GitHub Security Advisory will be published with credit
(if requested) and a CVE assigned where appropriate.

## Hall of fame

Security researchers who report valid vulnerabilities will be credited
here unless they request anonymity.

*(empty — be the first)*
