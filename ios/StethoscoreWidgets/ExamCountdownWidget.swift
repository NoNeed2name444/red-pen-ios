import SwiftUI
import WidgetKit

/// Days to the exam. Home Screen small, Lock Screen circular and inline.
struct ExamCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "stethoscore.countdown", provider: GlanceProvider()) { entry in
            ExamCountdownView(entry: entry)
                .glanceBackground()
                .widgetURL(AppLink.examPlan.url)
        }
        .configurationDisplayName("Exam countdown")
        .description("Days until your exam.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct ExamCountdownView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    private var days: Int? { entry.digest.daysToExam(now: entry.date) }
    private var name: String { entry.digest.examName ?? "Your exam" }

    private var phrase: String {
        guard let days else { return "Set your exam date" }
        if days == 0 { return "Exam day" }
        if days == 1 { return "Tomorrow" }
        return "\(days) days"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(days.map { "\($0)" } ?? "\u{2013}")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.5)
                Text("days").font(.caption2)
            }
            .widgetAccentable()
        case .accessoryInline:
            Text(days == nil ? "No exam date" : name + ": " + phrase)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).lineLimit(1).widgetAccentable()
                Text(phrase).font(.body)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "calendar")
                    .font(.headline)
                    .foregroundStyle(GlanceStyle.pen)
                Spacer(minLength: 0)
                Text(days.map { "\($0)" } ?? "\u{2013}")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                Text(days == nil ? "Set your exam date" : (days == 1 ? "day to " : "days to ") + name)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
