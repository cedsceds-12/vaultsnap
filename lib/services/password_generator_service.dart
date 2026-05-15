import 'dart:math';

/// Pure-Dart cryptographically random password generator.
///
/// Uses [Random.secure] so the output is suitable for credentials.
/// All character classes are opt-in; if at least one class is enabled
/// and [length] permits, the output is guaranteed to contain at least
/// one character from every enabled class.
class PasswordGenerator {
  static const String lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String digits = '0123456789';

  /// Default symbol set — common, broadly accepted by most websites.
  static const String defaultSymbols = r'!@#$%&*';

  final Random _random;

  PasswordGenerator({Random? random}) : _random = random ?? Random.secure();

  String generate({
    required int length,
    bool useLowercase = true,
    bool useUppercase = true,
    bool useDigits = true,
    bool useSymbols = true,
    String customSymbols = defaultSymbols,
  }) {
    if (length <= 0) return '';

    final pools = <String>[];
    if (useLowercase) pools.add(lowercase);
    if (useUppercase) pools.add(uppercase);
    if (useDigits) pools.add(digits);
    if (useSymbols) {
      final cleaned = _sanitizeSymbols(customSymbols);
      if (cleaned.isNotEmpty) pools.add(cleaned);
    }
    if (pools.isEmpty) return '';

    final chars = <String>[];
    for (final pool in pools) {
      if (chars.length >= length) break;
      chars.add(_pick(pool));
    }

    final all = pools.join();
    while (chars.length < length) {
      chars.add(_pick(all));
    }

    chars.shuffle(_random);
    return chars.join();
  }

  /// Strip whitespace and duplicate characters from a user-supplied symbol set.
  static String _sanitizeSymbols(String input) {
    final seen = <int>{};
    final out = StringBuffer();
    for (final code in input.runes) {
      if (code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D) {
        continue;
      }
      if (seen.add(code)) {
        out.writeCharCode(code);
      }
    }
    return out.toString();
  }

  String _pick(String pool) => pool[_random.nextInt(pool.length)];
}
