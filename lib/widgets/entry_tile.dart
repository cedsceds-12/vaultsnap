import 'package:flutter/material.dart';

import '../models/password_entry.dart';
import '../models/vault_entry.dart';
import '../theme/app_theme.dart';

class EntryTile extends StatelessWidget {
  final VaultEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether the parent screen is currently in multi-select mode. When
  /// true, the chevron is replaced by a checkbox indicator and tapping
  /// the tile toggles selection (the parent maps `onTap` accordingly).
  final bool selectionMode;

  /// Whether THIS tile is among the currently-selected entries.
  final bool selected;

  const EntryTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = entry.category.accent;
    final accentBg = accent.withValues(alpha: isDark ? 0.16 : 0.12);
    final accentBorder = accent.withValues(alpha: isDark ? 0.32 : 0.24);

    final bg = selected
        ? scheme.primary.withValues(alpha: isDark ? 0.18 : 0.12)
        : scheme.surfaceContainer;
    final border = selected
        ? scheme.primary.withValues(alpha: isDark ? 0.5 : 0.36)
        : Colors.transparent;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accentBorder),
                ),
                alignment: Alignment.center,
                child: Icon(entry.category.icon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.username ?? entry.url ?? entry.category.label,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!selectionMode && entry.reused)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Tooltip(
                    message: 'Reused password',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppTheme.healthReused(context),
                    ),
                  ),
                ),
              if (!selectionMode) ...[
                _StrengthDot(strength: entry.strength),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ] else
                _SelectionMark(selected: selected, scheme: scheme),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  final bool selected;
  final ColorScheme scheme;
  const _SelectionMark({required this.selected, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final size = 24.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            selected ? scheme.primary : scheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant,
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

class _StrengthDot extends StatelessWidget {
  final PasswordStrength strength;
  const _StrengthDot({required this.strength});

  // Cached static colors so list scrolls never re-allocate.
  // Weak + fair both use red on the dot so it never reads like the yellow reused chip.
  static const _weakOrFair = Color(0xFFEF4444);
  static const _good = Color(0xFF10B981);
  static const _strong = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    final color = switch (strength) {
      PasswordStrength.weak => _weakOrFair,
      PasswordStrength.fair => _weakOrFair,
      PasswordStrength.good => _good,
      PasswordStrength.strong => _strong,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }
}
