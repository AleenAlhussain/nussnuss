import Flutter
import UIKit
#if canImport(AppIntents)
import AppIntents
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let accessibility = AccessibilityBridge()
  private let widgets = WidgetBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Launched from a Home Screen quick action (without scenes; with them, see ShortcutBridge).
    if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
      ShortcutBridge.shared.receive(item.type)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    accessibility.attach(to: engineBridge.applicationRegistrar.messenger())
    widgets.attach(to: engineBridge.applicationRegistrar.messenger())
    ShortcutBridge.shared.attach(to: engineBridge.applicationRegistrar.messenger())
    // Quick actions arrive through the scene; Flutter passes scene events to this delegate.
    engineBridge.pluginRegistry.registrar(forPlugin: "NussNussShortcuts")?
      .addSceneDelegate(ShortcutBridge.shared)
  }
}

/// Home Screen quick actions (Add expense, Activity) and the Siri shortcut, handed to Flutter on
/// MethodChannel "nussnuss/shortcuts": Flutter asks "initial" once it is running (a cold start
/// keeps the action until then), and later actions arrive as "open" with "add" or "activity".
final class ShortcutBridge: NSObject, FlutterSceneLifeCycleDelegate {
  static let shared = ShortcutBridge()

  private var channel: FlutterMethodChannel?
  private var pending: String?
  private var ready = false

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "nussnuss/shortcuts", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      if call.method == "initial" {
        self.ready = true
        result(self.pending)
        self.pending = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  /// A quick action's type ("app.nussnuss.add") or the Siri shortcut's action ("add").
  func receive(_ type: String) {
    let action: String
    switch type {
    case "app.nussnuss.add", "add":
      action = "add"
    case "app.nussnuss.activity", "activity":
      action = "activity"
    default:
      return
    }
    if ready, let channel = channel {
      channel.invokeMethod("open", arguments: action)
    } else {
      pending = action
    }
  }

  @objc(scene:willConnectToSession:options:)
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    if let item = connectionOptions?.shortcutItem {
      receive(item.type)
    }
    return false
  }

  @objc(windowScene:performActionForShortcutItem:completionHandler:)
  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) -> Bool {
    receive(shortcutItem.type)
    completionHandler(true)
    return true
  }
}

#if canImport(AppIntents)
/// "Add an expense in NussNuss": Siri and the Shortcuts app open the add flow (as Home's +).
@available(iOS 16.0, *)
struct AddExpenseIntent: AppIntent {
  static let title: LocalizedStringResource = "Add an expense"
  static let description = IntentDescription("Opens NussNuss to add an expense to a group.")
  static let openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    ShortcutBridge.shared.receive("add")
    return .result()
  }
}

@available(iOS 16.0, *)
struct NussNussShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: AddExpenseIntent(),
      phrases: ["Add an expense in \(.applicationName)"]
    )
  }
}
#endif

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
