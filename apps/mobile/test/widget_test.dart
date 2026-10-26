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
import 'package:nussnuss/design/widgets.dart';
import 'package:nussnuss/format.dart';
import 'package:nussnuss/l10n/strings.g.dart';
import 'package:nussnuss/screens/intro.dart';
import 'package:nussnuss/screens/keypad.dart';

import 'fake_server.dart';

class TestApp {
  TestApp(this.server, this.session, this.device);
  final FakeServer server;
  final Session session;
  final QuietDevice device;
}

/// Starts the app. The launch intro is off unless [intro]; without [settle] it returns right after
/// the first frame, for tests that step through time themselves.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  Map<String, String>? store,
  FakeServer? server,
  bool intro = false,
  bool settle = true,
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
  launchIntroEnabled = intro;
  await tester.pumpWidget(NussNussApp(session: session));
  if (settle) await tester.pumpAndSettle();
  return TestApp(fake, session, device);
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) => tapIt(tester, byKey(k));

Future<void> tapIt(WidgetTester tester, Finder f) async {
  await reveal(tester, f);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  // ensureVisible lines the target up with the top of its list, which on a long page is under
  // the top bar; if a tap there would not reach it, bring it to the middle first.
  if (!_reachable(tester, f)) {
    await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
    await tester.pumpAndSettle();
  }
  expect(_reachable(tester, f), isTrue, reason: 'nothing covers $f');
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Whether a tap at the centre of [f] lands on it (not on a bar floating over it).
bool _reachable(WidgetTester tester, Finder f) {
  final target = tester.renderObject(f);
  final hit = tester.hitTestOnBinding(tester.getCenter(f));
  return hit.path.any((e) => e.target == target);
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
      // Let the top bar finish handing the title over before anything is checked.
      await tester.pumpAndSettle();
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

/// Records haptics instead of playing them, for this test.
List<Haptic> recordHaptics() {
  final played = <Haptic>[];
  final before = hapticPlayer;
  hapticPlayer = played.add;
  addTearDown(() => hapticPlayer = before);
  return played;
}

/// On the group screen: an expense of [amount] for [title], paid by me, split equally.
Future<void> addExpense(
  WidgetTester tester,
  String amount,
  String title,
) async {
  await tapKey(tester, 'add');
  await typeAmount(tester, amount);
  await tester.enterText(byKey('title'), title);
  await tapKey(tester, 'save-expense');
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

  testWidgets('split by item is part of Plus', (tester) async {
    await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    await tapKey(tester, 'add');
    await tapKey(tester, 'details');
    await tapKey(tester, 'seg-SplitChoice.items');
    expect(byKey('paywall'), findsOneWidget);
    await tapIt(tester, byKey('sheet-close').last);
    // Still split equally: nothing changed without Plus.
    expect(byKey('add-item'), findsNothing);
    await tapKey(tester, 'sheet-close');
    await leave(tester);
  });

  testWidgets('split a receipt by item, with tax shared by item', (
    tester,
  ) async {
    final server = FakeServer()..plus = true;
    final app = await pumpApp(tester, server: server);
    await startWithGroup(tester, friends: const ['Sara']);
    await tapKey(tester, 'add');
    await typeAmount(tester, '110');
    await tapKey(tester, 'details');
    await tapKey(tester, 'seg-SplitChoice.items');
    final g = app.server.groupNamed('Salalah trip');
    final sara = g.members[1]['id']! as String;
    final me = g.members[0]['id']! as String;
    // Everyone is on a new line; take people off to say who had what.
    await tester.enterText(byKey('item-price-0'), '60');
    await tapKey(tester, 'item-0-$sara');
    await tapKey(tester, 'add-item');
    await tester.enterText(byKey('item-price-1'), '40');
    await tapKey(tester, 'item-1-$me');
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

  testWidgets('scan a receipt into lines, with its total as the amount', (
    tester,
  ) async {
    final server = FakeServer()..plus = true;
    final app = await pumpApp(tester, server: server);
    await startWithGroup(tester, friends: const ['Sara']);
    app.device.receiptText = [
      'SHAWARMA HOUSE',
      'Tel 04 123 4567',
      '2 x Chicken shawarma   24.00',
      'Fries 8.50',
      'Fresh juice x2 ..... 18',
      'Subtotal 50.50',
      'VAT 5% 2.53',
      'Service 5.00',
      'TOTAL AED 58.03',
      'Cash 60.00',
      'Change 1.97',
      'شاي كرك ٣٫٥٠',
    ].join('\n');
    await tapKey(tester, 'add');
    await tapKey(tester, 'details');
    await tapKey(tester, 'seg-SplitChoice.items');
    await tapKey(tester, 'scan-receipt');
    expect(byKey('scan-sheet'), findsOneWidget);
    await tapKey(tester, 'scan-camera');
    expect(app.device.scans, [true]);

    // The empty first line made way for the four read from the receipt, everyone on each.
    for (final (i, name, price) in [
      (0, 'Chicken shawarma', '24.00'),
      (1, 'Fries', '8.50'),
      (2, 'Fresh juice', '18.00'),
      (3, 'شاي كرك', '3.50'),
    ]) {
      expect(
        tester.widget<TextField>(byKey('item-name-$i')).controller!.text,
        name,
      );
      expect(
        tester.widget<TextField>(byKey('item-price-$i')).controller!.text,
        price,
      );
    }
    expect(byKey('item-name-4'), findsNothing);
    expect(find.text('Found 4 items'), findsOneWidget);
    // No amount was typed, so the receipt's total is the amount; the rest is tax and service.
    expect(tester.widget<Text>(byKey('amount')).data, '58.03');
    expect(
      tester.widget<Text>(byKey('remaining')).data,
      'AED 4.03 tax and service, shared by item',
    );
    await tapKey(tester, 'save-expense');
    // Each had half of every line; the odd cent of the tax stays with me, so Sara owes 29.01.
    expect(balance(tester), 'AED 29.01');

    // A photo with no prices on it says so and leaves the lines as they are.
    app.device.receiptText = 'a blurry photo';
    await tapKey(tester, 'add');
    await tapKey(tester, 'details');
    await tapKey(tester, 'seg-SplitChoice.items');
    await tapKey(tester, 'scan-receipt');
    await tapKey(tester, 'scan-library');
    expect(app.device.scans, [true, false]);
    expect(
      tester.widget<Text>(byKey('scan-note')).data,
      'Couldn’t read that receipt. Add the items by hand.',
    );
    expect(byKey('item-price-0'), findsOneWidget);
    expect(byKey('item-price-1'), findsNothing);

    // Cancelling the photo changes nothing.
    app.device.receiptText = null;
    await tapKey(tester, 'scan-receipt');
    await tapKey(tester, 'scan-camera');
    expect(byKey('item-price-1'), findsNothing);
    await tapKey(tester, 'sheet-close');
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

  test('glass levels: Clear, Tinted (the default), Solid; older choices '
      'carry over', () {
    expect(GlassPref.values, [
      GlassPref.clear,
      GlassPref.tinted,
      GlassPref.solid,
    ]);
    expect(GlassPref.parse(null), GlassPref.tinted);
    expect(GlassPref.parse('tinted'), GlassPref.tinted);
    expect(GlassPref.parse('clear'), GlassPref.clear);
    expect(GlassPref.parse('auto'), GlassPref.clear);
    expect(GlassPref.parse('solid'), GlassPref.solid);
    expect(GlassPref.parse('frosted'), GlassPref.solid);
  });

  testWidgets('glass blurs when Clear or Tinted, not when Solid or with '
      'Increase Contrast, and never sits on glass', (tester) async {
    Widget host(GlassPref pref, {bool nested = false}) => MaterialApp(
      theme: buildTheme(brightness: Brightness.light, glass: pref),
      highContrastTheme: buildTheme(
        brightness: Brightness.light,
        glass: pref,
        highContrast: true,
      ),
      home: Scaffold(
        body: Center(
          child: Glass(
            child: nested
                ? const Glass(child: SizedBox(width: 120, height: 44))
                : const SizedBox(width: 120, height: 44),
          ),
        ),
      ),
    );

    // MaterialApp cross-fades theme changes, so let each one finish before looking.
    await tester.pumpWidget(host(GlassPref.tinted));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.pumpWidget(host(GlassPref.clear));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);

    // Glass inside glass is a plain fill.
    await tester.pumpWidget(host(GlassPref.tinted, nested: true));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.pumpWidget(host(GlassPref.solid));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(host(GlassPref.clear));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('settings: the glass level has three choices and starts '
      'Tinted', (tester) async {
    final app = await pumpApp(tester);
    expect(app.session.glass, GlassPref.tinted);
    await startWithGroup(tester);
    await goBack(tester);
    await tapKey(tester, 'tab-1');
    await reveal(tester, byKey('settings-glass'));
    for (final g in GlassPref.values) {
      expect(byKey('seg-$g'), findsOneWidget);
    }
    expect(
      tester.widget<Segmented<GlassPref>>(byKey('settings-glass')).selected,
      GlassPref.tinted,
    );
    await tapKey(tester, 'seg-GlassPref.solid');
    expect(app.session.glass, GlassPref.solid);
    expect((app.session.store as MemoryStore).values['nn:glass'], 'solid');
    await leave(tester);

    // A choice saved by an older version: Frosted is now Solid, Auto is Clear.
    final frosted = await pumpApp(tester, store: {'nn:glass': 'frosted'});
    expect(frosted.session.glass, GlassPref.solid);
    await leave(tester);
    final auto = await pumpApp(tester, store: {'nn:glass': 'auto'});
    expect(auto.session.glass, GlassPref.clear);
    await leave(tester);
  });

  testWidgets('tabs keep their own pages; tapping the tab you are on scrolls '
      'up, then goes back to its first page', (tester) async {
    await pumpApp(tester);
    await startWithGroup(tester);
    // The tab bar floats over the group too.
    expect(byKey('tab-0'), findsOneWidget);

    // Settings and back: the group is still open under Groups.
    await tapKey(tester, 'tab-1');
    expect(byKey('settings'), findsOneWidget);
    await tapKey(tester, 'tab-0');
    expect(byKey('group'), findsOneWidget);

    // Already at the top of the group: tapping Groups goes back to the list.
    await tapKey(tester, 'tab-0');
    expect(byKey('group'), findsNothing);
    expect(byKey('groups'), findsOneWidget);
    expect(find.text('Salalah trip'), findsOneWidget);

    // Scrolled down in Settings: tapping Settings scrolls back to the top.
    await tapKey(tester, 'tab-1');
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: byKey('settings'),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    await tester.drag(byKey('settings'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(position().pixels, greaterThan(100));
    await tapKey(tester, 'tab-1');
    expect(position().pixels, 0);
    await leave(tester);
  });

  testWidgets('a notification opens its group inside the Groups tab', (
    tester,
  ) async {
    final server = FakeServer();
    await pumpApp(tester, server: server);
    await startWithGroup(tester);
    final g = server.groupNamed('Salalah trip');
    await goBack(tester);
    server.notifications['Talal'] = [
      {
        'id': 'n1',
        'kind': 'reminder',
        'groupId': g.id,
        'data': {
          'to': 'Sara',
          'amount': 2500,
          'currency': 'AED',
          'group': 'Salalah trip',
          'emoji': g.emoji,
        },
        'createdAt': DateTime.now().toIso8601String(),
        'read': false,
      },
    ];
    await tapKey(tester, 'bell');
    expect(byKey('notifications-sheet'), findsOneWidget);
    await tapKey(tester, 'notice-n1');
    expect(byKey('notifications-sheet'), findsNothing);
    expect(byKey('group'), findsOneWidget);
    expect(byKey('tab-0'), findsOneWidget);
    // Back goes to the groups list underneath.
    await goBack(tester);
    expect(byKey('groups'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('search groups: by name and people, expenses by title, and '
      'recent searches', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await startWithGroup(tester);
    await addExpense(tester, '120', 'Chalet');
    await goBack(tester);
    await tapKey(tester, 'add');
    await tester.enterText(byKey('group-name'), 'Our flat');
    await tester.enterText(byKey('person-name'), 'Huda');
    await tapKey(tester, 'add-person');
    await tapKey(tester, 'create-group');
    await goBack(tester);
    expect(byKey('search'), findsOneWidget);
    await meetsStandards(tester);

    Future<void> search(String q) async {
      await tester.enterText(byKey('search'), q);
      await tester.pumpAndSettle();
    }

    await search('sala');
    expect(find.text('Salalah trip'), findsOneWidget);
    expect(find.text('Our flat'), findsNothing);
    await search('huda');
    expect(find.text('Our flat'), findsOneWidget);
    expect(find.text('Salalah trip'), findsNothing);
    // Expenses are found in the groups kept on this phone.
    await search('chal');
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Chalet'), findsOneWidget);
    await search('nothing like this');
    expect(find.text('No results for “nothing like this”'), findsOneWidget);

    // A search that led somewhere is remembered.
    await search('chal');
    await tapIt(tester, find.text('Chalet'));
    expect(byKey('group'), findsOneWidget);
    await goBack(tester);
    await search('');
    expect(byKey('recent-searches'), findsOneWidget);
    await tapKey(tester, 'recent-0');
    expect(find.text('Chalet'), findsOneWidget);
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('search in a group: by title, who paid or amount', (
    tester,
  ) async {
    await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    for (final (amount, title) in [
      ('10', 'Taxi'),
      ('20', 'Lunch'),
      ('30', 'Fuel'),
      ('40', 'Tickets'),
    ]) {
      await addExpense(tester, amount, title);
    }
    // A short list needs no search.
    expect(byKey('expense-search'), findsNothing);
    await addExpense(tester, '55', 'Dinner');
    await reveal(tester, byKey('expense-search'));

    Future<void> search(String q) async {
      await tester.enterText(byKey('expense-search'), q);
      await tester.pumpAndSettle();
    }

    await search('fue');
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);
    await search('55');
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Fuel'), findsNothing);
    await search('talal');
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    await search('zzz');
    expect(byKey('no-results'), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);
    await leave(tester);
  });

  testWidgets('a form error shakes the field or message, with the error '
      'haptic', (tester) async {
    final played = recordHaptics();
    await pumpApp(tester);
    await startWithGroup(tester);
    await tapKey(tester, 'add');
    Shake shakeOf(Finder f) => tester.widget<Shake>(
      find.ancestor(of: f, matching: find.byType(Shake)).first,
    );

    played.clear();
    await tapKey(tester, 'save-expense');
    expect(find.text('Enter an amount.'), findsOneWidget);
    expect(played, [Haptic.error]);
    expect(shakeOf(byKey('expense-error')).trigger, 1);
    // No amount: the amount shakes too.
    expect(shakeOf(byKey('amount')).trigger, 1);
    // The same mistake again shakes again.
    await tapKey(tester, 'save-expense');
    expect(played, [Haptic.error, Haptic.error]);
    expect(shakeOf(byKey('expense-error')).trigger, 2);
    await tapKey(tester, 'sheet-close');
    await leave(tester);

    // A code that does not work.
    await pumpApp(tester);
    await tapKey(tester, 'have-account');
    played.clear();
    await tester.enterText(byKey('code'), 'nope-nope');
    await tapKey(tester, 'use-code');
    expect(find.textContaining('code doesn’t work'), findsOneWidget);
    expect(played, [Haptic.error]);
    await leave(tester);
  });

  testWidgets('pull to refresh reloads the group and the groups, with a '
      'light tap', (tester) async {
    final played = recordHaptics();
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    final id = app.server.groupNamed('Salalah trip').id;
    int count(String call) => app.server.calls.where((c) => c == call).length;

    final group = count('GET /groups/$id');
    played.clear();
    await tester.drag(byKey('group'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(count('GET /groups/$id'), group + 1);
    expect(played, contains(Haptic.light));
    expect(byKey('pull-refresh'), findsNothing);

    await goBack(tester);
    final groups = count('GET /groups');
    played.clear();
    await tester.drag(byKey('groups'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(count('GET /groups'), groups + 1);
    expect(played, contains(Haptic.light));

    // A short pull does nothing.
    await tester.drag(byKey('groups'), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(count('GET /groups'), groups + 1);
    await leave(tester);
  });

  group('launch intro', () {
    /// Moves time on in 50 ms frames.
    Future<void> run(WidgetTester tester, int ms) async {
      for (var t = 0; t < ms; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Finder inIntro(Finder f) =>
        find.descendant(of: byKey('intro'), matching: f);

    testWidgets('the first launch plays the whole story, then the app is '
        'usable', (tester) async {
      final app = await pumpApp(tester, intro: true, settle: false);
      await tester.pump();
      expect(byKey('intro'), findsOneWidget);
      await run(tester, 1000);
      // The app is already there underneath.
      expect(byKey('welcome'), findsOneWidget);
      expect(byKey('intro-coin'), findsOneWidget);
      await run(tester, 2300);
      expect(byKey('intro-wordmark'), findsOneWidget);
      expect(inIntro(find.text('Split it fair.')), findsOneWidget);
      await run(tester, 600);
      // At 3.7 s the doors open.
      expect(byKey('intro-doors'), findsOneWidget);
      await run(tester, 1000);
      expect(byKey('intro'), findsNothing);
      expect(
        (app.session.store as MemoryStore).values['nn:introSeen'],
        isNotNull,
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'start');
      expect(byKey('name'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('haptics: a light tap as the coin pops in, a firm one as the '
        'halves snap back', (tester) async {
      final played = recordHaptics();
      await pumpApp(tester, intro: true, settle: false);
      await tester.pump();
      await run(tester, 850);
      expect(played, isEmpty);
      await run(tester, 100);
      expect(played, [Haptic.light]);
      await run(tester, 1550);
      expect(played, [Haptic.light]);
      await run(tester, 100);
      expect(played, [Haptic.light, Haptic.medium]);
      await run(tester, 2300);
      expect(byKey('intro'), findsNothing);
      await leave(tester);
    });

    testWidgets('Skip goes straight to the doors', (tester) async {
      final played = recordHaptics();
      await pumpApp(tester, intro: true, settle: false);
      await tester.pump();
      await run(tester, 400);
      await tester.tap(byKey('intro-skip'));
      await tester.pump();
      expect(byKey('intro-doors'), findsOneWidget);
      await run(tester, 1100);
      expect(byKey('intro'), findsNothing);
      expect(played, isNot(contains(Haptic.medium)));
      expect(byKey('welcome'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('later launches play the short version, gone within a '
        'second', (tester) async {
      final played = recordHaptics();
      await pumpApp(
        tester,
        intro: true,
        settle: false,
        store: {'nn:introSeen': '1'},
      );
      await tester.pump();
      expect(byKey('intro'), findsOneWidget);
      expect(byKey('intro-wordmark'), findsNothing);
      await run(tester, 1100);
      expect(byKey('intro'), findsNothing);
      // The halves snap shut with a light tap.
      expect(played, [Haptic.light]);
      await leave(tester);
    });

    testWidgets('Reduce Motion: a still coin that fades, no doors; a screen '
        'reader: no intro', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpApp(tester, intro: true, settle: false);
      await tester.pump();
      expect(byKey('intro-coin'), findsOneWidget);
      for (var t = 0; t < 900; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(byKey('intro-doors'), findsNothing);
      }
      expect(byKey('intro'), findsNothing);
      await leave(tester);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      await pumpApp(tester, intro: true, settle: false);
      expect(byKey('intro'), findsNothing);
      await leave(tester);
    });
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
