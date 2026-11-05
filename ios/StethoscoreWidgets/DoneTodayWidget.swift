import SwiftUI
import WidgetKit

/// What has been done today, against the daily goal. Home Screen small,
/// Lock Screen circular and inline. It took the place of the Today and
/// streak widget and keeps its kind, so a widget already placed stays; no
/// surface shows the streak (docs/design/widgets-watches-proposal.md).
struct DoneTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "stethoscore.today", provider: GlanceProvider()) { entry in
            DoneTodayView(entry: entry)
                .glanceBackground()
                .widgetURL(AppLink.reviewDue.url)
        }
        .configurationDisplayName("Done today")
        .description("Today\u{2019}s count against your daily goal.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct DoneTodayView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    private var today: Int { entry.digest.todayShown(at: entry.date) }
    private var goal: Int { entry.digest.goalShown }
    private var hasFile: Bool { entry.hasFile }
    /// "32 of 50 done today".
    private var sentence: String { "\(today) of \(goal) done today" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Group {
                if hasFile {
                    Gauge(value: Double(min(today, goal)), in: 0...Double(goal)) {
                        Text("today")
                    } currentValueLabel: {
                        Text("\(today)").monospacedDigit()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                } else {
                    Text(GlanceWords.noNumber)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                }
            }
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hasFile ? sentence : GlanceWords.openApp)
        case .accessoryInline:
            Text(hasFile ? sentence : GlanceWords.openApp)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.headline)
                    .foregroundStyle(GlanceStyle.pen)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(hasFile ? "\(today)" : GlanceWords.noNumber)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(GlanceStyle.ink)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
                Text(!hasFile ? GlanceWords.openApp + " to see today\u{2019}s count" : "of \(goal) done today")
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(GlanceStyle.inkSecondary)
                    .accessibilityLabel(hasFile ? sentence : GlanceWords.openApp + " to see today\u{2019}s count")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
