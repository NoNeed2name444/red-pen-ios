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
        // the view puts the system's margins back itself, with less above and
        // below on the medium widget, so two rows and the button fit
        .contentMarginsDisabled()
    }
}

struct DueCardsView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins

    private var due: Int { entry.digest.dueShown(at: entry.date) }
    private var hasFile: Bool { entry.hasFile }

    var body: some View {
        content.padding(insets)
    }

    /// The system's margins, except the medium widget's top and bottom.
    private var insets: EdgeInsets {
        guard family == .systemMedium else { return margins }
        return EdgeInsets(top: GlanceStyle.mediumVerticalMargin, leading: margins.leading,
                          bottom: GlanceStyle.mediumVerticalMargin, trailing: margins.trailing)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(hasFile ? "\(due)" : GlanceWords.noNumber)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.5)
                Text("due").font(.caption2)
            }
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hasFile ? cardWords(due) + " due" : GlanceWords.openApp)
        case .accessoryInline:
            Text(!hasFile ? GlanceWords.openApp : (due == 0 ? "Nothing due" : cardWords(due) + " due"))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(!hasFile ? GlanceWords.openApp : (due == 0 ? "All caught up" : cardWords(due) + " due"))
                    .font(.headline)
                    .widgetAccentable()
                if !hasFile {
                    Text("to see your cards").font(.caption)
                }
                ForEach(entry.digest.topDecks.prefix(2)) { deck in
                    Text("\(deck.name) \u{00B7} \(deck.count)")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                bigCount
                // two deck rows and the button, each a 44 pt target, when
                // they fit; on a shorter widget one row, then the button alone
                ViewThatFits(in: .vertical) {
                    mediumColumn(decks: 2)
                    mediumColumn(decks: 1)
                    mediumColumn(decks: 0)
                }
                .foregroundStyle(GlanceStyle.ink)
            }
        default:
            bigCount
        }
    }

    /// Up to `decks` deck rows, each opening its deck (owner decision D4),
    /// and the Review button.
    private func mediumColumn(decks: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entry.digest.topDecks.prefix(decks)) { deck in
                Link(destination: AppLink.openSet(deck.id).url) {
                    HStack {
                        Text(deck.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(deck.count)").monospacedDigit()
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: GlanceStyle.minTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("\(deck.name), \(cardWords(deck.count)) due")
            }
            Spacer(minLength: 0)
            if due > 0 {
                // interactive: opens the app on the due cards
                Button(intent: ReviewDueIntent()) {
                    // plain, with the look drawn on the label: a bordered
                    // style's own padding would make the target 56 pt and
                    // push the second deck row out
                    Label("Review", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GlanceStyle.pen)
                        .frame(maxWidth: .infinity, minHeight: GlanceStyle.minTarget)
                        .background(GlanceStyle.pen.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bigCount: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "rectangle.stack")
                .font(.headline)
                .foregroundStyle(GlanceStyle.pen)
            Spacer(minLength: 0)
            Text(hasFile ? "\(due)" : GlanceWords.noNumber)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .foregroundStyle(GlanceStyle.ink)
                .contentTransition(.numericText())
                .accessibilityHidden(!hasFile)
            Text(!hasFile ? GlanceWords.openApp + " to see your cards" : (due == 0 ? "All caught up" : "due now"))
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(GlanceStyle.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
