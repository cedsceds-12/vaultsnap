import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vault_snap/models/password_entry.dart';
import 'package:vault_snap/models/vault_entry.dart';
import 'package:vault_snap/services/attachment_service.dart';
import 'package:vault_snap/services/backup_service.dart';
import 'package:vault_snap/services/crypto_service.dart';
import 'package:vault_snap/services/vault_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late VaultDatabase db;
  late AttachmentService attachments;
  late BackupService backup;
  late CryptoService crypto;
  late SecretKey vmkKey;
  late Uint8List vmkBytes;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaultsnap-backup-test');
    db = await VaultDatabase.open(tempDir.path);
    crypto = CryptoService();
    attachments = AttachmentService(
      crypto: crypto,
      documentsDirectoryResolver: () async => tempDir.path,
    );
    backup = BackupService(crypto, attachments: attachments);
    vmkBytes = Uint8List.fromList(crypto.randomBytes(32));
    vmkKey = SecretKey(vmkBytes);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('v2 roundtrip — entries + attachments survive a backup/import cycle',
      () async {
    // Seed: one entry + two attachments under it.
    final entryId = 'entry-abc123';
    final entryBlob = await VaultEntry.encryptFieldMap(
      crypto: crypto,
      vmk: vmkKey,
      fields: const {'name': 'Test', 'username': 'u@x.com', 'password': 'pw'},
    );
    await db.insertRow({
      'id': entryId,
      'name': 'Test',
      'category': EntryCategory.login.name,
      'username': 'u@x.com',
      'url': 'example.com',
      'android_packages': null,
      'strength': PasswordStrength.fair.name,
      'reused': 0,
      'encrypted_blob': entryBlob.ciphertext,
      'nonce': entryBlob.nonce,
      'mac': entryBlob.mac,
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    });

    final originalA = Uint8List.fromList(List<int>.generate(2048, (i) => i));
    final originalB = Uint8List.fromList(List<int>.generate(8192, (i) => 255 - (i & 0xff)));
    final encA = await attachments.encryptAndStore(vmk: vmkKey, bytes: originalA);
    final encB = await attachments.encryptAndStore(vmk: vmkKey, bytes: originalB);
    await db.insertAttachment({
      'id': encA.id,
      'entry_id': entryId,
      'name': 'a.bin',
      'mime': 'application/octet-stream',
      'blob_size': encA.blobSize,
      'nonce': encA.nonce,
      'mac': encA.mac,
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    });
    await db.insertAttachment({
      'id': encB.id,
      'entry_id': entryId,
      'name': 'b.bin',
      'mime': 'application/octet-stream',
      'blob_size': encB.blobSize,
      'nonce': encB.nonce,
      'mac': encB.mac,
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    });

    // Export under a backup password.
    final exported = await backup.exportToBytes(
      db: db,
      vmk: vmkBytes,
      backupPassword: 'correct horse battery staple',
    );
    expect(exported, isNotEmpty);

    // Wipe the source: empty the DB and remove the attachment files.
    await db.deleteAll();
    await attachments.wipeAll();
    expect((await db.queryAllOrdered()).length, 0);
    expect((await db.allAttachments()).length, 0);

    // Import on the same DB (simulating a "freshly set-up vault").
    final count = await backup.importFromBytes(
      db: db,
      currentVmk: vmkBytes,
      backupPassword: 'correct horse battery staple',
      bytes: exported,
    );
    expect(count, 1);

    // Entry survived.
    final restoredEntries = await db.queryAllOrdered();
    expect(restoredEntries.length, 1);
    expect(restoredEntries.first['id'], entryId);

    // Both attachments survived AND decrypt back to the original bytes
    // under the current VMK (they were re-encrypted on import).
    final restored = await db.allAttachments();
    expect(restored.length, 2);
    final byId = {for (final r in restored) r['id'] as String: r};
    final restoredA = byId[encA.id]!;
    final restoredB = byId[encB.id]!;
    final backA = await attachments.decrypt(
      vmk: vmkKey,
      id: encA.id,
      nonce: restoredA['nonce']! as Uint8List,
      mac: restoredA['mac']! as Uint8List,
    );
    final backB = await attachments.decrypt(
      vmk: vmkKey,
      id: encB.id,
      nonce: restoredB['nonce']! as Uint8List,
      mac: restoredB['mac']! as Uint8List,
    );
    expect(backA, originalA);
    expect(backB, originalB);
  });

  test('v2 import survives even when the current VMK differs from the source VMK',
      () async {
    // Seeds an entry+attachment under one VMK, exports under that VMK,
    // then imports into a fresh DB whose CURRENT VMK is a different
    // random key — simulates "I wiped and reset, now restoring." The
    // import path re-encrypts everything under the current VMK so the
    // result must still be readable.
    final originalBytes = Uint8List.fromList(List<int>.generate(1234, (i) => i));
    final entryBlob = await VaultEntry.encryptFieldMap(
      crypto: crypto,
      vmk: vmkKey,
      fields: const {'name': 'X', 'password': 'y'},
    );
    await db.insertRow({
      'id': 'e1',
      'name': 'X',
      'category': EntryCategory.login.name,
      'username': null,
      'url': null,
      'android_packages': null,
      'strength': PasswordStrength.weak.name,
      'reused': 0,
      'encrypted_blob': entryBlob.ciphertext,
      'nonce': entryBlob.nonce,
      'mac': entryBlob.mac,
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    });
    final enc = await attachments.encryptAndStore(vmk: vmkKey, bytes: originalBytes);
    await db.insertAttachment({
      'id': enc.id,
      'entry_id': 'e1',
      'name': 'doc.bin',
      'mime': 'application/octet-stream',
      'blob_size': enc.blobSize,
      'nonce': enc.nonce,
      'mac': enc.mac,
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    });

    final exported = await backup.exportToBytes(
      db: db,
      vmk: vmkBytes,
      backupPassword: 'pw',
    );

    await db.deleteAll();
    await attachments.wipeAll();

    // Generate a *new* VMK and import under it.
    final newVmkBytes = Uint8List.fromList(crypto.randomBytes(32));
    final newVmkKey = SecretKey(newVmkBytes);
    await backup.importFromBytes(
      db: db,
      currentVmk: newVmkBytes,
      backupPassword: 'pw',
      bytes: exported,
    );

    final restored = await db.allAttachments();
    expect(restored.length, 1);
    final back = await attachments.decrypt(
      vmk: newVmkKey,
      id: enc.id,
      nonce: restored.first['nonce']! as Uint8List,
      mac: restored.first['mac']! as Uint8List,
    );
    expect(back, originalBytes);
  });
}
