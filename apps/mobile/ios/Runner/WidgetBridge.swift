import Flutter
import UIKit
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Hands the home-screen widget and the trip Live Activity what to show. Flutter calls
/// MethodChannel "nussnuss/widget": "update" {title, amount, sub} after each overview, and
/// "startTrip" / "updateTrip" {groupId, title, amount, sub} and "endTrip" {groupId} for a trip.
final class WidgetBridge {
  static let suite = "group.app.nussnuss.shared"
  private var channel: FlutterMethodChannel?

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "nussnuss/widget", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      let text = { (key: String) -> String in args[key] as? String ?? "" }
      switch call.method {
      case "update":
        let defaults = UserDefaults(suiteName: WidgetBridge.suite)
        defaults?.set(text("title"), forKey: "title")
        defaults?.set(text("amount"), forKey: "amount")
        defaults?.set(text("sub"), forKey: "sub")
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      case "startTrip", "updateTrip":
        if #available(iOS 16.1, *) {
          TripActivities.upsert(groupId: text("groupId"), title: text("title"), amount: text("amount"), sub: text("sub"))
        }
        result(nil)
      case "endTrip":
        if #available(iOS 16.1, *) {
          TripActivities.end(groupId: text("groupId"))
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
enum TripActivities {
  /// Starts the trip's Live Activity, or updates it when it is already showing.
  static func upsert(groupId: String, title: String, amount: String, sub: String) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let state = TripActivityAttributes.ContentState(amount: amount, sub: sub)
    if let running = Activity<TripActivityAttributes>.activities.first(where: { $0.attributes.groupId == groupId }) {
      Task { await running.update(using: state) }
      return
    }
    _ = try? Activity<TripActivityAttributes>.request(
      attributes: TripActivityAttributes(groupId: groupId, title: title),
      contentState: state,
      pushType: nil
    )
  }

  static func end(groupId: String) {
    for activity in Activity<TripActivityAttributes>.activities where activity.attributes.groupId == groupId {
      Task { await activity.end(dismissalPolicy: .immediate) }
    }
  }
}
#else
@available(iOS 16.1, *)
enum TripActivities {
  static func upsert(groupId: String, title: String, amount: String, sub: String) {}
  static func end(groupId: String) {}
}
#endif
