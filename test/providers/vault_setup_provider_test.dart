import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/providers/vault_setup_provider.dart';
import 'package:vault_snap/services/biometric_service.dart';
import 'package:vault_snap/services/crypto_service.dart';
import 'package:vault_snap/services/vault_storage.dart';

void main() {
  late Directory tmp;
  late VaultStorage storage;
  late VaultSetupService service;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vaultsnap_setup_test_');
    storage = VaultStorage('${tmp.path}${Platform.pathSeparator}meta.json');
    service = VaultSetupService(
      CryptoService(),
      storage,
      BiometricService(),
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('recovery reset rotates password wrap and keeps recovery valid',
      () async {
    final meta = await service.createVault(
      masterPassword: 'old-master-pass',
      recoveryQuestion: 'First pet?',
      recoveryAnswer: '  Luna  Cat ',
    );

    final reset = await service.resetMasterPasswordWithRecovery(
      recoveryAnswer: 'luna cat',
      newPassword: 'new-master-pass',
      meta: meta,
    );

    expect(reset, isNotNull);
    expect(
      reset!.meta.wrappedVmkPassword.ciphertext,
      isNot(equals(meta.wrappedVmkPassword.ciphertext)),
    );
    expect(
      reset.meta.wrappedVmkRecovery.ciphertext,
      equals(meta.wrappedVmkRecovery.ciphertext),
    );

    expect(
      await service.verifyPassword(
        masterPassword: 'old-master-pass',
        meta: reset.meta,
      ),
      isNull,
    );
    expect(
      await service.verifyPassword(
        masterPassword: 'new-master-pass',
        meta: reset.meta,
      ),
      isNotNull,
    );
    expect(
      await service.verifyRecoveryAnswer(answer: 'LUNA   CAT', meta: reset.meta),
      equals(reset.vmk),
    );
  });

  test('recovery reset rejects wrong answer without changing meta', () async {
    final meta = await service.createVault(
      masterPassword: 'old-master-pass',
      recoveryQuestion: 'First pet?',
      recoveryAnswer: 'luna',
    );

    final reset = await service.resetMasterPasswordWithRecovery(
      recoveryAnswer: 'wrong',
      newPassword: 'new-master-pass',
      meta: meta,
    );

    expect(reset, isNull);
    final loaded = await storage.load();
    expect(
      loaded!.wrappedVmkPassword.ciphertext,
      equals(meta.wrappedVmkPassword.ciphertext),
    );
  });
}
