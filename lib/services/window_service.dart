import 'dart:io';

import 'package:flutter/services.dart';

/// Result of a Storage Access Framework file pick.
class PickedFile {
  final Uint8List bytes;
  final String name;
  const PickedFile({required this.bytes, required this.name});
}

/// Bridges the small set of Android-only window/SAF features we use.
///
/// Methods are no-ops on non-Android platforms (or in tests where the
/// platform channel is not registered).
class WindowService {
  static const _channel = MethodChannel('com.vaultsnap.app/window');

  bool _secure = false;
  bool get isSecure => _secure;

  Future<void> setSecure(bool secure) async {
    if (!Platform.isAndroid) return;
    if (_secure == secure) return;
    try {
      await _channel.invokeMethod('setSecure', {'secure': secure});
      _secure = secure;
    } on MissingPluginException {
      // Running in tests or on a platform without the channel.
    }
  }

  Future<void> setThemeMode(String mode) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setThemeMode', {'mode': mode});
    } on MissingPluginException {
      // Running in tests or on a platform without the channel.
    }
  }

  /// Opens the system file picker (ACTION_CREATE_DOCUMENT) so the user
  /// can choose where to save [bytes]. Returns the user-visible display
  /// name on success, `null` if the user cancelled.
  Future<String?> saveBytes({
    required Uint8List bytes,
    required String suggestedName,
    String mime = 'application/octet-stream',
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _channel.invokeMethod<String>('saveBytesToUri', {
        'bytes': bytes,
        'name': suggestedName,
        'mime': mime,
      });
      return res;
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens the system file picker (ACTION_OPEN_DOCUMENT) and returns
  /// the picked file's bytes + display name, or `null` if the user
  /// cancelled.
  Future<PickedFile?> pickFile({String mime = '*/*'}) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _channel
          .invokeMapMethod<String, Object?>('pickBytesFromUri', {'mime': mime});
      if (res == null) return null;
      final bytes = res['bytes'] as Uint8List?;
      final name = res['name'] as String? ?? '';
      if (bytes == null) return null;
      return PickedFile(bytes: bytes, name: name);
    } on MissingPluginException {
      return null;
    }
  }
}
