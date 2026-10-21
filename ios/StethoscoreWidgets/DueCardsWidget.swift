import AppIntents
import SwiftUI
import WidgetKit

/// Cards due now, and the decks with the most. Home Screen (small and
/// medium, StandBy), Lock Screen (circular, rectangular, inline).
struct DueCardsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "stethoscore.due", provider: GlanceProvider()) { entry in
            DueCardsView(entry: entry)
                .glanceBackground()
                .widgetURL(AppLink.reviewDue.url)
        }
        .configurationDisplayName("Due cards")
        .description("How many cards are waiting, and where.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct DueCardsView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    private var due: Int { entry.digest.dueShown(at: entry.date) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("\(due)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.5)
                Text("due").font(.caption2)
            }
            .widgetAccentable()
        case .accessoryInline:
            Text(due == 0 ? "Nothing due" : cardWords(due) + " due")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(due == 0 ? "All caught up" : cardWords(due) + " due")
                    .font(.headline)
                    .widgetAccentable()
                ForEach(entry.digest.topDecks.prefix(2)) { deck in
                    Text("\(deck.name) \u{00B7} \(deck.count)")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                bigCount
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.digest.topDecks) { deck in
                        HStack {
                            Text(deck.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(deck.count)").monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                    if due > 0 {
                        // interactive: opens the app on the due cards
                        Button(intent: ReviewDueIntent()) {
                            Label("Review", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(GlanceStyle.pen)
                    }
                }
                .foregroundStyle(.white)
            }
        default:
            bigCount
        }
    }

    private var bigCount: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "rectangle.stack")
                .font(.headline)
                .foregroundStyle(GlanceStyle.pen)
            Spacer(minLength: 0)
            Text("\(due)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(due == 0 ? "All caught up" : "due now")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
