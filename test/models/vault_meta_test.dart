import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/models/vault_meta.dart';

void main() {
  Uint8List bytes(int len, [int seed = 0]) =>
      Uint8List.fromList(List.generate(len, (i) => (i + seed) & 0xff));

  test('VaultMeta round-trips through JSON without losing fields', () {
    final original = VaultMeta(
      version: VaultMeta.currentVersion,
      kdf: KdfParams.defaults,
      passwordSalt: bytes(16, 1),
      wrappedVmkPassword: WrappedSecret(
        nonce: bytes(12, 2),
        ciphertext: bytes(32, 3),
        mac: bytes(16, 4),
      ),
      wrappedVmkRecovery: WrappedSecret(
        nonce: bytes(12, 5),
        ciphertext: bytes(32, 6),
        mac: bytes(16, 7),
      ),
      wrappedVmkBiometric: WrappedSecret(
        nonce: bytes(12, 8),
        ciphertext: bytes(32, 9),
        mac: bytes(16, 10),
      ),
      recovery: RecoveryMeta(
        question: 'What was your childhood nickname?',
        salt: bytes(16, 11),
      ),
      createdAt: DateTime.utc(2026, 4, 28, 1, 53),
      lastUnlockAt: DateTime.utc(2026, 4, 28, 2, 0),
    );

    final round = VaultMeta.fromJson(original.toJson());

    expect(round.version, original.version);
    expect(round.kdf.name, original.kdf.name);
    expect(round.kdf.memKiB, original.kdf.memKiB);
    expect(round.kdf.iterations, original.kdf.iterations);
    expect(round.kdf.parallelism, original.kdf.parallelism);
    expect(round.passwordSalt, original.passwordSalt);
    expect(round.wrappedVmkPassword.nonce, original.wrappedVmkPassword.nonce);
    expect(round.wrappedVmkPassword.ciphertext,
        original.wrappedVmkPassword.ciphertext);
    expect(round.wrappedVmkPassword.mac, original.wrappedVmkPassword.mac);
    expect(round.wrappedVmkRecovery.ciphertext,
        original.wrappedVmkRecovery.ciphertext);
    expect(round.wrappedVmkBiometric, isNotNull);
    expect(
      round.wrappedVmkBiometric!.ciphertext,
      original.wrappedVmkBiometric!.ciphertext,
    );
    expect(round.recovery.question, original.recovery.question);
    expect(round.recovery.salt, original.recovery.salt);
    expect(round.recovery.normalizationVersion, 1);
    expect(round.createdAt, original.createdAt);
    expect(round.lastUnlockAt, original.lastUnlockAt);
  });

  test('biometric and lastUnlockAt are nullable', () {
    final original = VaultMeta(
      version: 1,
      kdf: KdfParams.defaults,
      passwordSalt: bytes(16),
      wrappedVmkPassword: WrappedSecret(
        nonce: bytes(12, 1),
        ciphertext: bytes(32, 2),
        mac: bytes(16, 3),
      ),
      wrappedVmkRecovery: WrappedSecret(
        nonce: bytes(12, 4),
        ciphertext: bytes(32, 5),
        mac: bytes(16, 6),
      ),
      wrappedVmkBiometric: null,
      recovery: RecoveryMeta(question: 'q', salt: bytes(16, 7)),
      createdAt: DateTime.utc(2026, 4, 28),
      lastUnlockAt: null,
    );

    final round = VaultMeta.fromJson(original.toJson());
    expect(round.wrappedVmkBiometric, isNull);
    expect(round.lastUnlockAt, isNull);
    expect(round.hasBiometric, isFalse);
  });

  test('copyWith clearBiometric drops the biometric wrap', () {
    final base = VaultMeta(
      version: 1,
      kdf: KdfParams.defaults,
      passwordSalt: bytes(16),
      wrappedVmkPassword: WrappedSecret(
        nonce: bytes(12, 1),
        ciphertext: bytes(32, 2),
        mac: bytes(16, 3),
      ),
      wrappedVmkRecovery: WrappedSecret(
        nonce: bytes(12, 4),
        ciphertext: bytes(32, 5),
        mac: bytes(16, 6),
      ),
      wrappedVmkBiometric: WrappedSecret(
        nonce: bytes(12, 7),
        ciphertext: bytes(32, 8),
        mac: bytes(16, 9),
      ),
      recovery: RecoveryMeta(question: 'q', salt: bytes(16, 10)),
      createdAt: DateTime.utc(2026, 4, 28),
      lastUnlockAt: null,
    );
    expect(base.hasBiometric, isTrue);
    final cleared = base.copyWith(clearBiometric: true);
    expect(cleared.hasBiometric, isFalse);
    expect(cleared.wrappedVmkBiometric, isNull);
  });
}
