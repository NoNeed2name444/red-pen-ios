import ActivityKit
import SwiftUI
import WidgetKit

/// The ward round's Live Activity: "Round 2 of 4 · 12:40 · 38 cards" on the
/// Lock Screen, the time left in the Dynamic Island. Started, updated and
/// ended by the app (WardRoundActivity in WardRoundClock.swift); the clock
/// is the system's own timer text, so nothing here animates or is sent each
/// second. A tap opens the exam plan, where the round's tile is.
struct WardRoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WardRoundAttributes.self) { context in
            WardRoundLockView(state: context.state, stale: context.isStale)
                .padding(16)
                .activityBackgroundTint(GlanceStyle.night)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(AppLink.examPlan.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(WardRoundWords.title(context.state), systemImage: WardRoundWords.symbol(context.state))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WardRoundLiveClock(state: context.state, stale: context.isStale)
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(cardWords(context.state.items) + " this ward round")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: WardRoundWords.symbol(context.state))
                    .foregroundStyle(GlanceStyle.star)
            } compactTrailing: {
                WardRoundLiveClock(state: context.state, stale: context.isStale)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: WardRoundWords.symbol(context.state))
                    .foregroundStyle(GlanceStyle.star)
            }
            .widgetURL(AppLink.examPlan.url)
        }
    }
}

/// What the activity says about the phase.
enum WardRoundWords {
    static func title(_ state: WardRoundAttributes.ContentState) -> String {
        switch state.phase {
        case "rest": return "Break"
        case "ready": return "Round \(state.round + 1) of \(state.rounds) next"
        case "done": return "Ward round done"
        default: return "Round \(state.round) of \(state.rounds)"
        }
    }

    static func symbol(_ state: WardRoundAttributes.ContentState) -> String {
        switch state.phase {
        case "rest": return "moon.stars.fill"
        case "ready": return "play.fill"
        case "done": return "checkmark"
        default: return "stethoscope"
        }
    }

    static func held(_ seconds: Double) -> String {
        let whole: Int = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// The time left: the system's countdown while running, the held time while
/// paused, nothing once the phase is over.
struct WardRoundLiveClock: View {
    let state: WardRoundAttributes.ContentState
    let stale: Bool

    var body: some View {
        if let held = state.heldSeconds {
            Text(WardRoundWords.held(held))
        } else if let ends = state.endsAt, ends > Date(), !stale {
            Text(timerInterval: Date()...ends, countsDown: true)
                .multilineTextAlignment(.trailing)
        } else {
            Text(state.phase == "focus" ? "Done" : "\u{2013}")
        }
    }
}

struct WardRoundLockView: View {
    let state: WardRoundAttributes.ContentState
    let stale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: WardRoundWords.symbol(state))
                .font(.title2)
                .foregroundStyle(GlanceStyle.star)
            VStack(alignment: .leading, spacing: 3) {
                Text(WardRoundWords.title(state))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(cardWords(state.items))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 8)
            WardRoundLiveClock(state: state, stale: stale)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}
