import 'package:flutter/material.dart';

import 'theme_controller.dart';

/// Wraps app content in a [RepaintBoundary] that the [ThemeController]
/// snapshots before each theme change, and overlays the captured frame
/// while it crossfades away on top of the (already-applied) new theme.
///
/// This is the same trick Telegram & Discord use: the actual theme swap
/// is **instant** (single frame, no per-frame lerp work) but the user sees
/// a smooth crossfade because a snapshot of the previous frame fades out
/// over the new one.
class ThemeCrossfade extends StatefulWidget {
  final ThemeController controller;
  final GlobalKey captureKey;
  final Widget child;

  /// How long the snapshot takes to fade out. 240ms with easeOutCubic is
  /// the Telegram/Discord-style sweet spot — the new theme appears
  /// immediately while the old frame gracefully dissolves on top.
  final Duration duration;

  const ThemeCrossfade({
    super.key,
    required this.controller,
    required this.captureKey,
    required this.child,
    this.duration = const Duration(milliseconds: 240),
  });

  @override
  State<ThemeCrossfade> createState() => _ThemeCrossfadeState();
}

class _ThemeCrossfadeState extends State<ThemeCrossfade>
    with SingleTickerProviderStateMixin {
  // Initialized eagerly in initState — `late final` here would defer the
  // ticker creation until first access, and disposing the controller
  // before that triggers an inherited-widget lookup outside the build
  // phase (Ticker needs TickerMode), which crashes.
  late final AnimationController _anim;

  // Eased fade from 1 → 0. easeOutCubic starts dropping immediately so
  // the new theme is visible within the first ~50ms — the same "snappy
  // start, soft settle" feel Telegram and iOS use for theme/mode swaps.
  late final Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: widget.duration);
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _anim.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (widget.controller.snapshot != null) {
      _anim.forward(from: 0).whenCompleteOrCancel(() {
        if (mounted) widget.controller.clearSnapshot();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.controller.snapshot;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The boundary is what gets captured. Its child is the live app
        // already showing the NEW theme by the time we render the snapshot.
        RepaintBoundary(key: widget.captureKey, child: widget.child),
        if (snap != null)
          Positioned.fill(
            child: IgnorePointer(
              // Isolate the fade in its own layer so the underlying app
              // tree (which just rebuilt with the new theme) doesn't get
              // re-rasterized every frame of the animation.
              child: RepaintBoundary(
                child: FadeTransition(
                  opacity: _fadeOut,
                  // RawImage with BoxFit.fill paints the captured texture
                  // at the same logical size — much cheaper than rebuilding
                  // the old theme tree for the duration of the fade.
                  child: RawImage(image: snap, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
