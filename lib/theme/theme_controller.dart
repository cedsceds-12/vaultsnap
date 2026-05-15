import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// App-wide controller for [ThemeMode].
///
/// To make theme switching feel instant on high-refresh-rate screens we
/// avoid Flutter's built-in [AnimatedTheme] lerp (which interpolates 30+
/// theme properties per frame). Instead, on a mode change we synchronously
/// snapshot the current frame, swap the mode (the new theme is applied in
/// a single frame), and then crossfade the snapshot away while the new
/// theme is already on screen underneath. The GPU just composites a single
/// texture, so the animation stays buttery smooth even on slow devices.
class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initial = ThemeMode.system}) : _mode = initial;

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  /// Set by the root app widget so the controller can capture a snapshot
  /// of the rendered frame before mode changes.
  GlobalKey? captureKey;

  ui.Image? _snapshot;
  ui.Image? get snapshot => _snapshot;

  /// Pixel ratio used when capturing the snapshot. Set by the root widget
  /// from `MediaQuery.devicePixelRatioOf(context)`. Clamped at capture
  /// time to keep the snapshot texture small enough that the GPU upload
  /// itself doesn't drop a frame.
  double pixelRatio = 1.0;

  /// Maximum pixelRatio used when capturing the snapshot. 2.0 is enough
  /// to look crisp during a sub-300ms fade — going higher (3.0 on modern
  /// phones) creates a 4-9× larger texture for no perceivable benefit.
  static const double _maxCapturePixelRatio = 2.0;

  void setMode(ThemeMode value) {
    if (_mode == value) return;

    final boundary = captureKey?.currentContext?.findRenderObject();
    if (boundary is RenderRepaintBoundary && boundary.attached) {
      try {
        _snapshot?.dispose();
        final ratio = pixelRatio < _maxCapturePixelRatio
            ? pixelRatio
            : _maxCapturePixelRatio;
        // toImageSync (Flutter 3.7+) avoids an async gap so the captured
        // frame is guaranteed to show the OLD theme.
        _snapshot = boundary.toImageSync(pixelRatio: ratio);
      } catch (_) {
        _snapshot = null;
      }
    }

    _mode = value;
    notifyListeners();
  }

  void clearSnapshot() {
    if (_snapshot == null) return;
    _snapshot?.dispose();
    _snapshot = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _snapshot?.dispose();
    _snapshot = null;
    super.dispose();
  }
}

/// Inherited scope so any descendant can read & update the theme controller.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope not found in widget tree');
    return scope!.notifier!;
  }
}
