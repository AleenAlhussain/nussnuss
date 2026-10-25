import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/theme.dart';
import '../l10n/strings.g.dart';
import 'api.dart';
import 'models.dart';

/// Small key-value storage for the session token and preferences. Memory-only in tests.
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

enum ThemePref { system, light, dark }

/// Who is signed in and how they like the app. One per app, provided by [SessionScope].
class Session extends ChangeNotifier {
  Session({required this.api, required this.store});

  final Api api;
  final KeyValueStore store;

  static const _tokenKey = 'nn:token';
  static const _langKey = 'nn:lang';
  static const _themeKey = 'nn:theme';
  static const _glassKey = 'nn:glass';
  static const _meKey = 'nn:me';

  bool ready = false;
  Me? me;
  String lang = 'en';
  ThemePref theme = ThemePref.system;
  GlassPref glass = GlassPref.clear;

  /// Bumped whenever groups change, so lists know to refresh.
  int revision = 0;

  NNStrings get s => NNStrings.of(lang);

  /// Restores preferences and the session token. Works offline: a saved token is enough to show the app.
  Future<void> load({String? systemLang}) async {
    lang = await store.read(_langKey) ?? (systemLang == 'ar' ? 'ar' : 'en');
    theme =
        ThemePref.values.asNameMap()[await store.read(_themeKey)] ??
        ThemePref.system;
    glass =
        GlassPref.values.asNameMap()[await store.read(_glassKey)] ??
        GlassPref.clear;
    final token = await store.read(_tokenKey);
    if (token != null) {
      api.token = token;
      final saved = await store.read(_meKey);
      if (saved != null) {
        me = Me.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      }
      try {
        await _remember(await api.me());
      } on ApiException catch (e) {
        if (e.status == 401) {
          await _forget();
        } else {
          // Offline or server trouble: the saved token is enough to open the app with what we have.
          me ??= Me(id: '', name: '', locale: lang);
        }
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> start(String name) async {
    final r = await api.anonymous(name.trim(), lang);
    api.token = r.token;
    await store.write(_tokenKey, r.token);
    await _remember(r.me);
    notifyListeners();
  }

  Future<void> setLang(String v) async {
    lang = v;
    notifyListeners();
    await store.write(_langKey, v);
    if (me != null && me!.id.isNotEmpty) {
      try {
        await _remember(await api.patchMe(locale: v));
      } on ApiException {
        // The language is a local preference first; the server copy can catch up later.
      }
    }
  }

  Future<void> setTheme(ThemePref v) async {
    theme = v;
    notifyListeners();
    await store.write(_themeKey, v.name);
  }

  Future<void> setGlass(GlassPref v) async {
    glass = v;
    notifyListeners();
    await store.write(_glassKey, v.name);
  }

  void touch() {
    revision++;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await api.deleteMe();
    await _forget();
    notifyListeners();
  }

  Future<void> _remember(Me m) async {
    me = m;
    await store.write(_meKey, jsonEncode(m.toJson()));
  }

  Future<void> _forget() async {
    me = null;
    api.token = null;
    await store.write(_tokenKey, null);
    await store.write(_meKey, null);
  }
}

class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({
    super.key,
    required Session session,
    required super.child,
  }) : super(notifier: session);

  static Session of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// For callbacks: reads the session without rebuilding when it changes.
  static Session read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}

extension SessionContext on BuildContext {
  Session get session => SessionScope.of(this);
  NNStrings get s => SessionScope.of(this).s;
}
