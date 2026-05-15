import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/vault_meta.dart';
import 'attachment_service.dart';
import 'crypto_service.dart';
import 'vault_database.dart';

/// Export/import encrypted vault backups.
///
/// Backup file is JSON with the full entry list encrypted under the VMK,
/// the VMK wrapped under a user-chosen backup password via Argon2id, and
/// — since v2 — every attachment's ciphertext re-wrapped under the
/// backup key alongside its metadata.
///
/// **Format versions:**
/// - **v1** — entries only. Top-level `"version": 1`. Still imports.
/// - **v2** — adds `"attachments"` array and re-encrypts each attachment
///   blob under the backup key (decrypt under VMK at export, re-encrypt
///   under backup key, store {nonce, ciphertext, mac} alongside the
///   attachment metadata). Import path detects the version field and
///   walks the attachments list.
class BackupService {
  final CryptoService _crypto;
  final AttachmentService _attachments;

  BackupService(
    this._crypto, {
    AttachmentService? attachments,
  }) : _attachments = attachments ?? AttachmentService(crypto: _crypto);

  /// Build encrypted backup bytes ready to be handed to the OS file picker
  /// (Storage Access Framework on Android). The bytes are an UTF-8 JSON
  /// document — see fields below.
  Future<Uint8List> exportToBytes({
    required VaultDatabase db,
    required Uint8List vmk,
    required String backupPassword,
  }) async {
    final rows = await db.queryAllOrdered();

    final serializable = rows.map((row) {
      return row.map((k, v) {
        if (v is Uint8List) return MapEntry(k, base64Encode(v));
        return MapEntry(k, v);
      });
    }).toList();

    final payloadJson = jsonEncode(serializable);
    final payloadBytes = Uint8List.fromList(utf8.encode(payloadJson));

    final vmkKey = SecretKey(Uint8List.fromList(vmk));
    final encryptedPayload = await _crypto.wrap(
      plaintext: payloadBytes,
      key: vmkKey,
    );

    final kdf = KdfParams.defaults;
    final backupSalt = _crypto.generateSalt();
    final backupKey = await _crypto.deriveKey(
      secret: backupPassword,
      salt: backupSalt,
      params: kdf,
    );
    final wrappedVmk = await _crypto.wrap(plaintext: vmk, key: backupKey);

    // Phase 9 — attachments. For each row, read the on-disk ciphertext
    // (encrypted under VMK), decrypt to plaintext, re-encrypt under the
    // backup key. The re-encrypted envelope rides inside the JSON next
    // to the attachment's metadata. Old vaults with no attachments
    // emit an empty array — fully backwards-compatible at the JSON
    // level, parser just sees `"attachments": []`.
    final attachmentRows = await db.allAttachments();
    final attachmentsOut = <Map<String, dynamic>>[];
    for (final row in attachmentRows) {
      final id = row['id']! as String;
      final filePath = await _attachments.filePathFor(id);
      final file = File(filePath);
      if (!await file.exists()) {
        // Skip orphaned rows — should never happen but a single
        // missing file shouldn't fail the whole export.
        continue;
      }
      final ciphertext = await file.readAsBytes();
      final plaintext = await _crypto.unwrap(
        wrapped: WrappedSecret(
          nonce: row['nonce']! as Uint8List,
          ciphertext: ciphertext,
          mac: row['mac']! as Uint8List,
        ),
        key: vmkKey,
      );
      final wrapped = await _crypto.wrap(
        plaintext: plaintext,
        key: backupKey,
      );
      attachmentsOut.add({
        'id': id,
        'entry_id': row['entry_id']! as String,
        'name': row['name']! as String,
        'mime': row['mime']! as String,
        'blob_size': (row['blob_size']! as num).toInt(),
        'created_at': row['created_at']! as String,
        'blob': wrapped.toJson(),
      });
    }

    final backup = {
      'version': 2,
      'kdf': kdf.toJson(),
      'backupSalt': base64Encode(backupSalt),
      'wrappedVmk': wrappedVmk.toJson(),
      'payload': encryptedPayload.toJson(),
      'attachments': attachmentsOut,
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(backup)));
  }

  /// Dry-run validation of a backup — decrypts everything (entry blobs +
  /// every attachment blob) so any tampering / wrong-password failure
  /// surfaces, but does **not** touch the DB or the on-disk attachments
  /// directory. Used by Settings → "Verify backup" so users can confirm
  /// a `.vsb` actually decrypts before they trust it (i.e., before they
  /// wipe their device assuming the backup is good).
  ///
  /// Returns a [BackupVerifyResult] on success, or `null` if the backup
  /// password is wrong (matches [importFromBytes]'s null-on-wrong-pw).
  /// Throws [FormatException] for an unsupported version, or
  /// `SecretBoxAuthenticationError` if the file is corrupt past the
  /// initial wrappedVmk envelope (e.g. a single attachment MAC failed).
  Future<BackupVerifyResult?> verifyBytes({
    required Uint8List bytes,
    required String backupPassword,
  }) async {
    final contents = await _decryptAndValidate(
      bytes: bytes,
      backupPassword: backupPassword,
    );
    if (contents == null) return null;
    return BackupVerifyResult(
      version: contents.version,
      entryCount: contents.rows.length,
      attachmentCount: contents.attachments.length,
    );
  }

  /// Import entries from an encrypted backup blob into the **currently
  /// unlocked** vault.
  ///
  /// Each row's encrypted_blob in the backup is encrypted under the
  /// backup's VMK (the source vault's VMK at export time), which may be
  /// a different key than the *current* vault's VMK — for example if the
  /// user wiped & re-set up, or is migrating from another vault. To make
  /// import correct in all cases, every entry's blob is transparently
  /// re-encrypted under [currentVmk] before insert. Same logic applies
  /// to attachment ciphertext for v2 backups.
  ///
  /// Returns the number of entries imported, or `null` if the backup
  /// password is wrong.
  Future<int?> importFromBytes({
    required VaultDatabase db,
    required Uint8List currentVmk,
    required String backupPassword,
    required Uint8List bytes,
  }) async {
    // Phase 10 — share the upfront crypto/validation path with
    // verifyBytes. _decryptAndValidate decrypts every row + every
    // attachment blob (so any MAC failure surfaces *before* we start
    // mutating the DB), then this method re-encrypts under the current
    // VMK and writes everything down.
    final contents = await _decryptAndValidate(
      bytes: bytes,
      backupPassword: backupPassword,
    );
    if (contents == null) return null;

    final currentVmkKey = SecretKey(Uint8List.fromList(currentVmk));

    for (var i = 0; i < contents.rows.length; i++) {
      final row = contents.rows[i];
      final entryPlain = contents.entryPlaintexts[i];
      final reWrapped = await _crypto.wrap(
        plaintext: entryPlain,
        key: currentVmkKey,
      );
      final dbRow = <String, Object?>{
        ...row,
        'encrypted_blob': reWrapped.ciphertext,
        'nonce': reWrapped.nonce,
        'mac': reWrapped.mac,
      };
      try {
        await db.insertRow(dbRow);
      } catch (_) {
        await db.updateRow(dbRow);
      }
    }

    // v2 attachments — already validated by _decryptAndValidate, so
    // every plaintext is in hand. Re-encrypt under the current VMK,
    // write per-file ciphertext, INSERT row.
    for (var i = 0; i < contents.attachments.length; i++) {
      final entry = contents.attachments[i];
      final plaintext = contents.attachmentPlaintexts[i];
      final id = entry['id'] as String;
      final reWrapped = await _attachments.encryptAndStore(
        vmk: currentVmkKey,
        bytes: plaintext,
        id: id,
      );
      await db.insertAttachment({
        'id': id,
        'entry_id': entry['entry_id'] as String,
        'name': entry['name'] as String,
        'mime': entry['mime'] as String,
        'blob_size': (entry['blob_size'] as num).toInt(),
        'nonce': reWrapped.nonce,
        'mac': reWrapped.mac,
        'created_at': entry['created_at'] as String,
      });
    }

    return contents.rows.length;
  }

  // ---------- shared decrypt/validate path (Phase 10) ----------

  /// Walks the full backup payload — derives the backup key, decrypts
  /// the wrappedVmk envelope, decrypts the entries payload, and (for
  /// v2) decrypts every attachment blob. Returns the parsed plaintexts
  /// alongside the original metadata so [importFromBytes] can re-wrap
  /// them under the current VMK without redoing the work.
  ///
  /// Returns `null` if the backup password is wrong (the wrappedVmk
  /// envelope failed to decrypt). Throws [FormatException] on bad
  /// version. Throws [SecretBoxAuthenticationError] if any later MAC
  /// fails (entries payload, any attachment blob) — that means the
  /// file is tampered or corrupt past the point where wrong-password
  /// is the explanation.
  Future<_BackupContents?> _decryptAndValidate({
    required Uint8List bytes,
    required String backupPassword,
  }) async {
    final raw = utf8.decode(bytes);
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final version = json['version'] as int;
    if (version != 1 && version != 2) {
      throw const FormatException('Unsupported backup version');
    }

    final kdf = KdfParams.fromJson(json['kdf'] as Map<String, dynamic>);
    final backupSalt = base64Decode(json['backupSalt'] as String);
    final wrappedVmk = WrappedSecret.fromJson(
      json['wrappedVmk'] as Map<String, dynamic>,
    );
    final encryptedPayload = WrappedSecret.fromJson(
      json['payload'] as Map<String, dynamic>,
    );

    final backupKey = await _crypto.deriveKey(
      secret: backupPassword,
      salt: backupSalt,
      params: kdf,
    );

    Uint8List backupVmkBytes;
    try {
      backupVmkBytes = await _crypto.unwrap(
        wrapped: wrappedVmk,
        key: backupKey,
      );
    } on SecretBoxAuthenticationError {
      // Wrong backup password — distinguishable from "file is
      // corrupt" because the wrappedVmk envelope is the first thing
      // that the password-derived key touches.
      return null;
    }

    final backupVmkKey = SecretKey(Uint8List.fromList(backupVmkBytes));

    final payloadBytes = await _crypto.unwrap(
      wrapped: encryptedPayload,
      key: backupVmkKey,
    );
    final rows = (jsonDecode(utf8.decode(payloadBytes)) as List)
        .cast<Map<String, dynamic>>();

    // Decrypt each entry's blob now (under the SOURCE vault's VMK)
    // so the import path can re-wrap under the current VMK without
    // redoing the work. This also surfaces any per-row MAC failure
    // *before* the import loop touches the DB.
    final entryPlaintexts = <Uint8List>[];
    for (final row in rows) {
      final wrapped = WrappedSecret(
        nonce: base64Decode(row['nonce'] as String),
        ciphertext: base64Decode(row['encrypted_blob'] as String),
        mac: base64Decode(row['mac'] as String),
      );
      entryPlaintexts.add(
        await _crypto.unwrap(wrapped: wrapped, key: backupVmkKey),
      );
    }

    // v2 attachments — decrypt each blob under the BACKUP key (note:
    // attachments are wrapped under backupKey at export, NOT VMK,
    // matching what exportToBytes writes).
    final attachments = <Map<String, dynamic>>[];
    final attachmentPlaintexts = <Uint8List>[];
    if (version == 2) {
      final list = (json['attachments'] as List? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>();
      for (final entry in list) {
        final blob = WrappedSecret.fromJson(
          entry['blob'] as Map<String, dynamic>,
        );
        attachmentPlaintexts.add(
          await _crypto.unwrap(wrapped: blob, key: backupKey),
        );
        attachments.add(entry);
      }
    }

    return _BackupContents(
      version: version,
      rows: rows,
      entryPlaintexts: entryPlaintexts,
      attachments: attachments,
      attachmentPlaintexts: attachmentPlaintexts,
    );
  }
}

/// Public success type for [BackupService.verifyBytes]. Counts only —
/// plaintext / ciphertext stays inside the service.
class BackupVerifyResult {
  final int version;
  final int entryCount;
  final int attachmentCount;
  const BackupVerifyResult({
    required this.version,
    required this.entryCount,
    required this.attachmentCount,
  });
}

/// Internal carrier — output of [_decryptAndValidate], consumed by
/// [importFromBytes] (which needs the plaintexts to re-wrap under the
/// current VMK) and [verifyBytes] (which only reads the counts).
class _BackupContents {
  final int version;
  final List<Map<String, dynamic>> rows;
  final List<Uint8List> entryPlaintexts;
  final List<Map<String, dynamic>> attachments;
  final List<Uint8List> attachmentPlaintexts;
  const _BackupContents({
    required this.version,
    required this.rows,
    required this.entryPlaintexts,
    required this.attachments,
    required this.attachmentPlaintexts,
  });
}
