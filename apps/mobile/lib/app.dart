import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/session.dart';
import 'design/coin.dart';
import 'design/theme.dart';
import 'screens/home.dart';
import 'screens/welcome_screen.dart';

class NussNussApp extends StatefulWidget {
  const NussNussApp({super.key, required this.session});
  final Session session;

  @override
  State<NussNussApp> createState() => _NussNussAppState();
}

class _NussNussAppState extends State<NussNussApp> {
  // Themes are rebuilt only when the glass choice changes, so ordinary session updates stay cheap.
  final _themes = <String, ThemeData>{};
  ThemeData _theme(Brightness b, GlassPref g, {bool highContrast = false}) =>
      _themes.putIfAbsent(
        '${b.name}-${g.name}-$highContrast',
        () => buildTheme(brightness: b, glass: g, highContrast: highContrast),
      );

  @override
  void initState() {
    super.initState();
    if (!widget.session.ready) {
      widget.session.load(
        systemLang:
            WidgetsBinding.instance.platformDispatcher.locale.languageCode,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return SessionScope(
      session: session,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final glass = session.glass;
          return MaterialApp(
            title: session.s.appName,
            debugShowCheckedModeBanner: false,
            locale: Locale(session.lang),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            themeMode: switch (session.theme) {
              ThemePref.system => ThemeMode.system,
              ThemePref.light => ThemeMode.light,
              ThemePref.dark => ThemeMode.dark,
            },
            theme: _theme(Brightness.light, glass),
            darkTheme: _theme(Brightness.dark, glass),
            highContrastTheme: _theme(
              Brightness.light,
              glass,
              highContrast: true,
            ),
            highContrastDarkTheme: _theme(
              Brightness.dark,
              glass,
              highContrast: true,
            ),
            home: const _Root(),
          );
        },
      ),
    );
  }
}

/// Picks the first screen from the session. Kept as one stable home so signing in or out swaps it in place.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final Widget child = !session.ready
        ? const _Launch()
        : session.me == null
        ? const WelcomeScreen()
        : const HomeShell();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: child,
    );
  }
}

class _Launch extends StatelessWidget {
  const _Launch();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NNTheme.of(context).palette.bg,
      body: const Center(child: Coin(size: 96)),
    );
  }
}
