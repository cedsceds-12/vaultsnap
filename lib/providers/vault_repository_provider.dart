import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attachment.dart';
import '../models/password_entry.dart';
import '../models/vault_entry.dart';
import '../services/autofill_matching.dart';
import '../services/crypto_service.dart';
import '../services/vault_database.dart';
import 'vault_providers.dart';
import '../widgets/vault_lock_scope.dart';
import 'vault_locked_error.dart';

class VaultRepository extends AsyncNotifier<List<VaultEntry>> {
  @override
  Future<List<VaultEntry>> build() async {
    final db = await ref.watch(vaultDatabaseProvider.future);
    final rows = await db.queryAllOrdered();
    return rows.map(VaultEntry.fromDatabaseRow).toList();
  }

  Future<List<VaultEntry>> _load() async {
    final db = await ref.read(vaultDatabaseProvider.future);
    final rows = await db.queryAllOrdered();
    return rows.map(VaultEntry.fromDatabaseRow).toList();
  }

  SecretKey _requireVmkKey() {
    final vmk = ref.read(vaultLockControllerProvider).vmk;
    if (vmk == null) throw VaultLockedError();
    return SecretKey(Uint8List.fromList(vmk));
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<void> refreshSecurityFlags() async {
    final db = await ref.read(vaultDatabaseProvider.future);
    final updated = await _recalculateSecurityFlags(db);
    state = AsyncValue.data(updated);
  }

  Future<void> addEntry({
    required EntryCategory category,
    required Map<String, String> fields,
  }) async {
    final crypto = ref.read(cryptoServiceProvider);
    final vmk = _requireVmkKey();
    final db = await ref.read(vaultDatabaseProvider.future);

    final cleartext = VaultEntry.cleartextFromFields(category, fields);
    final strength = VaultEntry.strengthFromFields(category, fields);
    final androidPackages = parseAndroidPackagesField(fields['android_packages']);
    final fieldsForEncrypt = Map<String, String>.from(fields)
      ..remove('android_packages');
    final wrapped = await VaultEntry.encryptFieldMap(
      crypto: crypto,
      vmk: vmk,
      fields: fieldsForEncrypt,
    );

    final id = _randomEntryId(ref.read(cryptoServiceProvider));
    final now = DateTime.now().toUtc();
    final entry = VaultEntry(
      id: id,
      name: cleartext.name,
      username: cleartext.username,
      url: cleartext.url,
      androidPackages: androidPackages,
      category: category,
      strength: strength,
      reused: false,
      createdAt: now,
      updatedAt: now,
      encryptedPayload: wrapped,
    );

    await db.insertRow(entry.toDatabaseRow());
    state = AsyncValue.data(await _recalculateSecurityFlags(db));
  }

  Future<void> updateEntry({
    required VaultEntry existing,
    required EntryCategory category,
    required Map<String, String> fields,
  }) async {
    final crypto = ref.read(cryptoServiceProvider);
    final vmk = _requireVmkKey();
    final db = await ref.read(vaultDatabaseProvider.future);

    final cleartext = VaultEntry.cleartextFromFields(category, fields);
    final strength = VaultEntry.strengthFromFields(category, fields);
    final androidPackages = parseAndroidPackagesField(fields['android_packages']);
    final fieldsForEncrypt = Map<String, String>.from(fields)
      ..remove('android_packages');
    final wrapped = await VaultEntry.encryptFieldMap(
      crypto: crypto,
      vmk: vmk,
      fields: fieldsForEncrypt,
    );

    final now = DateTime.now().toUtc();
    final entry = VaultEntry(
      id: existing.id,
      name: cleartext.name,
      username: cleartext.username,
      url: cleartext.url,
      androidPackages: androidPackages,
      category: category,
      strength: strength,
      reused: existing.reused,
      createdAt: existing.createdAt,
      updatedAt: now,
      encryptedPayload: wrapped,
    );

    await db.updateRow(entry.toDatabaseRow());
    state = AsyncValue.data(await _recalculateSecurityFlags(db));
  }

  Future<void> deleteEntry(String id) async {
    final db = await ref.read(vaultDatabaseProvider.future);
    await _cascadeDeleteAttachments(db, [id]);
    await db.deleteById(id);
    await refresh();
  }

  /// Bulk delete used by the multi-select UI on the Vault and
  /// Authenticator tabs. Drops every row in [ids] and recalculates
  /// security flags once at the end (vs. once per entry — keeps a
  /// 50-entry batch from doing 50 reuse-detection passes).
  Future<void> deleteEntries(Iterable<String> ids) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    final db = await ref.read(vaultDatabaseProvider.future);
    await _cascadeDeleteAttachments(db, list);
    for (final id in list) {
      await db.deleteById(id);
    }
    await refresh();
  }

