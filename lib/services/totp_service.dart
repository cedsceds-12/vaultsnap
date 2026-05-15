import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter;
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/macs/hmac.dart';

/// HMAC algorithm choices for TOTP. Most issuers use SHA-1; some (Steam,
/// banks) use SHA-256 or SHA-512.
enum TotpAlgorithm { sha1, sha256, sha512 }

/// Parsed `otpauth://totp/...` parameters. The [secret] is the raw bytes
/// after base32 decode — never base32-encoded text — so the generator
/// doesn't have to re-decode on every tick.
class TotpSpec {
  final List<int> secret;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;
  final String? issuer;
  final String? account;

  const TotpSpec({
    required this.secret,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.issuer,
    this.account,
  });
}

/// RFC 6238 TOTP generator + `otpauth://` URI parser. Pure Dart, no Flutter.
///
/// Crypto via `package:pointycastle` (already a project dep — used elsewhere
/// for RSA-OAEP). No new dependency required for this phase.
///
/// Throws nothing on bad input — invalid base32 / unknown algorithm / missing
/// secret produce `null` from [parseUri] and an empty string from
/// [generateCode] when given a corrupt [TotpSpec], so UI code can fall back
/// gracefully instead of catching exceptions on every rebuild.
class TotpService {
  TotpService._();

  /// RFC 6238 §4 / RFC 4226 §5: HOTP truncation against `T = floor(now / period)`.
  /// [now] is exposed only for tests — in production callers omit it.
  static String generateCode(TotpSpec spec, {DateTime? now}) {
    if (spec.secret.isEmpty) return '';
    final t = _counter(spec.period, now: now);
    final mac = _hmac(spec.algorithm, spec.secret, _bigEndian64(t));
    // Dynamic truncation (RFC 4226 §5.3): pick the 4-byte window starting
    // at the offset encoded in the low nibble of the last MAC byte, mask
    // off the top bit (sign), then take the last [digits] base-10 digits.
    final offset = mac[mac.length - 1] & 0x0f;
    final binary = ((mac[offset] & 0x7f) << 24) |
        ((mac[offset + 1] & 0xff) << 16) |
        ((mac[offset + 2] & 0xff) << 8) |
        (mac[offset + 3] & 0xff);
    final modulus = _powTen(spec.digits);
    final code = binary % modulus;
    return code.toString().padLeft(spec.digits, '0');
  }

  /// Whole seconds remaining in the current TOTP step. Used for the
  /// Authenticator tab's period ring countdown.
  static int secondsRemaining(int period, {DateTime? now}) {
    final n = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return period - (n % period);
  }

  /// 0.0 → just-rolled-over, 1.0 → about to roll over. Inverse of
  /// [secondsRemaining]/[period]; useful for `CustomPaint` arcs.
  static double progress(int period, {DateTime? now}) {
    if (period <= 0) return 0;
    final n = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;
    final phase = (n % period) / period;
    return phase.clamp(0.0, 1.0);
  }

  /// Parses an `otpauth://totp/{label}?secret=…&issuer=…&algorithm=SHA1
  /// &digits=6&period=30` URI per the de-facto Google Authenticator spec
  /// (https://github.com/google/google-authenticator/wiki/Key-Uri-Format).
  ///
  /// Returns `null` for any kind of malformed input (wrong scheme, wrong
  /// host, missing/invalid secret, unknown algorithm) so the calling UI
  /// can show a clean "not a valid otpauth URI" error without try/catch.
  static TotpSpec? parseUri(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return null;
    }
    if (uri.scheme.toLowerCase() != 'otpauth') return null;
    if (uri.host.toLowerCase() != 'totp') return null;

    final params = uri.queryParameters;
    final rawSecret = params['secret'];
    if (rawSecret == null || rawSecret.isEmpty) return null;

    final List<int> secret;
    try {
      secret = decodeBase32(rawSecret);
    } catch (_) {
      return null;
    }
    if (secret.isEmpty) return null;

    final algoRaw = params['algorithm']?.toUpperCase() ?? 'SHA1';
    final algorithm = switch (algoRaw) {
      'SHA1' => TotpAlgorithm.sha1,
      'SHA256' => TotpAlgorithm.sha256,
      'SHA512' => TotpAlgorithm.sha512,
      _ => null,
    };
    if (algorithm == null) return null;

    final digits = int.tryParse(params['digits'] ?? '6') ?? 6;
    if (digits != 6 && digits != 8) return null;

    final period = int.tryParse(params['period'] ?? '30') ?? 30;
    if (period <= 0 || period > 600) return null;

    // Label format: "Issuer:Account" or just "Account". The path starts
    // with a leading "/" we strip first. Issuer query param wins over
    // the label-prefix issuer when both are present (Google AGW behaviour).
    final pathLabel = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final decodedLabel = Uri.decodeComponent(pathLabel);
    String? labelIssuer;
    String? labelAccount;
    final colon = decodedLabel.indexOf(':');
    if (colon >= 0) {
      labelIssuer = decodedLabel.substring(0, colon).trim();
      labelAccount = decodedLabel.substring(colon + 1).trim();
    } else if (decodedLabel.isNotEmpty) {
      labelAccount = decodedLabel;
    }
    final issuerParam = params['issuer']?.trim();
    final issuer = (issuerParam != null && issuerParam.isNotEmpty)
        ? issuerParam
        : (labelIssuer != null && labelIssuer.isNotEmpty ? labelIssuer : null);
    final account =
        (labelAccount != null && labelAccount.isNotEmpty) ? labelAccount : null;

    return TotpSpec(
      secret: secret,
      algorithm: algorithm,
      digits: digits,
      period: period,
      issuer: issuer,
      account: account,
    );
  }

  /// RFC 4648 §6 base32 decoder. Tolerates lowercase, ignores whitespace
  /// and `=` padding (Google Authenticator URIs sometimes drop padding).
  /// Throws [FormatException] on illegal characters — callers that want
  /// graceful failure go through [parseUri] which catches it.
  static List<int> decodeBase32(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('=', '')
        .toUpperCase();
    if (cleaned.isEmpty) return const <int>[];

    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (var i = 0; i < cleaned.length; i++) {
      final c = cleaned[i];
      final v = alphabet.indexOf(c);
      if (v < 0) {
        throw FormatException('Invalid base32 character "$c"', input, i);
      }
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return out;
  }

  // ------------------------- internals -------------------------

  static int _counter(int period, {DateTime? now}) {
    final secs = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return secs ~/ period;
  }

  static Uint8List _bigEndian64(int value) {
    final bytes = Uint8List(8);
    var v = value;
    for (var i = 7; i >= 0; i--) {
      bytes[i] = v & 0xff;
      v >>>= 8;
    }
    return bytes;
  }

  static Uint8List _hmac(
    TotpAlgorithm algo,
    List<int> key,
    Uint8List message,
  ) {
    final digest = switch (algo) {
      TotpAlgorithm.sha1 => SHA1Digest(),
      TotpAlgorithm.sha256 => SHA256Digest(),
      TotpAlgorithm.sha512 => SHA512Digest(),
    };
    // pointycastle HMac block sizes are detected from the digest itself;
    // RFC 2104 padding is handled internally.
    final mac = HMac.withDigest(digest)
      ..init(KeyParameter(Uint8List.fromList(key)));
    final out = Uint8List(mac.macSize);
    mac.update(message, 0, message.length);
    mac.doFinal(out, 0);
    return out;
  }

  static int _powTen(int n) {
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}
