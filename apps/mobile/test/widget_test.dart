import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nussnuss/app.dart';
import 'package:nussnuss/core/identity.dart';
import 'package:nussnuss/core/suggest.dart';
import 'package:nussnuss/data/api.dart';
import 'package:nussnuss/data/native.dart';
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

/// A store with prices, as the App Store or Google Play would give them.
class FakeStore implements Store {
  final _purchases = StreamController<StorePurchase>.broadcast();
  int restored = 0;

  static const _all = [
    StoreProduct(id: Products.plusYearly, price: 'AED 79.99'),
    StoreProduct(id: Products.plusMonthly, price: 'AED 9.99'),
    StoreProduct(id: Products.tripPass, price: 'AED 14.99'),
    StoreProduct(id: Products.lookNight, price: 'AED 3.99'),
    StoreProduct(id: Products.lookSaffron, price: 'AED 3.99'),
  ];

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async => [
    for (final p in _all)
      if (ids.contains(p.id)) p,
  ];

  @override
  Future<void> buy(StoreProduct product, {required bool subscription}) async {}

  @override
  Future<void> restore() async => restored++;

  @override
  Stream<StorePurchase> get purchases => _purchases.stream;

  @override
  Future<void> finish(StorePurchase purchase) async {}
}

/// Records what the app sends to the home-screen widget and the Lock Screen, for this test.
List<MethodCall> recordWidgetCalls(WidgetTester tester) {
  const channel = MethodChannel('nussnuss/widget');
  final calls = <MethodCall>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

/// Presses and holds [f] once it is on screen.
Future<void> holdIt(WidgetTester tester, Finder f) async {
  await bringIntoView(tester, f);
  await tester.longPress(f);
  await tester.pumpAndSettle();
}

/// Swipes the row [f] from the end toward the start (to the left in English).
Future<void> swipeOpen(WidgetTester tester, Finder f) async {
  await bringIntoView(tester, f);
  await tester.drag(f, const Offset(-240, 0));
  await tester.pumpAndSettle();
}

/// Starts the app. The launch intro is off unless [intro]; without [settle] it returns right after
/// the first frame, for tests that step through time themselves.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  Map<String, String>? store,
  FakeServer? server,
  bool intro = false,
  bool settle = true,
  Store? purchases,
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
    purchases: purchases,
  );
  launchIntroEnabled = intro;
  await tester.pumpWidget(NussNussApp(session: session));
  if (settle) await tester.pumpAndSettle();
  return TestApp(fake, session, device);
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) => tapIt(tester, byKey(k));

