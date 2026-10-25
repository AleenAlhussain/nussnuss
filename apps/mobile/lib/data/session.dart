import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/extras.dart';
import '../design/theme.dart';
import '../l10n/strings.g.dart';
import 'api.dart';
import 'live.dart';
import 'models.dart';
import 'offline.dart';
import 'services.dart';
import 'store.dart';

export 'store.dart';

enum ThemePref { system, light, dark }

/// The looks people can pick. Night is always dark.
const looks = ['default', 'night', 'saffron'];

/// Who is signed in and how they like the app. One per app, provided by [SessionScope].
class Session extends ChangeNotifier {
  Session({
    required this.api,
    required this.store,
    KeyValueStore? secrets,
    Device? device,
    Store? purchases,
    this.live,
  }) : secrets = secrets ?? store,
       device = device ?? QuietDevice(),
       purchases = purchases ?? NoStore() {
    repo = Repo(api: api, store: store)..addListener(notifyListeners);
  }

  final Api api;

  /// Preferences and the offline copy.
  final KeyValueStore store;

  /// The session token: the Keychain or Keystore in the app.
  final KeyValueStore secrets;
  final Device device;
  final Store purchases;

  /// Live updates for an open group; null falls back to a slow poll.
  final LiveUpdates? live;
  late final Repo repo;

  static const _tokenKey = 'nn:token';
  static const _langKey = 'nn:lang';
  static const _themeKey = 'nn:theme';
  static const _glassKey = 'nn:glass';
  static const _lookKey = 'nn:look';
  static const _soundsKey = 'nn:sounds';
  static const _meKey = 'nn:me';

  bool ready = false;
  Me? me;
  String lang = 'en';
  ThemePref theme = ThemePref.system;
  GlassPref glass = GlassPref.clear;
  String look = 'default';
  bool sounds = false;
  Plan plan = Plan.free;

  /// True right after someone starts for the first time, so the app can open "New group" for them.
  bool firstRun = false;

  /// An invite link that opened the app, waiting to be shown.
  String? pendingInvite;

  /// A group to open as soon as the groups list shows (after joining from a link).
  String? openGroupId;

  void openInvite(String token) {
    pendingInvite = token;
    notifyListeners();
  }

  /// Bumped whenever groups change, so lists know to refresh.
  int revision = 0;

  NNStrings get s => NNStrings.of(lang);

  /// The look actually shown: one that is owned, else the default.
  String get activeLook => plan.ownsLook(look) ? look : 'default';

  StreamSubscription<StorePurchase>? _purchaseSub;
  final _buying = <String, ({String? groupId, Completer<Plan?> done})>{};

