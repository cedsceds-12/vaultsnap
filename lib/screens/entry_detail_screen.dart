import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attachment.dart';
import '../models/field_spec.dart';
import '../models/password_entry.dart';
import '../models/vault_entry.dart';
import '../providers/vault_locked_error.dart';
import '../providers/vault_providers.dart';
import '../providers/vault_repository_provider.dart';
import '../services/attachment_service.dart';
import '../services/autofill_session_service.dart';
import '../services/totp_service.dart';
import '../widgets/attachment_tile.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/vault_toast.dart';
import 'add_edit_entry_screen.dart';
import 'attachment_viewer_screen.dart';

class EntryDetailScreen extends ConsumerStatefulWidget {
  final VaultEntry entry;
  const EntryDetailScreen({super.key, required this.entry});

  @override
  ConsumerState<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends ConsumerState<EntryDetailScreen> {
  late VaultEntry _entry;
  Map<String, String>? _fields;
  bool _loading = true;
  String? _error;
  final Map<String, bool> _revealed = {};

  /// Cached resolved label / icon for the linked Android package, looked up
  /// asynchronously after the payload decrypts. Stays null on iOS / when the
  /// app is no longer installed; the row falls back to the bare package name.
  String? _linkedAppLabel;
  Uint8List? _linkedAppIcon;

  /// Loaded once with the payload; re-loaded after every add/delete so
  /// the section stays in sync with the SQL `attachments` rows.
  List<VaultAttachment> _attachments = const <VaultAttachment>[];
  bool _attachmentBusy = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPayload());
  }

  Future<void> _loadPayload() async {
    try {
      final map = await ref
          .read(vaultRepositoryProvider.notifier)
          .decryptEntryPayload(_entry);
      if (!mounted) return;
      setState(() {
        _fields = map;
        _loading = false;
      });
      unawaitedHydrate();
      unawaited(_loadAttachments());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadAttachments() async {
    try {
      final list = await ref
          .read(vaultRepositoryProvider.notifier)
          .attachmentsFor(_entry.id);
      if (!mounted) return;
      setState(() => _attachments = list);
    } catch (_) {
      // Non-fatal — keep the rest of the screen usable. Toast would
      // be noisy on every detail open if the DB hiccuped briefly.
    }
  }

  Future<void> _pickAndAddAttachment() async {
    if (_attachmentBusy) return;
    setState(() => _attachmentBusy = true);
    try {
      // Multi-pick lets the user attach a stack of related files
      // (e.g. front + back of a passport, or both sides of a driver's
      // licence) in one go instead of running the picker N times.
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
        allowMultiple: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      var oversized = false;
      for (final file in picked.files) {
        final bytes = file.bytes;
        if (bytes == null) continue; // Skip ones we couldn't read.
        if (bytes.length >= AttachmentService.softWarningBytes) {
          oversized = true;
        }
        await ref.read(vaultRepositoryProvider.notifier).addAttachment(
              entryId: _entry.id,
              name: file.name,
              mime: _mimeFromExtension(file.name),
              bytes: bytes,
            );
        if (!mounted) return;
      }
      if (!mounted) return;
      if (oversized) {
        VaultToast.show(
          context,
          'Large file(s) encrypted — backups will take a moment',
          icon: Icons.hourglass_top_rounded,
        );
      }
      await _loadAttachments();
      if (!mounted) return;
      VaultToast.showSuccess(
        context,
        picked.files.length == 1
            ? 'Document added'
            : '${picked.files.length} documents added',
      );
    } on VaultLockedError {
      if (!mounted) return;
      VaultToast.showError(context, 'Unlock the vault first');
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Could not attach file: $e');
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<void> _confirmDeleteAttachment(VaultAttachment a) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete document?',
      message: '"${a.name}" will be permanently removed from this device. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(vaultRepositoryProvider.notifier)
          .deleteAttachment(a);
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Delete failed: $e');
      return;
    }
    if (!mounted) return;
    await _loadAttachments();
    if (!mounted) return;
    VaultToast.show(
      context,
      'Document deleted',
      icon: Icons.delete_outline_rounded,
    );
  }

  void _openAttachment(VaultAttachment a) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AttachmentViewerScreen(attachment: a),
      ),
    );
  }

  /// Best-effort MIME guess from filename extension. Mirrors the
  /// suffixes file_picker reports for the common types we expect
  /// users to attach (passport scans = jpg/png/pdf, recovery codes =
  /// txt/pdf, IDs = pdf). Falls back to `application/octet-stream`.
  static String _mimeFromExtension(String name) {
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }

  void unawaitedHydrate() {
    final pkgs = _entry.androidPackages;
    if (pkgs.isEmpty || !Platform.isAndroid) return;
    final pkg = pkgs.first;
    unawaited(_hydrateLinkedApp(pkg));
  }

  Future<void> _hydrateLinkedApp(String pkg) async {
    try {
      final apps = await AutofillSessionService.queryLaunchableApps();
      if (!mounted) return;
      for (final a in apps) {
        if (a.packageName == pkg) {
          setState(() {
            _linkedAppLabel = a.label;
            _linkedAppIcon = a.iconPng;
          });
          return;
        }
      }
    } catch (_) {
      // Ignore — fall back to package name.
    }
  }

  Future<void> _copy(String label, String value) async {
    await ref.read(clipboardServiceProvider).copyAndScheduleClear(value);
    if (!mounted) return;
    VaultToast.show(
      context,
      '$label copied',
      icon: Icons.content_copy_rounded,
      duration: const Duration(milliseconds: 1400),
    );
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEditEntryScreen(entry: _entry),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;

    final entries = ref.read(vaultRepositoryProvider).maybeWhen(
          data: (d) => d,
          orElse: () => null,
        );
    if (entries != null) {
      VaultEntry? fresh;
      for (final e in entries) {
        if (e.id == _entry.id) {
          fresh = e;
          break;
        }
      }
      if (fresh == null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _entry = fresh!);
    }
    await _loadPayload();
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete entry?',
      message:
          'This will permanently remove “${_entry.name}” from this device. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(vaultRepositoryProvider.notifier)
          .deleteEntry(_entry.id);
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Delete failed: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    VaultToast.show(
      context,
      'Entry deleted',
      icon: Icons.delete_outline_rounded,
    );
  }

  bool _isObscurable(FieldType t) {
    return t == FieldType.password ||
        t == FieldType.pin ||
        t == FieldType.cardNumber;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entry = _entry;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Entry')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not decrypt entry.\n$_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final fields = _fields!;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            actions: [
              IconButton(
                tooltip: 'Edit',
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: _delete,
                icon:
                    Icon(Icons.delete_outline_rounded, color: scheme.error),
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _DetailHeader(entry: entry),
              titlePadding:
                  const EdgeInsetsDirectional.only(start: 56, bottom: 14),
              title: Text(
                entry.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 16),
              if (entry.category == EntryCategory.totp) ...[
                _TotpHeroCard(
                  entry: entry,
                  fields: fields,
                  onCopy: _copy,
                ),
                const SizedBox(height: 12),
              ],
              for (final spec in CategoryFields.forCategory(entry.category)) ...[
                if (entry.category == EntryCategory.login &&
                    spec.key == 'url') ...[
                  _autofillSummaryCard(entry, fields, scheme),
                  const SizedBox(height: 8),
                ] else ...[
                  _buildFieldRow(spec, fields, scheme),
                  const SizedBox(height: 8),
                ],
              ],
              _AttachmentsSection(
                attachments: _attachments,
                busy: _attachmentBusy,
                onAdd: _pickAndAddAttachment,
                onOpen: _openAttachment,
                onDelete: _confirmDeleteAttachment,
              ),
              const SizedBox(height: 8),
              _DetailRow(
                icon: Icons.update_rounded,
                label: 'Last updated',
                value: _formatDate(entry.updatedAt),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Stored locally only',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                'Sensitive fields are encrypted on this device. '
                                'Name and username stay searchable without opening the vault blob.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(
    FieldSpec spec,
    Map<String, String> fields,
    ColorScheme scheme,
  ) {
    final raw = fields[spec.key] ?? '';
    final display = raw.isEmpty ? '—' : raw;
    final obscurable = _isObscurable(spec.type);
    final revealed = _revealed[spec.key] ?? false;
    final showObscured = obscurable && !revealed && raw.isNotEmpty;
    final dots = showObscured
        ? '•' * display.length.clamp(8, 48).toInt()
        : display;
    final valueText = dots;

    return _DetailRow(
      icon: spec.icon,
      label: spec.label,
      value: valueText,
      obscure: showObscured,
      onCopy: raw.isEmpty ? null : () => _copy(spec.label, raw),
      trailing: obscurable && raw.isNotEmpty
          ? IconButton(
              tooltip: revealed ? 'Hide' : 'Reveal',
              onPressed: () => setState(
                () => _revealed[spec.key] = !revealed,
              ),
              icon: Icon(
                revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            )
          : null,
    );
  }

  /// Replaces the bare "Website" row on login entries with a card that shows
  /// both the linked Android app (if any) and the website URL together — same
  /// "Autofill matching" framing the editor uses, so users can see at a
  /// glance which app/site this entry will autofill.
  Widget _autofillSummaryCard(
    VaultEntry entry,
    Map<String, String> fields,
    ColorScheme scheme,
  ) {
    final isDark = scheme.brightness == Brightness.dark;
    final url = (fields['url'] ?? '').trim();
    final pkg = entry.androidPackages.isNotEmpty
        ? entry.androidPackages.first
        : null;
    final hasAny = pkg != null || url.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: isDark ? 0.06 : 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.primary.withValues(alpha: isDark ? 0.32 : 0.20),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Autofill matching',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hasAny
                  ? 'VaultSnap will offer this entry for the linked app or site.'
                  : 'No app or website linked yet — edit to enable autofill.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            if (Platform.isAndroid)
              _autofillAppRow(pkg: pkg, scheme: scheme),
            _autofillWebsiteRow(url: url, scheme: scheme),
          ],
        ),
      ),
    );
  }

  Widget _autofillAppRow({required String? pkg, required ColorScheme scheme}) {
    final hasPkg = pkg != null && pkg.isNotEmpty;
    final iconBytes = _linkedAppIcon;
    final leading = hasPkg && iconBytes != null && iconBytes.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              iconBytes,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.apps_rounded, color: scheme.primary, size: 22),
            ),
          )
        : Icon(
            Icons.apps_rounded,
            size: 22,
            color: hasPkg ? scheme.primary : scheme.onSurfaceVariant,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 36, height: 36, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App',
                  style:
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.4,
                          ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPkg
                      ? (_linkedAppLabel ?? pkg)
                      : 'Not linked',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: hasPkg ? null : scheme.onSurfaceVariant,
                        fontStyle: hasPkg ? null : FontStyle.italic,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasPkg && _linkedAppLabel != null && _linkedAppLabel != pkg)
                  Text(
                    pkg,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (hasPkg)
            IconButton(
              tooltip: 'Copy package',
              onPressed: () => _copy('Package', pkg),
              icon: const Icon(Icons.copy_rounded),
            ),
        ],
      ),
    );
  }

  Widget _autofillWebsiteRow({
    required String url,
    required ColorScheme scheme,
  }) {
    final hasUrl = url.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: Icon(
                Icons.public_rounded,
                size: 22,
                color: hasUrl ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Website',
                  style:
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.4,
                          ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasUrl ? url : 'Not linked',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: hasUrl ? null : scheme.onSurfaceVariant,
                        fontStyle: hasUrl ? null : FontStyle.italic,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (hasUrl)
            IconButton(
              tooltip: 'Copy URL',
              onPressed: () => _copy('Website', url),
              icon: const Icon(Icons.copy_rounded),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';
    return '${(diff.inDays / 365).floor()} years ago';
  }
}

class _DetailHeader extends StatelessWidget {
  final VaultEntry entry;
  const _DetailHeader({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = entry.category.accent;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.32 : 0.18),
            scheme.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 24,
            top: 70,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.5 : 0.35),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(entry.category.icon, color: accent, size: 30),
            ),
          ),
          Positioned(
            left: 100,
            top: 90,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.category.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                ),
                const SizedBox(height: 2),
                if (entry.url != null)
                  Text(
                    entry.url!,
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

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool obscure;
  final VoidCallback? onCopy;
  final Widget? trailing;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.obscure = false,
    this.onCopy,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                letterSpacing: 0.4,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(
                            fontFamily: obscure ? 'monospace' : null,
                            letterSpacing: obscure ? 1.4 : null,
                          ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: obscure ? 1 : 6,
                    ),
                  ],
                ),
              ),
              ?trailing,
              if (onCopy != null)
                IconButton(
                  tooltip: 'Copy',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Big live-code header shown at the top of an Authenticator entry's
/// detail page. Owns its own [Ticker] so the code rolls over once per
/// second and the period ring sweeps smoothly. Decodes the secret on
/// every rebuild from the supplied [fields] map (cheap — `decodeBase32`
/// is a few microseconds for 32 bytes); avoids any caching shenanigans
/// on a single-entry screen.
class _TotpHeroCard extends StatefulWidget {
  final VaultEntry entry;
  final Map<String, String> fields;
  final Future<void> Function(String label, String value) onCopy;

  const _TotpHeroCard({
    required this.entry,
    required this.fields,
    required this.onCopy,
  });

  @override
  State<_TotpHeroCard> createState() => _TotpHeroCardState();
}

class _TotpHeroCardState extends State<_TotpHeroCard> {
  /// Wall-clock 4 Hz refresh — see comment in
  /// [authenticator_screen.dart] for why this isn't a `Ticker`. Same
  /// reasoning: HMAC every animation frame is pointless when digits
  /// change once per period.
  Timer? _ticker;
  TotpSpec? _spec;
  bool _failed = false;
  // Memoised (T, code) so generateCode's HMAC only runs when the
  // current period rolls over.
  int _lastT = -1;
  String _lastCode = '';

  @override
  void initState() {
    super.initState();
    _rebuildSpec();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _TotpHeroCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fields != widget.fields) {
      _rebuildSpec();
    }
  }

  void _rebuildSpec() {
    final secret = (widget.fields['secret'] ?? '').trim();
    if (secret.isEmpty) {
      _spec = null;
      _failed = true;
      return;
    }
    try {
      final bytes = TotpService.decodeBase32(secret);
      final algoRaw = (widget.fields['algorithm'] ?? 'SHA1').toUpperCase();
      final algorithm = switch (algoRaw) {
        'SHA256' => TotpAlgorithm.sha256,
        'SHA512' => TotpAlgorithm.sha512,
        _ => TotpAlgorithm.sha1,
      };
      final digits = int.tryParse(widget.fields['digits'] ?? '6') ?? 6;
      final period = int.tryParse(widget.fields['period'] ?? '30') ?? 30;
      _spec = TotpSpec(
        secret: bytes,
        algorithm: algorithm,
        digits: digits == 6 || digits == 8 ? digits : 6,
        period: period > 0 ? period : 30,
        issuer: widget.fields['issuer'],
        account: widget.fields['account'],
      );
      _failed = false;
    } catch (_) {
      _spec = null;
      _failed = true;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _currentCode(TotpSpec spec) {
    final t = (DateTime.now().millisecondsSinceEpoch ~/ 1000) ~/ spec.period;
    if (t != _lastT) {
      _lastT = t;
      _lastCode = TotpService.generateCode(spec);
    }
    return _lastCode;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = EntryCategory.totp.accent;
    final spec = _spec;

    String code = '';
    int remaining = 0;
    double progress = 0;
    if (spec != null) {
      code = _currentCode(spec);
      remaining = TotpService.secondsRemaining(spec.period);
      progress = TotpService.progress(spec.period);
    }

    final formatted = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : (code.length == 8
            ? '${code.substring(0, 4)} ${code.substring(4)}'
            : code);
    final ringColor = remaining <= 5 ? scheme.error : accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: isDark ? 0.18 : 0.12),
              accent.withValues(alpha: isDark ? 0.08 : 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: isDark ? 0.40 : 0.28),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _failed ? 'Invalid secret' : 'Current code',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _failed ? '——————' : formatted,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: _failed ? scheme.error : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _failed
                        ? 'Edit to fix the secret'
                        : 'Tap to copy · refreshes in ${remaining}s',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            if (!_failed && spec != null)
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(56, 56),
                      painter: _HeroRingPainter(
                        progress: progress,
                        color: ringColor,
                        trackColor: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    Text(
                      '$remaining',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ringColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Copy',
              onPressed: code.isEmpty
                  ? null
                  : () => widget.onCopy(widget.entry.name, code),
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _HeroRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    final sweep = (1.0 - progress) * 2 * math.pi;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _HeroRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// Block of attachment tiles + an "Add attachment" affordance, shown
/// after the field rows on the entry detail. Stays mounted even when
/// empty so users notice the affordance and learn the feature exists.
class _AttachmentsSection extends StatelessWidget {
  final List<VaultAttachment> attachments;
  final bool busy;
  final VoidCallback onAdd;
  final void Function(VaultAttachment) onOpen;
  final Future<void> Function(VaultAttachment) onDelete;

  const _AttachmentsSection({
    required this.attachments,
    required this.busy,
    required this.onAdd,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(
              children: [
                Icon(
                  Icons.attach_file_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'DOCUMENTS',
                  style:
                      Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                          ),
                ),
                const SizedBox(width: 6),
                Text(
                  '· ${attachments.length}',
                  style:
                      Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.6,
                          ),
                ),
              ],
            ),
          ),
          for (final a in attachments) ...[
            AttachmentTile(
              attachment: a,
              onTap: () => onOpen(a),
              onLongPress: () => onDelete(a),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: busy ? null : onAdd,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(busy ? 'Encrypting…' : 'Add document'),
          ),
        ],
      ),
    );
  }
}
