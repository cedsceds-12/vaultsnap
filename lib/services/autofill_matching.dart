// Pure helpers for Android Autofill matching (offline). Kept Dart-testable;
// Kotlin service mirrors the same rules.
import 'dart:convert';

import 'public_suffix_list.dart';

/// Normalizes a hostname for comparison (lowercase, strip leading www.).
String normalizeHost(String input) {
  var s = input.trim().toLowerCase();
  if (s.startsWith('www.')) {
    s = s.substring(4);
  }
  return s;
}

class _Authority {
  _Authority(this.host, this.port);
  final String host;
  final int? port;
}

_Authority? _parseAuthority(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final direct = Uri.tryParse(trimmed);
  if (direct != null &&
      (direct.isScheme('http') || direct.isScheme('https')) &&
      direct.hasAuthority &&
      direct.host.isNotEmpty) {
    return _Authority(
      normalizeHost(direct.host),
      direct.hasPort ? direct.port : null,
    );
  }
  if (!trimmed.contains('/') && !trimmed.contains(' ')) {
    final fake = Uri.tryParse('https://$trimmed');
    if (fake != null && fake.hasAuthority && fake.host.isNotEmpty) {
      return _Authority(
        normalizeHost(fake.host),
        fake.hasPort ? fake.port : null,
      );
    }
  }
  return null;
}

/// Parses a host from [entryUrl] (full URL, or bare host like netflix.com).
String? hostFromEntryUrl(String? entryUrl) {
  if (entryUrl == null || entryUrl.isEmpty) return null;
  return _parseAuthority(entryUrl)?.host;
}

/// Tolerant port comparison: when either side omits the port, treat as
/// match-any. This matches typical password-manager UX — users rarely care
/// about port numbers and saving `https://example.com:8080` shouldn't make
/// matching brittle.
bool _portsMatch(int? a, int? b) {
  if (a == null || b == null) return true;
  return a == b;
}

/// True when [fillHost] from Autofill matches [entryUrl]. Uses PSL-aware
/// eTLD+1 so `login.example.co.uk` matches an entry stored under
/// `example.co.uk` (which the previous naive `endsWith` would miss).
bool fillHostMatchesEntryUrl(String? fillHost, String? entryUrl) {
  if (fillHost == null || fillHost.isEmpty) return false;
  final fillAuth = _parseAuthority(fillHost);
  if (fillAuth == null) return false;
  final entryAuth = entryUrl == null ? null : _parseAuthority(entryUrl);
  if (entryAuth == null) return false;

  if (!_portsMatch(fillAuth.port, entryAuth.port)) return false;

  // Both sides must share a registrable domain (eTLD+1). Then the fill host
  // must be the same as or a subdomain of the entry's host — never the other
  // way around (a stored `login.example.co.uk` should not match a fill on
  // the bare `example.co.uk`).
  final fillRegistrable = PublicSuffixList.etldPlus1(fillAuth.host);
  final entryRegistrable = PublicSuffixList.etldPlus1(entryAuth.host);
  if (fillRegistrable != entryRegistrable) return false;
  return PublicSuffixList.isSameOrSubdomain(fillAuth.host, entryAuth.host);
}

/// Parses `android_packages` column: JSON array or comma-separated IDs.
List<String> parseAndroidPackagesColumn(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  final t = raw.trim();
  if (t.startsWith('[')) {
    try {
      final decoded = jsonDecode(t);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
      }
    } catch (_) {
      // fall through
    }
  }
  return t
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
}

/// Normalizes user input from the edit form into a DB column value (JSON array).
String? androidPackagesToColumn(List<String> packages) {
  if (packages.isEmpty) return null;
  final unique = packages.toSet().toList()..sort();
  return jsonEncode(unique);
}

/// Parses the login form field (comma-separated package IDs).
List<String> parseAndroidPackagesField(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  return raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
}