  /// Restores preferences and the session token. Works offline: a saved token is enough to show the app.
  Future<void> load({String? systemLang}) async {
    lang = await store.read(_langKey) ?? (systemLang == 'ar' ? 'ar' : 'en');
    theme =
        ThemePref.values.asNameMap()[await store.read(_themeKey)] ??
        ThemePref.system;
    glass =
        GlassPref.values.asNameMap()[await store.read(_glassKey)] ??
        GlassPref.clear;
    final savedLook = await store.read(_lookKey);
    look = looks.contains(savedLook) ? savedLook! : 'default';
    sounds = await store.read(_soundsKey) == 'on';
    await repo.load();
    _purchaseSub ??= purchases.purchases.listen(_onPurchase);

    var token = await secrets.read(_tokenKey);
    if (token == null && !identical(secrets, store)) {
      // Older builds kept the token with the preferences: move it into secure storage once.
      final old = await store.read(_tokenKey);
      if (old != null) {
        await secrets.write(_tokenKey, old);
        await store.write(_tokenKey, null);
        token = old;
      }
    }
    if (token != null) {
      api.token = token;
      final saved = await store.read(_meKey);
      if (saved != null) {
        me = Me.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      }
      try {
        await _remember(await api.me());
        unawaited(refreshPlan());
        unawaited(repo.sync());
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

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  Future<void> _signedIn(({String token, Me me}) r) async {
    api.token = r.token;
    await secrets.write(_tokenKey, r.token);
    await _remember(r.me);
    unawaited(refreshPlan());
    notifyListeners();
  }

  Future<void> start(String name) async {
    await _signedIn(await api.anonymous(name.trim(), lang));
    firstRun = true;
    notifyListeners();
  }

  /// "I have a code": a recovery code, or a code made on another device.
  Future<void> signInWithCode(String code) async {
    await repo.forget();
    await _signedIn(await api.signInWithCode(code));
    touch();
  }

  Future<void> refreshPlan() async {
    try {
      plan = await api.plan();
      notifyListeners();
    } on ApiException {
      // Keep what we knew; Plus features ask the server again when used.
    }
  }

  /// Plus for this group: the person's own plan or a Trip Pass someone bought for it.
  bool hasPlus(GroupDetail? g) =>
      plan.plus ||
      (g != null && (g.tripPass || plan.tripPasses.containsKey(g.id)));

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

  Future<void> setLook(String v) async {
    look = v;
    notifyListeners();
    await store.write(_lookKey, v);
  }

  Future<void> setSounds(bool on) async {
    sounds = on;
    notifyListeners();
    await store.write(_soundsKey, on ? 'on' : null);
  }

  /// A quiet coin tap, only when Sounds is on (the phone's silent switch still wins).
  void click() {
    if (sounds) unawaited(SystemSound.play(SystemSoundType.click));
  }

  Future<void> setPayTo(List<PayTo> list) async {
    await _remember(await api.patchMe(payTo: list));
    notifyListeners();
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

  // ---- purchases ---------------------------------------------------------------------------

  /// Starts a store purchase. Completes with the new plan once the server has checked it, or null
  /// when the person cancels or the store says no.
  Future<Plan?> buy(StoreProduct p, {String? groupId}) async {
    final done = Completer<Plan?>();
    _buying[p.id] = (groupId: groupId, done: done);
    try {
      await purchases.buy(p, subscription: Products.isSubscription(p.id));
    } on Exception {
      _buying.remove(p.id);
      return null;
    }
    return done.future.timeout(
      const Duration(minutes: 10),
      onTimeout: () => null,
    );
  }

  /// Test builds only: the server grants it without a store when it allows test purchases.
  Future<Plan> devBuy(String productId, {String? groupId}) async {
    plan = await api.devPurchase(productId, groupId: groupId);
    touch();
    return plan;
  }

  Future<void> restore() async {
    await purchases.restore();
    await refreshPlan();
  }

  Future<void> _onPurchase(StorePurchase p) async {
    final waiting = _buying[p.productId];
    switch (p.outcome) {
      case StoreOutcome.pending:
        return;
      case StoreOutcome.canceled || StoreOutcome.error:
        _buying.remove(p.productId);
        await purchases.finish(p);
        waiting?.done.complete(null);
        return;
      case StoreOutcome.purchased || StoreOutcome.restored:
        if (waiting == null && p.productId == Products.tripPass) {
          // A Trip Pass is tied to the group it was bought for, which the server already knows.
          await purchases.finish(p);
          return;
        }
        try {
          plan = p.platform == 'apple'
              ? await api.verifyApple(p.proof, groupId: waiting?.groupId)
              : await api.verifyGoogle(
                  p.productId,
                  p.proof,
                  groupId: waiting?.groupId,
                );
          await purchases.finish(p);
          touch();
          waiting?.done.complete(plan);
        } on ApiException {
          // Not finished, so the store offers it again next time and nothing is lost.
          waiting?.done.complete(null);
        }
        _buying.remove(p.productId);
    }
  }

  Future<void> _remember(Me m) async {
    me = m;
    await store.write(_meKey, jsonEncode(m.toJson()));
  }

  Future<void> _forget() async {
    me = null;
    plan = Plan.free;
    api.token = null;
    await secrets.write(_tokenKey, null);
    await store.write(_meKey, null);
    await repo.forget();
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
