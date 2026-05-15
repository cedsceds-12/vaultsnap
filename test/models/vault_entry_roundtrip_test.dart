import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/models/password_entry.dart';
import 'package:vault_snap/models/vault_entry.dart';
import 'package:vault_snap/services/crypto_service.dart';

void main() {
  test('encryptFieldMap / decryptFieldMap roundtrip', () async {
    final crypto = CryptoService();
    final vmk = SecretKey(crypto.randomBytes(32));
    const fields = {'name': 'GitHub', 'password': 'secret123', 'notes': ''};

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

    expect(back['name'], 'GitHub');
    expect(back['password'], 'secret123');
    expect(back['notes'], '');
  });

  test('cleartextFromFields maps login username and url', () {
    final fields = {
      'name': 'Test',
      'username': 'u@x.com',
      'url': 'example.com',
      'password': 'x',
    };
    final c = VaultEntry.cleartextFromFields(EntryCategory.login, fields);
    expect(c.name, 'Test');
    expect(c.username, 'u@x.com');
    expect(c.url, 'example.com');
  });

  test('strengthFromFields matches password meter buckets', () {
    expect(
      VaultEntry.strengthFromFields(
        EntryCategory.login,
        const {'password': '12345678'},
      ),
      PasswordStrength.weak,
    );
    expect(
      VaultEntry.strengthFromFields(
        EntryCategory.login,
        const {'password': 'abc12345'},
      ),
      PasswordStrength.fair,
    );
    expect(
      VaultEntry.strengthFromFields(
        EntryCategory.login,
        const {'password': 'abcDEF12345678'},
      ),
      PasswordStrength.good,
    );
    expect(
      VaultEntry.strengthFromFields(
        EntryCategory.login,
        const {'password': 'abcDEF12345678!'},
      ),
      PasswordStrength.strong,
    );
  });

  test('passwordFromFields only returns real password fields', () {
    expect(
      VaultEntry.passwordFromFields(
        EntryCategory.wifi,
        const {'password': 'same-secret'},
      ),
      'same-secret',
    );
    expect(
      VaultEntry.passwordFromFields(
        EntryCategory.note,
        const {'content': 'same-secret'},
      ),
      isEmpty,
    );
  });

  test('copyWithSecurity updates only health flags', () async {
    final crypto = CryptoService();
    final vmk = SecretKey(crypto.randomBytes(32));
    final wrapped = await VaultEntry.encryptFieldMap(
      crypto: crypto,
      vmk: vmk,
      fields: const {'name': 'GitHub', 'password': 'secret123'},
    );
    final entry = VaultEntry(
      id: '1',
      name: 'GitHub',
      category: EntryCategory.login,
      strength: PasswordStrength.good,
      reused: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 1, 2),
      encryptedPayload: wrapped,
    );

    final updated = entry.copyWithSecurity(
      strength: PasswordStrength.weak,
      reused: true,
    );

    expect(updated.id, entry.id);
    expect(updated.name, entry.name);
    expect(updated.updatedAt, entry.updatedAt);
    expect(updated.strength, PasswordStrength.weak);
    expect(updated.reused, isTrue);
  });
}
