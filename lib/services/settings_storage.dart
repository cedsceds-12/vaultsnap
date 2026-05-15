import 'dart:convert';
import 'dart:io';

/// Simple JSON-file persistence for non-secret user preferences
/// (auto-lock minutes, clipboard-clear toggle, FLAG_SECURE toggle).
class SettingsStorage {
  final String path;

  const SettingsStorage(this.path);

  File get _file => File(path);

  Future<Map<String, dynamic>> load() async {
    if (!await _file.exists()) return {};
    final raw = await _file.readAsString();
    if (raw.isEmpty) return {};
    return (jsonDecode(raw) as Map<String, dynamic>?) ?? {};
  }

  Future<void> save(Map<String, dynamic> data) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<void> delete() async {
    if (await _file.exists()) await _file.delete();
  }
}
