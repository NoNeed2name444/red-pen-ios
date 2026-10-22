import SwiftUI
import UIKit
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

// MARK: - The look: the app's plain grey ground and ink, and the pen's red, drawn flat

enum GlanceStyle {
    /// The app's ground, ink and second ink (WardPalette .background, .ink
    /// and .inkSecondary, by day and at night), flat as the app is (the
    /// owner: flat colours only, the plain grey grounds #E9EDF2 / #171C24).
    /// The widget target does not build Ward, so the values are repeated
    /// here; they must stay WardPalette's.
    static let ground = Color(uiColor: dynamic(light: 0xE9EDF2, dark: 0x171C24))
    static let ink = Color(uiColor: dynamic(light: 0x232C39, dark: 0xF1F4F8))
    static let inkSecondary = Color(uiColor: dynamic(light: 0x536171, dark: 0xB8C2D0))
    /// Vital Coral #FF6B6B and Care Blue #3B82F6 (docs/design/palette-2026-10-21.md).
    static let pen = Color(red: 255 / 255, green: 107 / 255, blue: 107 / 255)
    static let star = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

extension View {
    /// The widget's background in every family: the app's flat grey.
    /// Lock Screen and StandBy tint it themselves.
    func glanceBackground() -> some View {
        containerBackground(for: .widget) {
            GlanceStyle.ground
        }
    }
}

/// "12 cards", "1 card".
func cardWords(_ count: Int) -> String {
    count == 1 ? "1 card" : "\(count) cards"
}
