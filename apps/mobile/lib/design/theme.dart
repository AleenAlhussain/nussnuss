import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// The person's glass choice. Frosted also turns on by itself with Increase Contrast.
enum GlassPref { clear, frosted }

/// Palette and glass resolved for one brightness and contrast level.
/// Read it with `NNTheme.of(context)`; every NussNuss widget draws from this, never from raw hex.
@immutable
class NNTheme extends ThemeExtension<NNTheme> {
  const NNTheme({
    required this.palette,
    required this.glass,
    required this.isDark,
    required this.highContrast,
  });

  final NNPalette palette;
  final NNGlassStyle glass;
  final bool isDark;
  final bool highContrast;

  bool get frosted => glass.bordered;

  static NNTheme of(BuildContext context) =>
      Theme.of(context).extension<NNTheme>()!;

  @override
  NNTheme copyWith({
    NNPalette? palette,
    NNGlassStyle? glass,
    bool? isDark,
    bool? highContrast,
  }) => NNTheme(
    palette: palette ?? this.palette,
    glass: glass ?? this.glass,
    isDark: isDark ?? this.isDark,
    highContrast: highContrast ?? this.highContrast,
  );

  // Theme changes are rare and instant (no cross-fade of the palette), so lerp just snaps halfway.
  @override
  NNTheme lerp(NNTheme? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Increase Contrast: secondary text reads as primary, hairlines get darker, glass goes solid.
NNPalette _contrasted(NNPalette p) => NNPalette(
  bg: p.bg,
  surface: p.surface,
  surface2: p.surface2,
  separator: p.text3,
  text: p.text,
  text2: p.text,
  text3: p.text2,
  accent: p.accent,
  onAccent: p.onAccent,
  accentSoft: p.accentSoft,
  onAccentSoft: p.onAccentSoft,
  highlight: p.highlight,
  onHighlight: p.onHighlight,
  success: p.success,
  successSoft: p.successSoft,
  danger: p.danger,
  dangerSoft: p.dangerSoft,
  focus: p.focus,
);

/// The palette for a look ('default', 'night', 'saffron') in one brightness. Night is always dark.
NNPalette paletteFor(String look, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (look) {
    'night' => NNLooks.nightDark,
    'saffron' => dark ? NNLooks.saffronDark : NNLooks.saffronLight,
    _ => dark ? NNColors.dark : NNColors.light,
  };
}

/// Builds the Material theme from the tokens. [highContrast] themes are picked by MaterialApp itself
/// when the system asks for more contrast.
ThemeData buildTheme({
  required Brightness brightness,
  required GlassPref glass,
  bool highContrast = false,
  String look = 'default',
}) {
  if (NNLooks.alwaysDark.contains(look)) brightness = Brightness.dark;
  final dark = brightness == Brightness.dark;
  final base = paletteFor(look, brightness);
  final p = highContrast ? _contrasted(base) : base;
  final frosted = highContrast || glass == GlassPref.frosted;
  final g = switch ((dark, frosted)) {
    (false, false) => NNGlass.regularLight,
    (true, false) => NNGlass.regularDark,
    (false, true) => NNGlass.frostedLight,
    (true, true) => NNGlass.frostedDark,
  };

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    primaryContainer: p.accentSoft,
    onPrimaryContainer: p.onAccentSoft,
    secondary: p.highlight,
    onSecondary: p.onHighlight,
    error: p.danger,
    onError: p.surface,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.text2,
    surfaceContainerHighest: p.surface2,
    outline: p.separator,
    outlineVariant: p.separator,
  );

  final text = const TextTheme(
    displayLarge: NNType.amountHero,
    headlineLarge: NNType.largeTitle,
    headlineMedium: NNType.title1,
    headlineSmall: NNType.title2,
    titleLarge: NNType.title3,
    titleMedium: NNType.headline,
    titleSmall: NNType.subhead,
    bodyLarge: NNType.body,
    bodyMedium: NNType.callout,
    bodySmall: NNType.footnote,
    labelLarge: NNType.headline,
    labelMedium: NNType.subhead,
    labelSmall: NNType.caption,
  ).apply(bodyColor: p.text, displayColor: p.text);

  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(NNRadius.control),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    highlightColor: p.text.withValues(alpha: 0.06),
    dividerColor: p.separator,
    focusColor: p.focus.withValues(alpha: 0.24),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionHandleColor: p.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface2,
      hintStyle: NNType.body.copyWith(color: p.text3),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NNSpace.md,
        vertical: 14,
      ),
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(
        borderSide: BorderSide(color: p.focus, width: 2),
      ),
      errorBorder: field.copyWith(
        borderSide: BorderSide(color: p.danger, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? p.surface2 : p.text,
      contentTextStyle: NNType.subhead.copyWith(
        color: dark ? p.text : p.bg,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: dark ? p.accent : NNColors.dark.accent,
      shape: const StadiumBorder(),
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(
        NNSpace.md,
        0,
        NNSpace.md,
        NNLayout.tabBar + NNSpace.xl,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      primaryColor: p.accent,
      brightness: brightness,
    ),
    extensions: [
      NNTheme(palette: p, glass: g, isDark: dark, highContrast: highContrast),
    ],
  );
}
