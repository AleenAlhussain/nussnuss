import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

/// A file to hand to the share sheet.
class SharedFile {
  const SharedFile(this.bytes, {required this.name, required this.mimeType});
  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// What the app asks of the phone itself: the share sheet, opening another app, the tilt.
/// The app uses plugins ([PluginDevice] in plugins.dart); tests use [QuietDevice].
abstract class Device {
  Future<void> share({
    String? text,
    List<SharedFile> files = const [],
    Rect? origin,
  });

  /// Opens a link in the app that handles it (WhatsApp, a bank, the browser). False if nothing could.
  Future<bool> open(Uri url);

  /// The phone's tilt from the accelerometer, roughly -1…1 on each axis. Empty where there is none.
  Stream<Offset> tilt();
}

/// Records what would have been shared or opened. For tests and for platforms without plugins.
class QuietDevice implements Device {
  final shared = <({String? text, List<SharedFile> files})>[];
  final opened = <Uri>[];

  /// What [open] answers; tests flip it to check the fallbacks.
  bool canOpen = true;

  @override
  Future<void> share({
    String? text,
    List<SharedFile> files = const [],
    Rect? origin,
  }) async => shared.add((text: text, files: files));

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return canOpen;
  }

  @override
  Stream<Offset> tilt() => const Stream.empty();
}

/// A product as the store shows it, with the price in the person's own currency.
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.price,
    this.title = '',
    this.native,
  });
  final String id;
  final String price;
  final String title;

  /// The plugin's own object, handed back on purchase.
  final Object? native;
}

enum StoreOutcome { purchased, restored, pending, canceled, error }

/// A purchase the store reports. [proof] is what the server checks: the signed StoreKit 2
/// transaction on iOS, the purchase token on Android.
class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.platform,
    required this.proof,
    required this.outcome,
    this.error,
    this.native,
  });
  final String productId;

  /// 'apple' or 'google'.
  final String platform;
  final String proof;
  final StoreOutcome outcome;
  final String? error;
  final Object? native;
}

/// The App Store or Google Play. [NoStore] when there is none (tests, or before the products exist).
abstract class Store {
  Future<List<StoreProduct>> products(Set<String> ids);
  Future<void> buy(StoreProduct product, {required bool subscription});
  Future<void> restore();
  Stream<StorePurchase> get purchases;

  /// Tells the store the purchase was delivered (Play refunds unacknowledged ones).
  Future<void> finish(StorePurchase purchase);
}

class NoStore implements Store {
  final _controller = StreamController<StorePurchase>.broadcast();

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async => const [];

  @override
  Future<void> buy(StoreProduct product, {required bool subscription}) async {}

  @override
  Future<void> restore() async {}

  @override
  Stream<StorePurchase> get purchases => _controller.stream;

  @override
  Future<void> finish(StorePurchase purchase) async {}
}

/// Product ids, the same in both stores and on the server.
abstract final class Products {
  static const plusMonthly = 'nussnuss.plus.monthly';
  static const plusYearly = 'nussnuss.plus.yearly';
  static const tripPass = 'nussnuss.trip_pass';
  static const lookNight = 'nussnuss.look.night';
  static const lookSaffron = 'nussnuss.look.saffron';
  static const all = {
    plusMonthly,
    plusYearly,
    tripPass,
    lookNight,
    lookSaffron,
  };
  static bool isSubscription(String id) =>
      id == plusMonthly || id == plusYearly;
}