  /// Removes every attachment row (and on-disk ciphertext file)
  /// belonging to the given entry ids. Stands in for the
  /// `ON DELETE CASCADE` we don't have because sqflite ships with
  /// `foreign_keys` off and switching it on retroactively is fragile.
  Future<void> _cascadeDeleteAttachments(
    VaultDatabase db,
    Iterable<String> entryIds,
  ) async {
    final svc = ref.read(attachmentServiceProvider);
    for (final entryId in entryIds) {
      final removedIds = await db.deleteAttachmentsForEntry(entryId);
      for (final attachmentId in removedIds) {
        await svc.deleteFile(attachmentId);
      }
    }
  }

  // ---------- Attachments ----------

  /// Returns the attachments for [entryId] in creation order.
  Future<List<VaultAttachment>> attachmentsFor(String entryId) async {
    final db = await ref.read(vaultDatabaseProvider.future);
    final rows = await db.attachmentsForEntry(entryId);
    return rows.map(VaultAttachment.fromDatabaseRow).toList();
  }

  /// Encrypts [bytes] under VMK, writes ciphertext to
  /// `<docs>/vault_attachments/<id>.bin`, INSERTs the metadata row,
  /// and refreshes the entry list (so any consumers picking up the
  /// updated row see it). Returns the freshly-built [VaultAttachment].
  Future<VaultAttachment> addAttachment({
    required String entryId,
    required String name,
    required String mime,
    required Uint8List bytes,
  }) async {
    final vmk = _requireVmkKey();
    final db = await ref.read(vaultDatabaseProvider.future);
    final svc = ref.read(attachmentServiceProvider);

    final result = await svc.encryptAndStore(vmk: vmk, bytes: bytes);
    final attachment = VaultAttachment(
      id: result.id,
      entryId: entryId,
      name: name,
      mime: mime,
      blobSize: result.blobSize,
      nonce: result.nonce,
      mac: result.mac,
      createdAt: DateTime.now().toUtc(),
    );
    await db.insertAttachment(attachment.toDatabaseRow());
    return attachment;
  }

  /// Decrypts the attachment for in-memory display. Plaintext bytes
  /// are NOT cached or written to disk by this call — the caller
  /// (viewer screen) holds them in RAM only.
  Future<Uint8List> decryptAttachment(VaultAttachment a) async {
    final vmk = _requireVmkKey();
    final svc = ref.read(attachmentServiceProvider);
    return svc.decrypt(
      vmk: vmk,
      id: a.id,
      nonce: a.nonce,
      mac: a.mac,
    );
  }

  Future<void> deleteAttachment(VaultAttachment a) async {
    final db = await ref.read(vaultDatabaseProvider.future);
    final svc = ref.read(attachmentServiceProvider);
    await db.deleteAttachmentById(a.id);
    await svc.deleteFile(a.id);
  }

  /// Decrypt an entry's payload (detail / edit screens). Requires unlock.
  Future<Map<String, String>> decryptEntryPayload(VaultEntry entry) async {
    final crypto = ref.read(cryptoServiceProvider);
    final vmk = _requireVmkKey();
    return VaultEntry.decryptFieldMap(
      crypto: crypto,
      vmk: vmk,
      payload: entry.encryptedPayload,
    );
  }

  Future<List<VaultEntry>> _recalculateSecurityFlags(VaultDatabase db) async {
    final rows = await db.queryAllOrdered();
    final entries = rows.map(VaultEntry.fromDatabaseRow).toList();
    if (entries.isEmpty) return entries;

    final crypto = ref.read(cryptoServiceProvider);
    final vmk = _requireVmkKey();
    final fingerprintById = <String, String>{};
    final strengthById = <String, PasswordStrength>{};

    for (final entry in entries) {
      final fields = await VaultEntry.decryptFieldMap(
        crypto: crypto,
        vmk: vmk,
        payload: entry.encryptedPayload,
      );
      final password = VaultEntry.passwordFromFields(entry.category, fields);
      if (password.isNotEmpty) {
        fingerprintById[entry.id] = await _passwordFingerprint(password);
      }
      strengthById[entry.id] =
          VaultEntry.strengthFromFields(entry.category, fields);
    }

    final counts = <String, int>{};
    for (final fingerprint in fingerprintById.values) {
      counts[fingerprint] = (counts[fingerprint] ?? 0) + 1;
    }

    final updated = <VaultEntry>[];
    for (final entry in entries) {
      final fingerprint = fingerprintById[entry.id];
      final next = entry.copyWithSecurity(
        strength: strengthById[entry.id] ?? entry.strength,
        reused: fingerprint != null && (counts[fingerprint] ?? 0) > 1,
      );
      updated.add(next);
      if (next.strength != entry.strength || next.reused != entry.reused) {
        await db.updateRow(next.toDatabaseRow());
      }
    }
    return updated;
  }

  Future<String> _passwordFingerprint(String password) async {
    final digest = await Sha256().hash(utf8.encode(password));
    return base64UrlEncode(digest.bytes);
  }

  String _randomEntryId(CryptoService crypto) {
    final b = crypto.randomBytes(16);
    return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }
}

final vaultRepositoryProvider =
    AsyncNotifierProvider<VaultRepository, List<VaultEntry>>(
  VaultRepository.new,
);
