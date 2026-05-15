import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/services/password_generator_service.dart';

void main() {
  group('PasswordGenerator', () {
    final gen = PasswordGenerator();

    test('respects requested length', () {
      for (final len in [8, 16, 32, 64]) {
        expect(gen.generate(length: len).length, len);
      }
    });

    test('returns empty when no pools enabled', () {
      final out = gen.generate(
        length: 16,
        useLowercase: false,
        useUppercase: false,
        useDigits: false,
        useSymbols: false,
      );
      expect(out, isEmpty);
    });

    test('returns empty when length is zero or negative', () {
      expect(gen.generate(length: 0), isEmpty);
      expect(gen.generate(length: -3), isEmpty);
    });

    test('only contains chars from enabled pools (digits only)', () {
      final out = gen.generate(
        length: 32,
        useLowercase: false,
        useUppercase: false,
        useDigits: true,
        useSymbols: false,
      );
      expect(RegExp(r'^\d+$').hasMatch(out), isTrue, reason: out);
    });

    test('respects custom symbols', () {
      final out = gen.generate(
        length: 64,
        useLowercase: false,
        useUppercase: false,
        useDigits: false,
        useSymbols: true,
        customSymbols: '@#',
      );
      expect(RegExp(r'^[@#]+$').hasMatch(out), isTrue, reason: out);
    });

    test('falls back when symbols enabled but custom set is empty', () {
      final out = gen.generate(
        length: 16,
        useLowercase: true,
        useUppercase: false,
        useDigits: false,
        useSymbols: true,
        customSymbols: '   ',
      );
      expect(out.length, 16);
      expect(RegExp(r'^[a-z]+$').hasMatch(out), isTrue, reason: out);
    });

    test('returns empty when only symbols enabled with empty custom set', () {
      final out = gen.generate(
        length: 16,
        useLowercase: false,
        useUppercase: false,
        useDigits: false,
        useSymbols: true,
        customSymbols: '',
      );
      expect(out, isEmpty);
    });

    test('contains at least one char from each enabled pool', () {
      // Use a deterministic seed so the assertion is stable.
      final seeded = PasswordGenerator(random: Random(42));
      for (var i = 0; i < 50; i++) {
        final out = seeded.generate(
          length: 20,
          useLowercase: true,
          useUppercase: true,
          useDigits: true,
          useSymbols: true,
          customSymbols: '!@#',
        );
        expect(RegExp(r'[a-z]').hasMatch(out), isTrue, reason: out);
        expect(RegExp(r'[A-Z]').hasMatch(out), isTrue, reason: out);
        expect(RegExp(r'\d').hasMatch(out), isTrue, reason: out);
        expect(RegExp(r'[!@#]').hasMatch(out), isTrue, reason: out);
      }
    });

    test('two consecutive calls almost certainly differ', () {
      final a = gen.generate(length: 32);
      final b = gen.generate(length: 32);
      expect(a == b, isFalse);
    });

    test('dedupes whitespace and repeats from custom symbols', () {
      final out = gen.generate(
        length: 24,
        useLowercase: false,
        useUppercase: false,
        useDigits: false,
        useSymbols: true,
        customSymbols: '!! @@ ##',
      );
      expect(RegExp(r'^[!@#]+$').hasMatch(out), isTrue, reason: out);
    });
  });
}
