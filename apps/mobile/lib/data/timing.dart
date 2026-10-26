import 'dart:async';
import 'dart:io';

import 'api.dart';

/// Phase 0 of the design plan: how long the five main jobs take people, sent anonymously so the
/// redesign can be measured. Fire and forget: it never waits, never blocks and never fails loudly.
///
/// The jobs: add_expense (+ tapped → saved), uneven_split (Unequally opened → Done), settle (a
/// person or the settle-up list opened → marked paid), invite (the invite sheet opened → the link
/// shared or copied) and find_balance (app start → Home showing the overall balance).
class Timings {
  Timings(this.api);
  final Api api;
  final _started = <String, Stopwatch>{};
  final _sent = <String>{};

  /// From app start, for find_balance.
  final _launch = Stopwatch()..start();

  static String get _app => Platform.isIOS ? 'ios' : 'android';
  static const _version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '2.0.0',
  );

  void start(String job) => _started[job] = Stopwatch()..start();

  /// The job was left without finishing (the sheet closed): nothing is sent.
  void cancel(String job) => _started.remove(job);

  bool running(String job) => _started.containsKey(job);

  void finish(String job, {bool ok = true}) {
    final w = _started.remove(job);
    if (w == null) return;
    send(job, w.elapsedMilliseconds, ok: ok);
  }

  /// find_balance: the first time Home shows the overall balance after the app started.
  void balanceShown() {
    if (!_sent.add('find_balance')) return;
    send('find_balance', _launch.elapsedMilliseconds);
  }

  void send(String job, int ms, {bool ok = true}) {
    try {
      unawaited(
        api
            .timing(app: _app, version: _version, job: job, ms: ms, ok: ok)
            .catchError((Object _) {}),
      );
    } on Object {
      // Measuring must never get in the way.
    }
  }
}
