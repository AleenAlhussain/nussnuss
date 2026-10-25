import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value storage for preferences, the offline copy and the session token.
/// Memory-only in tests.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class PrefsStore implements KeyValueStore {
  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _p).getString(key);

  @override
  Future<void> write(String key, String? value) async {
    final p = await _p;
    if (value == null) {
      await p.remove(key);
    } else {
      await p.setString(key, value);
    }
  }
}

class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? initial]) : _m = {...?initial};
  final Map<String, String> _m;

  /// Everything stored, for tests.
  Map<String, String> get values => Map.unmodifiable(_m);

  @override
  Future<String?> read(String key) async => _m[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }
}
