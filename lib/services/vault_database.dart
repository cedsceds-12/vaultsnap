import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQL store for vault entry rows (cleartext metadata + encrypted blob).
///
/// **TODO (PR-3 deferred)** — privacy: `android_packages` is a cleartext JSON
/// column that leaks app↔login linkages to anyone with file-level access.
/// The plan is to migrate to HMAC-SHA256 hashes (key = HKDF(VMK,
/// "vaultsnap.autofill.pkg-hmac.v1")) so the column reveals nothing about
/// which apps are linked. The full implementation needs:
///   1. CryptoService HKDF + HMAC helpers
///   2. New cleartext column `android_package_hashes` (or in-place rewrite)
///   3. Encrypted-blob carrying the original names so the edit/detail screens
///      can still display them
///   4. Migration on unlock (VMK required)
///   5. Kotlin: receive hmacKey via MethodChannel, HMAC caller package at fill
///      time, compare against the hashed column
/// Tracked in `vault_snap/ROADMAP.md` Phase 7.5.
class VaultDatabase {
  static const _version = 4;
  static const _table = 'entries';
  static const _attachmentsTable = 'attachments';

  final Database _db;

  VaultDatabase._(this._db);

  static Future<VaultDatabase> open(String documentsDirectoryPath) async {
    final filePath = p.join(documentsDirectoryPath, 'vault_entries.db');
    final db = await openDatabase(
      filePath,
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE $_table (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  username TEXT,
  url TEXT,
  android_packages TEXT,
  strength TEXT NOT NULL,
  reused INTEGER NOT NULL,
  encrypted_blob BLOB NOT NULL,
  nonce BLOB NOT NULL,
  mac BLOB NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
        await _createAttachmentsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN android_packages TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "UPDATE $_table SET category = 'login' WHERE category = 'app'",
          );
        }
        if (oldVersion < 4) {
          // Phase 9 — encrypted attachments. New table; per-file
          // ciphertext lives outside SQLite at
          // `<docs>/vault_attachments/<id>.bin`. No FK constraint
          // because sqflite has `foreign_keys` off by default and
          // turning it on retroactively is fragile. Repository
          // handles cascade-on-entry-delete manually.
          await _createAttachmentsTable(db);
        }
      },
    );
    return VaultDatabase._(db);
  }

  static Future<void> _createAttachmentsTable(Database db) async {
    await db.execute('''
CREATE TABLE $_attachmentsTable (
  id TEXT PRIMARY KEY NOT NULL,
  entry_id TEXT NOT NULL,
  name TEXT NOT NULL,
  mime TEXT NOT NULL,
  blob_size INTEGER NOT NULL,
  nonce BLOB NOT NULL,
  mac BLOB NOT NULL,
  created_at TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX idx_attachments_entry ON '
      '$_attachmentsTable(entry_id)',
    );
  }

  Future<List<Map<String, Object?>>> queryAllOrdered() async {
    return _db.query(
      _table,
      orderBy: 'updated_at DESC',
    );
  }

  Future<Map<String, Object?>?> queryById(String id) async {
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> insertRow(Map<String, Object?> row) async {
    await _db.insert(_table, row);
  }

  Future<void> updateRow(Map<String, Object?> row) async {
    final id = row['id'] as String;
    await _db.update(
      _table,
      row,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteById(String id) async {
    return _db.delete(
      _table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAll() async {
    await _db.delete(_table);
    await _db.delete(_attachmentsTable);
  }

  // ---------- Attachments ----------

  /// All attachment rows for [entryId], ordered by creation time.
  Future<List<Map<String, Object?>>> attachmentsForEntry(
    String entryId,
  ) async {
    return _db.query(
      _attachmentsTable,
      where: 'entry_id = ?',
      whereArgs: [entryId],
      orderBy: 'created_at ASC',
    );
  }

  /// All attachments across the vault — used by backup export.
  Future<List<Map<String, Object?>>> allAttachments() async {
    return _db.query(_attachmentsTable, orderBy: 'created_at ASC');
  }

  Future<void> insertAttachment(Map<String, Object?> row) async {
    await _db.insert(_attachmentsTable, row);
  }

  Future<int> deleteAttachmentById(String id) async {
    return _db.delete(
      _attachmentsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Removes every attachment row whose `entry_id` matches and returns
  /// the deleted ids so the caller can also remove the on-disk
  /// ciphertext files. Used by the repository's cascade-delete path
  /// when an entry (or batch of entries) is removed.
  Future<List<String>> deleteAttachmentsForEntry(String entryId) async {
    final rows = await _db.query(
      _attachmentsTable,
      columns: ['id'],
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );
    if (rows.isEmpty) return const <String>[];
    await _db.delete(
      _attachmentsTable,
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );
    return rows.map((r) => r['id']! as String).toList(growable: false);
  }

  Future<void> close() async {
    await _db.close();
  }
}
