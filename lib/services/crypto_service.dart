import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/vault_meta.dart';

/// Pure-Dart cryptographic primitives for VaultSnap.
///
/// Responsibilities — and ONLY these:
///   * Argon2id key derivation (master password / recovery answer)
///   * AES-GCM 256 envelope encryption (wrap / unwrap)
///   * Cryptographically-secure random byte generation
///   * Deterministic answer normalization (so the user isn't fighting
///     capitalization or stray whitespace on recovery)
///
/// This class MUST stay pure-Dart (no Flutter, no dart:io, no plugin
/// channels) so it is trivially unit-testable and can be reused on any
/// future platform.
class CryptoService {
  static const int vmkLengthBytes = 32; // 256-bit
  static const int saltLengthBytes = 16;

  final Random _random;

  /// [random] is injectable for tests. Production callers should use the
  /// default which uses [Random.secure].
  CryptoService({Random? random}) : _random = random ?? Random.secure();

  /// Returns [n] cryptographically-secure random bytes.
  Uint8List randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// 256-bit Vault Master Key. Generated once per vault, never leaves
  /// memory in cleartext beyond the unlock scope.
  Uint8List generateVmk() => randomBytes(vmkLengthBytes);

  /// 128-bit salt for KDF inputs. Each KDF context (password, recovery,
  /// future per-entry) MUST get its own unique salt.
  Uint8List generateSalt() => randomBytes(saltLengthBytes);

  /// Normalize a recovery answer for hashing.
  ///
  /// Steps (normalizationVersion: 1):
  ///   1. trim
  ///   2. lowercase (case-folded via String.toLowerCase)
  ///   3. collapse internal whitespace runs to a single space
  ///
  /// Diacritic stripping is intentionally NOT done in v1 — adding it
  /// later will be a normalizationVersion bump on a per-vault basis.
  String normalizeAnswer(String input, {int version = 1}) {
    if (version != 1) {
      throw ArgumentError('Unsupported normalizationVersion: $version');
    }
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Derive a 256-bit symmetric key from a UTF-8 secret + salt using
  /// the params recorded in the vault. Returns the raw key bytes;
  /// callers wrap them in [SecretKey] when handing off to AES-GCM.
  Future<Uint8List> deriveKeyBytes({
    required String secret,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    if (params.name != KdfParams.argon2id) {
      throw UnsupportedError('Only argon2id is supported (got ${params.name})');
    }
    final algo = Argon2id(
      parallelism: params.parallelism,
      memory: params.memKiB,
      iterations: params.iterations,
      hashLength: vmkLengthBytes,
    );
    final secretKey = await algo.deriveKeyFromPassword(
      password: secret,
      nonce: salt,
    );
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Convenience wrapper that returns a [SecretKey] ready for AES-GCM.
  Future<SecretKey> deriveKey({
    required String secret,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    final bytes = await deriveKeyBytes(
      secret: secret,
      salt: salt,
      params: params,
    );
    return SecretKey(bytes);
  }

  /// AES-GCM-256 encrypt [plaintext] under [key]. A fresh 96-bit nonce
  /// is generated per call (the cryptography package handles this
  /// automatically when no nonce is supplied).
  Future<WrappedSecret> wrap({
    required Uint8List plaintext,
    required SecretKey key,
  }) async {
    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(plaintext, secretKey: key);
    return WrappedSecret(
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  /// Decrypt a [WrappedSecret] under [key]. Throws [SecretBoxAuthenticationError]
  /// from the cryptography package if the MAC fails — callers should
  /// translate that into a user-facing "wrong password / corrupted
  /// vault" error.
  Future<Uint8List> unwrap({
    required WrappedSecret wrapped,
    required SecretKey key,
  }) async {
    final aes = AesGcm.with256bits();
    final box = SecretBox(
      wrapped.ciphertext,
      nonce: wrapped.nonce,
      mac: Mac(wrapped.mac),
    );
    final clear = await aes.decrypt(box, secretKey: key);
    return Uint8List.fromList(clear);
  }

  /// Helper to produce a UTF-8 byte view of [s] for callers building
  /// payloads outside the standard wrap/unwrap path.
  Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
}
