import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nussnuss/app.dart';
import 'package:nussnuss/data/api.dart';
import 'package:nussnuss/data/session.dart';
import 'package:nussnuss/design/glass.dart';
import 'package:nussnuss/design/theme.dart';
import 'package:nussnuss/format.dart';
import 'package:nussnuss/l10n/strings.g.dart';
import 'package:nussnuss/screens/keypad.dart';

import 'fake_server.dart';

Future<FakeServer> pumpApp(
  WidgetTester tester, {
  Map<String, String>? store,
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // iPhone 15 at 3x
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final server = FakeServer();
  final session = Session(
    api: Api(baseUrl: 'http://api.test', transport: server.call),
    store: MemoryStore(store),
  );
  await tester.pumpWidget(NussNussApp(session: session));
  await tester.pumpAndSettle();
  return server;
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) => tapIt(tester, byKey(k));

Future<void> tapIt(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> meetsStandards(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  testWidgets(
    'first run: name, a group, an expense on the keypad, settle up with undo',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      expect(byKey('welcome'), findsOneWidget);
      await meetsStandards(tester);

      await tapKey(tester, 'start');
      await tester.enterText(byKey('name'), 'Talal');
      await tapKey(tester, 'start');
      expect(byKey('groups'), findsOneWidget);
      expect(find.text('No groups yet'), findsOneWidget);
      await meetsStandards(tester);

      // A new group with two friends.
      await tapKey(tester, 'add');
      await tester.enterText(byKey('group-name'), 'Salalah trip');
      for (final name in ['Sara', 'Omar']) {
        await tester.enterText(byKey('person-name'), name);
        await tapKey(tester, 'add-person');
      }
      await tapKey(tester, 'create-group');
      expect(byKey('group'), findsOneWidget);
      expect(find.text('Nothing spent yet'), findsOneWidget);

      // 100 + 20.5 on the keypad, split equally between three.
      await tapKey(tester, 'add');
      for (final k in '100+20.5'.split('')) {
        await tapKey(tester, 'key-$k');
      }
      expect(find.text('= AED 120.50'), findsOneWidget);
      await tester.enterText(byKey('title'), 'Chalet');
      await tapKey(tester, 'cat-stay');
      await tapKey(tester, 'save-expense');
      expect(byKey('expense-sheet'), findsNothing);
      expect(
        find.text('AED 80.33'),
        findsOneWidget,
      ); // 120.50 paid, 40.17 my share
      expect(find.text('Chalet'), findsOneWidget);
      await meetsStandards(tester);

      // An empty save explains itself.
      await tapKey(tester, 'add');
      await tapKey(tester, 'save-expense');
      expect(find.text('Enter an amount.'), findsOneWidget);
      await tapKey(tester, 'sheet-close');
      expect(byKey('expense-sheet'), findsNothing);

      // Settle up: mark paid, undo, then settle everything.
      await tapKey(tester, 'seg-_Tab.settle');
      expect(byKey('mark-paid'), findsNWidgets(2));
      await tapIt(tester, byKey('mark-paid').first);
      expect(find.text('Marked as paid'), findsOneWidget);
      expect(byKey('mark-paid'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(byKey('mark-paid'), findsNWidgets(2));
      await tapIt(tester, byKey('mark-paid').first);
      await tapIt(tester, byKey('mark-paid').first);
      expect(byKey('all-settled'), findsOneWidget);

      // Leave the group screen so its polling timer stops.
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets('Arabic lays out right to left with Arabic copy', (tester) async {
    await pumpApp(tester, store: {'nn:lang': 'ar'});
    expect(find.text('خلّيها نص نص.'), findsOneWidget);
    expect(
      Directionality.of(tester.element(byKey('welcome'))),
      TextDirection.rtl,
    );
  });

  testWidgets('glass turns solid with Frosted and with Increase Contrast', (
    tester,
  ) async {
    Widget host(GlassPref pref) => MaterialApp(
      theme: buildTheme(brightness: Brightness.light, glass: pref),
      highContrastTheme: buildTheme(
        brightness: Brightness.light,
        glass: pref,
        highContrast: true,
      ),
      home: const Scaffold(
        body: Center(child: Glass(child: SizedBox(width: 120, height: 44))),
      ),
    );

    // MaterialApp cross-fades theme changes, so let each one finish before looking.
    await tester.pumpWidget(host(GlassPref.clear));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.pumpWidget(host(GlassPref.frosted));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(host(GlassPref.clear));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
  });

  test('keypad rules match the web', () {
    expect(keypadPress('', '.', 'AED'), '0.');
    expect(keypadPress('12.5', '5', 'AED'), '12.55');
    expect(keypadPress('12.55', '1', 'AED'), '12.55');
    expect(keypadPress('1.25', '5', 'KWD'), '1.255');
    expect(keypadPress('', '.', 'JPY'), '');
    expect(keypadPress('', '+', 'AED'), '');
    expect(keypadPress('5+', '-', 'AED'), '5+');
    expect(keypadPress('5+2.', '.', 'AED'), '5+2.');
    expect(keypadPress('5+', '.', 'AED'), '5+0.');
    expect(keypadPress('12', 'back', 'AED'), '1');
  });

  test('day labels', () {
    final now = DateTime(2026, 10, 25, 9);
    expect(
      dayLabel(DateTime(2026, 10, 25, 23), NNStrings.en, now: now),
      'Today',
    );
    expect(dayLabel(DateTime(2026, 10, 24, 1), NNStrings.ar, now: now), 'أمس');
  });
}
