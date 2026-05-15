import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vault_meta.dart';
import '../services/biometric_service.dart';
import '../services/crypto_service.dart';
import '../services/vault_storage.dart';
import 'vault_providers.dart';

/// Orchestrates first-time vault creation (setup wizard) and master
/// password verification (unlock screen).
///
/// All crypto runs through [CryptoService]; nothing here touches raw
/// primitives directly. The provider is intentionally NOT a Notifier —
/// it exposes simple async methods that any screen can call.
class VaultSetupService {
  final CryptoService _crypto;
  final VaultStorage _storage;
  final BiometricService _biometric;

  const VaultSetupService(this._crypto, this._storage, this._biometric);

  /// Create a brand-new vault from the user's chosen master password
  /// and recovery question + answer. Returns the [VaultMeta] that was
  /// persisted to disk.
  ///
  /// Flow:
  ///   1. Generate a random 256-bit VMK.
  ///   2. Generate salts for the password and recovery contexts.
  ///   3. Derive AES keys from both inputs via Argon2id.
  ///   4. Wrap the VMK under each derived key (AES-GCM-256).
  ///   5. Persist the [VaultMeta] atomically to disk.
  Future<VaultMeta> createVault({
    required String masterPassword,
    required String recoveryQuestion,
    required String recoveryAnswer,
  }) async {
    final kdf = KdfParams.defaults;
    final vmk = _crypto.generateVmk();

    final passwordSalt = _crypto.generateSalt();
    final recoverySalt = _crypto.generateSalt();

    final passwordKey = await _crypto.deriveKey(
      secret: masterPassword,
      salt: passwordSalt,
      params: kdf,
    );

    final normalizedAnswer = _crypto.normalizeAnswer(recoveryAnswer);
    final recoveryKey = await _crypto.deriveKey(
      secret: normalizedAnswer,
      salt: recoverySalt,
      params: kdf,
    );

    final wrappedVmkPassword = await _crypto.wrap(
      plaintext: vmk,
      key: passwordKey,
    );

    final wrappedVmkRecovery = await _crypto.wrap(
      plaintext: vmk,
      key: recoveryKey,
    );

    final meta = VaultMeta(
      version: VaultMeta.currentVersion,
      kdf: kdf,
      passwordSalt: passwordSalt,
      wrappedVmkPassword: wrappedVmkPassword,
      wrappedVmkRecovery: wrappedVmkRecovery,
      wrappedVmkBiometric: null,
      recovery: RecoveryMeta(
        question: recoveryQuestion,
        salt: recoverySalt,
      ),
      createdAt: DateTime.now().toUtc(),
      lastUnlockAt: null,
    );

    await _storage.save(meta);
    return meta;
  }

