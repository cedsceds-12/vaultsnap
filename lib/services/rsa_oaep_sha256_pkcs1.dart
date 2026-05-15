// RSAES-OAEP with SHA-256 OAEP hash + MGF1-SHA-1 per RFC 8017 (PKCS #1 v2.1).
// Matches Android: Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
// with OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA1,
// PSource.PSpecified.DEFAULT) — empty P label.
//
// MGF1 must be SHA-1: Android Keystore only authorizes SHA-1 for MGF1 by
// default and `setMgf1Digests` (API 34+) is not reliable across versions.
// RFC 8017 §B.2.1 explicitly allows different OAEP and MGF1 hashes; the
// security of OAEP rests on the OAEP hash (SHA-256), not MGF1.
//
// package:encrypt uses PointyCastle OAEPEncoding (PKCS #1 v2.0 / RFC 2437),
// which is not interoperable with Android's OAEP.

import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha256.dart';

/// Encrypts [message] under [publicKey] for Android Keystore RSA-OAEP decrypt.
///
/// D-4: best-effort zeroing of intermediate buffers (`seed`, `db`, `dbMask`,
/// `seedMask`, `maskedDb`, `maskedSeed`, `em`) before the function returns.
/// Dart heap allocations aren't deterministically wiped on GC, so this is a
/// hardening measure rather than a guarantee — but it shrinks the window in
/// which a memory dump could surface VMK-derived bytes.
Uint8List rsaOaepSha256Encrypt(RSAPublicKey publicKey, Uint8List message) {
  final hash = SHA256Digest();
  final hLen = hash.digestSize;

  final modulus = publicKey.modulus!;
  final k = (modulus.bitLength + 7) >> 3;
  if (message.length > k - 2 * hLen - 2) {
    throw ArgumentError('message too long for RSA-OAEP ($k-byte key)');
  }

  final lHash = _hashSha256(hash, Uint8List(0));

  final psLen = k - message.length - 2 * hLen - 2;
  final dbLen = k - hLen - 1;
  final db = Uint8List(dbLen);
  final seed = Uint8List(hLen);
  final maskedDb = Uint8List(dbLen);
  final maskedSeed = Uint8List(hLen);
  final em = Uint8List(k);

  try {
    var o = 0;
    db.setRange(o, o + hLen, lHash);
    o += hLen;
    o += psLen;
    db[o] = 0x01;
    o += 1;
    db.setRange(o, o + message.length, message);

    _fillSecureRandom(seed);

    final dbMask = _mgf1Sha1(seed, k - hLen - 1);
    try {
      for (var i = 0; i < dbLen; i++) {
        maskedDb[i] = db[i] ^ dbMask[i];
      }
    } finally {
      dbMask.fillRange(0, dbMask.length, 0);
    }

    final seedMask = _mgf1Sha1(maskedDb, hLen);
    try {
      for (var i = 0; i < hLen; i++) {
        maskedSeed[i] = seed[i] ^ seedMask[i];
      }
    } finally {
      seedMask.fillRange(0, seedMask.length, 0);
    }

    em[0] = 0x00;
    em.setRange(1, 1 + hLen, maskedSeed);
    em.setRange(1 + hLen, k, maskedDb);

    final engine = RSAEngine()
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return engine.process(em);
  } finally {
    db.fillRange(0, db.length, 0);
    seed.fillRange(0, seed.length, 0);
    maskedDb.fillRange(0, maskedDb.length, 0);
    maskedSeed.fillRange(0, maskedSeed.length, 0);
    em.fillRange(0, em.length, 0);
  }
}

Uint8List _hashSha256(SHA256Digest hash, Uint8List data) {
  final out = Uint8List(hash.digestSize);
  hash.reset();
  hash.update(data, 0, data.length);
  hash.doFinal(out, 0);
  return out;
}

/// MGF1 with SHA-1 (RFC 8017 §B.2.1). Matches Android Keystore's default MGF1.
Uint8List _mgf1Sha1(Uint8List mgfSeed, int maskLen) {
  final hash = SHA1Digest();
  final hLen = hash.digestSize;
  final mask = Uint8List(maskLen);
  var counter = 0;
  var offset = 0;
  final counterBytes = Uint8List(4);
  final digestBuf = Uint8List(hLen);

  while (offset < maskLen) {
    _i2osp4(counter, counterBytes);
    hash.reset();
    hash.update(mgfSeed, 0, mgfSeed.length);
    hash.update(counterBytes, 0, 4);
    hash.doFinal(digestBuf, 0);
    final take = (offset + hLen <= maskLen) ? hLen : maskLen - offset;
    mask.setRange(offset, offset + take, digestBuf, 0);
    offset += take;
    counter++;
  }
  digestBuf.fillRange(0, digestBuf.length, 0);
  return mask;
}

void _i2osp4(int i, Uint8List out) {
  out[0] = (i >> 24) & 0xff;
  out[1] = (i >> 16) & 0xff;
  out[2] = (i >> 8) & 0xff;
  out[3] = i & 0xff;
}

void _fillSecureRandom(Uint8List bytes) {
  final r = Random.secure();
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = r.nextInt(256);
  }
}
