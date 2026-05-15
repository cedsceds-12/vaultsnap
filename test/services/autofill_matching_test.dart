import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/services/autofill_matching.dart';
import 'package:vault_snap/services/public_suffix_list.dart';

void main() {
  group('normalizeHost', () {
    test('lowercase and strip www', () {
      expect(normalizeHost('WWW.Example.COM'), 'example.com');
    });
  });

  group('hostFromEntryUrl', () {
    test('https URL preserves full host (matching uses subdomain rules)', () {
      expect(
        hostFromEntryUrl('https://login.netflix.com/foo'),
        'login.netflix.com',
      );
    });
    test('bare host', () {
      expect(hostFromEntryUrl('netflix.com'), 'netflix.com');
    });
    test('empty', () {
      expect(hostFromEntryUrl(null), isNull);
      expect(hostFromEntryUrl(''), isNull);
    });
  });

  group('fillHostMatchesEntryUrl', () {
    test('exact match', () {
      expect(
        fillHostMatchesEntryUrl('netflix.com', 'https://netflix.com'),
        isTrue,
      );
    });
    test('subdomain', () {
      expect(
        fillHostMatchesEntryUrl('www.netflix.com', 'netflix.com'),
        isTrue,
      );
      expect(
        fillHostMatchesEntryUrl('accounts.netflix.com', 'netflix.com'),
        isTrue,
      );
    });
    test('no entry url', () {
      expect(fillHostMatchesEntryUrl('netflix.com', null), isFalse);
    });
    test('eTLD+1: subdomain on co.uk', () {
      expect(
        fillHostMatchesEntryUrl('login.example.co.uk', 'example.co.uk'),
        isTrue,
      );
      expect(
        fillHostMatchesEntryUrl('example.co.uk', 'login.example.co.uk'),
        isFalse,
      );
    });
    test('eTLD+1: different registrable domain on co.uk', () {
      expect(
        fillHostMatchesEntryUrl('other.co.uk', 'example.co.uk'),
        isFalse,
      );
    });
    test('eTLD+1: com.au', () {
      expect(
        fillHostMatchesEntryUrl('shop.example.com.au', 'example.com.au'),
        isTrue,
      );
    });
    test('eTLD+1: deep subdomain chain', () {
      expect(
        fillHostMatchesEntryUrl('a.b.c.example.com', 'example.com'),
        isTrue,
      );
    });
    test('port: tolerant when one side omits', () {
      expect(
        fillHostMatchesEntryUrl(
          'example.com',
          'https://example.com:8080',
        ),
        isTrue,
      );
      expect(
        fillHostMatchesEntryUrl(
          'https://example.com:8080',
          'https://example.com',
        ),
        isTrue,
      );
    });
    test('port: explicit ports must match when both present', () {
      expect(
        fillHostMatchesEntryUrl(
          'https://example.com:8080',
          'https://example.com:9090',
        ),
        isFalse,
      );
      expect(
        fillHostMatchesEntryUrl(
          'https://example.com:8080',
          'https://example.com:8080',
        ),
        isTrue,
      );
    });
  });

  group('PublicSuffixList.etldPlus1', () {
    test('default rule: last 2 labels', () {
      expect(PublicSuffixList.etldPlus1('login.example.com'), 'example.com');
      expect(PublicSuffixList.etldPlus1('example.com'), 'example.com');
    });
    test('co.uk family', () {
      expect(
        PublicSuffixList.etldPlus1('login.example.co.uk'),
        'example.co.uk',
      );
      expect(PublicSuffixList.etldPlus1('example.co.uk'), 'example.co.uk');
    });
    test('com.au family', () {
      expect(
        PublicSuffixList.etldPlus1('shop.example.com.au'),
        'example.com.au',
      );
    });
    test('co.jp family', () {
      expect(PublicSuffixList.etldPlus1('foo.example.co.jp'), 'example.co.jp');
    });
    test('single-label fallback', () {
      expect(PublicSuffixList.etldPlus1('localhost'), 'localhost');
    });
  });

  group('PublicSuffixList.isSameOrSubdomain', () {
    test('exact', () {
      expect(
        PublicSuffixList.isSameOrSubdomain('example.com', 'example.com'),
        isTrue,
      );
    });
    test('subdomain', () {
      expect(
        PublicSuffixList.isSameOrSubdomain('a.example.com', 'example.com'),
        isTrue,
      );
    });
    test('different domain', () {
      expect(
        PublicSuffixList.isSameOrSubdomain('other.com', 'example.com'),
        isFalse,
      );
    });
  });

  group('parseAndroidPackagesColumn', () {
    test('JSON array', () {
      expect(
        parseAndroidPackagesColumn('["a.b","c.d"]'),
        ['a.b', 'c.d'],
      );
    });
    test('comma separated', () {
      expect(
        parseAndroidPackagesColumn('com.a, com.b'),
        ['com.a', 'com.b'],
      );
    });
  });

  group('androidPackagesToColumn', () {
    test('null when empty', () {
      expect(androidPackagesToColumn([]), isNull);
    });
    test('JSON', () {
      expect(
        androidPackagesToColumn(['z', 'a']),
        '["a","z"]',
      );
    });
  });
}