  /// Verify the master password against the vault. Returns the
  /// decrypted VMK bytes on success, `null` on wrong password.
  ///
  /// Never throws for wrong-password — callers get a clean null.
  /// Only throws for truly unexpected errors (corrupted file, IO).
  Future<Uint8List?> verifyPassword({
    required String masterPassword,
    required VaultMeta meta,
  }) async {
    final key = await _crypto.deriveKey(
      secret: masterPassword,
      salt: meta.passwordSalt,
      params: meta.kdf,
    );

    try {
      return await _crypto.unwrap(
        wrapped: meta.wrappedVmkPassword,
        key: key,
      );
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  /// Verify the recovery answer and return the decrypted VMK, or null.
  Future<Uint8List?> verifyRecoveryAnswer({
    required String answer,
    required VaultMeta meta,
  }) async {
    final normalized = _crypto.normalizeAnswer(
      answer,
      version: meta.recovery.normalizationVersion,
    );
    final key = await _crypto.deriveKey(
      secret: normalized,
      salt: meta.recovery.salt,
      params: meta.kdf,
    );

    try {
      return await _crypto.unwrap(
        wrapped: meta.wrappedVmkRecovery,
        key: key,
      );
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  /// Re-wrap the VMK under a new master password. The VMK itself does
  /// not change, so all existing entry blobs remain valid.
  ///
  /// Returns the updated [VaultMeta] on success, `null` if the current
  /// password is wrong.
  Future<VaultMeta?> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
    required VaultMeta meta,
  }) async {
    final vmk = await verifyPassword(
      masterPassword: currentPassword,
      meta: meta,
    );
    if (vmk == null) return null;

    final newSalt = _crypto.generateSalt();
    final newKey = await _crypto.deriveKey(
      secret: newPassword,
      salt: newSalt,
      params: meta.kdf,
    );
    final newWrap = await _crypto.wrap(plaintext: vmk, key: newKey);

    final updated = VaultMeta(
      version: meta.version,
      kdf: meta.kdf,
      passwordSalt: newSalt,
      wrappedVmkPassword: newWrap,
      wrappedVmkRecovery: meta.wrappedVmkRecovery,
      wrappedVmkBiometric: meta.wrappedVmkBiometric,
      recovery: meta.recovery,
      createdAt: meta.createdAt,
      lastUnlockAt: meta.lastUnlockAt,
    );
    await _storage.save(updated);
    return updated;
  }

  /// Verify the recovery answer and replace the master-password wrap.
  ///
  /// The VMK stays the same, so entry blobs, recovery unlock, and optional
  /// biometric unlock remain valid. Only the master-password salt/wrap are
  /// rotated.
  Future<({VaultMeta meta, Uint8List vmk})?> resetMasterPasswordWithRecovery({
    required String recoveryAnswer,
    required String newPassword,
    required VaultMeta meta,
  }) async {
    final vmk = await verifyRecoveryAnswer(answer: recoveryAnswer, meta: meta);
    if (vmk == null) return null;

    final newSalt = _crypto.generateSalt();
    final newKey = await _crypto.deriveKey(
      secret: newPassword,
      salt: newSalt,
      params: meta.kdf,
    );
    final newWrap = await _crypto.wrap(plaintext: vmk, key: newKey);

    final updated = VaultMeta(
      version: meta.version,
      kdf: meta.kdf,
      passwordSalt: newSalt,
      wrappedVmkPassword: newWrap,
      wrappedVmkRecovery: meta.wrappedVmkRecovery,
      wrappedVmkBiometric: meta.wrappedVmkBiometric,
      recovery: meta.recovery,
      createdAt: meta.createdAt,
      lastUnlockAt: meta.lastUnlockAt,
    );
    await _storage.save(updated);
    return (meta: updated, vmk: vmk);
  }

  /// Stamp [lastUnlockAt] on the vault metadata.
  Future<void> recordUnlock(VaultMeta meta) async {
    await _storage.save(
      meta.copyWith(lastUnlockAt: DateTime.now().toUtc()),
    );
  }

  // ---------------------------------------------------------------
  // Biometric enroll / disable / unlock
  // ---------------------------------------------------------------

  /// Whether the device supports biometric authentication.
  Future<bool> isBiometricAvailable() => _biometric.isAvailable();

  /// Enable biometric unlock for an already-unlocked vault.
  ///
  /// 1. Prompt biometric auth (so the keystore entry is created behind
  ///    biometric gating).
  /// 2. Generate a random 256-bit "biometric key".
  /// 3. Wrap VMK under that key (AES-GCM).
  /// 4. Store the biometric key in secure storage.
  /// 5. Update `vault_meta.json` with the new `wrappedVmkBiometric`.
  Future<VaultMeta?> enableBiometric({
    required VaultMeta meta,
    required Uint8List vmk,
  }) async {
    final ok = await _biometric.authenticate(
      reason: 'Confirm your identity to enable biometric unlock',
    );
    if (!ok) return null;

    final bioKeyBytes = _crypto.randomBytes(CryptoService.vmkLengthBytes);
    final bioKey = SecretKey(bioKeyBytes);
    final wrapped = await _crypto.wrap(plaintext: vmk, key: bioKey);

    await _biometric.storeKey(Uint8List.fromList(bioKeyBytes));

    final updated = meta.copyWith(wrappedVmkBiometric: wrapped);
    await _storage.save(updated);
    return updated;
  }

  /// Disable biometric unlock: wipe the keystore key and clear the wrap
  /// from `vault_meta.json`.
  Future<VaultMeta> disableBiometric({required VaultMeta meta}) async {
    await _biometric.deleteKey();
    final updated = meta.copyWith(clearBiometric: true);
    await _storage.save(updated);
    return updated;
  }

  /// Unlock the vault via biometric. Prompts the user, retrieves the
  /// stored key, and unwraps the VMK. Returns `null` if the user cancels
  /// or no biometric wrap exists.
  Future<Uint8List?> unlockWithBiometric({required VaultMeta meta}) async {
    if (!meta.hasBiometric) return null;

    final ok = await _biometric.authenticate();
    if (!ok) return null;

    final bioKeyBytes = await _biometric.retrieveKey();
    if (bioKeyBytes == null) return null;

    try {
      final vmk = await _crypto.unwrap(
        wrapped: meta.wrappedVmkBiometric!,
        key: SecretKey(bioKeyBytes),
      );
      return vmk;
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}

/// Provider for [VaultSetupService]. Depends on the async
/// [vaultStorageProvider], so it's a FutureProvider itself.
final vaultSetupServiceProvider = FutureProvider<VaultSetupService>((ref) async {
  final crypto = ref.read(cryptoServiceProvider);
  final storage = await ref.watch(vaultStorageProvider.future);
  final biometric = ref.read(biometricServiceProvider);
  return VaultSetupService(crypto, storage, biometric);
});
