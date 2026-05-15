import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vault_snap/main.dart';
import 'package:vault_snap/models/vault_entry.dart';
import 'package:vault_snap/models/vault_meta.dart';
import 'package:vault_snap/providers/vault_providers.dart';
import 'package:vault_snap/providers/vault_repository_provider.dart';
import 'package:vault_snap/theme/app_theme.dart';

/// Avoids sqflite + path I/O during widget tests (pumpAndSettle would hang).
class _TestVaultRepository extends VaultRepository {
  @override
  Future<List<VaultEntry>> build() async => const [];
}

void main() {
  testWidgets('First launch shows setup wizard welcome screen',
      (WidgetTester tester) async {
    // Override vaultMetaProvider to return null (no vault exists)
    // so the AppRouter shows the SetupWizardScreen.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultMetaProvider.overrideWith((ref) async => null),
        ],
        child: VaultSnapApp(
          lightTheme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          initialThemeMode: ThemeMode.dark,
        ),
      ),
    );
    // Let the FutureProvider resolve.
    await tester.pumpAndSettle();

    expect(find.text('Welcome to VaultSnap'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
  });

  testWidgets('Existing vault shows unlock screen',
      (WidgetTester tester) async {
    final meta = VaultMeta(
      version: VaultMeta.currentVersion,
      kdf: KdfParams.defaults,
      passwordSalt: Uint8List(16),
      wrappedVmkPassword: WrappedSecret(
        nonce: Uint8List(12),
        ciphertext: Uint8List(32),
        mac: Uint8List(16),
      ),
      wrappedVmkRecovery: WrappedSecret(
        nonce: Uint8List(12),
        ciphertext: Uint8List(32),
        mac: Uint8List(16),
      ),
      wrappedVmkBiometric: null,
      recovery: RecoveryMeta(
        question: 'Question?',
        salt: Uint8List(16),
      ),
      createdAt: DateTime.utc(2026),
      lastUnlockAt: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultMetaProvider.overrideWith((ref) async => meta),
          vaultRepositoryProvider.overrideWith(_TestVaultRepository.new),
        ],
        child: VaultSnapApp(
          lightTheme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          initialThemeMode: ThemeMode.dark,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VaultSnap'), findsOneWidget);
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    // Biometric button only shows when wrappedVmkBiometric != null
    expect(find.text('Use biometrics'), findsNothing);
  });
}
