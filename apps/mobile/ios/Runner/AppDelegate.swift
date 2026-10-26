import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let accessibility = AccessibilityBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    accessibility.attach(to: engineBridge.applicationRegistrar.messenger())
  }
}

/// Tells Flutter whether Reduce Transparency is on, now and whenever it changes, so the app's
/// glass can turn solid (Flutter itself only reports Increase Contrast).
final class AccessibilityBridge: NSObject, FlutterStreamHandler {
  private var methods: FlutterMethodChannel?
  private var changes: FlutterEventChannel?
  private var sink: FlutterEventSink?

  func attach(to messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(name: "nussnuss/accessibility", binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in
      if call.method == "reduceTransparency" {
        result(UIAccessibility.isReduceTransparencyEnabled)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    let changes = FlutterEventChannel(name: "nussnuss/accessibility/changes", binaryMessenger: messenger)
    changes.setStreamHandler(self)
    self.methods = methods
    self.changes = changes
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(changed),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil
    )
    events(UIAccessibility.isReduceTransparencyEnabled)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(
      self,
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil
    )
    sink = nil
    return nil
  }

  @objc private func changed() {
    sink?(UIAccessibility.isReduceTransparencyEnabled)
  }
}
