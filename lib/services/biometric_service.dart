import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Biometric enrollment + retrieval for VaultSnap.
///
/// Flow:
///   1. [isAvailable] — device has enrolled biometrics.
///   2. [enroll] — authenticate, then persist a random AES key in keystore.
///   3. [authenticate] + [retrieveKey] — on each lock-screen unlock.
///   4. [delete] — remove the stored key (disable biometrics).
///
/// The "biometric key" is a random 256-bit key that wraps the VMK via
/// AES-GCM. It lives in Android Keystore / iOS Keychain behind biometric
/// gating (`flutter_secure_storage`). The VMK itself never touches the
/// keystore.
class BiometricService {
  static const _keyId = 'vaultsnap_biometric_key';

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  BiometricService({
    LocalAuthentication? auth,
    FlutterSecureStorage? storage,
  })  : _auth = auth ?? LocalAuthentication(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  /// `true` when the device has at least one enrolled biometric AND the
  /// hardware is present.
  Future<bool> isAvailable() async {
    final canCheck = await _auth.canCheckBiometrics;
    if (!canCheck) return false;
    final available = await _auth.getAvailableBiometrics();
    return available.isNotEmpty;
  }

  /// Prompt the user for biometric authentication.
  /// Returns `true` on success, `false` on cancel / failure.
  Future<bool> authenticate({String reason = 'Unlock VaultSnap'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Store [keyBytes] (the biometric wrap key) behind biometric gating.
  Future<void> storeKey(Uint8List keyBytes) async {
    final encoded = keyBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _keyId, value: encoded);
  }

  /// Retrieve the stored biometric key. Returns `null` if no key exists.
  Future<Uint8List?> retrieveKey() async {
    final encoded = await _storage.read(key: _keyId);
    if (encoded == null || encoded.isEmpty) return null;
    final bytes = Uint8List(encoded.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(encoded.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Whether a biometric key is currently stored.
  Future<bool> hasKey() async {
    final val = await _storage.read(key: _keyId);
    return val != null && val.isNotEmpty;
  }

  /// Remove the biometric key from secure storage.
  Future<void> deleteKey() async {
    await _storage.delete(key: _keyId);
  }
}
