import 'dart:convert';
import 'dart:io';

import '../models/vault_meta.dart';

/// On-disk persistence of [VaultMeta] as JSON.
///
/// Pure-Dart (uses only `dart:io` — Flutter-free) so it can be
/// instantiated against an arbitrary path in tests.
///
/// Writes are atomic: we always write to `<path>.tmp` first, flush,
/// then `rename` over the live file. A crash between those steps leaves
/// the previous good copy intact rather than producing a half-written
/// corrupted vault.
class VaultStorage {
  final String path;

  const VaultStorage(this.path);

  File get _file => File(path);
  File get _tmp => File('$path.tmp');

  Future<bool> exists() => _file.exists();

  Future<VaultMeta?> load() async {
    if (!await _file.exists()) return null;
    final raw = await _file.readAsString();
    if (raw.isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return VaultMeta.fromJson(json);
  }

  Future<void> save(VaultMeta meta) async {
    await _file.parent.create(recursive: true);
    final encoded = jsonEncode(meta.toJson());
    await _tmp.writeAsString(encoded, flush: true);
    await _tmp.rename(path);
  }

  Future<void> delete() async {
    if (await _file.exists()) await _file.delete();
    if (await _tmp.exists()) await _tmp.delete();
  }
}
