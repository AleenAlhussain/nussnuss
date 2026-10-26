import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reduce Transparency, from the native side: iOS's own setting; on Android, window blur turned
/// off by the system or high-contrast text. Glass turns Solid while it is on, exactly as with
/// Increase Contrast. Flutter itself does not report it, hence the small bridge in AppDelegate.swift
/// and MainActivity.kt.
final reduceTransparency = ValueNotifier<bool>(false);

const _methods = MethodChannel('nussnuss/accessibility');
const _changes = EventChannel('nussnuss/accessibility/changes');
StreamSubscription<Object?>? _sub;

/// Reads it once and follows changes. Called from main only (tests have no native side).
Future<void> watchReduceTransparency() async {
  try {
    reduceTransparency.value =
        await _methods.invokeMethod<bool>('reduceTransparency') ?? false;
  } on Object {
    // An older build without the bridge: glass follows the Glass setting only.
  }
  _sub ??= _changes.receiveBroadcastStream().listen((v) {
    if (v is bool) reduceTransparency.value = v;
  }, onError: (Object _) {});
}
