import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vault_meta.dart';
import '../services/attachment_service.dart';
import '../services/biometric_service.dart';
import '../services/clipboard_service.dart';
import '../services/crypto_service.dart';
import '../services/settings_storage.dart';
import '../services/vault_database.dart';
import '../services/vault_storage.dart';
import '../services/window_service.dart';

/// Service providers — singletons for the lifetime of the ProviderScope.

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoService();
});

/// Encrypted attachment storage. Reuses [cryptoServiceProvider] so the
/// non-isolate path goes through the same AES-GCM helper used elsewhere
/// in the app, and looks up `vault_attachments/` under the standard
/// app-documents directory.
final attachmentServiceProvider = Provider<AttachmentService>((ref) {
  return AttachmentService(crypto: ref.read(cryptoServiceProvider));
});

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final clipboardServiceProvider = Provider<ClipboardService>((ref) {
  final service = ClipboardService();
  ref.onDispose(service.dispose);
  return service;
});

final windowServiceProvider = Provider<WindowService>((ref) {
  return WindowService();
});

final settingsStorageProvider = FutureProvider<SettingsStorage>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return SettingsStorage('${dir.path}/vaultsnap_settings.json');
});

/// Resolves the on-disk path for `vault_meta.json` via path_provider, then
/// returns the file-backed [VaultStorage]. Async because path_provider is
/// async on first call.
final vaultStorageProvider = FutureProvider<VaultStorage>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return VaultStorage('${dir.path}/vault_meta.json');
});

/// SQLite database for encrypted vault entries (cleartext metadata columns).
final vaultDatabaseProvider = FutureProvider<VaultDatabase>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return VaultDatabase.open(dir.path);
});

/// The currently-loaded vault descriptor, or `null` if the user hasn't
/// completed setup yet. The setup gate watches this to choose between
/// the wizard and the unlock screen.
final vaultMetaProvider = FutureProvider<VaultMeta?>((ref) async {
  final storage = await ref.watch(vaultStorageProvider.future);
  return storage.load();
});
