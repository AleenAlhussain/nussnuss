import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nussnuss/app.dart';
import 'package:nussnuss/core/suggest.dart';
import 'package:nussnuss/data/api.dart';
import 'package:nussnuss/data/services.dart';
import 'package:nussnuss/data/session.dart';
import 'package:nussnuss/design/glass.dart';
import 'package:nussnuss/design/motion.dart';
import 'package:nussnuss/design/theme.dart';
import 'package:nussnuss/format.dart';
import 'package:nussnuss/l10n/strings.g.dart';
import 'package:nussnuss/screens/keypad.dart';

import 'fake_server.dart';

class TestApp {
  TestApp(this.server, this.session, this.device);
  final FakeServer server;
  final Session session;
  final QuietDevice device;
}

Future<TestApp> pumpApp(
  WidgetTester tester, {
  Map<String, String>? store,
  FakeServer? server,
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // iPhone 15 at 3x
  tester.view.devicePixelRatio = 3;
  // English, in the Emirates: the currency guess is AED.
  tester.platformDispatcher.localeTestValue = const Locale('en', 'AE');
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  final fake = server ?? FakeServer();
  final device = QuietDevice();
  final session = Session(
    api: Api(baseUrl: 'http://api.test', transport: fake.call),
    store: MemoryStore(store),
    device: device,
  );
  await tester.pumpWidget(NussNussApp(session: session));
  await tester.pumpAndSettle();
  return TestApp(fake, session, device);
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) => tapIt(tester, byKey(k));

Future<void> tapIt(WidgetTester tester, Finder f) async {
  await reveal(tester, f);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Lists build lazily: scrolls the front-most list down, then up, until [f] is built.
Future<void> reveal(WidgetTester tester, Finder f) async {
  if (f.evaluate().isNotEmpty) return;
  final lists = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  if (lists.evaluate().isEmpty) return;
  for (final step in [250.0, -250.0]) {
    try {
      await tester.scrollUntilVisible(
        f,
        step,
        scrollable: lists.last,
        maxScrolls: 40,
      );
      return;
    } on StateError {
      // Not that way: try the other.
    }
  }
}

Future<void> typeAmount(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tapKey(tester, 'key-$k');
  }
}

Future<void> meetsStandards(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

String balance(WidgetTester tester) =>
    tester.widget<RollingText>(byKey('my-balance')).text;

/// Signs up as [name] and makes a group with [friends]; leaves the group screen open.
Future<void> startWithGroup(
  WidgetTester tester, {
  String name = 'Talal',
  String group = 'Salalah trip',
  List<String> friends = const ['Sara', 'Omar'],
}) async {
  await tapKey(tester, 'start');
  await tester.enterText(byKey('name'), name);
  await tapKey(tester, 'start');
  // First run goes straight to making the first group.
  expect(byKey('new-group-sheet'), findsOneWidget);
  await tester.enterText(byKey('group-name'), group);
  for (final f in friends) {
    await tester.enterText(byKey('person-name'), f);
    await tapKey(tester, 'add-person');
  }
  await tapKey(tester, 'create-group');
  expect(byKey('group'), findsOneWidget);
}

/// From the group screen back to the groups list.
Future<void> goBack(WidgetTester tester) async {
  Navigator.of(tester.element(byKey('group'))).pop();
  await tester.pumpAndSettle();
}

/// Leaves every screen so polling timers stop before the test ends.
Future<void> leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
    'first run: name, a group, an expense on the keypad, settle up with undo',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await pumpApp(tester);
      expect(byKey('welcome'), findsOneWidget);
      await meetsStandards(tester);

      await startWithGroup(tester);
      expect(find.text('Nothing spent yet'), findsOneWidget);

      // 100 + 20.5 on the keypad, split equally between three.
      await tapKey(tester, 'add');
      await typeAmount(tester, '100+20.5');
      expect(find.text('= AED 120.50'), findsOneWidget);
      await tester.enterText(byKey('title'), 'Chalet');
      await tapKey(tester, 'details');
      await tapKey(tester, 'cat-stay');
      await meetsStandards(tester);
      await tapKey(tester, 'save-expense');
      expect(byKey('expense-sheet'), findsNothing);
      expect(balance(tester), 'AED 80.33'); // 120.50 paid, 40.17 my share
      expect(find.text('Chalet'), findsOneWidget);
      await meetsStandards(tester);

      // An empty save explains itself.
      await tapKey(tester, 'add');
      await tapKey(tester, 'save-expense');
      expect(find.text('Enter an amount.'), findsOneWidget);
      await tapKey(tester, 'sheet-close');
      expect(byKey('expense-sheet'), findsNothing);

      // Settle up: remind, mark paid, undo, then settle everything.
      await tapKey(tester, 'seg-_Tab.settle');
      expect(byKey('share-summary'), findsOneWidget);
      expect(byKey('remind'), findsNWidgets(2));
      await tapIt(tester, byKey('remind').first);
      expect(app.device.opened.single.host, 'wa.me');
      expect(
        app.device.opened.single.queryParameters['text'],
        contains('Salalah trip'),
      );
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

      await leave(tester);
      semantics.dispose();
    },
  );

  testWidgets('three taps: amount, suggested title, save; repeat with a long '
      'press', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    final emoji = app.server.groupNamed('Salalah trip').emoji;

    // Amount only: the title is the first suggestion for this hour and kind of group, and its
    // category comes with it (Lunch is food), in the summary and in what is saved.
    final first = suggestTitles(
      recent: const [],
      hour: DateTime.now().hour,
      emoji: emoji,
    ).first;
    final title = NNStrings.en.raw('sug_${first.key}');
    final category = NNStrings.en.raw('cat_${first.category}');
    await tapKey(tester, 'add');
    expect(
      tester.widget<Text>(byKey('details-summary')).data,
      'You paid · split equally · $category',
    );
    expect(byKey('sug-0'), findsOneWidget);
    await typeAmount(tester, '45');
    await tapKey(tester, 'save-expense');
    expect(find.text(title), findsOneWidget);
    expect(
      app.server.groupNamed('Salalah trip').expenses.single['category'],
      first.category,
    );
    expect(balance(tester), 'AED 30.00');

    // Typing a title that matches a suggestion picks up its category; picking one by hand wins.
    await tapKey(tester, 'add');
    await tester.enterText(byKey('title'), 'taxi');
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(byKey('details-summary')).data,
      endsWith(NNStrings.en.catTransport),
    );
    await tapKey(tester, 'details');
    await tapKey(tester, 'cat-fun');
    expect(
      tester.widget<Text>(byKey('details-summary')).data,
      endsWith(NNStrings.en.catFun),
    );
    await tapKey(tester, 'sheet-close');

    // The same again, from the sheet's "Repeat" chip and from a long press on +.
    await tapKey(tester, 'add');
    expect(byKey('repeat-last'), findsOneWidget);
    await tapKey(tester, 'repeat-last');
    await tapKey(tester, 'save-expense');
    expect(find.text(title), findsNWidgets(2));
    await tester.longPress(byKey('add'));
    await tester.pumpAndSettle();
    expect(find.text('Added again'), findsOneWidget);
    expect(find.text(title), findsNWidgets(3));
    expect(balance(tester), 'AED 90.00');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text(title), findsNWidgets(2));

    // A repeating bill is part of Plus: asking for one opens the paywall.
    await tapKey(tester, 'add');
    await tapKey(tester, 'details');
    await tapKey(tester, 'seg-week');
    expect(byKey('paywall'), findsOneWidget);
    expect(byKey('store-soon'), findsOneWidget);
    await meetsStandards(tester);
    await tapIt(tester, byKey('sheet-close').last);
    expect(byKey('paywall'), findsNothing);
    await tapKey(tester, 'sheet-close');

    await leave(tester);
    semantics.dispose();
  });

  testWidgets('split a receipt by item, with tax shared by item', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    await tapKey(tester, 'add');
    await typeAmount(tester, '110');
    await tapKey(tester, 'details');
    await tapKey(tester, 'seg-SplitChoice.items');
    final g = app.server.groupNamed('Salalah trip');
    final sara = g.members[1]['id']! as String;
    final me = g.members[0]['id']! as String;
    await tester.enterText(byKey('item-price-0'), '60');
    await tapKey(tester, 'item-0-$me');
    await tapKey(tester, 'add-item');
    await tester.enterText(byKey('item-price-1'), '40');
    await tapKey(tester, 'item-1-$sara');
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(byKey('remaining')).data,
      'AED 10.00 tax and service, shared by item',
    );
    await tapKey(tester, 'save-expense');
    // I had 60 + 6 of the tax; Sara owes me 44.
    expect(balance(tester), 'AED 44.00');
    await leave(tester);
  });

  testWidgets('pay with the way a friend shared, and the share summary', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    final g = app.server.groupNamed('Salalah trip');
    final sara = g.members[1]['id']! as String;
    app.server.setPayTo('Salalah trip', 'Sara', [
      {'kind': 'paypal', 'value': 'https://paypal.me/sara'},
      {'kind': 'iban', 'value': 'AE070331234567890123456'},
    ]);

    // Sara paid 50, split equally: I owe her 25.
    await tapKey(tester, 'add');
    await typeAmount(tester, '50');
    await tester.enterText(byKey('title'), 'Dinner');
    await tapKey(tester, 'details');
    await tapKey(tester, 'payer-$sara');
    await tapKey(tester, 'save-expense');
    await tapKey(tester, 'seg-_Tab.settle');
    expect(byKey('remind'), findsNothing);
    await tapKey(tester, 'pay-with-0');
    expect(
      app.device.opened.single.toString(),
      'https://paypal.me/sara/25.00AED',
    );
    await tapKey(tester, 'pay-with-1');
    expect(app.device.copied.single, 'AE070331234567890123456');
    expect(find.textContaining('Bank (IBAN) copied'), findsOneWidget);
    expect(byKey('share-summary'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('money circle: made from group options, shown on the group', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await startWithGroup(tester);
    await tapKey(tester, 'more');
    expect(byKey('group-options'), findsOneWidget);
    expect(byKey('spending-locked'), findsOneWidget);
    await meetsStandards(tester);
    await tapKey(tester, 'new-circle');
    await tester.enterText(byKey('circle-name'), 'Family circle');
    await tester.enterText(byKey('circle-amount'), '500');
    await tester.pumpAndSettle();
    final turns = [
      for (final e
          in find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith('turn-'),
              )
              .evaluate())
        (e.widget.key! as ValueKey<String>).value,
    ];
    expect(turns, hasLength(3));
    for (final k in turns) {
      await tapKey(tester, k);
    }
    await tapKey(tester, 'create-circle');
    await tapIt(tester, byKey('sheet-close').last);
    expect(find.text('Family circle'), findsOneWidget);
    expect(find.textContaining('You get the pot'), findsOneWidget);
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('new group templates fill the name and emoji', (tester) async {
    await pumpApp(tester);
    await tapKey(tester, 'start');
    await tester.enterText(byKey('name'), 'Huda');
    await tapKey(tester, 'start');
    await tapKey(tester, 'tpl-iftar');
    expect(find.text('Ramadan iftars'), findsOneWidget);
    await tapKey(tester, 'tpl-flat');
    expect(find.text('Our flat'), findsOneWidget);
    await tester.enterText(byKey('group-name'), 'Villa 9');
    await tapKey(tester, 'tpl-office');
    expect(find.text('Villa 9'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('offline: the expense is kept, shown, and sent later', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    app.server.offline = true;
    await tapKey(tester, 'add');
    await typeAmount(tester, '30');
    await tester.enterText(byKey('title'), 'Taxi');
    await tapKey(tester, 'save-expense');
    expect(find.text('Taxi'), findsOneWidget);
    expect(byKey('pending'), findsOneWidget);
    expect(balance(tester), 'AED 20.00');

    app.server.offline = false;
    await app.session.repo.sync();
    await tester.pumpAndSettle();
    expect(byKey('pending'), findsNothing);
    expect(app.server.groupNamed('Salalah trip').expenses, hasLength(1));
    await leave(tester);
  });

  testWidgets('settings: keeping the account, plan, pay-to, looks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    await goBack(tester);
    // With narrow space the other tab shows only its icon, so tap it by key.
    await tapKey(tester, 'tab-1');
    expect(byKey('settings'), findsOneWidget);
    // The status card is at the top; the list builds lazily, so look before scrolling away.
    expect(
      find.text('Keep your groups if you lose this phone'),
      findsOneWidget,
    );
    for (final k in [
      'account-status',
      'recovery',
      'link-device',
      'plan',
      'add-pay-to',
      'look-night',
      'privacy',
    ]) {
      await reveal(tester, byKey(k));
      expect(byKey(k), findsOneWidget);
    }
    await meetsStandards(tester);

    await tapKey(tester, 'recovery');
    expect(byKey('shown-code'), findsOneWidget);
    await tapKey(tester, 'sheet-close');
    await reveal(tester, byKey('account-status'));
    expect(find.text('Your account is saved'), findsOneWidget);

    await tapKey(tester, 'add-pay-to');
    await tester.enterText(byKey('pay-value'), 'not an iban');
    await tapKey(tester, 'save-pay-to');
    expect(find.text('That IBAN does not look right.'), findsOneWidget);
    await tester.enterText(byKey('pay-value'), 'AE07 0331 2345 6789 0123 456');
    await tapKey(tester, 'save-pay-to');
    expect(byKey('pay-to-0'), findsOneWidget);

    // A locked look opens the paywall; the test purchase is not offered without the flag.
    await tapKey(tester, 'look-night');
    expect(byKey('paywall'), findsOneWidget);
    expect(byKey('dev-buy'), findsNothing);
    await tapIt(tester, byKey('sheet-close').last);

    await tapKey(tester, 'privacy');
    expect(app.device.opened.single.path, '/privacy');
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('a code from another phone signs in to the same account', (
    tester,
  ) async {
    final server = FakeServer();
    final first = await pumpApp(tester, server: server);
    await startWithGroup(tester);
    final code = await first.session.api.makeLinkCode();
    await leave(tester);

    await pumpApp(tester, server: server);
    await tapKey(tester, 'have-account');
    await tester.enterText(byKey('code'), 'nope-nope');
    await tapKey(tester, 'use-code');
    expect(find.textContaining('code doesn’t work'), findsOneWidget);
    await tester.enterText(byKey('code'), code.code);
    await tapKey(tester, 'use-code');
    expect(byKey('groups'), findsOneWidget);
    expect(find.text('Salalah trip'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('an invite link opens the join screen and then the group', (
    tester,
  ) async {
    final server = FakeServer();
    final host = await pumpApp(tester, server: server);
    await startWithGroup(tester);
    final g = server.groupNamed('Salalah trip');
    final token = await host.session.api.invite(g.id);
    await leave(tester);

    final guest = await pumpApp(tester, server: server);
    guest.session.openInvite(token);
    await tester.pumpAndSettle();
    expect(byKey('join-screen'), findsOneWidget);
    await tapKey(tester, 'who-${g.members[1]['id']}');
    await tapKey(tester, 'join');
    expect(byKey('group'), findsOneWidget);
    expect(find.text('${g.emoji} Salalah trip'), findsWidgets);
    await leave(tester);
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('large text ($scale×): main screens lay out without '
        'overflowing', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester);
      await startWithGroup(tester);
      await tapKey(tester, 'add');
      await typeAmount(tester, '12');
      await tapKey(tester, 'details');
      await tapKey(tester, 'save-expense');
      await tapKey(tester, 'seg-_Tab.settle');
      await tapKey(tester, 'more');
      await tapIt(tester, byKey('sheet-close').last);
      await goBack(tester);
      await tapKey(tester, 'tab-1');
      expect(byKey('settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await leave(tester);
    });
  }

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

  test('looks: Night is always dark, Saffron follows the setting', () {
    expect(
      buildTheme(
        brightness: Brightness.light,
        glass: GlassPref.clear,
        look: 'night',
      ).brightness,
      Brightness.dark,
    );
    expect(
      buildTheme(
        brightness: Brightness.light,
        glass: GlassPref.clear,
        look: 'saffron',
      ).colorScheme.primary,
      const Color(0xFF8C5A00),
    );
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

  test('invite links', () {
    expect(
      inviteToken(Uri.parse('https://nussnuss.app/join/abcdefgh12')),
      'abcdefgh12',
    );
    expect(inviteToken(Uri.parse('/join/abcdefgh12')), 'abcdefgh12');
    expect(inviteToken(Uri.parse('https://nussnuss.app/g/abc')), isNull);
    expect(inviteToken(Uri.parse('/')), isNull);
  });
}
