import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/models/password_entry.dart';
import 'package:vault_snap/models/vault_entry.dart';
import 'package:vault_snap/services/crypto_service.dart';

void main() {
  group('VaultEntry — TOTP category', () {
    test('cleartextFromFields uses issuer as searchable username', () {
      final cleartext = VaultEntry.cleartextFromFields(
        EntryCategory.totp,
        const {
          'name': 'GitHub 2FA',
          'issuer': 'GitHub',
          'account': 'alice@example.com',
          'secret': 'JBSWY3DPEHPK3PXP',
        },
      );
      expect(cleartext.name, 'GitHub 2FA');
      expect(cleartext.username, 'GitHub');
      expect(cleartext.url, isNull);
    });

    test('cleartextFromFields falls back to account when issuer is blank', () {
      final cleartext = VaultEntry.cleartextFromFields(
        EntryCategory.totp,
        const {
          'name': 'Side project',
          'issuer': '',
          'account': 'alice@example.com',
        },
      );
      expect(cleartext.username, 'alice@example.com');
    });

    test('cleartextFromFields name falls back to "Untitled" when blank', () {
      final cleartext = VaultEntry.cleartextFromFields(
        EntryCategory.totp,
        const {'name': '', 'issuer': 'GitHub'},
      );
      expect(cleartext.name, 'Untitled');
    });

    test('strengthFromFields returns good (TOTP secrets are not user-chosen)', () {
      expect(
        VaultEntry.strengthFromFields(
          EntryCategory.totp,
          const {'secret': 'JBSWY3DPEHPK3PXP'},
        ),
        PasswordStrength.good,
      );
    });

    test('passwordFromFields returns empty (TOTP has no password column)', () {
      expect(
        VaultEntry.passwordFromFields(
          EntryCategory.totp,
          const {'secret': 'JBSWY3DPEHPK3PXP'},
        ),
        '',
      );
    });

    test('encrypt/decrypt roundtrip preserves every TOTP field', () async {
      final crypto = CryptoService();
      final vmk = SecretKey(crypto.randomBytes(32));
      const fields = {
        'name': 'GitHub 2FA',
        'issuer': 'GitHub',
        'account': 'alice@example.com',
        'secret': 'JBSWY3DPEHPK3PXP',
        'algorithm': 'SHA1',
        'digits': '6',
        'period': '30',
        'notes': 'paper backup in safe',
      };

      final wrapped = await VaultEntry.encryptFieldMap(
        crypto: crypto,
        vmk: vmk,
        fields: fields,
      );
      final back = await VaultEntry.decryptFieldMap(
        crypto: crypto,
        vmk: vmk,
        payload: wrapped,
      );

      expect(back['name'], 'GitHub 2FA');
      expect(back['issuer'], 'GitHub');
      expect(back['account'], 'alice@example.com');
      expect(back['secret'], 'JBSWY3DPEHPK3PXP');
      expect(back['algorithm'], 'SHA1');
      expect(back['digits'], '6');
      expect(back['period'], '30');
      expect(back['notes'], 'paper backup in safe');
    });
  });
}
