import 'package:flutter/material.dart';

/// Plain-language "How VaultSnap stores your data" page. Reachable
/// from Settings → ABOUT.
///
/// The goal is *legibility* — every claim the app makes about your
/// privacy should be visible and explainable here, in words a
/// non-engineer can read on the way to deciding whether to trust the
/// thing with their passport scan. No marketing copy, no scary
/// security jargon — just "what we do, what we don't, and what an
/// attacker can and can't see."
class ThreatModelScreen extends StatelessWidget {
  const ThreatModelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('How VaultSnap stores your data'),
        backgroundColor: scheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: const [
          _Header(),
          SizedBox(height: 16),
          _Section(
            icon: Icons.storage_rounded,
            title: 'Where do my passwords live?',
            body:
                'Inside a local SQLite database on this device, encrypted '
                'with AES-GCM-256 under a key (the VMK) that exists only '
                'in your phone\'s memory. Nothing is uploaded. The vault '
                'never leaves the device.',
          ),
          _Section(
            icon: Icons.key_rounded,
            title: 'What about the master password?',
            body:
                'Your master password is fed through Argon2id (a slow, '
                'memory-hard hash) to derive a wrapping key. That wrapping '
                'key encrypts the VMK. We store the encrypted VMK on disk; '
                'we do NOT store the password itself. Without the '
                'password, the encrypted VMK is useless.',
          ),
          _Section(
            icon: Icons.search_rounded,
            title: "What's encrypted vs. searchable?",
            body:
                'Entry name, username, and website URL stay in cleartext '
                'SQL columns so search and autofill work without unlocking '
                'the whole vault. Passwords, TOTP secrets, attachments, '
                'and notes are all encrypted under the VMK and only '
                'readable when the vault is unlocked.',
          ),
          _Section(
            icon: Icons.help_outline_rounded,
            title: 'What if I lose my master password?',
            body:
                'Your recovery answer (set during setup) wraps the same '
                'VMK with a different KDF salt. Get the answer right and '
                'you can unlock + set a new master password. If you lose '
                'BOTH the master password and the recovery answer, the '
                'vault is unrecoverable — by design. There is no support '
                'line that can restore it.',
          ),
          _Section(
            icon: Icons.lock_rounded,
            title: 'What happens when the vault locks?',
            body:
                'The VMK is overwritten with zeroes in memory. Decrypted '
                'bytes from the last viewed attachment are scrubbed too. '
                'Auto-fill stops returning matches until you unlock '
                'again. Background → lock is automatic per your '
                'auto-lock setting.',
          ),
          _Section(
            icon: Icons.cloud_off_rounded,
            title: 'Does VaultSnap connect to the internet?',
            body:
                'No. Release builds ship without the INTERNET permission, '
                'so Android itself blocks any network call — even if the '
                'app tried, the OS would refuse. You can verify this in '
                'Settings → Apps → VaultSnap → Permissions: "Network" '
                'should not appear.',
          ),
          _Section(
            icon: Icons.fingerprint_rounded,
            title: 'How does biometric unlock work?',
            body:
                'A randomly-generated key in the Android Keystore wraps '
                'a copy of the VMK. The biometric prompt unlocks the '
                'Keystore key, which unlocks the VMK. Your fingerprint '
                'or face data never leaves the secure hardware on your '
                'phone — VaultSnap never sees it, only a yes/no signal '
                'from the OS.',
          ),
          _Section(
            icon: Icons.backup_outlined,
            title: 'How do backups work?',
            body:
                '`.vsb` files are encrypted under a separate '
                'backup-password-derived key — independent of your '
                'master password. Use Settings → "Verify backup" to '
                'confirm a backup actually decrypts before you trust '
                'it. Don\'t wipe your device just because you have a '
                '.vsb file — verify it first.',
          ),
          _Section(
            icon: Icons.warning_amber_rounded,
            title: 'What can an attacker with my unlocked phone see?',
            body:
                'Everything in the vault. Full stop. Once the app is '
                'open, the lock-on-background timer and biometric prompt '
                'are the only defences. If you\'re handing your phone '
                'to someone, lock the vault first (top-right lock icon).',
          ),
          _Section(
            icon: Icons.folder_off_outlined,
            title: 'What can an attacker with file-system access see?',
            body:
                'Entry names, usernames, website URLs, and the list of '
                'linked Android apps for autofill. None of those reveal '
                'passwords, TOTP secrets, attachments, or notes — those '
                'are AES-GCM-encrypted under the VMK, which they '
                'cannot derive without the master password.',
          ),
          SizedBox(height: 24),
          _Footer(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = scheme.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: isDark ? 0.22 : 0.16),
            accent.withValues(alpha: isDark ? 0.10 : 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.36 : 0.24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(
        children: [
          Icon(Icons.shield_rounded, color: accent, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Local-only, end-to-end encrypted',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No accounts, no cloud, no analytics. Plain English '
                  'below explains exactly what that means.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Section({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Selectable so users can quote / share specific guarantees.
            SelectableText(
              body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: scheme.onSurface,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'If anything here ever stops being true — for example a '
        'release build that asks for INTERNET permission — that\'s '
        'a bug. Report it.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
