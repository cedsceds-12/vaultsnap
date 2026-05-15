import 'dart:math' as math;
import 'dart:ui' as ui;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/password_entry.dart';
import '../models/vault_entry.dart';
import '../providers/vault_providers.dart';
import '../providers/vault_repository_provider.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/entry_tile.dart';
import '../widgets/large_page_header.dart';
import '../widgets/section_header.dart';
import '../theme/app_theme.dart';
import '../widgets/vault_lock_scope.dart';
import '../widgets/vault_toast.dart';
import 'add_edit_entry_screen.dart';
import 'entry_detail_screen.dart';
import 'search_screen.dart';

enum _SortMode { recent, name, category }

enum _HealthFilter { all, weak, reused }

class VaultHomeScreen extends ConsumerStatefulWidget {
  const VaultHomeScreen({super.key});

  @override
  ConsumerState<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends ConsumerState<VaultHomeScreen>
    with SingleTickerProviderStateMixin {
  EntryCategory? _filter;
  _HealthFilter _healthFilter = _HealthFilter.all;
  _SortMode _sort = _SortMode.recent;

  /// Multi-select state. Long-press an entry to enter selection mode and
  /// pick more by tapping; the app-bar swaps to a contextual delete bar
  /// while [_selectedIds] is non-empty. Selections clear when the screen
  /// rebuilds from a Riverpod refresh after a batch delete, when the
  /// user taps Cancel, or implicitly when the vault locks (the lock
  /// scope unmounts this subtree).
  final Set<String> _selectedIds = {};
  bool get _selectionMode => _selectedIds.isNotEmpty;

  /// Settings JSON key for the persisted sort mode. Held in
  /// `vaultsnap_settings.json` alongside autoLockMinutes etc. We don't
  /// persist `_filter` or `_healthFilter` — those reset per-session so a
  /// user landing on "weak only" never thinks their vault is empty.
  static const _sortPrefKey = 'vaultDefaultSort';

  late final AnimationController _fabController;
  late final CurvedAnimation _fabCurve;
  bool _fabOpen = false;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabCurve = CurvedAnimation(
      parent: _fabController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInQuart,
    );
    unawaited(_loadPersistedSort());
  }

