import 'package:flutter/material.dart';

/// Tab-name page header used across the main tabs (Vault, Settings, etc).
///
/// Uses `SliverAppBar` + `FlexibleSpaceBar` so the title scales smoothly
/// between a large expanded form (~32sp) and a compact collapsed form
/// (~20sp) as the user scrolls — feels closer to iOS large titles than
/// Material's default `SliverAppBar.large` (which tops out around 28sp).
class LargePageHeader extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  const LargePageHeader({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Beta testers reported the default 24sp search/sort/lock icons felt
    // invisible against the title. We bump only the icons (not the title)
    // and give the toolbar a touch more vertical space so the larger icons
    // have breathing room.
    final sizedActions = actions == null
        ? null
        : [
            for (final a in actions!)
              IconTheme.merge(
                data: const IconThemeData(size: 28),
                child: a,
              ),
          ];
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 132,
      collapsedHeight: 60,
      toolbarHeight: 60,
      leading: leading,
      actions: sizedActions,
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      flexibleSpace: FlexibleSpaceBar(
        // Aligns the expanded title flush-left with the body content
        // (which uses a 20px horizontal padding).
        titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 16),
        // Collapsed style: ~20sp. The expanded scale of 1.6 brings it to
        // ~32sp — large enough to read as a real page title without
        // dominating the screen.
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        expandedTitleScale: 1.6,
      ),
    );
  }
}
