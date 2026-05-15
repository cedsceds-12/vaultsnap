import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/services/totp_service.dart';

void main() {
  group('TotpService — RFC 6238 Appendix B vectors', () {
    // Per RFC 6238 §B, the test seeds are ASCII strings used directly as the
    // HMAC key. (Real TOTP keys are random bytes; the RFC uses this readable
    // form to make verification easier.)
    final seedSha1 = utf8.encode('12345678901234567890');
    final seedSha256 = utf8.encode('12345678901234567890123456789012');
    final seedSha512 =
        utf8.encode('1234567890123456789012345678901234567890123456789012345678901234');

    final cases = <_Vector>[
      _Vector(t: 59, sha1: '94287082', sha256: '46119246', sha512: '90693936'),
      _Vector(t: 1111111109, sha1: '07081804', sha256: '68084774', sha512: '25091201'),
      _Vector(t: 1111111111, sha1: '14050471', sha256: '67062674', sha512: '99943326'),
      _Vector(t: 1234567890, sha1: '89005924', sha256: '91819424', sha512: '93441116'),
      _Vector(t: 2000000000, sha1: '69279037', sha256: '90698825', sha512: '38618901'),
      _Vector(t: 20000000000, sha1: '65353130', sha256: '77737706', sha512: '47863826'),
    ];

    for (final c in cases) {
      test('T=${c.t}', () {
        // The RFC vectors are 8-digit codes computed at the given Unix time
        // with a 30-second step. Build a DateTime at exactly t * 1000 ms.
        final at = DateTime.fromMillisecondsSinceEpoch(c.t * 1000, isUtc: true);

        expect(
          TotpService.generateCode(
            TotpSpec(
              secret: seedSha1,
              algorithm: TotpAlgorithm.sha1,
              digits: 8,
            ),
            now: at,
          ),
          c.sha1,
          reason: 'SHA1 mismatch at T=${c.t}',
        );
        expect(
          TotpService.generateCode(
            TotpSpec(
              secret: seedSha256,
              algorithm: TotpAlgorithm.sha256,
              digits: 8,
            ),
            now: at,
          ),
          c.sha256,
          reason: 'SHA256 mismatch at T=${c.t}',
        );
        expect(
          TotpService.generateCode(
            TotpSpec(
              secret: seedSha512,
              algorithm: TotpAlgorithm.sha512,
              digits: 8,
            ),
            now: at,
          ),
          c.sha512,
          reason: 'SHA512 mismatch at T=${c.t}',
        );
      });
    }
  });

  group('TotpService — six-digit codes', () {
    test('JBSWY3DPEHPK3PXP at T=0 matches Google Authenticator reference', () {
      // Canonical "JBSWY3DPEHPK3PXP" (= ASCII "Hello!\xDE\xAD\xBE\xEF") is
      // the most common smoke-test secret. At T=0 (1970-01-01), the SHA1/30/6
      // code is "282760" — verifiable in any other authenticator app.
      final spec = TotpSpec(
        secret: TotpService.decodeBase32('JBSWY3DPEHPK3PXP'),
        algorithm: TotpAlgorithm.sha1,
      );
      final code = TotpService.generateCode(
        spec,
        now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(code, '282760');
      expect(code.length, 6);
    });

    test('empty secret returns empty string (no exception)', () {
      final code = TotpService.generateCode(
        const TotpSpec(secret: <int>[]),
      );
      expect(code, '');
    });
  });

  group('TotpService.parseUri', () {
    test('happy path with all params', () {
      final spec = TotpService.parseUri(
        'otpauth://totp/ACME%20Co:alice@example.com'
        '?secret=JBSWY3DPEHPK3PXP'
        '&issuer=ACME%20Co'
        '&algorithm=SHA256'
        '&digits=8'
        '&period=60',
      );
      expect(spec, isNotNull);
      expect(spec!.algorithm, TotpAlgorithm.sha256);
      expect(spec.digits, 8);
      expect(spec.period, 60);
      expect(spec.issuer, 'ACME Co');
      expect(spec.account, 'alice@example.com');
      expect(spec.secret, isNotEmpty);
    });

    test('defaults applied when params missing', () {
      final spec = TotpService.parseUri(
        'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP',
      );
      expect(spec, isNotNull);
      expect(spec!.algorithm, TotpAlgorithm.sha1);
      expect(spec.digits, 6);
      expect(spec.period, 30);
    });

    test('rejects wrong scheme', () {
      expect(TotpService.parseUri('https://example.com'), isNull);
    });

    test('rejects HOTP host (out of scope)', () {
      expect(
        TotpService.parseUri('otpauth://hotp/Test?secret=JBSWY3DPEHPK3PXP&counter=1'),
        isNull,
      );
    });

    test('rejects missing secret', () {
      expect(TotpService.parseUri('otpauth://totp/Test'), isNull);
    });

    test('rejects unknown algorithm', () {
      expect(
        TotpService.parseUri(
          'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&algorithm=MD5',
        ),
        isNull,
      );
    });

    test('rejects illegal digit count', () {
      expect(
        TotpService.parseUri(
          'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&digits=7',
        ),
        isNull,
      );
    });

    test('rejects garbage base32 secret', () {
      expect(
        TotpService.parseUri('otpauth://totp/Test?secret=NOT_BASE_32!!'),
        isNull,
      );
    });

    test('issuer query param wins over label-prefix issuer', () {
      final spec = TotpService.parseUri(
        'otpauth://totp/OldCo:alice?secret=JBSWY3DPEHPK3PXP&issuer=NewCo',
      );
      expect(spec!.issuer, 'NewCo');
      expect(spec.account, 'alice');
    });

    test('label without colon is treated as account only', () {
      final spec = TotpService.parseUri(
        'otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP',
      );
      expect(spec!.account, 'alice');
      expect(spec.issuer, isNull);
    });
  });

  group('TotpService.decodeBase32', () {
    // RFC 4648 §10 vectors against ASCII inputs.
    test('empty', () => expect(TotpService.decodeBase32(''), isEmpty));

    test('"f" → MY', () {
      expect(TotpService.decodeBase32('MY'), [0x66]);
    });

    test('"fo" → MZXQ', () {
      expect(TotpService.decodeBase32('MZXQ'), [0x66, 0x6f]);
    });

    test('"foo" → MZXW6', () {
      expect(TotpService.decodeBase32('MZXW6'), [0x66, 0x6f, 0x6f]);
    });

    test('"foob" → MZXW6YQ', () {
      expect(
        TotpService.decodeBase32('MZXW6YQ'),
        [0x66, 0x6f, 0x6f, 0x62],
      );
    });

    test('"fooba" → MZXW6YTB', () {
      expect(
        TotpService.decodeBase32('MZXW6YTB'),
        [0x66, 0x6f, 0x6f, 0x62, 0x61],
      );
    });

    test('"foobar" → MZXW6YTBOI', () {
      expect(
        TotpService.decodeBase32('MZXW6YTBOI'),
        [0x66, 0x6f, 0x6f, 0x62, 0x61, 0x72],
      );
    });

    test('lowercase is normalized', () {
      expect(TotpService.decodeBase32('mzxw6ytboi'), [
        0x66, 0x6f, 0x6f, 0x62, 0x61, 0x72,
      ]);
    });

    test('whitespace and `=` padding are tolerated', () {
      expect(TotpService.decodeBase32('MZXW 6YT BOI=='), [
        0x66, 0x6f, 0x6f, 0x62, 0x61, 0x72,
      ]);
    });

    test('illegal character throws FormatException', () {
      expect(
        () => TotpService.decodeBase32('MZXW1YTBOI'),
        throwsFormatException,
      );
    });
  });

  group('TotpService.secondsRemaining / progress', () {
    test('at T=0 of a 30s step → 30s remaining, 0.0 progress', () {
      final at = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      expect(TotpService.secondsRemaining(30, now: at), 30);
      expect(TotpService.progress(30, now: at), closeTo(0.0, 1e-9));
    });

    test('mid-step values are sane', () {
      final at = DateTime.fromMillisecondsSinceEpoch(15 * 1000, isUtc: true);
      expect(TotpService.secondsRemaining(30, now: at), 15);
      expect(TotpService.progress(30, now: at), closeTo(0.5, 1e-9));
    });

    test('progress wraps to 0 at the next step boundary', () {
      final at = DateTime.fromMillisecondsSinceEpoch(30 * 1000, isUtc: true);
      expect(TotpService.secondsRemaining(30, now: at), 30);
      expect(TotpService.progress(30, now: at), closeTo(0.0, 1e-9));
    });
  });
}

class _Vector {
  final int t;
  final String sha1;
  final String sha256;
  final String sha512;
  const _Vector({
    required this.t,
    required this.sha1,
    required this.sha256,
    required this.sha512,
  });
}
