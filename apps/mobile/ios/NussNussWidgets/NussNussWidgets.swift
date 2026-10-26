import ActivityKit
import SwiftUI
import WidgetKit

/// The app writes the latest overview here (WidgetBridge in the Runner target).
private let suite = "group.app.nussnuss.shared"
private let arabic = Locale.preferredLanguages.first?.hasPrefix("ar") ?? false

// MARK: - Colours (the same tokens as the app: tokens.json)

private extension UIColor {
  convenience init(hex: UInt32) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}

private func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
  Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
}

private enum NN {
  static let bg = adaptive(0xF2F1F7, 0x0D0A1C)
  static let text = adaptive(0x15121F, 0xF4F2FA)
  static let text2 = adaptive(0x57526D, 0xB4ADD0)
  static let accent = adaptive(0x4F3BD6, 0x9B8BFF)
  static let highlight = adaptive(0xF4B400, 0xFFC93D)
}

/// The NussNuss mark: a violet half and a saffron half of one coin, the saffron half dropped a little.
struct CoinMark: View {
  var size: CGFloat
  var body: some View {
    HStack(alignment: .top, spacing: size * 0.07) {
      UnevenRoundedRectangle(topLeadingRadius: size / 2, bottomLeadingRadius: size / 2, bottomTrailingRadius: 0, topTrailingRadius: 0)
        .fill(NN.accent)
        .frame(width: size / 2, height: size)
      UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: size / 2, topTrailingRadius: size / 2)
        .fill(NN.highlight)
        .frame(width: size / 2, height: size)
        .offset(y: size * 0.08)
    }
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityHidden(true)
  }
}

// MARK: - Home-screen widget: your overall balance

struct BalanceEntry: TimelineEntry {
  let date: Date
  let title: String
  let amount: String
  let sub: String
}

struct BalanceProvider: TimelineProvider {
  func placeholder(in context: Context) -> BalanceEntry {
    BalanceEntry(
      date: Date(),
      title: arabic ? "بالمجمل، لك" : "Overall, you get back",
      amount: arabic ? "230.00 د.إ" : "AED 230.00",
      sub: arabic ? "في 3 مجموعات" : "Across 3 groups"
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : current())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
    // The app reloads the widget whenever the balance changes; otherwise look again in an hour.
    completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(3600))))
  }

  private func current() -> BalanceEntry {
    let d = UserDefaults(suiteName: suite)
    let amount = d?.string(forKey: "amount") ?? ""
    return BalanceEntry(
      date: Date(),
      title: d?.string(forKey: "title") ?? "NussNuss",
      amount: amount,
      sub: d?.string(forKey: "sub") ?? (arabic ? "افتح التطبيق لتعرف وضعك." : "Open the app to see where you stand.")
    )
  }
}

struct BalanceWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: BalanceEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      CoinMark(size: 22)
      Spacer(minLength: 0)
      Text(entry.title)
        .font(.caption.weight(.medium))
        .foregroundStyle(NN.text2)
        .lineLimit(2)
      if !entry.amount.isEmpty {
        Text(entry.amount)
          .font(.system(size: family == .systemSmall ? 24 : 32, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(NN.text)
          .minimumScaleFactor(0.5)
          .lineLimit(1)
      }
      Text(entry.sub)
        .font(.caption2)
        .foregroundStyle(NN.text2)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .widgetBackground(NN.bg)
  }
}

private extension View {
  @ViewBuilder func widgetBackground(_ color: Color) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(color, for: .widget)
    } else {
      padding().background(color)
    }
  }
}

struct BalanceWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NussNussBalance", provider: BalanceProvider()) { entry in
      BalanceWidgetView(entry: entry)
    }
    .configurationDisplayName(arabic ? "رصيدك" : "Your balance")
    .description(arabic ? "وضعك في كل مجموعاتك." : "Where you stand across all your groups.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// MARK: - Live Activity: a trip on the Lock Screen and in the Dynamic Island

struct TripLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TripActivityAttributes.self) { context in
      HStack(spacing: 12) {
        CoinMark(size: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(context.attributes.title)
            .font(.headline)
            .foregroundStyle(NN.text)
            .lineLimit(1)
          Text(context.state.sub)
            .font(.caption)
            .foregroundStyle(NN.text2)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Text(context.state.amount)
          .font(.system(.title3, design: .rounded).weight(.bold))
          .monospacedDigit()
          .foregroundStyle(NN.text)
          .minimumScaleFactor(0.6)
          .lineLimit(1)
      }
      .padding(16)
      .activityBackgroundTint(NN.bg)
      .activitySystemActionForegroundColor(NN.accent)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CoinMark(size: 24)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.amount)
            .font(.headline)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text("\(context.attributes.title) · \(context.state.sub)")
            .font(.caption)
            .lineLimit(1)
        }
      } compactLeading: {
        CoinMark(size: 14)
      } compactTrailing: {
        Text(context.state.amount)
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      } minimal: {
        CoinMark(size: 12)
      }
    }
  }
}

@main
struct NussNussWidgets: WidgetBundle {
  var body: some Widget {
    BalanceWidget()
    TripLiveActivity()
  }
}
