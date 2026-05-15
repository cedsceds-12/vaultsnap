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

/// Phase 10 — `verifyBytes` runs the full decrypt + MAC-check path
/// against a `.vsb` and reports counts WITHOUT touching the DB or the
/// on-disk attachments dir. Lets users confirm a backup actually
/// decrypts before they trust it (i.e., before they wipe their
/// device).
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
  late Uint8List exportedBackup;
  late int initialEntryCount;
  late int initialAttachmentCount;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaultsnap-verify-test');
    db = await VaultDatabase.open(tempDir.path);
    crypto = CryptoService();
    attachments = AttachmentService(
      crypto: crypto,
      documentsDirectoryResolver: () async => tempDir.path,
    );
    backup = BackupService(crypto, attachments: attachments);
    vmkBytes = Uint8List.fromList(crypto.randomBytes(32));
    vmkKey = SecretKey(vmkBytes);

    // Seed: 2 entries + 1 attachment, then export under "pw".
    await _seedEntry(
      db: db,
      crypto: crypto,
      vmk: vmkKey,
      id: 'e1',
      name: 'GitHub',
    );
    await _seedEntry(
      db: db,
      crypto: crypto,
      vmk: vmkKey,
      id: 'e2',
      name: 'Bank',
    );
    final attBytes =
        Uint8List.fromList(List<int>.generate(1024, (i) => i & 0xff));
    final enc = await attachments.encryptAndStore(vmk: vmkKey, bytes: attBytes);
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

    exportedBackup = await backup.exportToBytes(
      db: db,
      vmk: vmkBytes,
      backupPassword: 'pw',
    );

    initialEntryCount = (await db.queryAllOrdered()).length;
    initialAttachmentCount = (await db.allAttachments()).length;
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('valid backup with right password → returns counts', () async {
    final result = await backup.verifyBytes(
      bytes: exportedBackup,
      backupPassword: 'pw',
    );
    expect(result, isNotNull);
    expect(result!.version, 2);
    expect(result.entryCount, 2);
    expect(result.attachmentCount, 1);
  });

  test('wrong backup password → returns null (no throw)', () async {
    final result = await backup.verifyBytes(
      bytes: exportedBackup,
      backupPassword: 'wrong-password',
    );
    expect(result, isNull);
  });

  test('verifyBytes does NOT mutate the DB', () async {
    await backup.verifyBytes(
      bytes: exportedBackup,
      backupPassword: 'pw',
    );
    // Critical: same row counts before vs. after.
    expect((await db.queryAllOrdered()).length, initialEntryCount);
    expect((await db.allAttachments()).length, initialAttachmentCount);
  });

  test('verifyBytes does NOT write to the attachments dir', () async {
    final dirPath = await attachments.directoryPath();
    final beforeFiles = Directory(dirPath).existsSync()
        ? Directory(dirPath).listSync().length
        : 0;
    await backup.verifyBytes(
      bytes: exportedBackup,
      backupPassword: 'pw',
    );
    final afterFiles = Directory(dirPath).existsSync()
        ? Directory(dirPath).listSync().length
        : 0;
    expect(afterFiles, beforeFiles);
  });

  test('tampered ciphertext (single bit flip) → throws', () async {
    // Flip a byte deep in the JSON ciphertext — but NOT in a
    // base64-padding-relevant position. Easiest: just mutate the
    // backup bytes near the end (some attachment ciphertext byte
    // base64-encoded). The MAC will reject it.
    final tampered = Uint8List.fromList(exportedBackup);
    // Find a byte that's clearly inside a base64 ciphertext field by
    // walking from near-end backward looking for a normal alpha char.
    var idx = tampered.length - 100;
    while (idx > 0 && (tampered[idx] < 0x41 || tampered[idx] > 0x5a)) {
      idx--;
    }
    tampered[idx] = (tampered[idx] == 0x41) ? 0x42 : 0x41;

    expect(
      () => backup.verifyBytes(
        bytes: tampered,
        backupPassword: 'pw',
      ),
      throwsA(anyOf(
        isA<SecretBoxAuthenticationError>(),
        isA<FormatException>(),
      )),
    );
  });

  test('non-VSB garbage bytes → throws (FormatException)', () async {
    final junk = Uint8List.fromList('this is not a vault backup'.codeUnits);
    expect(
      () => backup.verifyBytes(bytes: junk, backupPassword: 'pw'),
      throwsA(isA<FormatException>()),
    );
  });

  test(
      'verify result lines up with what importFromBytes would actually import',
      () async {
    // Run verify on the backup, then run importFromBytes on a fresh
    // DB and confirm the counts the user saw in the verify dialog
    // match what they'll get after import.
    final result = await backup.verifyBytes(
      bytes: exportedBackup,
      backupPassword: 'pw',
    );
    expect(result, isNotNull);

    // Fresh DB + fresh attachments dir.
    final tempDir2 =
        await Directory.systemTemp.createTemp('vaultsnap-import-after-verify');
    final db2 = await VaultDatabase.open(tempDir2.path);
    final att2 = AttachmentService(
      crypto: crypto,
      documentsDirectoryResolver: () async => tempDir2.path,
    );
    final backup2 = BackupService(crypto, attachments: att2);
    final newVmk = Uint8List.fromList(crypto.randomBytes(32));

    final imported = await backup2.importFromBytes(
      db: db2,
      currentVmk: newVmk,
      backupPassword: 'pw',
      bytes: exportedBackup,
    );
    expect(imported, result!.entryCount);
    expect((await db2.allAttachments()).length, result.attachmentCount);

    await db2.close();
    if (await tempDir2.exists()) {
      await tempDir2.delete(recursive: true);
    }
  });
}

Future<void> _seedEntry({
  required VaultDatabase db,
  required CryptoService crypto,
  required SecretKey vmk,
  required String id,
  required String name,
}) async {
  final blob = await VaultEntry.encryptFieldMap(
    crypto: crypto,
    vmk: vmk,
    fields: {'name': name, 'username': 'u@x.com', 'password': 'pw'},
  );
  await db.insertRow({
    'id': id,
    'name': name,
    'category': EntryCategory.login.name,
    'username': 'u@x.com',
    'url': null,
    'android_packages': null,
    'strength': PasswordStrength.fair.name,
    'reused': 0,
    'encrypted_blob': blob.ciphertext,
    'nonce': blob.nonce,
    'mac': blob.mac,
    'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
  });
}
