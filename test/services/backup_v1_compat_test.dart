import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vault_snap/models/password_entry.dart';
import 'package:vault_snap/models/vault_entry.dart';
import 'package:vault_snap/models/vault_meta.dart';
import 'package:vault_snap/services/attachment_service.dart';
import 'package:vault_snap/services/backup_service.dart';
import 'package:vault_snap/services/crypto_service.dart';
import 'package:vault_snap/services/vault_database.dart';

/// Synthesises a v1 backup JSON document — same shape as the original
/// pre-Phase-9 format — and verifies that the new BackupService still
/// imports it cleanly. Locks backwards-compat: every old `.vsb` users
/// have on disk must keep working forever.
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaultsnap-v1-test');
    db = await VaultDatabase.open(tempDir.path);
    crypto = CryptoService();
    attachments = AttachmentService(
      crypto: crypto,
      documentsDirectoryResolver: () async => tempDir.path,
    );
    backup = BackupService(crypto, attachments: attachments);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('v1 backup (no attachments field) still imports', () async {
    // Build a v1 backup payload by hand — no `attachments` key.
    final sourceVmkBytes = Uint8List.fromList(crypto.randomBytes(32));
    final sourceVmkKey = SecretKey(sourceVmkBytes);

    // One entry encrypted under the source VMK.
    final entryBlob = await VaultEntry.encryptFieldMap(
      crypto: crypto,
      vmk: sourceVmkKey,
      fields: const {'name': 'V1', 'password': 'pw'},
    );
    final entryRow = <String, dynamic>{
      'id': 'v1-entry',
      'name': 'V1',
      'category': EntryCategory.login.name,
      'username': null,
      'url': null,
      'android_packages': null,
      'strength': PasswordStrength.fair.name,
      'reused': 0,
      'encrypted_blob': base64Encode(entryBlob.ciphertext),
      'nonce': base64Encode(entryBlob.nonce),
      'mac': base64Encode(entryBlob.mac),
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    };
    final payloadJson = jsonEncode([entryRow]);
    final payloadBytes = Uint8List.fromList(utf8.encode(payloadJson));
    final encryptedPayload = await crypto.wrap(
      plaintext: payloadBytes,
      key: sourceVmkKey,
    );

    // Backup-key envelope.
    final kdf = KdfParams.defaults;
    final backupSalt = crypto.generateSalt();
    final backupKey = await crypto.deriveKey(
      secret: 'pw',
      salt: backupSalt,
      params: kdf,
    );
    final wrappedVmk = await crypto.wrap(
      plaintext: sourceVmkBytes,
      key: backupKey,
    );

    final v1Json = {
      'version': 1,
      'kdf': kdf.toJson(),
      'backupSalt': base64Encode(backupSalt),
      'wrappedVmk': wrappedVmk.toJson(),
      'payload': encryptedPayload.toJson(),
      // intentionally NO 'attachments' field — that's the whole point.
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(v1Json)));

    // Current vault uses a different VMK (typical migration scenario).
    final currentVmkBytes = Uint8List.fromList(crypto.randomBytes(32));

    final count = await backup.importFromBytes(
      db: db,
      currentVmk: currentVmkBytes,
      backupPassword: 'pw',
      bytes: bytes,
    );

    expect(count, 1);
    final entries = await db.queryAllOrdered();
    expect(entries.length, 1);
    expect(entries.first['id'], 'v1-entry');

    // No attachments expected — v1 had none.
    final atts = await db.allAttachments();
    expect(atts, isEmpty);
  });

  test('wrong backup password returns null (no exception)', () async {
    // Same v1 build path; wrong password → null instead of crash.
    final sourceVmkBytes = Uint8List.fromList(crypto.randomBytes(32));
    final sourceVmkKey = SecretKey(sourceVmkBytes);
    final entryBlob = await VaultEntry.encryptFieldMap(
      crypto: crypto,
      vmk: sourceVmkKey,
      fields: const {'name': 'V1', 'password': 'pw'},
    );
    final payloadBytes = Uint8List.fromList(utf8.encode(jsonEncode([
      {
        'id': 'v1-entry',
        'name': 'V1',
        'category': EntryCategory.login.name,
        'username': null,
        'url': null,
        'android_packages': null,
        'strength': PasswordStrength.fair.name,
        'reused': 0,
        'encrypted_blob': base64Encode(entryBlob.ciphertext),
        'nonce': base64Encode(entryBlob.nonce),
        'mac': base64Encode(entryBlob.mac),
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      }
    ])));
    final encryptedPayload =
        await crypto.wrap(plaintext: payloadBytes, key: sourceVmkKey);
    final kdf = KdfParams.defaults;
    final backupSalt = crypto.generateSalt();
    final backupKey = await crypto.deriveKey(
      secret: 'right-password',
      salt: backupSalt,
      params: kdf,
    );
    final wrappedVmk = await crypto.wrap(
      plaintext: sourceVmkBytes,
      key: backupKey,
    );
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'version': 1,
      'kdf': kdf.toJson(),
      'backupSalt': base64Encode(backupSalt),
      'wrappedVmk': wrappedVmk.toJson(),
      'payload': encryptedPayload.toJson(),
    })));

    final result = await backup.importFromBytes(
      db: db,
      currentVmk: Uint8List.fromList(crypto.randomBytes(32)),
      backupPassword: 'wrong-password',
      bytes: bytes,
    );
    expect(result, isNull);
  });
}
