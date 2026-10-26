// The main screens as images, in light, dark and Arabic. CI compares them with test/goldens on every
// push, and publishes the latest ones as the v2-screens pre-release so they can be reviewed without a
// phone. Text uses Readex Pro (bundled with the app, Latin and Arabic) instead of the test font, and
// icons use the real Material Icons, so the images look like the app.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nussnuss/core/suggest.dart';
import 'package:nussnuss/format.dart' show clock;

import 'widget_test.dart'
    show goBack, leave, pumpApp, startWithGroup, tapKey, typeAmount;

Future<void> _loadFonts() async {
  Future<ByteData> asset(String w) =>
      rootBundle.load('assets/fonts/ReadexPro-$w.ttf');
  for (final family in ['Roboto', 'ReadexPro']) {
    final loader = FontLoader(family);
    for (final w in ['Medium', 'SemiBold', 'Bold']) {
      loader.addFont(asset(w));
    }
    await loader.load();
  }
  // The Material Icons font ships with the Flutter SDK, next to the test runner.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    final f = File(
      '${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (f.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
      break;
    }
    dir = dir.parent;
  }
}

/// Each look of the app that gets its own set of images.
const _modes = <String, Map<String, String>>{
  'light': {},
  'dark': {'nn:theme': 'dark'},
  'ar': {'nn:lang': 'ar'},
};

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  setUpAll(_loadFonts);
  // Suggestions follow the time of day: pin it to lunchtime so the images do not depend on when CI runs.
  // Times on Home and in Activity ("1:00 PM") follow the same pinned clock.
  setUp(() {
    suggestionClock = () => DateTime(2026, 10, 25, 13);
    clock = () => DateTime(2026, 10, 25, 13);
  });
  tearDown(() {
    suggestionClock = DateTime.now;
    clock = DateTime.now;
  });

  for (final MapEntry(key: mode, value: prefs) in _modes.entries) {
    testWidgets('screens · $mode', (tester) async {
      await pumpApp(tester, store: {...prefs});
      await _shot(tester, '$mode-01-welcome');

      await startWithGroup(
        tester,
        name: mode == 'ar' ? 'طلال' : 'Talal',
        group: mode == 'ar' ? 'رحلة صلالة' : 'Salalah trip',
        friends: mode == 'ar' ? const ['سارة', 'عمر'] : const ['Sara', 'Omar'],
      );
      await tapKey(tester, 'add');
      await typeAmount(tester, '120');
      await _shot(tester, '$mode-02-add');
      await tapKey(tester, 'details');
      await _shot(tester, '$mode-03-details');
      await tapKey(tester, 'save-expense');
      await tapKey(tester, 'add');
      await typeAmount(tester, '45');
      await tapKey(tester, 'save-expense');
      await _shot(tester, '$mode-04-group');

      await tapKey(tester, 'seg-_Tab.settle');
      await _shot(tester, '$mode-05-settle');

      await tapKey(tester, 'more');
      await _shot(tester, '$mode-06-options');
      await tapKey(tester, 'sheet-close');

      // The three tabs.
      await goBack(tester);
      await _shot(tester, '$mode-07-home');
      await tapKey(tester, 'tab-1');
      await _shot(tester, '$mode-08-activity');
      await tapKey(tester, 'tab-2');
      await _shot(tester, '$mode-09-you');

      await leave(tester);
    });
  }
}
