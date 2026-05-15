import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'authenticator_screen.dart';
import 'password_generator_screen.dart';
import 'settings_screen.dart';
import 'vault_home_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  int _previousIndex = 0;

  final Set<int> _visited = {};
  bool _vaultMountScheduled = false;

  // Material 3 recommends a simple fade between top-level destinations and
  // explicitly advises against lateral motion. Single controller drives both
  // entering and exiting tabs via ReverseAnimation, so the cross-fade is
  // perfectly time-aligned and the exit reuses the same curved value.
  late final AnimationController _tabController;
  late final CurvedAnimation _tabCurve;
  late final ReverseAnimation _tabCurveReversed;

  static const Animation<double> _kHidden = AlwaysStoppedAnimation<double>(0);
  static const Animation<double> _kVisible = AlwaysStoppedAnimation<double>(1);

  @override
  void initState() {
    super.initState();
    _tabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      value: 1,
    );
    _tabCurve = CurvedAnimation(
      parent: _tabController,
      curve: Curves.easeOutCubic,
    );
    _tabCurveReversed = ReverseAnimation(_tabCurve);
    _tabController.addStatusListener(_onTabAnimationStatus);
  }

  void _onTabAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        mounted &&
        _previousIndex != _index) {
      // Once the cross-fade settles, mark the previous tab fully hidden so its
      // FadeTransition picks up the cheap zero-opacity path on the next frame.
      setState(() => _previousIndex = _index);
    }
  }

  /// Heavy tab content mounts only after the route's forward animation
  /// completes — otherwise the first GPU + layout pass competes with the
  /// transition and reads as jank. Subsequent opens reuse layers.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vaultMountScheduled) return;
    _vaultMountScheduled = true;

    void mountVaultTab() {
      if (!mounted || _visited.contains(0)) return;
      setState(() => _visited.add(0));
    }

    final route = ModalRoute.of(context);
    final anim = route?.animation;
    if (anim == null || anim.status == AnimationStatus.completed) {
      mountVaultTab();
      return;
    }

    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        anim.removeStatusListener(listener);
        mountVaultTab();
      }
    }

    anim.addStatusListener(listener);
  }

  @override
  void dispose() {
    _tabController.removeStatusListener(_onTabAnimationStatus);
    _tabCurve.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Widget> _tabs() {
    return [
      if (_visited.contains(0))
        const VaultHomeScreen()
      else
        const SizedBox.shrink(),
      if (_visited.contains(1))
        const AuthenticatorScreen()
      else
        const SizedBox.shrink(),
      if (_visited.contains(2))
        const PasswordGeneratorScreen()
      else
        const SizedBox.shrink(),
      if (_visited.contains(3))
        const SettingsScreen()
      else
        const SizedBox.shrink(),
    ];
  }

  void _selectTab(int i) {
    if (i == _index) return;
    setState(() {
      _previousIndex = _index;
      _index = i;
      _visited.add(i);
    });
    _tabController.forward(from: 0);
  }

  Animation<double> _opacityFor(int i) {
    if (_previousIndex == _index) {
      return i == _index ? _kVisible : _kHidden;
    }
    if (i == _index) return _tabCurve;
    if (i == _previousIndex) return _tabCurveReversed;
    return _kHidden;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final body = reduceMotion
        ? IndexedStack(index: _index, children: tabs)
        : Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < tabs.length; i++)
                _TabPane(
                  active: i == _index,
                  opacity: _opacityFor(i),
                  child: tabs[i],
                ),
            ],
          );

    return Scaffold(
      body: body,
      bottomNavigationBar: _PolishedNavBar(
        selectedIndex: _index,
        onSelected: _selectTab,
        destinations: const [
          _NavDestination(
            label: 'Vault',
            icon: Icons.lock_outline_rounded,
            selectedIcon: Icons.lock_rounded,
          ),
          _NavDestination(
            label: 'Auth',
            icon: Icons.shield_moon_outlined,
            selectedIcon: Icons.shield_moon,
          ),
          _NavDestination(
            label: 'Generator',
            icon: Icons.shuffle_rounded,
            selectedIcon: Icons.auto_fix_high_rounded,
          ),
          _NavDestination(
            label: 'Settings',
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
          ),
        ],
      ),
    );
  }
}

class _TabPane extends StatelessWidget {
  final bool active;
  final Animation<double> opacity;
  final Widget child;

  const _TabPane({
    required this.active,
    required this.opacity,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active,
        child: TickerMode(
          enabled: active,
          child: FadeTransition(
            opacity: opacity,
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    );
  }
}

@immutable
class _NavDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

/// Custom bottom navigation bar with a top-edge accent bar that slides
/// between destinations. Replaces the Material 3 pill indicator (which
/// reads as a chunky highlight against the cool light theme) with a
/// thin 3dp brand-coloured bar at the top edge of the active cell —
/// cleaner, more iOS-style, still adapts to N tabs.
/// Bottom navigation bar — no indicator bar of any kind. Selection is
/// signalled purely by the icon + label color/weight transition that
/// `_NavItem` already animates. Cleaner than a sliding underline, gets
/// out of the way of the labels.
class _PolishedNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<_NavDestination> destinations;

  const _PolishedNavBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  static const double _barHeight = 72;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainer,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _NavItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  // Tracks the press state so we can drive a tiny scale-down on tap.
  // Replaces the InkResponse's circular splash highlight (which testers
  // disliked) with a pressed-down feel that matches the rest of the app.
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Selected uses scheme.primary for both icon and label so the active
    // tab carries a clear color signal beyond the pill background.
    final iconColor = widget.selected
        ? scheme.primary
        : scheme.onSurfaceVariant;
    final labelColor = widget.selected
        ? scheme.primary
        : scheme.onSurfaceVariant;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      selected: widget.selected,
      button: true,
      label: widget.destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.92 : 1.0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon: cross-fade between outline and filled variants on
              // select, with a tiny scale bump so the change reads as a
              // press rather than a hard swap.
              SizedBox(
                height: 28,
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1.0)
                            .animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Icon(
                    widget.selected
                        ? widget.destination.selectedIcon
                        : widget.destination.icon,
                    key: ValueKey(widget.selected),
                    size: 24,
                    color: iconColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Label weight + color animate too — gives the selection a
              // typographic emphasis on top of the pill highlight.
              AnimatedDefaultTextStyle(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      widget.selected ? FontWeight.w700 : FontWeight.w500,
                  color: labelColor,
                  letterSpacing: 0.2,
                ),
                child: Text(widget.destination.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
