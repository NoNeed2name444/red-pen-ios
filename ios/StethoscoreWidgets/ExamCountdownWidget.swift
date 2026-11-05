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

    /// Days to the exam, nil with no date or once it has passed (home shows
    /// no countdown then either).
    private var days: Int? { entry.digest.daysToExam(now: entry.date).flatMap { $0 >= 0 ? $0 : nil } }
    /// Home's name for the exam: the chosen one's short name, or finals.
    private var name: String { entry.digest.examName ?? WardWords.defaultExam }
    /// Home's sentence: "Step 1 in 90 days", "Finals tomorrow".
    private var sentence: String? { WardWords.countdown(days: days, exam: entry.digest.examName) }
    private var hasFile: Bool { entry.hasFile }

    private var caption: String {
        guard hasFile else { return GlanceWords.openApp + " to see your countdown" }
        guard let days else { return "Set your exam date" }
        if days == 0 { return sentence ?? name }
        return (days == 1 ? "day to " : "days to ") + name
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(days.map { "\($0)" } ?? GlanceWords.noNumber)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.5)
                Text("days").font(.caption2)
            }
            .widgetAccentable()
            // the en dash is never read out: no file, or no date, is said in words
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(!hasFile ? GlanceWords.openApp : (sentence ?? "No exam date"))
        case .accessoryInline:
            Text(!hasFile ? GlanceWords.openApp : (sentence ?? "No exam date"))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(hasFile ? (sentence ?? "Set your exam date") : GlanceWords.openApp)
                    .font(.headline).lineLimit(2).widgetAccentable()
                if !hasFile {
                    Text("to see your countdown").font(.body)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "calendar")
                    .font(.headline)
                    .foregroundStyle(GlanceStyle.pen)
                Spacer(minLength: 0)
                Text(days.map { "\($0)" } ?? GlanceWords.noNumber)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(GlanceStyle.ink)
                    .accessibilityHidden(days == nil)
                Text(caption)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(GlanceStyle.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
