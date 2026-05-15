import 'dart:async';

import 'package:flutter/material.dart';

/// Polished toast helper. Bypasses `ScaffoldMessenger.showSnackBar`
/// entirely and renders into the rootmost `Overlay` so we own the
/// forward AND reverse animations. The framework SnackBar approach
/// only animates the entrance — when the bar dismisses (timeout or
/// swipe) it slides off without our scale/fade exit, which makes the
/// dismiss read as an abrupt cut.
///
/// Three flavors:
/// - [show]        — neutral surface tone (default).
/// - [showError]   — error-container tone with an alert icon.
/// - [showSuccess] — primary tone with a check icon.
///
/// Only one toast is visible at a time. Calling any `show*` while a
/// previous toast is still on screen runs that one's reverse animation
/// first, then plays the new one's entrance — no instant snap-replace.
class VaultToast {
  VaultToast._();

  static _ToastEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onActionPressed,
    String? actionLabel,
  }) {
    _show(
      context,
      message: message,
      icon: icon,
      tone: _ToastTone.neutral,
      duration: duration,
      actionLabel: actionLabel,
      onActionPressed: onActionPressed,
    );
  }

  static void showError(
    BuildContext context,
    String message, {
    IconData icon = Icons.error_outline_rounded,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onActionPressed,
    String? actionLabel,
  }) {
    _show(
      context,
      message: message,
      icon: icon,
      tone: _ToastTone.error,
      duration: duration,
      actionLabel: actionLabel,
      onActionPressed: onActionPressed,
    );
  }

  static void showSuccess(
    BuildContext context,
    String message, {
    IconData icon = Icons.check_circle_outline_rounded,
    Duration duration = const Duration(seconds: 2),
    VoidCallback? onActionPressed,
    String? actionLabel,
  }) {
    _show(
      context,
      message: message,
      icon: icon,
      tone: _ToastTone.success,
      duration: duration,
      actionLabel: actionLabel,
      onActionPressed: onActionPressed,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required _ToastTone tone,
    required Duration duration,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // Replace any in-flight toast with a clean reverse animation first.
    _current?.dismiss();

    final entry = _ToastEntry(
      message: message,
      icon: icon,
      tone: tone,
      duration: duration,
      actionLabel: actionLabel,
      onActionPressed: onActionPressed,
    );
    _current = entry;
    entry.attach(overlay);
  }
}

enum _ToastTone { neutral, error, success }

/// Owns the OverlayEntry + timer + a one-shot lifecycle for a single
/// toast. The actual animation lives in [_ToastBody]'s state, which
/// signals back through the [_dismissTrigger] notifier when it's safe
/// to remove the overlay entry (i.e. after the reverse animation has
/// finished).
class _ToastEntry {
  final String message;
  final IconData? icon;
  final _ToastTone tone;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  OverlayEntry? _overlay;
  Timer? _autoDismissTimer;
  final ValueNotifier<bool> _dismissTrigger = ValueNotifier(false);
  bool _disposed = false;

  _ToastEntry({
    required this.message,
    required this.tone,
    required this.duration,
    this.icon,
    this.actionLabel,
    this.onActionPressed,
  });

  void attach(OverlayState overlay) {
    final entry = OverlayEntry(
      builder: (ctx) => _ToastHost(
        message: message,
        icon: icon,
        tone: tone,
        actionLabel: actionLabel,
        onActionPressed: () {
          onActionPressed?.call();
          dismiss();
        },
        dismissTrigger: _dismissTrigger,
        onSwipeDismiss: dismiss,
        onAnimationComplete: _removeOverlay,
      ),
    );
    _overlay = entry;
    overlay.insert(entry);
    _autoDismissTimer = Timer(duration, dismiss);
  }

  void dismiss() {
    if (_disposed) return;
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _dismissTrigger.value = true;
  }

  void _removeOverlay() {
    if (_disposed) return;
    _disposed = true;
    _overlay?.remove();
    _overlay = null;
    _dismissTrigger.dispose();
    if (VaultToast._current == this) {
      VaultToast._current = null;
    }
  }
}

/// Positions the toast above any bottom navigation / safe-area inset
/// and forwards lifecycle signals to the animated body.
class _ToastHost extends StatelessWidget {
  final String message;
  final IconData? icon;
  final _ToastTone tone;
  final String? actionLabel;
  final VoidCallback? onActionPressed;
  final ValueNotifier<bool> dismissTrigger;
  final VoidCallback onSwipeDismiss;
  final VoidCallback onAnimationComplete;

  const _ToastHost({
    required this.message,
    required this.tone,
    required this.dismissTrigger,
    required this.onSwipeDismiss,
    required this.onAnimationComplete,
    this.icon,
    this.actionLabel,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    return Positioned(
      // Sit above the system gesture / nav bar by default; bottom-nav
      // shells with their own bottom inset (~80px) still leave room for
      // the toast because we use viewPadding (system) only here.
      bottom: viewPadding.bottom + 16,
      left: 12,
      right: 12,
      child: Material(
        type: MaterialType.transparency,
        child: _ToastBody(
          message: message,
          icon: icon,
          tone: tone,
          actionLabel: actionLabel,
          onActionPressed: onActionPressed,
          dismissTrigger: dismissTrigger,
          onSwipeDismiss: onSwipeDismiss,
          onAnimationComplete: onAnimationComplete,
        ),
      ),
    );
  }
}

class _ToastBody extends StatefulWidget {
  final String message;
  final IconData? icon;
  final _ToastTone tone;
  final String? actionLabel;
  final VoidCallback? onActionPressed;
  final ValueNotifier<bool> dismissTrigger;
  final VoidCallback onSwipeDismiss;
  final VoidCallback onAnimationComplete;

  const _ToastBody({
    required this.message,
    required this.tone,
    required this.dismissTrigger,
    required this.onSwipeDismiss,
    required this.onAnimationComplete,
    this.icon,
    this.actionLabel,
    this.onActionPressed,
  });

  @override
  State<_ToastBody> createState() => _ToastBodyState();
}

class _ToastBodyState extends State<_ToastBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    // Forward (entrance): 360ms easeOutBack — slight overshoot so the
    // toast settles deliberately. Reverse (exit): 240ms easeInCubic —
    // a touch quicker than the entrance so the dismiss feels light
    // rather than dragged out. AnimationController.reverseDuration is
    // honoured automatically when we call .reverse().
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _controller.forward();
    widget.dismissTrigger.addListener(_onDismissRequest);
  }

  void _onDismissRequest() {
    if (_dismissing || !mounted) return;
    if (!widget.dismissTrigger.value) return;
    _dismissing = true;
    _controller.reverse().whenComplete(() {
      if (!mounted) return;
      widget.onAnimationComplete();
    });
  }

  @override
  void dispose() {
    widget.dismissTrigger.removeListener(_onDismissRequest);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    final (Color bg, Color fg, Color border) = switch (widget.tone) {
      _ToastTone.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurface,
          scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.5),
        ),
      _ToastTone.error => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          scheme.error.withValues(alpha: isDark ? 0.5 : 0.4),
        ),
      _ToastTone.success => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          scheme.primary.withValues(alpha: isDark ? 0.45 : 0.35),
        ),
    };

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          alignment: Alignment.bottomCenter,
          scale: _scale,
          child: Dismissible(
            key: const ValueKey('vault_toast'),
            direction: DismissDirection.horizontal,
            onDismissed: (_) => widget.onSwipeDismiss(),
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: fg, size: 22),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      widget.message,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  if (widget.actionLabel != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: widget.onActionPressed,
                      style: TextButton.styleFrom(
                        foregroundColor: fg,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        widget.actionLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
