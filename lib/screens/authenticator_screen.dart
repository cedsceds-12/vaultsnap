import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/password_entry.dart';
import '../models/vault_entry.dart';
import '../providers/vault_providers.dart';
import '../providers/vault_repository_provider.dart';
import '../services/totp_service.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/large_page_header.dart';
import '../widgets/section_header.dart';
import '../widgets/vault_lock_scope.dart';
import '../widgets/vault_toast.dart';
import 'add_edit_entry_screen.dart';
import 'entry_detail_screen.dart';

/// Bottom-nav 4th tab — lists every TOTP entry with a live, ticking
/// 6-/8-digit code and a circular period-ring countdown. One screen-level
/// `Ticker` drives all visible tiles in lockstep so codes never desync
/// across the list (cheaper too — N tickers per N tiles is wasteful).
///
/// Decryption isn't done here: the repository already exposes a list of
/// VaultEntry rows with cleartext metadata, and we only need the *secret*
/// bytes for code generation, which we lazily decrypt and cache once per
/// entry. Lock-on-background still clears those caches because the screen
/// is unmounted with the rest of the lock-scope subtree.
class AuthenticatorScreen extends ConsumerStatefulWidget {
  const AuthenticatorScreen({super.key});

  @override
  ConsumerState<AuthenticatorScreen> createState() =>
      _AuthenticatorScreenState();
}

class _AuthenticatorScreenState extends ConsumerState<AuthenticatorScreen> {
  /// Wall-clock timer driving the live code refresh. **Not** a `Ticker` —
  /// a Ticker calls back every animation frame (60 Hz) which means the
  /// screen rebuilds + every visible tile re-runs HMAC-SHA-{1,256,512}
  /// on every frame even though the digits only change once per period
  /// (typically 30 s). 250 ms / 4 Hz is enough resolution for both the
  /// period-ring sweep and the seconds-remaining countdown to read as
  /// smooth, while cutting screen-level rebuilds by ~15× compared to
  /// the previous Ticker.
  Timer? _ticker;

  /// Decrypted-once-per-session cache: entryId → parsed TOTP spec.
  /// Cleared whenever the Riverpod repo invalidates (entry added /
  /// updated / deleted). Secret bytes never leave this map.
  final Map<String, _CachedTotp> _cache = {};
  String? _decryptError;

