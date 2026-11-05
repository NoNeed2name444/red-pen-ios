import SwiftUI
import UIKit
import WidgetKit

/// One moment of the digest.
struct GlanceEntry: TimelineEntry {
    let date: Date
    /// The file the app wrote into the App Group; nil when the widget
    /// cannot read one (GlanceState.noFile).
    let stored: GlanceDigest?
    /// The gallery's preview, with example numbers.
    let isPreview: Bool

    /// The numbers to draw; zeros when there is no file, and then `state`
    /// says so, so no widget reads them as "nothing due".
    var digest: GlanceDigest { stored ?? .empty }
    var state: GlanceState { GlanceState.of(stored, at: date) }
    var hasFile: Bool { state != .noFile }
}

/// Reads the digest the app last wrote. The app asks WidgetKit to reload
/// only when a number changed (GlancePublisher); in between, the timeline
/// has an entry at midnight (today's count and the countdown turn over) and
/// at the next card's due time (the due count may have grown).
struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), stored: .sample, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        // example numbers only in the gallery; on the Home Screen a missing
        // file is shown as missing, never as the sample
        if context.isPreview {
            completion(GlanceEntry(date: Date(), stored: .sample, isPreview: true))
        } else {
            completion(GlanceEntry(date: Date(), stored: GlanceShelf.readShared(), isPreview: false))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date()
        // the shared file only: without it the widget says "open the app"
        // (GlanceState.noFile), not "All caught up"
        let stored: GlanceDigest? = GlanceShelf.readShared()
        let digest: GlanceDigest = stored ?? .empty
        var dates: [Date] = [now]
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.append(midnight)
        }
        if let next = digest.nextDue, next > now { dates.append(next) }
        dates.sort()
        let entries: [GlanceEntry] = dates.map { GlanceEntry(date: $0, stored: stored, isPreview: false) }
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
    /// The smallest tap target inside a widget: 44 pt (Apple's minimum, and
    /// the owner's rule).
    static let minTarget: CGFloat = 44
    /// The medium Due widget's top and bottom margin, smaller than the
    /// system's so two 44 pt deck rows and the 44 pt Review button fit
    /// (132 pt) on a 148 pt widget; a shorter one shows fewer rows.
    static let mediumVerticalMargin: CGFloat = 8

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

/// What a widget says when it has no file from the app. The app's name is
/// spelled out as in ReviewDueControl; the extension does not build Brand.
enum GlanceWords {
    static let openApp = "Open Stethoscore"
    /// The small widgets' number when there is none to show.
    static let noNumber = "\u{2013}"
}

/// "12 cards", "1 card".
func cardWords(_ count: Int) -> String {
    count == 1 ? "1 card" : "\(count) cards"
}
