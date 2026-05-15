import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/vault_meta.dart' show WrappedSecret;
import 'crypto_service.dart';

/// Encrypted file storage for vault attachments. Each attachment's
/// ciphertext lives at `<docs>/vault_attachments/<id>.bin`; metadata
/// (id, name, mime, blob_size, nonce, mac) sits in the SQL
/// `attachments` table next to the entries DB.
///
/// Crypto runs on a background isolate when the payload is large
/// enough that a synchronous AES-GCM pass would block the UI thread
/// long enough to drop frames — see [_isolateThresholdBytes]. Below
/// that threshold the wrap/unwrap happens inline.
class AttachmentService {
  AttachmentService({
    CryptoService? crypto,
    Future<String> Function()? documentsDirectoryResolver,
  }) : _crypto = crypto ?? CryptoService(),
       _documentsDirectoryResolver =
           documentsDirectoryResolver ?? _defaultDocumentsResolver;

  final CryptoService _crypto;
  final Future<String> Function() _documentsDirectoryResolver;

  /// Files at or above this size encrypt / decrypt on a background
  /// isolate. 1 MiB is the sweet spot empirically — below it a
  /// `Isolate.run` round-trip costs more than the AES pass, above it
  /// the UI thread visibly stutters during the encrypt.
  static const int _isolateThresholdBytes = 1024 * 1024;

  /// Soft warning shown by the UI when a single attachment exceeds
  /// this size. Not a hard cap — local-only storage means the user
  /// can keep going if they accept the brief encrypt latency.
  static const int softWarningBytes = 25 * 1024 * 1024;

  /// AES-GCM nonce length in bytes (the `cryptography` package's
  /// default). Mirrored here for tests + sanity checks.
  static const int nonceLength = 12;

  /// Name of the directory under app-documents that holds per-file
  /// ciphertext. Exposed so settings/wipe and tests can find it.
  static const String directoryName = 'vault_attachments';

  static Future<String> _defaultDocumentsResolver() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// Encrypts [bytes] under [vmk] and writes the ciphertext to a fresh
  /// per-attachment file. Returns the metadata the caller will INSERT
  /// into the SQL `attachments` table.
  Future<EncryptResult> encryptAndStore({
    required SecretKey vmk,
    required Uint8List bytes,
    String? id,
  }) async {
    final attachmentId = id ?? _newId();
    final wrapped = await _wrap(bytes, vmk);
    final file = File(await _filePath(attachmentId));
    await file.parent.create(recursive: true);
    // `writeAsBytes` is async-IO; the ciphertext is opaque so no special
    // handling needed beyond the standard write.
    await file.writeAsBytes(wrapped.ciphertext, flush: true);
    return EncryptResult(
      id: attachmentId,
      nonce: wrapped.nonce,
      mac: wrapped.mac,
      blobSize: bytes.length,
    );
  }

  /// Reads + decrypts the ciphertext for [id] using [nonce] / [mac]
  /// from the SQL row. Returns the plaintext bytes for in-memory
  /// display; nothing is persisted to disk by this call.
  Future<Uint8List> decrypt({
    required SecretKey vmk,
    required String id,
    required Uint8List nonce,
    required Uint8List mac,
  }) async {
    final file = File(await _filePath(id));
    if (!await file.exists()) {
      throw StateError('attachment file missing: $id');
    }
    final ciphertext = await file.readAsBytes();
    return _unwrap(
      ciphertext: ciphertext,
      nonce: nonce,
      mac: mac,
      vmk: vmk,
    );
  }

  /// Removes the ciphertext file for [id]. Caller is responsible for
  /// deleting the SQL row (kept separate so test code can wipe files
  /// without touching the DB).
  Future<void> deleteFile(String id) async {
    final file = File(await _filePath(id));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Recursively wipes the attachments directory. Called from the
  /// "Wipe vault" flow alongside the existing meta + DB cleanup.
  Future<void> wipeAll() async {
    final dir = Directory(await _directoryPath());
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Public path resolver — backup_service uses this to read ciphertext
  /// directly from disk during export.
  Future<String> filePathFor(String id) => _filePath(id);

  /// Public directory resolver for tests / settings.
  Future<String> directoryPath() => _directoryPath();

  // ---------- internals ----------

  Future<String> _directoryPath() async {
    final docs = await _documentsDirectoryResolver();
    return p.join(docs, directoryName);
  }

  Future<String> _filePath(String id) async {
    return p.join(await _directoryPath(), '$id.bin');
  }

  Future<_Wrapped> _wrap(Uint8List bytes, SecretKey vmk) async {
    if (bytes.length < _isolateThresholdBytes) {
      final w = await _crypto.wrap(plaintext: bytes, key: vmk);
      return _Wrapped(
        nonce: w.nonce,
        ciphertext: w.ciphertext,
        mac: w.mac,
      );
    }
    final vmkBytes = Uint8List.fromList(
      await vmk.extractBytes(),
    );
    final result = await Isolate.run(
      () => _isolateEncrypt(bytes, vmkBytes),
    );
    return result;
  }

  Future<Uint8List> _unwrap({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required Uint8List mac,
    required SecretKey vmk,
  }) async {
    if (ciphertext.length < _isolateThresholdBytes) {
      final w = WrappedSecret(
        nonce: nonce,
        ciphertext: ciphertext,
        mac: mac,
      );
      return _crypto.unwrap(wrapped: w, key: vmk);
    }
    final vmkBytes = Uint8List.fromList(
      await vmk.extractBytes(),
    );
    return Isolate.run(
      () => _isolateDecrypt(ciphertext, nonce, mac, vmkBytes),
    );
  }

  String _newId() {
    // Same ID shape as VaultEntry — 16 random bytes hex-encoded.
    // No collision protection beyond random chance; the caller
    // INSERT into a PK column will fail loud if it ever happens.
    final rnd = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

/// Result returned to the repository so it can build the SQL row.
class EncryptResult {
  final String id;
  final Uint8List nonce;
  final Uint8List mac;
  final int blobSize;

  const EncryptResult({
    required this.id,
    required this.nonce,
    required this.mac,
    required this.blobSize,
  });
}

class _Wrapped {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
  const _Wrapped({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });
}

// Top-level so they can run in `Isolate.run`. They take pure
// `Uint8List`s and return same — no SecretKey instances cross the
// isolate boundary (we recreate one from raw bytes on the other
// side). DartAesGcm is pure-Dart and isolate-safe.

Future<_Wrapped> _isolateEncrypt(Uint8List bytes, Uint8List vmkBytes) async {
  final aes = AesGcm.with256bits();
  final box = await aes.encrypt(bytes, secretKey: SecretKey(vmkBytes));
  return _Wrapped(
    nonce: Uint8List.fromList(box.nonce),
    ciphertext: Uint8List.fromList(box.cipherText),
    mac: Uint8List.fromList(box.mac.bytes),
  );
}

Future<Uint8List> _isolateDecrypt(
  Uint8List ciphertext,
  Uint8List nonce,
  Uint8List mac,
  Uint8List vmkBytes,
) async {
  final aes = AesGcm.with256bits();
  final box = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
  final clear = await aes.decrypt(box, secretKey: SecretKey(vmkBytes));
  return Uint8List.fromList(clear);
}
