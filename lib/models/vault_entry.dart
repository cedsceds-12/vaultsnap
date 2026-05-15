// Vault row model + Phase 4 storage helpers.
// Cleartext SQL columns: cleartextFromFields. Encrypted payload: JSON of all
// category field values, AES-GCM with VMK: encryptFieldMap / decryptFieldMap.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../services/autofill_matching.dart';
import '../services/crypto_service.dart';
import 'password_entry.dart';
import 'vault_meta.dart';

/// Cleartext list/search columns derived from category + field map.
typedef VaultCleartext = ({String name, String? username, String? url});

/// One vault row: cleartext metadata for list/search + [encryptedPayload]
/// for all category field values (JSON map, AES-GCM under VMK).
class VaultEntry {
  final String id;
  final String name;
  final String? username;
  final String? url;
  /// Android package names for Autofill matching (cleartext DB column).
  final List<String> androidPackages;
  final EntryCategory category;
  final PasswordStrength strength;
  final bool reused;
  final DateTime createdAt;
  final DateTime updatedAt;
  final WrappedSecret encryptedPayload;

  const VaultEntry({
    required this.id,
    required this.name,
    this.username,
    this.url,
    this.androidPackages = const [],
    required this.category,
    required this.strength,
    required this.reused,
    required this.createdAt,
    required this.updatedAt,
    required this.encryptedPayload,
  });

  /// Placeholder for list tiles (real secrets live in [encryptedPayload]).
  String get maskedSecret => '••••••••••••';

  /// Redacted toString — never dumps `encryptedPayload` bytes or the
  /// full username / URL. The cleartext list/search columns *are* on
  /// disk in plaintext and visible in the UI, so showing the entry
  /// name is fine; everything else is suppressed.
  @override
  String toString() => 'VaultEntry(id: $id, name: $name, '
      'category: ${category.label})';

  VaultEntry copyWithSecurity({
    required PasswordStrength strength,
    required bool reused,
  }) {
    return VaultEntry(
      id: id,
      name: name,
      username: username,
      url: url,
      androidPackages: androidPackages,
      category: category,
      strength: strength,
      reused: reused,
      createdAt: createdAt,
      updatedAt: updatedAt,
      encryptedPayload: encryptedPayload,
    );
  }

  factory VaultEntry.fromDatabaseRow(Map<String, Object?> row) {
    return VaultEntry(
      id: row['id']! as String,
      name: row['name']! as String,
      username: row['username'] as String?,
      url: row['url'] as String?,
      androidPackages: parseAndroidPackagesColumn(
        row['android_packages'] as String?,
      ),
      category: _parseCategory(row['category']! as String),
      strength: _parseStrength(row['strength']! as String),
      reused: (row['reused']! as int) != 0,
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      encryptedPayload: WrappedSecret(
        nonce: row['nonce']! as Uint8List,
        ciphertext: row['encrypted_blob']! as Uint8List,
        mac: row['mac']! as Uint8List,
      ),
    );
  }

  Map<String, Object?> toDatabaseRow() {
    return {
      'id': id,
      'name': name,
      'category': category.name,
      'username': username,
      'url': url,
      'android_packages': androidPackagesToColumn(androidPackages),
      'strength': strength.name,
      'reused': reused ? 1 : 0,
      'encrypted_blob': encryptedPayload.ciphertext,
      'nonce': encryptedPayload.nonce,
      'mac': encryptedPayload.mac,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  static Future<WrappedSecret> encryptFieldMap({
    required CryptoService crypto,
    required SecretKey vmk,
    required Map<String, String> fields,
  }) async {
    final json = jsonEncode(fields);
    final plaintext = Uint8List.fromList(utf8.encode(json));
    return crypto.wrap(plaintext: plaintext, key: vmk);
  }

  static Future<Map<String, String>> decryptFieldMap({
    required CryptoService crypto,
    required SecretKey vmk,
    required WrappedSecret payload,
  }) async {
    final clear = await crypto.unwrap(wrapped: payload, key: vmk);
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map) {
      throw const FormatException('Entry payload is not a JSON object');
    }
    return decoded.map(
      (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
    );
  }

  /// Derive list/search columns from category + field map.
  static VaultCleartext cleartextFromFields(
    EntryCategory category,
    Map<String, String> fields,
  ) {
    final rawName = (fields['name'] ?? '').trim();
    String? username;
    String? url;
    switch (category) {
      case EntryCategory.login:
        final u = (fields['username'] ?? '').trim();
        username = u.isEmpty ? null : u;
        final w = (fields['url'] ?? '').trim();
        url = w.isEmpty ? null : w;
        break;
      case EntryCategory.card:
        final h = (fields['cardholder'] ?? '').trim();
        username = h.isEmpty ? null : h;
        break;
      case EntryCategory.identity:
        final f = (fields['fullName'] ?? '').trim();
        username = f.isEmpty ? null : f;
        break;
      case EntryCategory.note:
        break;
      case EntryCategory.wifi:
        final s = (fields['ssid'] ?? '').trim();
        username = s.isEmpty ? null : s;
        break;
      case EntryCategory.totp:
        // Cleartext list-column derivation for an Authenticator entry:
        // surface issuer (or account if no issuer) as the searchable
        // "username" column. The `secret` stays inside the encrypted blob.
        final issuer = (fields['issuer'] ?? '').trim();
        final account = (fields['account'] ?? '').trim();
        final pick = issuer.isNotEmpty ? issuer : account;
        username = pick.isEmpty ? null : pick;
        break;
    }
    return (
      name: rawName.isEmpty ? 'Untitled' : rawName,
      username: username,
      url: url,
    );
  }

  static PasswordStrength strengthFromFields(
    EntryCategory category,
    Map<String, String> fields,
  ) {
    switch (category) {
      case EntryCategory.login:
      case EntryCategory.wifi:
        return _strengthFromPassword(fields['password'] ?? '');
      case EntryCategory.card:
      case EntryCategory.identity:
      case EntryCategory.note:
      case EntryCategory.totp:
        // TOTP secrets aren't human-chosen; weak/strong has no meaning.
        return PasswordStrength.good;
    }
  }

  static String passwordFromFields(
    EntryCategory category,
    Map<String, String> fields,
  ) {
    return switch (category) {
      EntryCategory.login || EntryCategory.wifi => fields['password'] ?? '',
      EntryCategory.card ||
      EntryCategory.identity ||
      EntryCategory.note ||
      EntryCategory.totp =>
        '',
    };
  }

  static PasswordStrength _strengthFromPassword(String password) {
    if (password.isEmpty) return PasswordStrength.weak;
    if (password.length < 6) return PasswordStrength.weak;
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 14) score++;
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasNum = password.contains(RegExp(r'[0-9]'));
    final hasSym = password.contains(RegExp(r'[^A-Za-z0-9]'));
    final classes =
        [hasLower, hasUpper, hasNum, hasSym].where((b) => b).length;
    if (classes >= 2) score++;
    if (classes >= 4) score++;
    if (score > 4) score = 4;
    return switch (score) {
      0 || 1 => PasswordStrength.weak,
      2 => PasswordStrength.fair,
      3 => PasswordStrength.good,
      _ => PasswordStrength.strong,
    };
  }

  static EntryCategory _parseCategory(String raw) {
    if (raw == 'app') {
      return EntryCategory.login;
    }
    return EntryCategory.values.firstWhere(
      (c) => c.name == raw,
      orElse: () => EntryCategory.login,
    );
  }

  static PasswordStrength _parseStrength(String raw) {
    return PasswordStrength.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => PasswordStrength.good,
    );
  }
}
