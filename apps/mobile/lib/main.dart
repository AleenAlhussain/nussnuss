import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/accessibility.dart';
import 'data/api.dart';
import 'data/live.dart';
import 'data/plugins.dart';
import 'data/session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(watchReduceTransparency());
  final transport = IoTransport();
  final api = Api(baseUrl: defaultApiUrl(), transport: transport.call);
  _reportCrashes(api);
  final session = Session(
    api: api,
    store: PrefsStore(),
    secrets: const SecureStore(),
    device: PluginDevice(),
    purchases: PluginStore(),
    live: (groupId) => sseVersions(
      baseUrl: api.baseUrl,
      groupId: groupId,
      token: () => api.token,
    ),
  );
  runApp(NussNussApp(session: session));
}

/// Sends uncaught errors to the API (off on the server unless CRASH_REPORTS=log). Only the message,
/// the stack and the app version go out, each distinct message once per run, never in debug builds.
void _reportCrashes(Api api) {
  if (kDebugMode) return;
  final seen = <String>{};
  void send(Object error, StackTrace? stack) {
    final message = error.toString();
    if (!seen.add(message) || seen.length > 20) return;
    unawaited(
      api
          .reportCrash(
            app: Platform.isIOS ? 'ios' : 'android',
            version: const String.fromEnvironment(
              'APP_VERSION',
              defaultValue: '2.0.0',
            ),
            message: message,
            stack: stack?.toString(),
          )
          .catchError((Object _) {}),
    );
  }

  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    send(details.exception, details.stack);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    send(error, stack);
    return false;
  };
}
