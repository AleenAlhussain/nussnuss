import 'package:flutter/material.dart';

import 'app.dart';
import 'data/api.dart';
import 'data/session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final transport = IoTransport();
  final session = Session(
    api: Api(baseUrl: defaultApiUrl(), transport: transport.call),
    store: PrefsStore(),
  );
  runApp(NussNussApp(session: session));
}
