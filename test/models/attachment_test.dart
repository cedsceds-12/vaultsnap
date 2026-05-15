import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/models/attachment.dart';

void main() {
  test('toDatabaseRow / fromDatabaseRow roundtrip preserves binary blobs',
      () {
    final created = DateTime.utc(2026, 5, 1, 12, 0, 0);
    final att = VaultAttachment(
      id: 'abc123',
      entryId: 'entry-1',
      name: 'passport.pdf',
      mime: 'application/pdf',
      blobSize: 12345,
      nonce: Uint8List.fromList(List<int>.generate(12, (i) => i)),
      mac: Uint8List.fromList(List<int>.generate(16, (i) => i + 100)),
      createdAt: created,
    );

    final row = att.toDatabaseRow();
    final back = VaultAttachment.fromDatabaseRow(row);

    expect(back.id, att.id);
    expect(back.entryId, att.entryId);
    expect(back.name, att.name);
    expect(back.mime, att.mime);
    expect(back.blobSize, att.blobSize);
    expect(back.nonce, att.nonce);
    expect(back.mac, att.mac);
    expect(back.createdAt, created);
  });

  test('mime convenience getters', () {
    final image = VaultAttachment(
      id: 'a',
      entryId: 'e',
      name: 'x.png',
      mime: 'image/png',
      blobSize: 0,
      nonce: Uint8List(12),
      mac: Uint8List(16),
      createdAt: DateTime.utc(2026, 1, 1),
    );
    expect(image.isImage, isTrue);
    expect(image.isPdf, isFalse);

    final pdf = VaultAttachment(
      id: 'b',
      entryId: 'e',
      name: 'x.pdf',
      mime: 'application/pdf',
      blobSize: 0,
      nonce: Uint8List(12),
      mac: Uint8List(16),
      createdAt: DateTime.utc(2026, 1, 1),
    );
    expect(pdf.isImage, isFalse);
    expect(pdf.isPdf, isTrue);
  });
}