  Future<void> _loadPersistedSort() async {
    try {
      final storage = await ref.read(settingsStorageProvider.future);
      final data = await storage.load();
      final raw = data[_sortPrefKey] as String?;
      if (raw == null || !mounted) return;
      final parsed = _SortMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => _SortMode.recent,
      );
      if (parsed != _sort) {
        setState(() => _sort = parsed);
      }
    } catch (_) {
      // Non-critical — defaults to recent. Don't surface to the user.
    }
  }

  Future<void> _persistSort(_SortMode sort) async {
    try {
      final storage = await ref.read(settingsStorageProvider.future);
      final data = await storage.load();
      data[_sortPrefKey] = sort.name;
      await storage.save(data);
    } catch (_) {
      // Non-critical — the in-memory value still works this session.
    }
  }

  @override
  void dispose() {
    _fabCurve.dispose();
    _fabController.dispose();
    super.dispose();
  }

  List<VaultEntry> _filtered(List<VaultEntry> entries) {
    // TOTP entries live in the dedicated Authenticator tab — keep them out
    // of the main vault list so the same code doesn't appear in two places.
    // The category chip row below also drops the Authenticator option for
    // the same reason; users add TOTPs from the Authenticator tab's FAB
    // (or via the Vault FAB's category picker, which routes them straight
    // through the same screen on save).
    final visible = entries
        .where((e) => e.category != EntryCategory.totp)
        .toList(growable: false);
    final list = _filter == null
        ? List<VaultEntry>.from(visible)
        : visible.where((e) => e.category == _filter).toList();
    switch (_healthFilter) {
      case _HealthFilter.all:
        break;
      case _HealthFilter.weak:
        list.removeWhere(
          (e) =>
              e.strength != PasswordStrength.weak &&
              e.strength != PasswordStrength.fair,
        );
      case _HealthFilter.reused:
        list.removeWhere((e) => !e.reused);
    }
    switch (_sort) {
      case _SortMode.recent:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _SortMode.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _SortMode.category:
        list.sort((a, b) => a.category.index.compareTo(b.category.index));
    }
    return list;
  }

  void _toggleFab() {
    HapticFeedback.lightImpact();
    setState(() => _fabOpen = !_fabOpen);
    if (_fabOpen) {
      _fabController.forward();
    } else {
      _fabController.reverse();
    }
  }

  void _closeFab() {
    if (!_fabOpen) return;
    setState(() => _fabOpen = false);
    _fabController.reverse();
  }

  void _openAdd([EntryCategory? category]) {
    _closeFab();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEditEntryScreen(initialCategory: category),
        fullscreenDialog: true,
      ),
    );
  }

  void _openDetail(VaultEntry entry) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: entry)));
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SearchScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openSort() async {
    final picked = await showModalBottomSheet<_SortMode>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    'Sort by',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _SortOption(
                  icon: Icons.history_rounded,
                  label: 'Recently updated',
                  selected: _sort == _SortMode.recent,
                  onTap: () => Navigator.of(context).pop(_SortMode.recent),
                ),
                _SortOption(
                  icon: Icons.sort_by_alpha_rounded,
                  label: 'Name (A → Z)',
                  selected: _sort == _SortMode.name,
                  onTap: () => Navigator.of(context).pop(_SortMode.name),
                ),
                _SortOption(
                  icon: Icons.category_outlined,
                  label: 'Category',
                  selected: _sort == _SortMode.category,
                  onTap: () => Navigator.of(context).pop(_SortMode.category),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => _sort = picked);
      unawaited(_persistSort(picked));
    }
  }

  void _lock() {
    VaultLockScope.of(context).lock();
  }

  // ---------- Multi-select ----------

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

  void _selectAllVisible(List<VaultEntry> visible) {
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
          ? 'This entry will be permanently removed from this device. '
              'This cannot be undone.'
          : 'These $count entries will be permanently removed from this '
              'device. This cannot be undone.',
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
    setState(_selectedIds.clear);
    VaultToast.show(
      context,
      count == 1 ? 'Entry deleted' : '$count entries deleted',
      icon: Icons.delete_outline_rounded,
    );
  }

  List<Widget> _buildCategoryGroupedSlivers(List<VaultEntry> sorted) {
    final groups = <EntryCategory, List<VaultEntry>>{};
    for (final e in sorted) {
      groups.putIfAbsent(e.category, () => []).add(e);
    }

    final slivers = <Widget>[];
    var isLast = false;
    final keys = groups.keys.toList();
    for (var gi = 0; gi < keys.length; gi++) {
      final cat = keys[gi];
      final items = groups[cat]!;
      isLast = gi == keys.length - 1;

      slivers.add(
        SliverToBoxAdapter(
          child: _CategoryGroupHeader(category: cat, count: items.length),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, isLast ? 100 : 4),
          sliver: SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final entry = items[i];
              // RepaintBoundary isolates each tile's paint layer so
              // toggling one entry's selection state during multi-
              // select doesn't repaint every other tile in the list.
              // Same trick the Authenticator screen already uses.
              return RepaintBoundary(
                child: EntryTile(
                  key: ValueKey(entry.id),
                  entry: entry,
                  selectionMode: _selectionMode,
                  selected: _selectedIds.contains(entry.id),
                  onTap: () => _selectionMode
                      ? _toggleSelection(entry)
                      : _openDetail(entry),
                  onLongPress: () => _selectionMode
                      ? _toggleSelection(entry)
                      : _enterSelection(entry),
                ),
              );
            },
          ),
        ),
      );
    }
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entriesAsync = ref.watch(vaultRepositoryProvider);

    return entriesAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load vault.\n$err',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      data: (entries) => _buildVaultBody(scheme: scheme, entries: entries),
    );
  }

  Widget _buildVaultBody({
    required ColorScheme scheme,
    required List<VaultEntry> entries,
  }) {
    final weakCount = entries
        .where(
          (e) =>
              e.strength == PasswordStrength.weak ||
              e.strength == PasswordStrength.fair,
        )
        .length;
    final reusedCount = entries.where((e) => e.reused).length;
    final filtered = _filtered(entries);

    // Back button (or predictive-back gesture) exits selection mode
    // before popping the screen — feels expected for any multi-select
    // pattern (Photos, Mail, Files all behave this way).
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
                      onPressed: () => _selectAllVisible(filtered),
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
                  title: 'Vault',
                  actions: [
                    IconButton(
                      onPressed: _openSearch,
                      tooltip: 'Search',
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      onPressed: _openSort,
                      tooltip: 'Sort',
                      icon: const Icon(Icons.sort_rounded),
                    ),
                    IconButton(
                      onPressed: _lock,
                      tooltip: 'Lock vault',
                      icon: const Icon(Icons.lock_outline_rounded),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: RepaintBoundary(
                    child: _SecuritySummaryCard(
                      total: entries.length,
                      weak: weakCount,
                      reused: reusedCount,
                      scheme: scheme,
                      healthFilter: _healthFilter,
                      onFilter: (filter) {
                        setState(() {
                          _healthFilter = _healthFilter == filter
                              ? _HealthFilter.all
                              : filter;
                        });
                      },
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _CategoryChip(
                        label: 'All',
                        icon: Icons.apps_rounded,
                        selected: _filter == null,
                        onTap: () => setState(() {
                          _filter = null;
                          _healthFilter = _HealthFilter.all;
                        }),
                      ),
                      // Authenticator (TOTP) is filtered out — it has its
                      // own bottom-nav tab, so a chip here would offer
                      // nothing to filter to.
                      for (final c in EntryCategory.values)
                        if (c != EntryCategory.totp)
                          _CategoryChip(
                            label: c.label,
                            icon: c.icon,
                            accent: c.accent,
                            selected: _filter == c,
                            onTap: () => setState(() {
                              _filter = _filter == c ? null : c;
                              _healthFilter = _HealthFilter.all;
                            }),
                          ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: _filter == null
                      ? '${_healthFilterLabel(_healthFilter)} · ${filtered.length}'
                      : '${_filter!.label.toUpperCase()} · ${filtered.length}',
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyVaultState(category: _filter),
                )
              else if (_sort == _SortMode.category)
                ..._buildCategoryGroupedSlivers(filtered)
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final entry = filtered[i];
                      // See comment above for why we wrap in
                      // RepaintBoundary — same per-tile paint
                      // isolation, used here in the category-grouped
                      // sliver list.
                      return RepaintBoundary(
                        child: EntryTile(
                          key: ValueKey(entry.id),
                          entry: entry,
                          selectionMode: _selectionMode,
                          selected: _selectedIds.contains(entry.id),
                          onTap: () => _selectionMode
                              ? _toggleSelection(entry)
                              : _openDetail(entry),
                          onLongPress: () => _selectionMode
                              ? _toggleSelection(entry)
                              : _enterSelection(entry),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          if (!_selectionMode) ...[
            _SpeedDialScrim(
              animation: _fabCurve,
              open: _fabOpen,
              onClose: _closeFab,
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: _SpeedDialFab(
                  animation: _fabCurve,
                  open: _fabOpen,
                  onToggle: _toggleFab,
                  onCategory: (c) => _openAdd(c),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

String _healthFilterLabel(_HealthFilter filter) {
  return switch (filter) {
    _HealthFilter.all => 'ALL ITEMS',
    _HealthFilter.weak => 'WEAK PASSWORDS',
    _HealthFilter.reused => 'REUSED PASSWORDS',
  };
}

class _SortOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? scheme.primary : null),
      title: Text(
        label,
        style: TextStyle(color: selected ? scheme.primary : null),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: scheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _EmptyVaultState extends StatelessWidget {
  final EntryCategory? category;
  const _EmptyVaultState({required this.category});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = category?.accent ?? scheme.primary;
    final icon = category?.icon ?? Icons.lock_outline_rounded;
    final title = category == null
        ? 'Your vault is empty'
        : 'No ${category!.label.toLowerCase()} items yet';
    final subtitle = category == null
        ? 'Tap + to add your first entry.'
        : 'Tap + to add a ${category!.label.toLowerCase()} item.';

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
              child: Icon(icon, color: accent, size: 38),
            ),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecuritySummaryCard extends StatelessWidget {
  final int total;
  final int weak;
  final int reused;
  final ColorScheme scheme;
  final _HealthFilter healthFilter;
  final ValueChanged<_HealthFilter> onFilter;

  const _SecuritySummaryCard({
    required this.total,
    required this.weak,
    required this.reused,
    required this.scheme,
    required this.healthFilter,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                color: scheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Vault health',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(
                label: 'Items',
                value: '$total',
                tone: scheme.onSurface,
                selected: healthFilter == _HealthFilter.all,
                onTap: () => onFilter(_HealthFilter.all),
              ),
              _divider(scheme),
              _Stat(
                label: 'Weak',
                value: '$weak',
                tone: const Color(0xFFEF4444),
                selected: healthFilter == _HealthFilter.weak,
                onTap: () => onFilter(_HealthFilter.weak),
              ),
              _divider(scheme),
              _Stat(
                label: 'Reused',
                value: '$reused',
                tone: AppTheme.healthReused(context),
                selected: healthFilter == _HealthFilter.reused,
                onTap: () => onFilter(_HealthFilter.reused),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Container(
    width: 1,
    height: 32,
    color: scheme.outlineVariant.withValues(alpha: 0.5),
  );
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _Stat({
    required this.label,
    required this.value,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? tone.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.36)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? accent;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final color = accent ?? scheme.primary;
    final displayColor = isDark ? color : _darken(color, 0.08);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: isDark ? 0.18 : 0.12)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: isDark ? 0.5 : 0.4)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? displayColor : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? displayColor : scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}

class _CategoryGroupHeader extends StatelessWidget {
  final EntryCategory category;
  final int count;

  const _CategoryGroupHeader({required this.category, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = category.accent;
    final displayAccent = isDark ? accent : _darken(accent, 0.1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Icon(category.icon, size: 16, color: displayAccent),
          const SizedBox(width: 8),
          Text(
            category.label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: displayAccent,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              color: accent.withValues(alpha: isDark ? 0.3 : 0.25),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  static Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}

class _SpeedDialScrim extends StatelessWidget {
  final Animation<double> animation;
  final bool open;
  final VoidCallback onClose;

  const _SpeedDialScrim({
    required this.animation,
    required this.open,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        if (t == 0) return const SizedBox.shrink();

        final blurSigma = 10.0 * t;

        return Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                ),
                child: ColoredBox(
                  color: (isDark ? Colors.black : scheme.surface).withValues(
                    alpha: (isDark ? 0.30 : 0.46) * t,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpeedDialFab extends StatelessWidget {
  final Animation<double> animation;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<EntryCategory> onCategory;

  const _SpeedDialFab({
    required this.animation,
    required this.open,
    required this.onToggle,
    required this.onCategory,
  });

  // TOTP is excluded from the Vault FAB speed-dial — Authenticator entries
  // are added from the Authenticator tab's own FAB. The vault speed-dial
  // is for password / card / note / wifi / identity items only.
  static final _categories = EntryCategory.values
      .where((c) => c != EntryCategory.totp)
      .toList(growable: false);
  static const _miniItemStep = 62.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SizedBox(
      width: 260,
      height: 56.0 + _categories.length * _miniItemStep + 12,
      child: Stack(
        alignment: Alignment.bottomRight,
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < _categories.length; i++)
            _buildMiniItem(
              context,
              index: i,
              category: _categories[i],
              scheme: scheme,
              reduceMotion: reduceMotion,
            ),
          _buildMainFab(scheme, reduceMotion),
        ],
      ),
    );
  }

  Widget _buildMainFab(ColorScheme scheme, bool reduceMotion) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final angle = animation.value * math.pi / 4;
        return FloatingActionButton(
          heroTag: '__speed_dial_main__',
          onPressed: onToggle,
          child: Transform.rotate(
            angle: reduceMotion ? 0 : angle,
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: reduceMotion ? 0 : 200),
              child: open
                  ? const Icon(Icons.close_rounded, key: ValueKey('close'))
                  : const Icon(Icons.add_rounded, key: ValueKey('add')),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniItem(
    BuildContext context, {
    required int index,
    required EntryCategory category,
    required ColorScheme scheme,
    required bool reduceMotion,
  }) {
    final count = _categories.length;
    final reverseIndex = count - 1 - index;
    // Per-item staggered interval. Pre-computed so we don't allocate a
    // CurvedAnimation on every rebuild (project rule: cache curves) —
    // the curve is applied manually inside the AnimatedBuilder.
    final begin = ((reverseIndex / count) * 0.4).clamp(0.0, 1.0);
    final end = (begin + 0.6).clamp(0.0, 1.0);
    final span = end - begin;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        if (reduceMotion) {
          if (!open) return const SizedBox.shrink();
          final yOffset = 56.0 + 12.0 + index * _miniItemStep;
          return Positioned(bottom: yOffset, right: 0, child: child!);
        }
        final raw = span <= 0
            ? (animation.value >= begin ? 1.0 : 0.0)
            : ((animation.value - begin) / span).clamp(0.0, 1.0);
        final t = Curves.easeOutCubic.transform(raw);
        if (t == 0) return const SizedBox.shrink();

        final yOffset = 56.0 + 12.0 + index * _miniItemStep;
        final scale = 0.4 + 0.6 * t;
        // Skip the offscreen Opacity layer once the item is fully opaque
        // — Opacity(1.0) is still cheaper than the < 1.0 case (no extra
        // compositing pass), but eliding it entirely is cheaper still.
        // The `t == 0` short-circuit above guarantees we don't render the
        // mini item at all while it's invisible. Project rule: prefer
        // *Transition widgets, but the manual `t` here drives both the
        // Positioned offset and the scale, so a per-frame check is the
        // smallest-diff option.
        final scaled = Transform.scale(
          scale: scale,
          alignment: Alignment.centerRight,
          child: child,
        );
        return Positioned(
          bottom: yOffset * t,
          right: 0,
          child: t >= 1.0 ? scaled : Opacity(opacity: t, child: scaled),
        );
      },
      child: _MiniDialItem(
        category: category,
        scheme: scheme,
        onTap: () => onCategory(category),
      ),
    );
  }
}

class _MiniDialItem extends StatelessWidget {
  final EntryCategory category;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _MiniDialItem({
    required this.category,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = category.accent;
    final isDark = scheme.brightness == Brightness.dark;
    final iconBg = isDark
        ? accent.withValues(alpha: 0.2)
        : Color.alphaBlend(
            accent.withValues(alpha: 0.12),
            scheme.surfaceContainerLowest,
          );
    final iconBorder = accent.withValues(alpha: isDark ? 0.36 : 0.28);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isDark
              ? scheme.surfaceContainer
              : scheme.surfaceContainerLowest.withValues(alpha: 0.94),
          elevation: isDark ? 2 : 4,
          shadowColor: Colors.black.withValues(alpha: isDark ? 0.26 : 0.14),
          borderRadius: BorderRadius.circular(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.outlineVariant.withValues(
                  alpha: isDark ? 0.28 : 0.6,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                category.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: iconBg,
            elevation: isDark ? 2 : 4,
            shadowColor: Colors.black.withValues(alpha: isDark ? 0.24 : 0.16),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: iconBorder),
                ),
                child: Icon(category.icon, color: accent, size: 22),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
