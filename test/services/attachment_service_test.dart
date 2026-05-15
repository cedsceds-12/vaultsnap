import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vault_snap/services/attachment_service.dart';
import 'package:vault_snap/services/crypto_service.dart';

void main() {
  late Directory tempDir;
  late AttachmentService svc;
  late SecretKey vmk;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaultsnap-att-test');
    final crypto = CryptoService();
    svc = AttachmentService(
      crypto: crypto,
      documentsDirectoryResolver: () async => tempDir.path,
    );
    final keyBytes = Uint8List.fromList(crypto.randomBytes(32));
    vmk = SecretKey(keyBytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AttachmentService — encrypt/decrypt roundtrip', () {
    test('small blob (1 KB) — roundtrip preserves bytes', () async {
      final bytes = _randomBytes(1024);
      final enc = await svc.encryptAndStore(vmk: vmk, bytes: bytes);
      final back = await svc.decrypt(
        vmk: vmk,
        id: enc.id,
        nonce: enc.nonce,
        mac: enc.mac,
      );
      expect(back, bytes);
      expect(enc.blobSize, 1024);
      expect(enc.nonce.length, AttachmentService.nonceLength);

      // File actually written.
      final filePath =
          p.join(tempDir.path, AttachmentService.directoryName, '${enc.id}.bin');
      expect(await File(filePath).exists(), isTrue);
    });

    test('large blob (5 MB) — roundtrip via isolate', () async {
      // 5 MiB > the 1 MiB isolate threshold, so this exercises the
      // Isolate.run code path. DartAesGcm is pure-Dart and isolate-safe;
      // the test failing here would mean our isolate plumbing is wrong.
      final bytes = _randomBytes(5 * 1024 * 1024);
      final enc = await svc.encryptAndStore(vmk: vmk, bytes: bytes);
      final back = await svc.decrypt(
        vmk: vmk,
        id: enc.id,
        nonce: enc.nonce,
        mac: enc.mac,
      );
      expect(back.length, bytes.length);
      expect(back, bytes);
    });

    test('MAC tamper rejected', () async {
      final bytes = _randomBytes(2048);
      final enc = await svc.encryptAndStore(vmk: vmk, bytes: bytes);

      // Flip a bit in the on-disk ciphertext.
      final filePath = await svc.filePathFor(enc.id);
      final file = File(filePath);
      final ct = await file.readAsBytes();
      final tampered = Uint8List.fromList(ct);
      tampered[0] ^= 0x01;
      await file.writeAsBytes(tampered, flush: true);

      expect(
        () => svc.decrypt(
          vmk: vmk,
          id: enc.id,
          nonce: enc.nonce,
          mac: enc.mac,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('wrong VMK rejected', () async {
      final bytes = _randomBytes(2048);
      final enc = await svc.encryptAndStore(vmk: vmk, bytes: bytes);

      final wrongKey = SecretKey(
        Uint8List.fromList(CryptoService().randomBytes(32)),
      );
      expect(
        () => svc.decrypt(
          vmk: wrongKey,
          id: enc.id,
          nonce: enc.nonce,
          mac: enc.mac,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('AttachmentService — file lifecycle', () {
    test('deleteFile removes the on-disk ciphertext', () async {
      final enc =
          await svc.encryptAndStore(vmk: vmk, bytes: _randomBytes(64));
      final path = await svc.filePathFor(enc.id);
      expect(await File(path).exists(), isTrue);
      await svc.deleteFile(enc.id);
      expect(await File(path).exists(), isFalse);
    });

    test('deleteFile is a no-op for missing files', () async {
      // Shouldn't throw — wipe paths and best-effort cleanup rely on
      // this being safe to call even when the file isn't there.
      await svc.deleteFile('nonexistent-id');
    });

    test('wipeAll removes the directory', () async {
      await svc.encryptAndStore(vmk: vmk, bytes: _randomBytes(64));
      await svc.encryptAndStore(vmk: vmk, bytes: _randomBytes(64));
      final dirPath = await svc.directoryPath();
      expect(await Directory(dirPath).exists(), isTrue);
      await svc.wipeAll();
      expect(await Directory(dirPath).exists(), isFalse);
    });
  });
}

Uint8List _randomBytes(int n) {
  final rnd = math.Random(42);
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = rnd.nextInt(256);
  }
  return out;
}
