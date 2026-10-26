import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/accessibility.dart';
import 'data/native.dart';
import 'data/session.dart';
import 'design/coin.dart';
import 'design/page.dart';
import 'design/theme.dart';
import 'design/tokens.g.dart';
import 'screens/home.dart';
import 'screens/intro.dart';
import 'screens/join_screen.dart';
import 'screens/welcome_screen.dart';

class NussNussApp extends StatefulWidget {
  const NussNussApp({super.key, required this.session});
  final Session session;

  @override
  State<NussNussApp> createState() => _NussNussAppState();
}

/// The invite code in a link like https://nussnuss.app/j/k7m2q9xd4p (or the older /join/…), or
/// null.
String? inviteToken(Uri uri) {
  final seg = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  return seg.length == 2 &&
          (seg[0] == 'j' || seg[0] == 'join') &&
          seg[1].length >= 8
      ? seg[1]
      : null;
}

class _NussNussAppState extends State<NussNussApp> with WidgetsBindingObserver {
  // Themes are rebuilt only when the glass choice changes, so ordinary session updates stay cheap.
  final _themes = <String, ThemeData>{};
  ThemeData _theme(
    Brightness b,
    GlassPref g,
    String look, {
    bool highContrast = false,
  }) => _themes.putIfAbsent(
    '${b.name}-${g.name}-$look-$highContrast',
    () => buildTheme(
      brightness: b,
      glass: g,
      highContrast: highContrast,
      look: look,
    ),
  );

  @override
  void initState() {
    super.initState();
    // Registered before MaterialApp's own handler, so invite links are ours to open.
    WidgetsBinding.instance.addObserver(this);
    final token = inviteToken(
      Uri.parse(WidgetsBinding.instance.platformDispatcher.defaultRouteName),
    );
    if (token != null) widget.session.pendingInvite = token;
    if (!widget.session.ready) {
      widget.session.load(
        systemLang:
            WidgetsBinding.instance.platformDispatcher.locale.languageCode,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A link tapped while the app is open (Universal Links on iOS, App Links on Android).
  @override
  Future<bool> didPushRouteInformation(RouteInformation info) async {
    // A shortcut link (nussnuss://add) that reached Flutter: Home acts on it.
    if (info.uri.scheme == 'nussnuss') {
      shortcutAction.value = info.uri.host;
      return true;
    }
    final token = inviteToken(info.uri);
    if (token == null) return false;
    widget.session.openInvite(token);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return SessionScope(
      session: session,
      child: ListenableBuilder(
        listenable: Listenable.merge([session, reduceTransparency]),
        builder: (context, _) {
          // Reduce Transparency turns glass solid, like Increase Contrast does.
          final glass = reduceTransparency.value
              ? GlassPref.solid
              : session.glass;
          final look = session.activeLook;
          return MaterialApp(
            title: session.s.appName,
            debugShowCheckedModeBanner: false,
            locale: Locale(session.lang),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            themeMode: NNLooks.alwaysDark.contains(look)
                ? ThemeMode.dark
                : switch (session.theme) {
                    ThemePref.system => ThemeMode.system,
                    ThemePref.light => ThemeMode.light,
                    ThemePref.dark => ThemeMode.dark,
                  },
            theme: _theme(Brightness.light, glass, look),
            darkTheme: _theme(Brightness.dark, glass, look),
            highContrastTheme: _theme(
              Brightness.light,
              glass,
              look,
              highContrast: true,
            ),
            highContrastDarkTheme: _theme(
              Brightness.dark,
              glass,
              look,
              highContrast: true,
            ),
            // Everything shares the theme's text style, including what floats above the pages
            // (the tab bar and toasts live in the root overlay, outside any page's Material).
            // The launch intro plays over the app, which builds underneath from the first frame.
            builder: (context, child) => Material(
              type: MaterialType.transparency,
              child: LaunchIntro(child: child!),
            ),
            // Launched from a link, the platform names the link as the first route; the root
            // screen reads the invite from the session instead of pushing a route for it.
            onGenerateInitialRoutes: (_) => [_rootRoute()],
            onGenerateRoute: (settings) =>
                settings.name == Navigator.defaultRouteName
                ? _rootRoute()
                : null,
          );
        },
      ),
    );
  }
}

Route<void> _rootRoute() => MaterialPageRoute<void>(
  settings: const RouteSettings(name: Navigator.defaultRouteName),
  builder: (_) => const _Root(),
);

/// Picks the first screen from the session. Kept as one stable home so signing in or out swaps it in place.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final invite = session.pendingInvite;
    final Widget child = !session.ready
        ? const _Launch()
        : invite != null
        ? JoinScreen(key: ValueKey('join-$invite'), token: invite)
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
      body: Ambient.behind(const Center(child: Coin(size: 96))),
    );
  }
}
