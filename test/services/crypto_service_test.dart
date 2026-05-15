import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/models/vault_meta.dart';
import 'package:vault_snap/services/crypto_service.dart';

void main() {
  // Cheaper KDF params keep the test suite fast — production callers use
  // KdfParams.defaults (64 MiB / 3 iters), which is too slow for unit tests.
  const fastKdf = KdfParams(
    name: KdfParams.argon2id,
    memKiB: 1024,
    iterations: 1,
    parallelism: 1,
  );

  late CryptoService crypto;

  setUp(() {
    crypto = CryptoService();
  });

  group('randomBytes', () {
    test('returns the requested length', () {
      expect(crypto.randomBytes(16).length, 16);
      expect(crypto.randomBytes(32).length, 32);
    });

    test('produces different output across calls', () {
      final a = crypto.randomBytes(32);
      final b = crypto.randomBytes(32);
      expect(a, isNot(equals(b)));
    });
  });

  group('normalizeAnswer', () {
    test('trims, lowercases, and collapses whitespace', () {
      expect(crypto.normalizeAnswer('  Hello   World  '), 'hello world');
      expect(crypto.normalizeAnswer('Tabs\tand\nnewlines'),
          'tabs and newlines');
      expect(crypto.normalizeAnswer('ALREADY-CLEAN'), 'already-clean');
    });

    test('rejects unsupported version', () {
      expect(() => crypto.normalizeAnswer('hi', version: 99),
          throwsArgumentError);
    });
  });

  group('deriveKey', () {
    test('is deterministic for the same secret + salt', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final a = await crypto.deriveKeyBytes(
        secret: 'correct horse battery staple',
        salt: salt,
        params: fastKdf,
      );
      final b = await crypto.deriveKeyBytes(
        secret: 'correct horse battery staple',
        salt: salt,
        params: fastKdf,
      );
      expect(a, equals(b));
    });

    test('different salt yields different key', () async {
      final saltA = Uint8List.fromList(List.generate(16, (i) => i));
      final saltB = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final a = await crypto.deriveKeyBytes(
        secret: 'same-password',
        salt: saltA,
        params: fastKdf,
      );
      final b = await crypto.deriveKeyBytes(
        secret: 'same-password',
        salt: saltB,
        params: fastKdf,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('wrap / unwrap', () {
    test('roundtrip recovers the original VMK', () async {
      final salt = crypto.generateSalt();
      final key = await crypto.deriveKey(
        secret: 'master-password',
        salt: salt,
        params: fastKdf,
      );
      final vmk = crypto.generateVmk();
      final wrapped = await crypto.wrap(plaintext: vmk, key: key);
      final recovered = await crypto.unwrap(wrapped: wrapped, key: key);
      expect(recovered, equals(vmk));
    });

    test('wrong key fails to unwrap (auth tag mismatch)', () async {
      final salt = crypto.generateSalt();
      final goodKey = await crypto.deriveKey(
        secret: 'right-password',
        salt: salt,
        params: fastKdf,
      );
      final badKey = await crypto.deriveKey(
        secret: 'wrong-password',
        salt: salt,
        params: fastKdf,
      );
      final wrapped = await crypto.wrap(
        plaintext: Uint8List.fromList(utf8.encode('top secret')),
        key: goodKey,
      );
      expect(
        () => crypto.unwrap(wrapped: wrapped, key: badKey),
        throwsA(anything),
      );
    });
  });
}
