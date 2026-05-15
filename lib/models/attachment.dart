import 'dart:typed_data';

/// Cleartext metadata for an encrypted attachment file. The actual bytes
/// live at `<docs>/vault_attachments/<id>.bin` as AES-GCM ciphertext
/// under the VMK; this row holds the [nonce] + [mac] needed to decrypt
/// it plus the user-facing filename / mime / size.
///
/// Mirrors the [VaultEntry] convention: SQL-column metadata stays in
/// cleartext for list rendering and backup, the secret material (the
/// file bytes) is encrypted under VMK and never lives in this row.
class VaultAttachment {
  final String id;
  final String entryId;
  final String name;
  final String mime;
  final int blobSize;
  final Uint8List nonce;
  final Uint8List mac;
  final DateTime createdAt;

  const VaultAttachment({
    required this.id,
    required this.entryId,
    required this.name,
    required this.mime,
    required this.blobSize,
    required this.nonce,
    required this.mac,
    required this.createdAt,
  });

  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';

  factory VaultAttachment.fromDatabaseRow(Map<String, Object?> row) {
    return VaultAttachment(
      id: row['id']! as String,
      entryId: row['entry_id']! as String,
      name: row['name']! as String,
      mime: row['mime']! as String,
      blobSize: (row['blob_size']! as num).toInt(),
      nonce: row['nonce']! as Uint8List,
      mac: row['mac']! as Uint8List,
      createdAt:
          DateTime.parse(row['created_at']! as String).toUtc(),
    );
  }

  Map<String, Object?> toDatabaseRow() {
    return {
      'id': id,
      'entry_id': entryId,
      'name': name,
      'mime': mime,
      'blob_size': blobSize,
      'nonce': nonce,
      'mac': mac,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
