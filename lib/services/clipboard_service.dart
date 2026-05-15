import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Manages clipboard copy + timed auto-clear + Android 13+ sensitive
/// content masking.
///
/// Call [copyAndScheduleClear] instead of raw [Clipboard.setData].
/// When [enabled] is true, the clipboard is wiped after [clearDelay].
///
/// **Sensitive content (Android 13+):** every copy routes through a
/// MethodChannel that sets the `EXTRA_IS_SENSITIVE` flag on the
/// `ClipDescription`. The system clipboard preview chip / quick-paste
/// UI / notification toast then masks the value as "••••••" — apps
/// reading the clipboard explicitly still get the real plaintext.
/// Same flag Google Authenticator and 1Password use for copied codes.
/// On iOS / non-Android the call falls back to plain
/// `Clipboard.setData` (no equivalent OS-level masking exists).
class ClipboardService {
  static const Duration clearDelay = Duration(seconds: 30);
  static const _channel = MethodChannel('com.vaultsnap.app/window');

  bool enabled;
  Timer? _timer;

  ClipboardService({this.enabled = true});

  Future<void> copyAndScheduleClear(String text) async {
    await _writeSensitive(text);
    HapticFeedback.lightImpact();
    _timer?.cancel();
    if (enabled) {
      _timer = Timer(clearDelay, _clear);
    }
  }

  Future<void> _writeSensitive(String text) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>(
          'copyToClipboardSensitive',
          {'text': text},
        );
        return;
      } on MissingPluginException {
        // Tests / non-embedded contexts — fall through to the
        // plain Flutter API.
      } on PlatformException {
        // Native handler errored — fall back too rather than fail
        // the entire copy.
      }
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  void _clear() {
    // Clearing is just an empty string — no need to mark sensitive,
    // and we want it to go through the standard path so this works
    // on every platform without depending on the native channel.
    Clipboard.setData(const ClipboardData(text: ''));
  }

  void dispose() {
    _timer?.cancel();
  }
}
