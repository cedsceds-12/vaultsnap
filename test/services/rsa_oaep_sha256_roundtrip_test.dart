import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/src/utils.dart' as utils;
import 'package:vault_snap/services/rsa_oaep_sha256_pkcs1.dart';

/// RFC 8017 RSAES-OAEP decode with SHA-256 OAEP digest + MGF1-SHA-1
/// (mirrors Android Keystore OAEP decrypt after raw RSA).
Uint8List _oaepSha256MgfSha1Decode(Uint8List em) {
  final oaepHash = SHA256Digest();
  final hLen = oaepHash.digestSize;
  final k = em.length;
  if (em[0] != 0) {
    throw StateError('OAEP: leading Y must be 0');
  }
  final maskedSeed = em.sublist(1, 1 + hLen);
  final maskedDb = em.sublist(1 + hLen, k);
  final dbLen = k - hLen - 1;

  final seedMask = _mgf1Sha1(maskedDb, hLen);
  final seed = Uint8List(hLen);
  for (var i = 0; i < hLen; i++) {
    seed[i] = maskedSeed[i] ^ seedMask[i];
  }

  final dbMask = _mgf1Sha1(seed, k - hLen - 1);
  final db = Uint8List(dbLen);
  for (var i = 0; i < dbLen; i++) {
    db[i] = maskedDb[i] ^ dbMask[i];
  }

  final lHash = Uint8List(hLen);
  oaepHash.reset();
  oaepHash.doFinal(lHash, 0);
  for (var i = 0; i < hLen; i++) {
    if (db[i] != lHash[i]) throw StateError('OAEP: lHash mismatch');
  }

  var idx = hLen;
  while (idx < dbLen && db[idx] == 0) {
    idx++;
  }
  if (idx >= dbLen || db[idx] != 0x01) {
    throw StateError('OAEP: missing 0x01');
  }
  idx++;
  return db.sublist(idx);
}

Uint8List _mgf1Sha1(Uint8List mgfSeed, int maskLen) {
  final hash = SHA1Digest();
  final hLen = hash.digestSize;
  final mask = Uint8List(maskLen);
  var counter = 0;
  var offset = 0;
  final counterBytes = Uint8List(4);
  final digestBuf = Uint8List(hLen);

  while (offset < maskLen) {
    counterBytes[0] = (counter >> 24) & 0xff;
    counterBytes[1] = (counter >> 16) & 0xff;
    counterBytes[2] = (counter >> 8) & 0xff;
    counterBytes[3] = counter & 0xff;
    hash.reset();
    hash.update(mgfSeed, 0, mgfSeed.length);
    hash.update(counterBytes, 0, 4);
    hash.doFinal(digestBuf, 0);
    final take = (offset + hLen <= maskLen) ? hLen : maskLen - offset;
    mask.setRange(offset, offset + take, digestBuf, 0);
    offset += take;
    counter++;
  }
  return mask;
}

Uint8List _i2osp(BigInt x, int k) {
  final raw = utils.encodeBigIntAsUnsigned(x);
  if (raw.length > k) {
    throw StateError('integer too large for $k bytes');
  }
  final out = Uint8List(k);
  out.setRange(k - raw.length, k, raw);
  return out;
}

Uint8List _rawRsaDecryptToEm(RSAPrivateKey priv, Uint8List ciphertext) {
  final n = priv.modulus!;
  final d = priv.privateExponent!;
  final c = utils.decodeBigIntWithSign(1, ciphertext);
  final m = c.modPow(d, n);
  final k = (n.bitLength + 7) >> 3;
  return _i2osp(m, k);
}

void main() {
  test('RSA-OAEP encrypt round-trips like Android decrypt (RFC 8017)', () {
    final rnd = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i + 3))));

    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
          rnd,
        ),
      );

    final pair = keyGen.generateKeyPair();
    final pub = pair.publicKey as RSAPublicKey;
    final priv = pair.privateKey as RSAPrivateKey;

    final vmk = Uint8List.fromList(List.generate(32, (i) => i ^ 0x5a));

    final ct = rsaOaepSha256Encrypt(pub, vmk);
    final em = _rawRsaDecryptToEm(priv, ct);
    final recovered = _oaepSha256MgfSha1Decode(em);

    expect(recovered, vmk);
  });
}
