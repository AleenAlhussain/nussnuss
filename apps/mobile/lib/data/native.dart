// The app's own channels to the phone: the home-screen widget and the trip on the Lock Screen
// ('nussnuss/widget'), and the shortcuts on the app icon and Siri ('nussnuss/shortcuts'). Every
// call is fire and forget: where nothing listens (tests, older builds) it quietly does nothing.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../l10n/strings.g.dart';
import 'models.dart';
import 'store.dart';

const _widget = MethodChannel('nussnuss/widget');
const _shortcuts = MethodChannel('nussnuss/shortcuts');

Future<void> _send(String method, Map<String, String> args) async {
  try {
    await _widget.invokeMethod<void>(method, args);
  } on MissingPluginException {
    // No widget on this platform or in this build.
  } on PlatformException {
    // The widget is a nicety; the app never waits for it.
  }
}

/// After each overview: what the home-screen widget shows. Title "Your balance", the main
/// currency's amount ("AED 110.00"), and "You get back", "You owe" or "All settled". When
/// everything is even the amount is empty and the widget says so in its own words.
Future<void> updateHomeWidget(Overview o, NNStrings s) {
  final first = o.totals.isEmpty ? null : o.totals.first;
  return _send('update', {
    'title': s.widgetName,
    'amount': first == null
        ? ''
        : money(first.amount.abs(), first.currency, s.lang),
    'sub': first == null
        ? s.allSettled
        : (first.amount > 0 ? s.youAreOwed : s.youOwe),
  });
}

/// Groups that are trips (by their cover), which can show on the Lock Screen.
bool isTripGroup(Cover c) =>
    const {'plane', 'beach', 'mountain', 'car'}.contains(c.icon);

const _liveKey = 'nn:liveTrips';

/// The groups whose balance is on the Lock Screen (kept on this device).
Future<Set<String>> liveTrips(KeyValueStore store) async {
  try {
    final raw = await store.read(_liveKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
  } on FormatException {
    return {};
  }
}

Future<void> _keepLive(KeyValueStore store, String groupId, bool on) async {
  final all = await liveTrips(store);
  if (on ? !all.add(groupId) : !all.remove(groupId)) return;
  await store.write(_liveKey, jsonEncode(all.toList()));
}

Map<String, String> _trip(GroupDetail g, NNStrings s) {
  final b = g.myBalance;
  return {
    'groupId': g.id,
    'title': g.name,
    'amount': money(b.abs(), g.currency, s.lang),
    'sub': b > 0 ? s.youAreOwed : (b < 0 ? s.youOwe : s.allSettled),
  };
}

/// The Lock Screen switch in group options.
Future<void> setLiveTrip(
  KeyValueStore store,
  GroupDetail g,
  NNStrings s, {
  required bool on,
}) async {
  await _keepLive(store, g.id, on);
  await (on
      ? _send('startTrip', _trip(g, s))
      : _send('endTrip', {'groupId': g.id}));
}

/// Each time a group's detail loads: a trip on the Lock Screen follows its balance, and goes once
/// the group is settled.
Future<void> syncLiveTrip(
  KeyValueStore store,
  GroupDetail g,
  NNStrings s,
) async {
  if (!(await liveTrips(store)).contains(g.id)) return;
  final settled = g.expenses.isNotEmpty && g.transfers.isEmpty;
  if (settled) {
    await setLiveTrip(store, g, s, on: false);
  } else {
    await _send('updateTrip', _trip(g, s));
  }
}

/// A shortcut to act on: 'add' (as Home's +) or 'activity'. Home takes it and sets it back to null.
final shortcutAction = ValueNotifier<String?>(null);

/// Listens for shortcuts and asks for the one that launched the app. From main only.
Future<void> watchShortcuts() async {
  _shortcuts.setMethodCallHandler((call) async {
    if (call.method == 'open' && call.arguments is String) {
      shortcutAction.value = call.arguments as String;
    }
    return null;
  });
  try {
    final first = await _shortcuts.invokeMethod<String>('initial');
    if (first != null) shortcutAction.value = first;
  } on MissingPluginException {
    // Not on this platform.
  } on PlatformException {
    // Nothing to open.
  }
}

/// Whether this is an iPhone or iPad (the Lock Screen switch is only there). Tests can override
/// the platform with debugDefaultTargetPlatformOverride.
bool get onIos => defaultTargetPlatform == TargetPlatform.iOS;
