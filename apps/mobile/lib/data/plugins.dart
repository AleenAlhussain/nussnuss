// The real phone: plugins behind the small interfaces in services.dart and session.dart.
// Nothing here runs in widget tests, which use QuietDevice, NoStore and MemoryStore.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services.dart';
import 'store.dart';

/// The session token lives in the iOS Keychain and the Android Keystore, never in a plain file.
class SecureStore implements KeyValueStore {
  const SecureStore();
  static const _s = FlutterSecureStorage();

  @override
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      await _s.delete(key: key);
    } else {
      await _s.write(key: key, value: value);
    }
  }
}

class PluginDevice implements Device {
  @override
  Future<void> share({
    String? text,
    List<SharedFile> files = const [],
    Rect? origin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: files.isEmpty
            ? null
            : [
                for (final f in files)
                  XFile.fromData(f.bytes, mimeType: f.mimeType, name: f.name),
              ],
        fileNameOverrides: files.isEmpty
            ? null
            : [for (final f in files) f.name],
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Future<bool> open(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// The photo stays on the phone: text recognition runs on the device (ML Kit, Latin script).
  @override
  Future<String?> scanReceiptText({required bool camera}) async {
    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 90,
      );
    } on Exception {
      return '';
    }
    if (photo == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final read = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      return read.text;
    } on Exception {
      return '';
    } finally {
      await recognizer.close();
    }
  }

  @override
  Future<Uint8List?> pickAvatarPhoto() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 80,
      );
      return photo == null ? null : await photo.readAsBytes();
    } on Exception {
      return null;
    }
  }

  @override
  Stream<Offset> tilt() {
    const g = 9.81;
    return accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .map(
          (e) =>
              Offset((-e.x / g).clamp(-1.0, 1.0), (e.z / g).clamp(-1.0, 1.0)),
        )
        .handleError((Object _) {});
  }
}

/// App Store and Google Play. On iOS the plugin uses StoreKit 2, so the server gets a signed
/// transaction (JWS) it can check against Apple's certificates.
class PluginStore implements Store {
  final _iap = InAppPurchase.instance;
  String get _platform => Platform.isIOS ? 'apple' : 'google';

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async {
    try {
      if (!await _iap.isAvailable()) return const [];
      final r = await _iap.queryProductDetails(ids);
      return [
        for (final p in r.productDetails)
          StoreProduct(id: p.id, price: p.price, title: p.title, native: p),
      ];
    } on Exception {
      return const [];
    }
  }

  @override
  Future<void> buy(StoreProduct product, {required bool subscription}) async {
    final details = product.native;
    if (details is! ProductDetails) return;
    // Subscriptions and one-off unlocks are both bought as non-consumables.
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Stream<StorePurchase> get purchases => _iap.purchaseStream.expand(
    (list) => [
      for (final p in list)
        StorePurchase(
          productId: p.productID,
          platform: _platform,
          proof: p.verificationData.serverVerificationData,
          outcome: switch (p.status) {
            PurchaseStatus.purchased => StoreOutcome.purchased,
            PurchaseStatus.restored => StoreOutcome.restored,
            PurchaseStatus.pending => StoreOutcome.pending,
            PurchaseStatus.canceled => StoreOutcome.canceled,
            PurchaseStatus.error => StoreOutcome.error,
          },
          error: p.error?.message,
          native: p,
        ),
    ],
  );

  @override
  Future<void> finish(StorePurchase purchase) async {
    final p = purchase.native;
    if (p is PurchaseDetails && p.pendingCompletePurchase) {
      await _iap.completePurchase(p);
    }
  }
}
