import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:vault_snap/services/rsa_oaep_sha256_pkcs1.dart';

void main() {
  test('RSA-OAEP encrypt output size matches modulus (1024-bit)', () {
    final rnd = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i + 1))));

    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 1024, 64),
          rnd,
        ),
      );

    final pair = keyGen.generateKeyPair();
    final pub = pair.publicKey as RSAPublicKey;
    final k = (pub.modulus!.bitLength + 7) >> 3;

    final ct = rsaOaepSha256Encrypt(pub, Uint8List(32));
    expect(ct.length, k);
  });
}
