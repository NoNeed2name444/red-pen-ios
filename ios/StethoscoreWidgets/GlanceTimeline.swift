import SwiftUI
import WidgetKit

/// One moment of the digest.
struct GlanceEntry: TimelineEntry {
    let date: Date
    let digest: GlanceDigest
    /// The gallery's preview, with example numbers.
    let isPreview: Bool
}

/// Reads the digest the app last wrote. The app asks WidgetKit to reload
/// only when a number changed (GlancePublisher); in between, the timeline
/// has an entry at midnight (today's count and the countdown turn over) and
/// at the next card's due time (the due count may have grown).
struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), digest: .sample, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        let stored: GlanceDigest? = GlanceShelf.read()
        let preview: Bool = context.isPreview || stored == nil
        let digest: GlanceDigest = preview ? .sample : (stored ?? .empty)
        completion(GlanceEntry(date: Date(), digest: digest, isPreview: preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date()
        let digest: GlanceDigest = GlanceShelf.read() ?? .empty
        var dates: [Date] = [now]
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.append(midnight)
        }
        if let next = digest.nextDue, next > now { dates.append(next) }
        dates.sort()
        let entries: [GlanceEntry] = dates.map { GlanceEntry(date: $0, digest: digest, isPreview: false) }
        // a fresh look within a few hours even if the app is never opened
        let refresh: Date = now.addingTimeInterval(4 * 3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

// MARK: - The look: the night sky and the pen's red, drawn flat

enum GlanceStyle {
    static let night = Color(red: 0.035, green: 0.047, blue: 0.11)
    static let dusk = Color(red: 0.11, green: 0.09, blue: 0.24)
    static let pen = Color(red: 0.886, green: 0.243, blue: 0.188)
    static let star = Color(red: 0.549, green: 0.784, blue: 0.941)

    /// The sky behind a Home Screen widget. Lock Screen and StandBy tint
    /// it themselves, so the accessory families get none.
    static var sky: LinearGradient {
        LinearGradient(colors: [dusk, night], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// The widget's background in every family.
    func glanceBackground() -> some View {
        containerBackground(for: .widget) {
            GlanceStyle.sky
        }
    }
}

/// "12 cards", "1 card".
func cardWords(_ count: Int) -> String {
    count == 1 ? "1 card" : "\(count) cards"
}
