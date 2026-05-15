import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/asymmetric/api.dart';

import 'rsa_oaep_sha256_pkcs1.dart';

/// Pushes VMK to the Android Autofill layer under RSA-OAEP (never plaintext
/// on the MethodChannel). Cleared when [clear] runs on vault lock.
class AutofillSessionService {
  static const _channel = MethodChannel('com.vaultsnap.app/autofill');

  /// Bumped on each [clear] and at the start of each [syncAfterUnlock] so a
  /// slow sync cannot call [autofillStartSession] after the user locked.
  static int _sessionGeneration = 0;

  /// True when the most recent [syncAfterUnlock] caused a programmatic
  /// `moveTaskToBack` (the autofill flow minimizes VaultSnap so the user
  /// returns to the calling app). The lock-scope checks and consumes this
  /// to skip the *next* auto-lock-on-background event — otherwise an
  /// `autoLockMinutes == 0` user would re-lock the vault before the
  /// autofill auth activity can deliver the FillResponse.
  static bool _suppressNextBackgroundLock = false;
  static DateTime? _suppressArmedAt;

  /// Returns true if a recent autofill flow armed the suppression and the
  /// arming hasn't expired (5s grace). Resets the flag when consumed.
  static bool consumeBackgroundLockSuppression() {
    if (!_suppressNextBackgroundLock) return false;
    final armed = _suppressArmedAt;
    _suppressNextBackgroundLock = false;
    _suppressArmedAt = null;
    if (armed == null) return false;
    return DateTime.now().difference(armed) < const Duration(seconds: 5);
  }

  static Future<void> syncAfterUnlock({required Uint8List vmk}) async {
    if (!Platform.isAndroid) return;
    final gen = ++_sessionGeneration;
    try {
      developer.log('syncAfterUnlock: get public key', name: 'VaultSnapAutofill');
      final pem = await _channel.invokeMethod<String>('autofillGetPublicKeyPem');
      if (pem == null || pem.isEmpty) {
        developer.log('syncAfterUnlock: empty pem — aborting',
            name: 'VaultSnapAutofill');
        return;
      }
      if (gen != _sessionGeneration) return;
      final parser = enc.RSAKeyParser();
      final pub = parser.parse(pem) as RSAPublicKey;
      final wrapped =
          rsaOaepSha256Encrypt(pub, Uint8List.fromList(vmk));
      final dir = await getApplicationDocumentsDirectory();
      if (gen != _sessionGeneration) return;
      final dbPath = p.join(dir.path, 'vault_entries.db');
      developer.log('syncAfterUnlock: invoking autofillStartSession dbPath=$dbPath',
          name: 'VaultSnapAutofill');
      // Pre-arm the suppression flag *before* the native invoke. The
      // native handler calls `moveTaskToBack(true)` synchronously right
      // after `result.success(...)`, so the lifecycle.paused event can
      // race ahead of Dart's await continuation. Arming up-front means
      // VaultLockScope will *always* see the flag when it checks. We
      // clear the flag again if the native side reports it didn't
      // minimize (e.g. autofill auth wasn't requested).
      _suppressNextBackgroundLock = true;
      _suppressArmedAt = DateTime.now();
      bool? didMinimize;
      try {
        didMinimize = await _channel.invokeMethod<bool>(
          'autofillStartSession',
          {'wrappedVmk': wrapped, 'vaultDbPath': dbPath},
        );
      } catch (_) {
        // Native call failed — never minimized — clear the speculative arm.
        _suppressNextBackgroundLock = false;
        _suppressArmedAt = null;
        rethrow;
      }
      if (didMinimize != true) {
        // No minimize happened — drop the speculative arm so a real
        // background event (user actually leaves the app) can lock.
        _suppressNextBackgroundLock = false;
        _suppressArmedAt = null;
      } else {
        developer.log('syncAfterUnlock: armed background-lock suppression',
            name: 'VaultSnapAutofill');
      }
      developer.log('syncAfterUnlock: session started minimize=$didMinimize',
          name: 'VaultSnapAutofill');
    } on MissingPluginException catch (e) {
      developer.log('syncAfterUnlock: MissingPluginException ${e.message}',
          name: 'VaultSnapAutofill');
    } on PlatformException catch (e) {
      developer.log(
          'syncAfterUnlock: PlatformException code=${e.code} msg=${e.message}',
          name: 'VaultSnapAutofill');
    } catch (e, st) {
      developer.log('syncAfterUnlock: unexpected $e',
          name: 'VaultSnapAutofill', stackTrace: st);
    }
  }

  static Future<void> clear() async {
    _sessionGeneration++;
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('autofillClearSession');
    } on MissingPluginException {
      // Widget tests / non-Android embeddings.
    }
  }

  /// Launchable apps for linking entries (names + package IDs). Android only.
  static Future<List<LaunchableApp>> queryLaunchableApps() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw =
          await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'queryLaunchableApps',
      );
      if (raw == null) return const [];
      return raw.map((m) {
        final iconRaw = m['iconPng'];
        Uint8List? iconPng;
        if (iconRaw is Uint8List) {
          iconPng = iconRaw;
        } else if (iconRaw is List) {
          iconPng = Uint8List.fromList(List<int>.from(iconRaw));
        }
        return LaunchableApp(
          packageName: m['packageName']! as String,
          label: m['label']! as String,
          iconPng: iconPng,
        );
      }).toList();
    } on MissingPluginException {
      return const [];
    }
  }

  static Future<void> openAndroidAutofillSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openAndroidAutofillSettings');
    } on MissingPluginException {
      // Tests.
    }
  }

  /// Number of pending save-requests captured while the vault was locked.
  /// Used by the home screen to decide whether to surface a "save these
  /// new credentials?" banner after unlock.
  static Future<int> pendingSaveCount() async {
    if (!Platform.isAndroid) return 0;
    try {
      final n = await _channel.invokeMethod<int>('autofillPendingSaveCount');
      return n ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Drains the pending-save queue. Returns the captured payloads (cleartext;
  /// the on-disk form is Keystore-encrypted). Callers must immediately use
  /// the payloads to add new entries — they are not returned to the queue.
  static Future<List<PendingSavePayload>> consumePendingSaves() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel
          .invokeListMethod<Map<dynamic, dynamic>>('autofillConsumePendingSaves');
      if (raw == null) return const [];
      return raw
          .map(
            (m) => PendingSavePayload(
              username: (m['username'] as String? ?? '').isEmpty
                  ? null
                  : m['username'] as String,
              password: m['password']! as String,
              callerPackage: (m['callerPackage'] as String? ?? '').isEmpty
                  ? null
                  : m['callerPackage'] as String,
              webHost: (m['webHost'] as String? ?? '').isEmpty
                  ? null
                  : m['webHost'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                (m['createdAtMs'] as num).toInt(),
                isUtc: true,
              ),
            ),
          )
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}

/// One pending save-request consumed from the Android queue.
class PendingSavePayload {
  final String? username;
  final String password;
  final String? callerPackage;
  final String? webHost;
  final DateTime createdAt;

  const PendingSavePayload({
    required this.username,
    required this.password,
    required this.callerPackage,
    required this.webHost,
    required this.createdAt,
  });
}

class LaunchableApp {
  final String packageName;
  final String label;
  final Uint8List? iconPng;

  const LaunchableApp({
    required this.packageName,
    required this.label,
    this.iconPng,
  });
}
