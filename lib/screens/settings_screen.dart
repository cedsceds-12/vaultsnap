import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_providers.dart';
import '../providers/vault_repository_provider.dart';
import '../providers/vault_setup_provider.dart';
import '../services/autofill_session_service.dart';
import '../services/backup_service.dart';
import '../theme/theme_controller.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/large_page_header.dart';
import '../widgets/section_header.dart';
import '../widgets/vault_bottom_sheet.dart';
import '../widgets/vault_lock_scope.dart';
import '../widgets/vault_toast.dart';
import 'threat_model_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeController = ThemeScope.of(context);
    final lockController = VaultLockScope.of(context);
    final autoLockMinutes = lockController.autoLockMinutes;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          LargePageHeader(
            title: 'Settings',
            actions: [
              IconButton(
                tooltip: 'Lock vault now',
                onPressed: _lockNow,
                icon: const Icon(Icons.lock_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: const _ProfileBanner(),
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader(title: 'SECURITY')),
          SliverToBoxAdapter(
            child: _Group(
              children: [
                _BiometricTile(ref: ref),
                _divider(scheme),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Auto-lock'),
                  subtitle: Text(_autoLockLabel(autoLockMinutes)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickAutoLock,
                ),
                _divider(scheme),
                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Change master password'),
                  subtitle: const Text(
                    'Re-encrypt your vault with a new password',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _changeMasterPassword,
                ),
                if (Platform.isAndroid) ...[
                  _divider(scheme),
                  ListTile(
                    leading: const Icon(Icons.login_rounded),
                    title: const Text('Android autofill'),
                    subtitle: const Text(
                      'Fill passwords in other apps after you unlock',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      AutofillSessionService.openAndroidAutofillSettings();
                    },
                  ),
                ],
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader(title: 'PRIVACY')),
          SliverToBoxAdapter(
            child: _Group(
              children: [
                SwitchListTile.adaptive(
                  value: ref.watch(windowServiceProvider).isSecure,
                  onChanged: (v) async {
                    await ref.read(windowServiceProvider).setSecure(v);
                    _persistSetting('flagSecure', v);
                    if (mounted) setState(() {});
                  },
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Hide app in recents'),
                  subtitle: const Text(
                    'Prevent screenshots & hide in task switcher',
                  ),
                ),
                _divider(scheme),
                SwitchListTile.adaptive(
                  value: ref.watch(clipboardServiceProvider).enabled,
                  onChanged: (v) {
                    ref.read(clipboardServiceProvider).enabled = v;
                    _persistSetting('clipboardClear', v);
                    setState(() {});
                  },
                  secondary: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear clipboard'),
                  subtitle: const Text(
                    'Wipe copied passwords after 30 seconds',
                  ),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader(title: 'APPEARANCE')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.palette_outlined),
                          const SizedBox(width: 12),
                          Text(
                            'Theme',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<ThemeMode>(
                        // Tighter padding + smaller label keeps "System"
                        // on a single line alongside its icon, matching
                        // the visual rhythm of "Light" and "Dark".
                        style: SegmentedButton.styleFrom(
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('System', softWrap: false),
                            icon: Icon(Icons.brightness_auto_rounded),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Light', softWrap: false),
                            icon: Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark', softWrap: false),
                            icon: Icon(Icons.dark_mode_outlined),
                          ),
                        ],
                        selected: {themeController.mode},
                        onSelectionChanged: (s) {
                          final mode = s.first;
                          themeController.setMode(mode);
                          ref
                              .read(windowServiceProvider)
                              .setThemeMode(mode.name);
                          _persistSetting('themeMode', mode.name);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader(title: 'VAULT')),
          SliverToBoxAdapter(
            child: _Group(
              children: [
                ListTile(
                  leading: const Icon(Icons.import_export_rounded),
                  title: const Text('Export encrypted backup'),
                  subtitle: const Text('Save a password-protected vault file'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _exportBackup,
                ),
                _divider(scheme),
                ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Import vault'),
                  subtitle: const Text('Restore from an encrypted backup file'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _importBackup,
                ),
                _divider(scheme),
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Verify backup'),
                  subtitle:
                      const Text('Check a .vsb file decrypts before you trust it'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _verifyBackup,
                ),
                _divider(scheme),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: scheme.error,
                  ),
                  title: Text(
                    'Wipe vault',
                    style: TextStyle(color: scheme.error),
                  ),
                  subtitle: const Text(
                    'Permanently erase all entries from this device',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _wipeVault,
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader(title: 'ABOUT')),
          SliverToBoxAdapter(
            child: _Group(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('How VaultSnap stores your data'),
                  subtitle:
                      const Text('Plain-language threat model & guarantees'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ThreatModelScreen(),
                    ),
                  ),
                ),
                _divider(scheme),
                ListTile(
                  leading: const Icon(Icons.shield_moon_outlined),
                  title: const Text('Privacy guarantee'),
                  subtitle: const Text(
                    'Fully offline · No tracking · No accounts required',
                  ),
                ),
                _divider(scheme),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Version'),
                  subtitle: const Text('VaultSnap 1.0.0 (1)'),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Future<void> _persistSetting(String key, dynamic value) async {
    try {
      final storage = await ref.read(settingsStorageProvider.future);
      final data = await storage.load();
      data[key] = value;
      await storage.save(data);
    } catch (_) {
      // Non-critical.
    }
  }

  String _autoLockLabel(int m) {
    if (m == 0) return 'When I leave the app';
    if (m == 1) return 'After 1 minute';
    if (m < 60) return 'After $m minutes';
    return 'After ${(m / 60).round()} hour';
  }

  Future<void> _pickAutoLock() async {
    final lockCtrl = VaultLockScope.of(context);
    final currentMinutes = lockCtrl.autoLockMinutes;
    final selected = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        const options = [0, 1, 5, 15, 30, 60];
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text(
                    'Auto-lock vault',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Timed options count while VaultSnap stays open.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: RadioGroup<int>(
                      groupValue: currentMinutes,
                      onChanged: (v) => Navigator.of(context).pop(v),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final o in options)
                            RadioListTile<int>(
                              value: o,
                              title: Text(_autoLockLabel(o)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      lockCtrl.autoLockMinutes = selected;
    }
  }

  Future<void> _changeMasterPassword() async {
    await showVaultBottomSheet<void>(
      context: context,
      child: const _ChangeMasterPasswordSheet(),
    );
  }

  void _lockNow() {
    VaultLockScope.of(context).lock();
  }

  Future<void> _exportBackup() async {
    final vmk = VaultLockScope.of(context).vmk;
    if (vmk == null) {
      VaultToast.showError(context, 'Unlock the vault first');
      return;
    }

    final password = await _askBackupPassword(
      title: 'Export backup',
      subtitle: 'Choose a password to protect this backup file.',
      action: 'Export',
    );
    if (password == null || !mounted) return;

    try {
      final crypto = ref.read(cryptoServiceProvider);
      final db = await ref.read(vaultDatabaseProvider.future);

      final bytes = await BackupService(
        crypto,
      ).exportToBytes(db: db, vmk: vmk, backupPassword: password);

      final ts = DateTime.now()
          .toIso8601String()
          .split('T')
          .first
          .replaceAll('-', '');
      final saved = await ref
          .read(windowServiceProvider)
          .saveBytes(bytes: bytes, suggestedName: 'vaultsnap_backup_$ts.vsb');

      if (!mounted) return;
      if (saved == null) return;
      VaultToast.showSuccess(context, 'Backup saved as $saved');
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Export failed: $e');
    }
  }

  Future<void> _importBackup() async {
    final currentVmk = VaultLockScope.of(context).vmk;
    if (currentVmk == null) {
      VaultToast.showError(context, 'Unlock the vault first');
      return;
    }

    final picked = await ref.read(windowServiceProvider).pickFile();
    if (picked == null || !mounted) return;

    final password = await _askBackupPassword(
      title: 'Import backup',
      subtitle: 'Enter the password used when exporting.',
      action: 'Import',
    );
    if (password == null || !mounted) return;

    try {
      final crypto = ref.read(cryptoServiceProvider);
      final db = await ref.read(vaultDatabaseProvider.future);

      final count = await BackupService(crypto).importFromBytes(
        db: db,
        currentVmk: currentVmk,
        backupPassword: password,
        bytes: picked.bytes,
      );

      if (!mounted) return;
      if (count == null) {
        VaultToast.showError(context, 'Wrong backup password');
        return;
      }

      ref.invalidate(vaultRepositoryProvider);
      VaultToast.showSuccess(context, 'Imported $count entries');
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Import failed: $e');
    }
  }

  /// Phase 10 — dry-run verification of a `.vsb` file. Decrypts and
  /// counts but does NOT touch the DB or the on-disk attachments dir,
  /// so the user can confirm a backup actually decrypts before they
  /// trust it (i.e., before they wipe their device assuming the
  /// backup is good). Verify is safe to run with the vault locked —
  /// no current-VMK access required.
  Future<void> _verifyBackup() async {
    final picked = await ref.read(windowServiceProvider).pickFile();
    if (picked == null || !mounted) return;

    final password = await _askBackupPassword(
      title: 'Verify backup',
      subtitle: 'Enter the password used when this backup was exported.',
      action: 'Verify',
    );
    if (password == null || !mounted) return;

    final crypto = ref.read(cryptoServiceProvider);
    final attachments = ref.read(attachmentServiceProvider);
    BackupVerifyResult? result;
    String? error;
    try {
      result = await BackupService(crypto, attachments: attachments)
          .verifyBytes(bytes: picked.bytes, backupPassword: password);
    } on FormatException catch (_) {
      error = 'corrupted';
    } catch (_) {
      // SecretBoxAuthenticationError thrown after wrappedVmk decrypts
      // means the file was modified — past the wrong-password gate but
      // the entries / attachments MAC failed.
      error = 'corrupted';
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _VerifyResultDialog(
        result: result,
        error: error,
      ),
    );
  }

  Future<String?> _askBackupPassword({
    required String title,
    required String subtitle,
    required String action,
  }) async {
    return showVaultBottomSheet<String>(
      context: context,
      child: _BackupPasswordSheet(
        title: title,
        subtitle: subtitle,
        action: action,
      ),
    );
  }

  Future<void> _wipeVault() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Wipe vault?',
      message:
          'All entries will be permanently erased from this device. '
          'This cannot be undone.',
      confirmLabel: 'Wipe everything',
      icon: Icons.delete_forever_outlined,
      destructive: true,
    );
    if (!ok || !mounted) return;

    try {
      final db = await ref.read(vaultDatabaseProvider.future);
      await db.deleteAll();
      // Phase 9 — also wipe per-file ciphertext under
      // <docs>/vault_attachments/. Best-effort: a missing dir is
      // fine, and a failure here shouldn't block the rest of the
      // wipe (the user explicitly asked for it).
      try {
        await ref.read(attachmentServiceProvider).wipeAll();
      } catch (_) {
        // Swallow.
      }
      final storage = await ref.read(vaultStorageProvider.future);
      await storage.delete();
      final bio = ref.read(biometricServiceProvider);
      await bio.deleteKey();

      if (!mounted) return;
      VaultLockScope.of(context).lock();
      ref.invalidate(vaultMetaProvider);
      ref.invalidate(vaultDatabaseProvider);
      ref.invalidate(vaultRepositoryProvider);
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Wipe failed: $e');
    }
  }

  Widget _divider(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.only(left: 60),
    child: Divider(
      height: 1,
      color: scheme.outlineVariant.withValues(alpha: 0.4),
    ),
  );
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(child: Column(children: children)),
    );
  }
}

/// Result dialog for [_SettingsScreenState._verifyBackup]. Shows one of
/// three states: valid (counts), wrong password, or corrupted file.
/// Single OK button, no further action — verify is read-only.
class _VerifyResultDialog extends StatelessWidget {
  final BackupVerifyResult? result;
  final String? error;
  const _VerifyResultDialog({this.result, this.error});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isValid = result != null;
    // result == null AND error == null → wrong password (verifyBytes
    // returns null). result == null AND error == 'corrupted' → MAC
    // failure or junk JSON. The two error states get different icons +
    // copy so users know whether to re-enter the password vs. give up.
    final isWrongPw = result == null && error == null;

    final (Color tone, IconData icon, String title, String body) =
        isValid
            ? (
                const Color(0xFF22C55E),
                Icons.check_circle_outline_rounded,
                'Backup is valid',
                _formatValidBody(result!),
              )
            : isWrongPw
                ? (
                    const Color(0xFFF59E0B),
                    Icons.warning_amber_rounded,
                    'Wrong backup password',
                    'The password you entered did not unlock this '
                        'backup. Try again or pick a different file.',
                  )
                : (
                    scheme.error,
                    Icons.error_outline_rounded,
                    'Backup is corrupted',
                    'This file is not a valid VaultSnap backup, or the '
                        'data inside has been modified since export.',
                  );

    return AlertDialog(
      icon: Icon(icon, color: tone, size: 36),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(
        body,
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }

  static String _formatValidBody(BackupVerifyResult r) {
    final entries =
        r.entryCount == 1 ? '1 entry' : '${r.entryCount} entries';
    final docs = r.attachmentCount == 1
        ? '1 document'
        : '${r.attachmentCount} documents';
    final docsLine = r.version == 1
        ? '' // v1 backups had no attachments support
        : ' and $docs';
    return 'This backup decrypts cleanly and contains $entries$docsLine. '
        'Safe to rely on for restore.';
  }
}

class _BackupPasswordSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String action;

  const _BackupPasswordSheet({
    required this.title,
    required this.subtitle,
    required this.action,
  });

  @override
  State<_BackupPasswordSheet> createState() => _BackupPasswordSheetState();
}

class _BackupPasswordSheetState extends State<_BackupPasswordSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              // K-14: backup password protects an exported `.vsb` and can
              // decrypt every entry inside it — opt out of cross-app
              // autofill so a different installed autofill service can't
              // see, suggest into, or log it.
              autofillHints: const <String>[],
              decoration: const InputDecoration(
                labelText: 'Backup password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.action),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileBanner extends ConsumerWidget {
  const _ProfileBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final entryCount = ref
        .watch(vaultRepositoryProvider)
        .maybeWhen(data: (list) => list.length, orElse: () => 0);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.18),
            scheme.tertiary.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.shield_rounded, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Vault stored locally · $entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
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

class _ChangeMasterPasswordSheet extends ConsumerStatefulWidget {
  const _ChangeMasterPasswordSheet();

  @override
  ConsumerState<_ChangeMasterPasswordSheet> createState() =>
      _ChangeMasterPasswordSheetState();
}

class _ChangeMasterPasswordSheetState
    extends ConsumerState<_ChangeMasterPasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final service = await ref.read(vaultSetupServiceProvider.future);
      final meta = await ref.read(vaultMetaProvider.future);
      if (meta == null || !mounted) return;

      final updated = await service.changeMasterPassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
        meta: meta,
      );

      if (!mounted) return;
      if (updated == null) {
        setState(() {
          _busy = false;
          _error = 'Current password is wrong';
        });
        return;
      }

      ref.invalidate(vaultMetaProvider);
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Master password updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Do NOT use MediaQuery.viewInsetsOf here.
    // It changes on every animation frame (~30 times) while the keyboard
    // slides open, triggering a full rebuild + re-layout each time — the
    // root cause of the "low FPS" scroll when the keyboard appears.
    //
    // Instead we rely on:
    //   • isScrollControlled: true  → the modal route already constrains
    //     this sheet to the space ABOVE the keyboard.
    //   • SingleChildScrollView     → content scrolls if it's still too tall.
    //   • ensureVisible (built into TextFormField) → the focused field
    //     scrolls into view with a single smooth animation, no per-frame
    //     rebuilds.
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Change master password',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your vault will be re-encrypted with the new password.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _currentController,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                // K-14: master password fields opted out of cross-app
                // autofill — see comment in VaultLockScope's unlock field.
                autofillHints: const <String>[],
                decoration: InputDecoration(
                  labelText: 'Current password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _newController,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const <String>[],
                decoration: const InputDecoration(
                  labelText: 'New password',
                  prefixIcon: Icon(Icons.lock_rounded),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 8) return 'Must be at least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const <String>[],
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.check_rounded),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v != _newController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Update password'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BiometricTile extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _BiometricTile({required this.ref});

  @override
  ConsumerState<_BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends ConsumerState<_BiometricTile> {
  bool _busy = false;

  Future<void> _toggle(bool enable) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final service = await ref.read(vaultSetupServiceProvider.future);
      final meta = await ref.read(vaultMetaProvider.future);
      if (meta == null || !mounted) {
        setState(() => _busy = false);
        return;
      }

      if (enable) {
        final vmk = VaultLockScope.of(context).vmk;
        if (vmk == null) {
          if (mounted) {
            VaultToast.showError(context, 'Vault must be unlocked first');
          }
          setState(() => _busy = false);
          return;
        }
        final updated = await service.enableBiometric(meta: meta, vmk: vmk);
        if (updated == null && mounted) {
          VaultToast.show(context, 'Biometric authentication cancelled');
        }
      } else {
        await service.disableBiometric(meta: meta);
      }

      ref.invalidate(vaultMetaProvider);
    } catch (e) {
      if (mounted) {
        VaultToast.showError(context, 'Biometric error: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metaAsync = ref.watch(vaultMetaProvider);
    final hasBio = metaAsync.whenOrNull(data: (m) => m?.hasBiometric) ?? false;

    return SwitchListTile.adaptive(
      value: hasBio,
      onChanged: _busy ? null : _toggle,
      secondary: const Icon(Icons.fingerprint_rounded),
      title: const Text('Biometric unlock'),
      subtitle: const Text(
        'Use fingerprint or Face ID instead of master password',
      ),
    );
  }
}
