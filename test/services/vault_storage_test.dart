import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/models/vault_meta.dart';
import 'package:vault_snap/services/vault_storage.dart';

void main() {
  late Directory tmp;
  late VaultStorage storage;

  Uint8List bytes(int n, [int seed = 0]) =>
      Uint8List.fromList(List.generate(n, (i) => (i + seed) & 0xff));

  VaultMeta sampleMeta() => VaultMeta(
        version: 1,
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
        wrappedVmkBiometric: null,
        recovery: RecoveryMeta(question: 'q?', salt: bytes(16, 8)),
        createdAt: DateTime.utc(2026, 4, 28),
        lastUnlockAt: null,
      );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vaultsnap_test_');
    storage = VaultStorage('${tmp.path}${Platform.pathSeparator}meta.json');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('exists() is false before any write', () async {
    expect(await storage.exists(), isFalse);
    expect(await storage.load(), isNull);
  });

  test('save then load returns the same VaultMeta', () async {
    final meta = sampleMeta();
    await storage.save(meta);

    expect(await storage.exists(), isTrue);

    final loaded = await storage.load();
    expect(loaded, isNotNull);
    expect(loaded!.version, meta.version);
    expect(loaded.passwordSalt, meta.passwordSalt);
    expect(loaded.wrappedVmkPassword.ciphertext,
        meta.wrappedVmkPassword.ciphertext);
    expect(loaded.recovery.question, meta.recovery.question);
  });

  test('save is atomic — no .tmp file left behind on success', () async {
    await storage.save(sampleMeta());
    final tmpFile = File('${storage.path}.tmp');
    expect(tmpFile.existsSync(), isFalse);
  });

  test('delete removes the file', () async {
    await storage.save(sampleMeta());
    expect(await storage.exists(), isTrue);
    await storage.delete();
    expect(await storage.exists(), isFalse);
    expect(await storage.load(), isNull);
  });
}
