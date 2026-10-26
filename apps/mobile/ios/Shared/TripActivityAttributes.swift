import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// A trip on the Lock Screen and in the Dynamic Island: the group's name, and your balance in it.
/// Compiled into both the app (which starts and updates it) and the widget extension (which draws it).
@available(iOS 16.1, *)
struct TripActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// "AED 110.00", already formatted in the person's language.
    var amount: String
    /// "You get back", "You owe" or "All settled".
    var sub: String
  }

  var groupId: String
  var title: String
}
#endif