Future<void> tapIt(WidgetTester tester, Finder f) async {
  await bringIntoView(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Builds [f], scrolls it on screen and checks nothing floats over it.
Future<void> bringIntoView(WidgetTester tester, Finder f) async {
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
    await tapKey(tester, 'seg-unequal');
    await tapKey(tester, 'seg-SplitChoice.items');
    expect(byKey('paywall'), findsOneWidget);
    await tapIt(tester, byKey('sheet-close').last);
    // Still by shares: nothing changed without Plus.
    expect(byKey('drag-shares'), findsOneWidget);
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
    await tapKey(tester, 'seg-unequal');
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
    await tapKey(tester, 'seg-unequal');
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
    await tapKey(tester, 'seg-unequal');
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
    // How much of this round is paid, as a ring on the card.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is ProgressRing &&
            (w.key as ValueKey<String>?)?.value.startsWith('circle-ring-') ==
                true,
      ),
      findsOneWidget,
    );
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('new group templates fill the name and the cover', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await tapKey(tester, 'start');
    await tester.enterText(byKey('name'), 'Huda');
    await tapKey(tester, 'start');
    String name() =>
        tester.widget<TextField>(byKey('group-name')).controller!.text;
    await tapKey(tester, 'tpl-iftar');
    expect(name(), 'Ramadan iftars');
    expect(byKey('new-cover-moon:violet'), findsOneWidget);
    await tapKey(tester, 'tpl-flat');
    expect(name(), 'Our flat');
    expect(byKey('new-cover-home:violet'), findsOneWidget);
    // A typed name stays when another template is picked; the cover still follows it.
    await tester.enterText(byKey('group-name'), 'Villa 9');
    await tapKey(tester, 'tpl-office');
    expect(name(), 'Villa 9');
    expect(byKey('new-cover-work:slate'), findsOneWidget);

    // Or any of the covers by hand: an icon, then a tone. The preview shows the name.
    await tapKey(tester, 'cover-music');
    await tapKey(tester, 'cover-tone-mint');
    expect(byKey('new-cover-music:mint'), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('new-group-sheet'),
        matching: find.text('Villa 9', findRichText: true),
      ),
      findsWidgets,
    );
    await tester.enterText(byKey('person-name'), 'Mona');
    await tapKey(tester, 'add-person');
    await tapKey(tester, 'create-group');
    final g = app.server.groupNamed('Villa 9');
    expect(g.cover, 'music:mint');
    expect(g.emoji, '🎵');
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
    // Home says so too.
    await goBack(tester);
    expect(byKey('pending-home'), findsOneWidget);

    app.server.offline = false;
    await app.session.repo.sync();
    await tester.pumpAndSettle();
    expect(byKey('pending-home'), findsNothing);
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
    await tapKey(tester, 'tab-2');
    expect(byKey('you'), findsOneWidget);
    // The profile comes first; keeping the account follows the appearance and Plus.
    expect(byKey('profile'), findsOneWidget);
    await reveal(tester, byKey('account-status'));
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
    expect(find.text('Salalah trip'), findsWidgets);
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
      expect(byKey('groups'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'tab-1');
      expect(byKey('activity'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'tab-2');
      expect(byKey('you'), findsOneWidget);
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
    await tapKey(tester, 'tab-2');
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

    // You and back: the group is still open under Home.
    await tapKey(tester, 'tab-2');
    expect(byKey('you'), findsOneWidget);
    await tapKey(tester, 'tab-0');
    expect(byKey('group'), findsOneWidget);

    // Already at the top of the group: tapping Home goes back to Home's first page.
    await tapKey(tester, 'tab-0');
    expect(byKey('group'), findsNothing);
    expect(byKey('groups'), findsOneWidget);
    expect(find.text('Salalah trip'), findsOneWidget);

    // Scrolled down in You: tapping You scrolls back to the top.
    await tapKey(tester, 'tab-2');
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(of: byKey('you'), matching: find.byType(Scrollable))
              .first,
        )
        .position;
    await tester.drag(byKey('you'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(position().pixels, greaterThan(100));
    await tapKey(tester, 'tab-2');
    expect(position().pixels, 0);
    await leave(tester);
  });

  testWidgets('a notification opens its group inside the Home tab', (
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
    await tapKey(tester, 'new-group');
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

  testWidgets('Home: the overall balance, the next step and the people '
      'strip, from the overview', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    await addExpense(tester, '120', 'Chalet');
    await goBack(tester);

    // 120 paid, 40 each: Sara and Omar owe me 40 each.
    expect(find.text('Overall, you get back'), findsOneWidget);
    expect(
      tester.widget<RollingText>(byKey('overall-balance')).text,
      'AED 80.00',
    );
    expect(find.text('In 1 group'), findsOneWidget);
    expect(byKey('next-step'), findsOneWidget);
    expect(
      tester.widget<Text>(byKey('next-line')).data,
      endsWith('owes you AED 40.00'),
    );
    for (final name in ['Sara', 'Omar']) {
      expect(
        find.descendant(of: byKey('people-strip'), matching: find.text(name)),
        findsOneWidget,
      );
    }
    await meetsStandards(tester);
    // The group card says what happened last, in words.
    await reveal(tester, find.textContaining('You added Chalet'));
    expect(find.textContaining('You added Chalet'), findsOneWidget);

    // Remind from the next step: WhatsApp with the amount and the group.
    await tapKey(tester, 'next-remind');
    expect(app.device.opened.last.host, 'wa.me');
    expect(
      app.device.opened.last.queryParameters['text'],
      contains('AED 40.00'),
    );

    // Marked as paid right there: the overall balance follows.
    await tapKey(tester, 'next-mark-paid');
    expect(find.text('Marked as paid'), findsOneWidget);
    expect(
      tester.widget<RollingText>(byKey('overall-balance')).text,
      'AED 40.00',
    );
    expect(app.server.groupNamed('Salalah trip').payments, hasLength(1));

    // "See all" lists everyone.
    await tapKey(tester, 'see-all-people');
    expect(byKey('people'), findsOneWidget);
    expect(find.text('Sara'), findsOneWidget);
    Navigator.of(tester.element(byKey('people'))).pop();
    await tester.pumpAndSettle();

    // The jobs the redesign measures were timed and sent.
    expect([
      for (final t in app.server.timings) t['job'],
    ], containsAll(<String>['add_expense', 'find_balance']));
    await leave(tester);
    semantics.dispose();
  });

  testWidgets("Home's + adds an expense: straight into the only group, or "
      'pick one', (tester) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    await goBack(tester);
    await tapKey(tester, 'add');
    expect(byKey('group'), findsOneWidget);
    expect(byKey('expense-sheet'), findsOneWidget);
    await typeAmount(tester, '30');
    await tapKey(tester, 'save-expense');
    expect(balance(tester), 'AED 20.00');
    await goBack(tester);

    await tapKey(tester, 'new-group');
    await tester.enterText(byKey('group-name'), 'Our flat');
    await tester.enterText(byKey('person-name'), 'Huda');
    await tapKey(tester, 'add-person');
    await tapKey(tester, 'create-group');
    await goBack(tester);
    await tapKey(tester, 'add');
    expect(byKey('group-picker'), findsOneWidget);
    expect(byKey('pick-new-group'), findsOneWidget);
    await tapKey(tester, 'pick-${app.server.groupNamed('Our flat').id}');
    expect(byKey('expense-sheet'), findsOneWidget);
    await tapKey(tester, 'sheet-close');
    expect(byKey('group'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('a person: settle everything in one go, with Undo', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    await addExpense(tester, '120', 'Chalet');
    await goBack(tester);
    final g = app.server.groupNamed('Salalah trip');

    await tapIt(
      tester,
      find.descendant(of: byKey('people-strip'), matching: find.text('Sara')),
    );
    expect(byKey('person'), findsOneWidget);
    expect(find.text('Overall, Sara owes you'), findsOneWidget);
    expect(
      tester.widget<RollingText>(byKey('person-amount')).text,
      'AED 40.00',
    );
    expect(byKey('shared-group-${g.id}'), findsOneWidget);
    await reveal(tester, find.text('Chalet'));
    expect(find.text('+AED 40.00'), findsOneWidget);
    await meetsStandards(tester);

    await tapKey(tester, 'remind-all');
    expect(
      app.device.opened.last.queryParameters['text'],
      contains('you owe me AED 40.00'),
    );

    await tapKey(tester, 'settle-all');
    expect(byKey('settle-sheet'), findsOneWidget);
    expect(byKey('settle-row-${g.id}'), findsOneWidget);
    await tapKey(tester, 'settle-confirm');
    expect(find.text('Settled with Sara'), findsOneWidget);
    expect(find.text('You and Sara are even'), findsOneWidget);
    expect(byKey('settle-all'), findsNothing);
    expect(g.payments, hasLength(1));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(g.payments, isEmpty);
    expect(find.text('Overall, Sara owes you'), findsOneWidget);
    // settle ran from opening Sara to settling up.
    expect([for (final t in app.server.timings) t['job']], contains('settle'));
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('Activity: what friends did, what it means for you, and Mark '
      'all read', (tester) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    await addExpense(tester, '30', 'Chalet');
    app.server.claim('Salalah trip', 'Sara');
    app.server.addExpenseBy('Salalah trip', 'Sara', 'Lunch', 4500);
    await goBack(tester);

    await tapKey(tester, 'tab-1');
    expect(byKey('activity'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Sara added Lunch', findRichText: true), findsOneWidget);
    expect(find.textContaining('your share AED 22.50'), findsOneWidget);
    expect(find.text('You added Chalet', findRichText: true), findsOneWidget);
    expect(find.textContaining('you lent AED 15.00'), findsOneWidget);
    // Only Sara's is new: the dot, the count and the badge on the tab.
    expect(find.text('1 new'), findsOneWidget);
    expect(byKey('tab-badge-1'), findsOneWidget);

    await tapKey(tester, 'mark-all-read');
    expect(app.server.calls, contains('POST /activity/seen'));
    expect(byKey('tab-badge-1'), findsNothing);
    expect(byKey('mark-all-read'), findsNothing);

    // A row opens its group, inside the Activity tab.
    await tapIt(tester, find.text('Sara added Lunch', findRichText: true));
    expect(byKey('group'), findsOneWidget);
    expect(byKey('tab-1'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('You: photo, emoji or initial, a colour and the name, with a '
      'live preview', (tester) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    await goBack(tester);
    await tapKey(tester, 'tab-2');
    await tapKey(tester, 'profile');
    expect(byKey('profile-sheet'), findsOneWidget);

    await tapKey(tester, 'seg-emoji');
    await tapKey(tester, 'emoji-4');
    await tapKey(tester, 'tone-mint');
    Avatar preview() => tester.widget<Avatar>(
      find.descendant(
        of: byKey('profile-preview'),
        matching: find.byType(Avatar),
      ),
    );
    expect(preview().look, const AvatarLook.emoji('🦊', 'mint'));
    await tester.enterText(byKey('profile-name'), 'Talal A');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: byKey('profile-preview'),
        matching: find.text('Talal A'),
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'profile-save');
    expect(byKey('profile-sheet'), findsNothing);
    expect(app.session.me!.name, 'Talal A');
    expect(app.session.me!.look, const AvatarLook.emoji('🦊', 'mint'));

    // A photo from the library goes up at once; one too big says so.
    await tapKey(tester, 'profile');
    await tapKey(tester, 'seg-photo');
    app.device.avatarPhoto = Uint8List(80000);
    await tapKey(tester, 'choose-photo');
    expect(
      find.text('That photo is too big. Try another one.'),
      findsOneWidget,
    );
    app.device.avatarPhoto = Uint8List(2000);
    await tapKey(tester, 'choose-photo');
    expect(app.session.me!.look.kind, 'photo');
    expect(byKey('remove-photo'), findsOneWidget);
    await tapKey(tester, 'remove-photo');
    expect(app.session.me!.look.kind, 'initial');
    await tapKey(tester, 'sheet-close');
    await leave(tester);
  });

  testWidgets('large text: the tab bar and + keep their size, and holding a '
      'tab shows it big', (tester) async {
    await pumpApp(tester);
    await startWithGroup(tester);
    await goBack(tester);
    final tab = tester.getRect(byKey('tab-1')).size;
    final add = tester.getRect(byKey('add')).size;
    // Below 135 % there is no large content viewer.
    final small = await tester.startGesture(tester.getCenter(byKey('tab-1')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(byKey('large-content'), findsNothing);
    await small.up();
    await leave(tester);

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);
    await startWithGroup(tester);
    await goBack(tester);
    expect(tester.getRect(byKey('tab-1')).size, tab);
    expect(tester.getRect(byKey('add')).size, add);

    final hold = await tester.startGesture(tester.getCenter(byKey('tab-1')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(byKey('large-content'), findsOneWidget);
    await hold.up();
    await tester.pumpAndSettle();
    expect(byKey('large-content'), findsNothing);
    // Letting go picks the tab.
    expect(byKey('activity'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('owing is never red: what you owe is in the text colour', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    final g = app.server.groupNamed('Salalah trip');
    final me = g.members[0]['id']! as String;
    final sara = g.members[1]['id']! as String;
    // Sara paid 50, split equally: I owe her 25.
    await tapKey(tester, 'add');
    await typeAmount(tester, '50');
    await tester.enterText(byKey('title'), 'Dinner');
    await tapKey(tester, 'details');
    await tapKey(tester, 'payer-$sara');
    await tapKey(tester, 'save-expense');
    final p = NNTheme.of(tester.element(byKey('my-balance'))).palette;
    expect(balance(tester), 'AED 25.00');
    expect(tester.widget<RollingText>(byKey('my-balance')).style.color, p.text);
    await tapKey(tester, 'seg-_Tab.settle');
    expect(tester.widget<AmountText>(byKey('balance-$me')).style.color, p.text);

    await goBack(tester);
    expect(find.text('Overall, you owe'), findsOneWidget);
    expect(
      tester.widget<RollingText>(byKey('overall-balance')).style.color,
      p.text,
    );
    expect(p.text, isNot(p.danger));
    // The next step is to pay Sara; she shared no way to be paid, so there is only Mark as paid.
    expect(
      tester.widget<Text>(byKey('next-line')).data,
      'You owe Sara AED 25.00',
    );
    expect(byKey('next-pay'), findsNothing);
    expect(byKey('next-mark-paid'), findsOneWidget);
    await reveal(tester, byKey('group-balance-${g.id}'));
    expect(
      tester.widget<AmountText>(byKey('group-balance-${g.id}')).style.color,
      p.text,
    );
    await leave(tester);
  });

  testWidgets('group options: a bill that repeats is added from the empty '
      'state', (tester) async {
    final server = FakeServer()..plus = true;
    await pumpApp(tester, server: server);
    await startWithGroup(tester);
    await tapKey(tester, 'more');
    expect(byKey('no-repeating'), findsOneWidget);
    await tapKey(tester, 'add-repeating');
    expect(byKey('expense-sheet'), findsOneWidget);
    await typeAmount(tester, '900');
    await tester.enterText(byKey('title'), 'Rent');
    await tapKey(tester, 'save-expense');
    expect(server.groupNamed('Salalah trip').recurring, hasLength(1));
    expect(byKey('no-repeating'), findsNothing);
    await tapIt(tester, byKey('sheet-close').last);
    await leave(tester);
  });

  testWidgets('an expense row: swipe for Duplicate (with Undo) and Delete, '
      'which are also screen-reader actions', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    await addExpense(tester, '120', 'Chalet');
    final g = app.server.groupNamed('Salalah trip');
    final id = g.expenses.single['id']! as String;

    // Nobody has to swipe: the row has the same actions for screen readers.
    final actions = [
      for (final a
          in tester
                  .getSemantics(byKey('expense-$id'))
                  .getSemanticsData()
                  .customSemanticsActionIds ??
              const <int>[])
        CustomSemanticsAction.getAction(a)!.label,
    ];
    expect(
      actions,
      containsAll(<String>['Duplicate', 'Change category', 'Delete']),
    );

    // Swiped toward the start, Duplicate and Delete show behind the row.
    await swipeOpen(tester, byKey('expense-$id'));
    expect(byKey('swipe-close'), findsOneWidget);
    await tapKey(tester, 'swipe-duplicate');
    expect(find.text('Duplicated'), findsOneWidget);
    expect(g.expenses, hasLength(2));
    expect(find.text('Chalet'), findsNWidgets(2));
    expect(balance(tester), 'AED 160.00');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(g.expenses, hasLength(1));
    expect(find.text('Chalet'), findsOneWidget);
    expect(balance(tester), 'AED 80.00');

    // A tap on an open row closes it.
    await swipeOpen(tester, byKey('expense-$id'));
    await tester.tap(byKey('swipe-close'));
    await tester.pumpAndSettle();
    expect(byKey('swipe-close'), findsNothing);
    expect(byKey('expense-sheet'), findsNothing);

    await swipeOpen(tester, byKey('expense-$id'));
    await tapKey(tester, 'swipe-delete');
    expect(find.text('Expense deleted'), findsOneWidget);
    expect(g.expenses, isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(g.expenses, hasLength(1));
    expect(find.text('Chalet'), findsOneWidget);
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('an expense row: hold it for the menu; the category changes from '
      'the menu or the tile, and nothing else does', (tester) async {
    final played = recordHaptics();
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    await addExpense(tester, '120', 'Chalet');
    final g = app.server.groupNamed('Salalah trip');
    final id = g.expenses.single['id']! as String;

    played.clear();
    await holdIt(tester, byKey('expense-$id'));
    expect(byKey('context-menu'), findsOneWidget);
    expect(played, [Haptic.medium]);
    expect(
      find.descendant(of: byKey('menu-preview'), matching: find.text('Chalet')),
      findsOneWidget,
    );
    for (final k in ['edit', 'duplicate', 'category', 'delete']) {
      expect(byKey('menu-$k'), findsOneWidget);
    }
    await meetsStandards(tester);

    await tapKey(tester, 'menu-category');
    expect(byKey('context-menu'), findsNothing);
    expect(byKey('category-sheet'), findsOneWidget);
    await tapKey(tester, 'pick-cat-fun');
    expect(find.text('Category changed'), findsOneWidget);
    expect(g.expenses.single['category'], 'fun');
    expect(g.expenses.single['amount'], 12000);
    expect(g.expenses.single['title'], 'Chalet');
    expect(byKey('cat-$id-fun'), findsOneWidget);

    // The tile on the row opens the same choice.
    await tapKey(tester, 'cat-tile-$id');
    expect(byKey('category-sheet'), findsOneWidget);
    await tapKey(tester, 'pick-cat-bills');
    expect(g.expenses.single['category'], 'bills');
    expect(g.expenses, hasLength(1));

    // Duplicate from the menu, with Undo.
    await holdIt(tester, byKey('expense-$id'));
    await tapKey(tester, 'menu-duplicate');
    expect(find.text('Duplicated'), findsOneWidget);
    expect(g.expenses, hasLength(2));
    expect(g.expenses.last['category'], 'bills');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(g.expenses, hasLength(1));

    // Edit opens the expense; tapping outside the menu does nothing.
    await holdIt(tester, byKey('expense-$id'));
    await tapKey(tester, 'menu-edit');
    expect(byKey('expense-sheet'), findsOneWidget);
    await tapKey(tester, 'sheet-close');
    await holdIt(tester, byKey('expense-$id'));
    await tester.tapAt(const Offset(12, 120));
    await tester.pumpAndSettle();
    expect(byKey('context-menu'), findsNothing);
    expect(g.expenses, hasLength(1));
    await leave(tester);
  });

  testWidgets('split unequally: drag a share onto someone, or use − and +, '
      'with a legend under the bar', (tester) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    final g = app.server.groupNamed('Salalah trip');
    final me = g.members[0]['id']! as String;
    final sara = g.members[1]['id']! as String;
    await tapKey(tester, 'add');
    await typeAmount(tester, '90');
    await tester.enterText(byKey('title'), 'Dinner');
    await tapKey(tester, 'details');
    // Two choices first; the ways to split unevenly only after Unequally.
    expect(byKey('split-mode'), findsNothing);
    await tapKey(tester, 'seg-unequal');
    expect(byKey('split-mode'), findsOneWidget);
    expect(byKey('split-legend'), findsOneWidget);
    expect(tester.widget<Text>(byKey('share-badge-$sara')).data, '×1');

    final played = recordHaptics();
    await bringIntoView(tester, byKey('share-token'));
    await bringIntoView(tester, byKey('share-drop-$sara'));
    final drag = await tester.startGesture(
      tester.getCenter(byKey('share-token')),
    );
    await tester.pump();
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    await drag.moveTo(tester.getCenter(byKey('share-drop-$sara')));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(byKey('share-badge-$sara')).data, '×2');
    expect(tester.widget<Text>(byKey('share-count-$sara')).data, '2');
    expect(played, containsAllInOrder([Haptic.selection, Haptic.success]));

    // The same with the buttons: one less for Sara, one more for me.
    await tapKey(tester, 'less-share-$sara');
    await tapKey(tester, 'less-share-$sara');
    await tapKey(tester, 'more-share-$sara');
    await tapKey(tester, 'more-share-$me');
    expect(tester.widget<Text>(byKey('share-count-$me')).data, '2');
    expect(tester.widget<Text>(byKey('share-count-$sara')).data, '1');
    await tapKey(tester, 'save-expense');
    // 90 in shares of 2 and 1: Sara's 30 is what she owes me.
    expect(balance(tester), 'AED 30.00');
    // uneven_split ran from choosing Unequally to Save.
    expect([
      for (final t in app.server.timings) t['job'],
    ], contains('uneven_split'));
    await leave(tester);
  });

  testWidgets('the invite sheet: what friends will see, a QR code, the short '
      'link with Copy, and who has joined', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    final g = app.server.groupNamed('Salalah trip');
    await tapKey(tester, 'share');
    expect(byKey('share-sheet'), findsOneWidget);
    Finder inPreview(String text) =>
        find.descendant(of: byKey('invite-preview'), matching: find.text(text));
    expect(inPreview('Salalah trip'), findsOneWidget);
    expect(inPreview('2 people · AED'), findsOneWidget);
    expect(byKey('invite-qr'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Scan to join, http.*/j/inv')),
      findsOneWidget,
    );
    final link = tester.widget<Text>(byKey('invite-link')).data!;
    expect(link, contains('/j/'));
    expect(link, isNot(startsWith('http')));
    for (final m in g.members) {
      expect(byKey('invite-member-${m['id']}'), findsOneWidget);
    }
    expect(find.text('Joined'), findsOneWidget);
    expect(find.text('Not joined yet'), findsOneWidget);
    await meetsStandards(tester);

    await tapKey(tester, 'copy-link');
    expect(app.device.copied.last, endsWith(link));
    await tester.pump(const Duration(seconds: 3));
    await tapKey(tester, 'whatsapp');
    expect(app.device.opened.last.host, 'wa.me');
    expect(app.device.opened.last.queryParameters['text'], contains(link));
    // invite ran from opening the sheet to the link going out.
    expect([for (final t in app.server.timings) t['job']], contains('invite'));
    await tapKey(tester, 'sheet-close');
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('the join screen: the cover, who invited you, and the names to '
      'pick from', (tester) async {
    final semantics = tester.ensureSemantics();
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
    expect(tester.widget<Text>(byKey('join-title')).data, 'Join Salalah trip');
    expect(
      tester.widget<Text>(byKey('join-meta')).data,
      'Talal invited you · 3 people · AED',
    );
    // Talal is in already, so his name says so and can't be picked.
    final talal = g.members[0]['id']! as String;
    final sara = g.members[1]['id']! as String;
    expect(
      find.descendant(
        of: byKey('who-$talal'),
        matching: find.text('Already joined'),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(byKey('who-$sara')).height, greaterThanOrEqualTo(44));
    expect(
      find.descendant(
        of: byKey('who-new'),
        matching: find.text('I’m someone else'),
      ),
      findsOneWidget,
    );
    await meetsStandards(tester);
    await tapKey(tester, 'who-$sara');
    await tapKey(tester, 'join');
    expect(byKey('group'), findsOneWidget);
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('empty states: the coin in two halves, one line and one button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await tapKey(tester, 'start');
    await tester.enterText(byKey('name'), 'Huda');
    await tapKey(tester, 'start');
    // Not ready for a group yet: Home says how to start one.
    await tapKey(tester, 'sheet-close');
    expect(byKey('home-empty'), findsOneWidget);
    expect(find.text('Start your first group'), findsOneWidget);
    expect(
      find.descendant(of: byKey('home-empty'), matching: byKey('drifted-coin')),
      findsOneWidget,
    );
    await meetsStandards(tester);
    await tapKey(tester, 'start-group');
    expect(byKey('new-group-sheet'), findsOneWidget);
    await tester.enterText(byKey('group-name'), 'Our flat');
    await tester.enterText(byKey('person-name'), 'Mona');
    await tapKey(tester, 'add-person');
    await tapKey(tester, 'create-group');

    // A new group: nothing spent yet, and the first expense is one tap away.
    expect(byKey('group-empty'), findsOneWidget);
    expect(find.text('Nothing spent yet'), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('group-empty'),
        matching: byKey('drifted-coin'),
      ),
      findsOneWidget,
    );
    await meetsStandards(tester);
    await tapKey(tester, 'add-first');
    expect(byKey('expense-sheet'), findsOneWidget);
    await tapKey(tester, 'sheet-close');
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('settle up: the swipe hint shows on the first visit only, and '
      'screen readers always get it', (tester) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    await addExpense(tester, '50', 'Dinner');
    await tapKey(tester, 'seg-_Tab.settle');
    expect(byKey('swipe-hint'), findsOneWidget);
    expect(
      (app.session.store as MemoryStore).values['nn:swipeHintSeen'],
      isNotNull,
    );
    Finder spoken() => find.byWidgetPredicate(
      (w) =>
          w is Semantics && w.properties.hint == 'Swipe right to mark as paid',
    );
    expect(spoken(), findsOneWidget);

    // The next time the group opens, the words are gone; the screen reader's hint stays.
    final g = app.server.groupNamed('Salalah trip');
    await goBack(tester);
    await tapKey(tester, 'group-${g.id}');
    await tapKey(tester, 'seg-_Tab.settle');
    expect(byKey('swipe-hint'), findsNothing);
    expect(spoken(), findsOneWidget);
    await leave(tester);

    // A phone that has seen it before never shows it.
    final again = await pumpApp(
      tester,
      store: {...(app.session.store as MemoryStore).values},
      server: app.server,
    );
    expect(again.session.me, isNotNull);
    await tapKey(tester, 'group-${g.id}');
    await tapKey(tester, 'seg-_Tab.settle');
    expect(byKey('swipe-hint'), findsNothing);
    await leave(tester);
  });

  testWidgets('welcome: three cards say what NussNuss does, above the name', (
    tester,
  ) async {
    await pumpApp(tester);
    for (final (i, title) in [
      (1, 'Add an expense in three taps'),
      (2, 'Settle with fewer payments'),
      (3, 'Friends join from a link'),
    ]) {
      expect(
        find.descendant(
          of: byKey('welcome-card-$i'),
          matching: find.text(title),
        ),
        findsOneWidget,
      );
    }
    await tapKey(tester, 'start');
    expect(
      tester.getRect(byKey('welcome-card-3')).bottom,
      lessThan(tester.getRect(byKey('name')).top),
    );
    await leave(tester);
  });

  testWidgets('Plus: what it adds, the plans side by side with the store '
      'price, Restore, and where billing happens', (tester) async {
    final semantics = tester.ensureSemantics();
    final store = FakeStore();
    final app = await pumpApp(tester, purchases: store);
    await startWithGroup(tester);
    await goBack(tester);
    await tapKey(tester, 'tab-2');
    await tapKey(tester, 'plan');
    expect(byKey('paywall'), findsOneWidget);
    expect(byKey('plus-free'), findsOneWidget);
    for (final i in [1, 2, 3]) {
      expect(byKey('plus-benefit-$i'), findsOneWidget);
    }
    expect(find.text('Bills that add themselves'), findsOneWidget);
    expect(find.text('Split a receipt by item'), findsOneWidget);

    // Yearly and monthly side by side, each with the store's price.
    final yearly = tester.getRect(byKey('plan-${Products.plusYearly}'));
    final monthly = tester.getRect(byKey('plan-${Products.plusMonthly}'));
    expect(yearly.top, monthly.top);
    expect(yearly.right, lessThan(monthly.left));
    String price(String id) => tester
        .widget<Text>(
          find.descendant(of: byKey('plan-$id'), matching: byKey('plan-price')),
        )
        .data!;
    expect(price(Products.plusYearly), startsWith('AED 79.99'));
    expect(price(Products.plusMonthly), startsWith('AED 9.99'));
    expect(byKey('store-soon'), findsNothing);
    expect(tester.widget<NNButton>(byKey('buy')).label, 'Start Plus');
    expect(tester.widget<NNButton>(byKey('buy')).onTap, isNotNull);
    await bringIntoView(tester, byKey('billed-by'));
    expect(byKey('paywall-privacy'), findsOneWidget);
    await meetsStandards(tester);

    await tapKey(tester, 'paywall-terms');
    expect(app.device.opened.last.path, '/terms');
    await tapKey(tester, 'restore');
    expect(store.restored, 1);
    await tapIt(tester, byKey('sheet-close').last);
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('the recovery code: Save to Passwords hands it to the password '
      'manager and says so, without saying it was saved', (tester) async {
    await pumpApp(tester);
    await startWithGroup(tester);
    await goBack(tester);
    await tapKey(tester, 'tab-2');
    await tapKey(tester, 'recovery');
    final code = tester.widget<SelectableText>(byKey('shown-code')).data!;
    tester.testTextInput.log.clear();
    await tapKey(tester, 'save-passwords');
    expect(
      [
        for (final c in tester.testTextInput.log)
          if (c.method == 'TextInput.finishAutofillContext') c.arguments,
      ],
      [true],
    );
    // The name and the code are what the password manager is offered.
    TextField field(String k) => tester.widget<TextField>(byKey(k));
    expect(field('passwords-user').controller!.text, 'Talal');
    expect(field('passwords-user').autofillHints, [AutofillHints.username]);
    expect(field('passwords-code').controller!.text, code);
    expect(field('passwords-code').autofillHints, [AutofillHints.password]);
    expect(byKey('passwords-toast'), findsOneWidget);
    expect(find.text('Saved to your passwords'), findsNothing);
    await tapKey(tester, 'sheet-close');
    await leave(tester);
  });

  testWidgets('group options: the cover and the name, changed together', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    final g = app.server.groupNamed('Salalah trip');
    await tapKey(tester, 'more');
    await tapKey(tester, 'cover-and-name');
    expect(byKey('cover-sheet'), findsOneWidget);
    expect(byKey('edit-cover-plane:sky'), findsOneWidget);
    await tester.enterText(byKey('edit-group-name'), 'Salalah 2026');
    await tapKey(tester, 'cover-beach');
    await tapKey(tester, 'cover-tone-saffron');
    expect(byKey('edit-cover-beach:saffron'), findsOneWidget);
    await tapKey(tester, 'save-cover');
    expect(byKey('cover-sheet'), findsNothing);
    expect(g.name, 'Salalah 2026');
    expect(g.cover, 'beach:saffron');
    expect(app.server.calls, contains('PATCH /groups/${g.id}'));
    expect(
      find.descendant(
        of: byKey('group-options'),
        matching: find.text('Salalah 2026'),
      ),
      findsOneWidget,
    );

    // An empty name is not saved.
    await tapKey(tester, 'cover-and-name');
    await tester.enterText(byKey('edit-group-name'), '  ');
    await tapKey(tester, 'save-cover');
    expect(byKey('cover-sheet'), findsOneWidget);
    expect(find.text('Give the group a name.'), findsOneWidget);
    expect(g.name, 'Salalah 2026');
    await tapIt(tester, byKey('sheet-close').last);
    await tapIt(tester, byKey('sheet-close').last);
    expect(find.text('Salalah 2026'), findsWidgets);
    await leave(tester);
  });

  testWidgets('Home: hold a group for Open, Add expense and Invite friends', (
    tester,
  ) async {
    final played = recordHaptics();
    final app = await pumpApp(tester);
    await startWithGroup(tester);
    await goBack(tester);
    final g = app.server.groupNamed('Salalah trip');

    played.clear();
    await holdIt(tester, byKey('group-${g.id}'));
    expect(byKey('context-menu'), findsOneWidget);
    expect(played, [Haptic.medium]);
    expect(
      find.descendant(
        of: byKey('menu-preview'),
        matching: find.text('Salalah trip'),
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'menu-add');
    expect(byKey('group'), findsOneWidget);
    expect(byKey('expense-sheet'), findsOneWidget);
    await tapKey(tester, 'sheet-close');
    await goBack(tester);

    await holdIt(tester, byKey('group-${g.id}'));
    await tapKey(tester, 'menu-invite');
    expect(byKey('share-sheet'), findsOneWidget);
    await tapKey(tester, 'sheet-close');

    await holdIt(tester, byKey('group-${g.id}'));
    await tapKey(tester, 'menu-open');
    expect(byKey('group'), findsOneWidget);
    expect(byKey('expense-sheet'), findsNothing);
    await leave(tester);
  });

  testWidgets('the group balance: who paid, as a bar with a legend', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    final sara = app.server.groupNamed('Salalah trip').members[1]['id']!;
    await addExpense(tester, '60', 'Fuel');
    expect(byKey('who-paid'), findsNothing);
    await tapKey(tester, 'add');
    await typeAmount(tester, '40');
    await tester.enterText(byKey('title'), 'Lunch');
    await tapKey(tester, 'details');
    await tapKey(tester, 'payer-$sara');
    await tapKey(tester, 'save-expense');
    expect(byKey('who-paid'), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('who-paid'),
        matching: find.text('You paid AED 60.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: byKey('who-paid'),
        matching: find.text('Sara AED 40.00'),
      ),
      findsOneWidget,
    );
    await leave(tester);
  });

  testWidgets('the home-screen widget gets the balance after each overview', (
    tester,
  ) async {
    final calls = recordWidgetCalls(tester);
    await pumpApp(tester);
    await startWithGroup(tester);
    await addExpense(tester, '120', 'Chalet');
    await goBack(tester);
    final updates = [
      for (final c in calls)
        if (c.method == 'update') c.arguments,
    ];
    expect(updates, isNotEmpty);
    expect(updates.last, {
      'title': 'Your balance',
      'amount': 'AED 80.00',
      'sub': 'You get back',
    });
    // Nothing goes on the Lock Screen unless asked for.
    expect(calls.where((c) => c.method == 'startTrip'), isEmpty);
    await leave(tester);
  });

  testWidgets('iPhone: a trip on the Lock Screen, from a switch in group '
      'options, follows the balance and goes once settled', (tester) async {
    final calls = recordWidgetCalls(tester);
    final app = await pumpApp(tester);
    await startWithGroup(tester, friends: const ['Sara']);
    final g = app.server.groupNamed('Salalah trip');
    // A fresh read each time: `values` is a copy taken when it is called.
    Map<String, String> store() => (app.session.store as MemoryStore).values;
    Finder toggle() => find.descendant(
      of: byKey('live-activity'),
      matching: find.byType(Switch),
    );
    // The last call about the trip (Home's widget update can come after it).
    MethodCall trip() => calls.lastWhere((c) => c.method != 'update');

    await tapKey(tester, 'more');
    expect(tester.widget<Switch>(toggle()).value, isFalse);
    await tapIt(tester, toggle());
    expect(trip().method, 'startTrip');
    expect(trip().arguments, {
      'groupId': g.id,
      'title': 'Salalah trip',
      'amount': 'AED 0.00',
      'sub': 'All settled',
    });
    expect(store()['nn:liveTrips'], contains(g.id));
    await tapIt(tester, byKey('sheet-close').last);

    // The balance changes: the trip follows.
    await addExpense(tester, '50', 'Dinner');
    final update = calls.lastWhere((c) => c.method == 'updateTrip');
    expect(update.arguments, {
      'groupId': g.id,
      'title': 'Salalah trip',
      'amount': 'AED 25.00',
      'sub': 'You get back',
    });

    // Settled: it goes, and the switch is off.
    await tapKey(tester, 'seg-_Tab.settle');
    await tapIt(tester, byKey('mark-paid').first);
    expect(trip().method, 'endTrip');
    expect(trip().arguments, {'groupId': g.id});
    expect(store()['nn:liveTrips'], isNot(contains(g.id)));
    await tapKey(tester, 'more');
    expect(tester.widget<Switch>(toggle()).value, isFalse);
    await tapIt(tester, byKey('sheet-close').last);
    await leave(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android: no Lock Screen switch', (tester) async {
    await pumpApp(tester);
    await startWithGroup(tester);
    await tapKey(tester, 'more');
    expect(byKey('group-options'), findsOneWidget);
    expect(byKey('live-activity'), findsNothing);
    await tapIt(tester, byKey('sheet-close').last);
    await leave(tester);
  });

  testWidgets('app icon shortcuts: Add expense is the +, Activity opens its '
      'tab', (tester) async {
    await pumpApp(tester);
    await startWithGroup(tester);
    await goBack(tester);
    shortcutAction.value = 'activity';
    await tester.pumpAndSettle();
    expect(byKey('activity'), findsOneWidget);
    expect(shortcutAction.value, isNull);

    shortcutAction.value = 'add';
    await tester.pumpAndSettle();
    expect(byKey('group'), findsOneWidget);
    expect(byKey('expense-sheet'), findsOneWidget);
    await tapKey(tester, 'sheet-close');

    // The same from a link (Android's shortcuts open nussnuss://activity).
    await tester.binding.handlePushRoute('nussnuss://activity');
    await tester.pumpAndSettle();
    expect(byKey('activity'), findsOneWidget);
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
    expect(
      inviteToken(Uri.parse('https://nussnuss.app/j/k7m2q9xd4p')),
      'k7m2q9xd4p',
    );
    expect(inviteToken(Uri.parse('https://nussnuss.app/g/abc')), isNull);
    expect(inviteToken(Uri.parse('/')), isNull);
  });
}