  /// Multi-select state — same shape as VaultHomeScreen's. Long-press to
  /// enter, tap to toggle, contextual app-bar replaces the page header
  /// while a selection is active. Cleared after a successful delete and
  /// when the back button / predictive-back pops the screen.
  final Set<String> _selectedIds = {};
  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _hydrate(VaultEntry entry) async {
    if (_cache.containsKey(entry.id)) return;
    try {
      final fields = await ref
          .read(vaultRepositoryProvider.notifier)
          .decryptEntryPayload(entry);
      if (!mounted) return;
      final secret = (fields['secret'] ?? '').trim();
      if (secret.isEmpty) {
        _cache[entry.id] = _CachedTotp.failed();
        return;
      }
      final List<int> bytes;
      try {
        bytes = TotpService.decodeBase32(secret);
      } catch (_) {
        _cache[entry.id] = _CachedTotp.failed();
        return;
      }
      final algoRaw = (fields['algorithm'] ?? 'SHA1').toUpperCase();
      final algorithm = switch (algoRaw) {
        'SHA256' => TotpAlgorithm.sha256,
        'SHA512' => TotpAlgorithm.sha512,
        _ => TotpAlgorithm.sha1,
      };
      final digits = int.tryParse(fields['digits'] ?? '6') ?? 6;
      final period = int.tryParse(fields['period'] ?? '30') ?? 30;
      _cache[entry.id] = _CachedTotp.ok(
        TotpSpec(
          secret: bytes,
          algorithm: algorithm,
          digits: digits == 6 || digits == 8 ? digits : 6,
          period: period > 0 ? period : 30,
          issuer: fields['issuer'],
          account: fields['account'],
        ),
      );
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => _decryptError = 'Could not decrypt one or more entries');
      _cache[entry.id] = _CachedTotp.failed();
    }
  }

  Future<void> _copy(String label, String code) async {
    if (code.isEmpty) return;
    await ref.read(clipboardServiceProvider).copyAndScheduleClear(code);
    if (!mounted) return;
    VaultToast.show(
      context,
      '$label code copied',
      icon: Icons.content_copy_rounded,
      duration: const Duration(milliseconds: 1400),
    );
  }

  void _openDetail(VaultEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: entry)),
    );
  }

  void _openAdd() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const AddEditEntryScreen(initialCategory: EntryCategory.totp),
        fullscreenDialog: true,
      ),
    );
  }

  void _lock() => VaultLockScope.of(context).lock();

  void _toggleSelection(VaultEntry entry) {
    setState(() {
      if (_selectedIds.contains(entry.id)) {
        _selectedIds.remove(entry.id);
      } else {
        _selectedIds.add(entry.id);
      }
    });
  }

  void _enterSelection(VaultEntry entry) {
    HapticFeedback.mediumImpact();
    setState(() => _selectedIds.add(entry.id));
  }

  void _exitSelection() {
    if (_selectedIds.isEmpty) return;
    setState(_selectedIds.clear);
  }

  void _selectAll(List<VaultEntry> visible) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(visible.map((e) => e.id));
    });
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete $count ${count == 1 ? 'entry' : 'entries'}?',
      message: count == 1
          ? 'This authenticator entry will be permanently removed from this '
              'device. This cannot be undone.'
          : 'These $count authenticator entries will be permanently removed '
              'from this device. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final ids = _selectedIds.toList(growable: false);
    try {
      await ref
          .read(vaultRepositoryProvider.notifier)
          .deleteEntries(ids);
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Delete failed: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      // Drop cache entries for the deleted ids so we don't keep the
      // decoded secret bytes around longer than necessary.
      for (final id in ids) {
        _cache.remove(id);
      }
    });
    VaultToast.show(
      context,
      count == 1 ? 'Entry deleted' : '$count entries deleted',
      icon: Icons.delete_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asyncEntries = ref.watch(vaultRepositoryProvider);

    return asyncEntries.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load vault.\n$err',
                textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (entries) {
        final totps = entries
            .where((e) => e.category == EntryCategory.totp)
            .toList(growable: false);
        // Hydrate any entries whose secret hasn't been decrypted yet.
        // Runs once per entry per session — repeated rebuilds short-circuit
        // on the cache hit at the top of `_hydrate`.
        for (final e in totps) {
          // ignore: discarded_futures
          _hydrate(e);
        }
        return PopScope(
          canPop: !_selectionMode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _selectionMode) _exitSelection();
          },
          child: Scaffold(
            body: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    if (_selectionMode)
                      LargePageHeader(
                        title: '${_selectedIds.length} selected',
                        leading: IconButton(
                          onPressed: _exitSelection,
                          tooltip: 'Cancel',
                          icon: const Icon(Icons.close_rounded),
                        ),
                        actions: [
                          IconButton(
                            onPressed: () => _selectAll(totps),
                            tooltip: 'Select all',
                            icon: const Icon(Icons.select_all_rounded),
                          ),
                          IconButton(
                            onPressed: _confirmDeleteSelected,
                            tooltip: 'Delete selected',
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: scheme.error,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      )
                    else
                      LargePageHeader(
                        title: 'Authenticator',
                        actions: [
                          IconButton(
                            onPressed: _lock,
                            tooltip: 'Lock vault',
                            icon: const Icon(Icons.lock_outline_rounded),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    if (totps.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(scheme: scheme),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: SectionHeader(
                          title: 'CODES · ${totps.length}',
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        sliver: SliverList.separated(
                          itemCount: totps.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final entry = totps[i];
                            final cached = _cache[entry.id];
                            return RepaintBoundary(
                              child: _TotpTile(
                                entry: entry,
                                cached: cached,
                                selectionMode: _selectionMode,
                                selected: _selectedIds.contains(entry.id),
                                onCopy: _copy,
                                onTap: () => _selectionMode
                                    ? _toggleSelection(entry)
                                    : _openDetail(entry),
                                onLongPress: () => _selectionMode
                                    ? _toggleSelection(entry)
                                    : _enterSelection(entry),
                                onOpenDetail: () => _openDetail(entry),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (_decryptError != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _decryptError!,
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                      ),
                  ],
                ),
                if (!_selectionMode)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      child: FloatingActionButton(
                        onPressed: _openAdd,
                        tooltip: 'Add authenticator entry',
                        child: const Icon(Icons.add_rounded),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Mutable per-entry cache. Holds the parsed spec plus a memoised
/// (T, code) pair so the HMAC inside `TotpService.generateCode` only
/// runs once per period instead of once per rebuild — the screen ticks
/// at 4 Hz, but the digits only change every `spec.period` seconds.
class _CachedTotp {
  final TotpSpec? spec;
  final bool failed;
  int _lastT = -1;
  String _lastCode = '';

  _CachedTotp.ok(TotpSpec this.spec) : failed = false;
  _CachedTotp.failed()
      : spec = null,
        failed = true;

  /// Returns the current code, recomputing only when the period
  /// rolls. Called from build, so it must be cheap on the steady-state
  /// path; the early-return cache hit is the whole point.
  String code() {
    final s = spec;
    if (s == null) return '';
    final t = (DateTime.now().millisecondsSinceEpoch ~/ 1000) ~/ s.period;
    if (t != _lastT) {
      _lastT = t;
      _lastCode = TotpService.generateCode(s);
    }
    return _lastCode;
  }
}

class _TotpTile extends StatelessWidget {
  final VaultEntry entry;
  final _CachedTotp? cached;
  final void Function(String label, String code) onCopy;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Opens the entry's detail screen (where Edit / Delete live). Wired
  /// to a small chevron at the trailing edge — long-press now means
  /// "enter selection mode", so users need an explicit tap target to
  /// reach the editor instead.
  final VoidCallback onOpenDetail;
  final bool selectionMode;
  final bool selected;

  const _TotpTile({
    required this.entry,
    required this.cached,
    required this.onCopy,
    required this.onTap,
    required this.onOpenDetail,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = EntryCategory.totp.accent;
    final cachedSpec = cached?.spec;
    final failed = cached?.failed ?? false;

    String code = '';
    int remaining = 0;
    double progress = 0.0;
    if (cachedSpec != null) {
      // `cached!.code()` is memoised on (spec, T) — the HMAC only runs
      // when a new period rolls. `secondsRemaining` and `progress` are
      // cheap arithmetic from DateTime.now().
      code = cached!.code();
      remaining = TotpService.secondsRemaining(cachedSpec.period);
      progress = TotpService.progress(cachedSpec.period);
    }

    final formattedCode = _spaceSplit(code);
    final subtitle = entry.username ?? '';
    final ringColor = remaining <= 5 ? scheme.error : accent;
    final tileBg = selected
        ? scheme.primary.withValues(alpha: isDark ? 0.18 : 0.12)
        : scheme.surfaceContainer;
    final tileBorder = selected
        ? scheme.primary.withValues(alpha: isDark ? 0.5 : 0.36)
        : Colors.transparent;

    return Material(
      color: tileBg,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // In selection mode the tap toggles selection (parent maps onTap
        // to _toggleSelection); otherwise tap-to-copy is the primary
        // action and the chevron is replaced by a check-mark indicator.
        onTap: selectionMode
            ? onTap
            : (code.isEmpty ? onTap : () => onCopy(entry.name, code)),
        onLongPress: onLongPress ?? onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tileBorder, width: 1),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      accent.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        accent.withValues(alpha: isDark ? 0.4 : 0.32),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  EntryCategory.totp.icon,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      failed
                          ? 'Invalid secret'
                          : (code.isEmpty ? '••••••' : formattedCode),
                      style: TextStyle(
                        fontSize: 26,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4,
                        color: failed
                            ? scheme.error
                            : (code.isEmpty
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (selectionMode)
                _AuthSelectionMark(selected: selected, scheme: scheme)
              else ...[
                if (cachedSpec != null && !failed)
                  _PeriodRing(
                    progress: progress,
                    remaining: remaining,
                    color: ringColor,
                    trackColor:
                        scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                // Chevron → detail screen (Edit / Delete). Long-press is
                // now reserved for entering selection mode, so users
                // need an explicit tap target to manage the entry.
                IconButton(
                  tooltip: 'View / edit',
                  onPressed: onOpenDetail,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "123456" → "123 456" / "12345678" → "1234 5678" so the digits are
  /// readable in the same one-glance way every authenticator app uses.
  static String _spaceSplit(String code) {
    if (code.length == 6) return '${code.substring(0, 3)} ${code.substring(3)}';
    if (code.length == 8) return '${code.substring(0, 4)} ${code.substring(4)}';
    return code;
  }
}

/// Circular countdown ring + remaining-seconds number in the centre.
/// Repaints once per parent rebuild — cheap because we're only painting
/// two arcs and a 12sp text label.
class _AuthSelectionMark extends StatelessWidget {
  final bool selected;
  final ColorScheme scheme;
  const _AuthSelectionMark({required this.selected, required this.scheme});

  @override
  Widget build(BuildContext context) {
    const size = 24.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
          : null,
    );
  }
}

class _PeriodRing extends StatelessWidget {
  final double progress;
  final int remaining;
  final Color color;
  final Color trackColor;

  const _PeriodRing({
    required this.progress,
    required this.remaining,
    required this.color,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(40, 40),
            painter: _RingPainter(
              progress: progress,
              color: color,
              trackColor: trackColor,
            ),
          ),
          Text(
            '$remaining',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 3;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    final sweep = (1.0 - progress) * 2 * math.pi;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
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
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}

class _EmptyState extends StatelessWidget {
  final ColorScheme scheme;
  const _EmptyState({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final isDark = scheme.brightness == Brightness.dark;
    final accent = EntryCategory.totp.accent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.14 : 0.10),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.32 : 0.24),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(EntryCategory.totp.icon, color: accent, size: 38),
            ),
            const SizedBox(height: 18),
            Text(
              'No authenticator entries',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Tap + to add. Paste an otpauth:// URI on the next screen, '
              'or enter the secret manually.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
