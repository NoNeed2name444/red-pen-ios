import SwiftUI
import WidgetKit

/// Done today and the streak. Home Screen small, Lock Screen circular and
/// inline.
struct TodayStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "stethoscore.today", provider: GlanceProvider()) { entry in
            TodayStreakView(entry: entry)
                .glanceBackground()
                .widgetURL(AppLink.reviewDue.url)
        }
        .configurationDisplayName("Today and streak")
        .description("What you have done today, and your run of days.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct TodayStreakView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    private var today: Int { entry.digest.todayShown(at: entry.date) }
    private var streak: Int { entry.digest.streakShown(at: entry.date) }
    private var hasFile: Bool { entry.hasFile }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                if hasFile {
                    Image(systemName: "flame.fill").font(.caption)
                }
                Text(hasFile ? "\(streak)" : GlanceWords.noNumber)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .accessibilityLabel(hasFile ? "\(streak)" : GlanceWords.openApp)
            }
            .widgetAccentable()
        case .accessoryInline:
            Text(hasFile ? "\(today) today \u{00B7} \(streak)-day streak" : GlanceWords.openApp)
        default:
            VStack(alignment: .leading, spacing: 6) {
                if hasFile {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)").monospacedDigit()
                    }
                    .font(.headline)
                    .foregroundStyle(GlanceStyle.pen)
                }
                Spacer(minLength: 0)
                Text(hasFile ? "\(today)" : GlanceWords.noNumber)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(GlanceStyle.ink)
                    .accessibilityHidden(!hasFile)
                Text(!hasFile ? GlanceWords.openApp + " to see today\u{2019}s count"
                     : (streak == 1 ? "done today \u{00B7} 1 day" : "done today \u{00B7} \(streak) days"))
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(GlanceStyle.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
