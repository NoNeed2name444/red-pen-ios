import ActivityKit
import SwiftUI
import WidgetKit

/// The exam-day Live Activity: the evening before and on the day, the Lock
/// Screen and the Dynamic Island show the exam, the time to the paper (when
/// the student gave one) and the cards still due. Started and ended by the
/// app (ExamDayActivity in GlancePublisher.swift); nothing here animates
/// beyond the system's own timer text.
struct ExamDayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExamDayAttributes.self) { context in
            ExamDayLockView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(GlanceStyle.night)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(AppLink.examPlan.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.examName, systemImage: "graduationcap.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExamDayClock(state: context.state, examDay: context.attributes.examDay)
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.dueNow == 0 ? "All caught up \u{2013} good luck" : cardWords(context.state.dueNow) + " for a last look")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(GlanceStyle.pen)
            } compactTrailing: {
                ExamDayClock(state: context.state, examDay: context.attributes.examDay)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(GlanceStyle.pen)
            }
            .widgetURL(AppLink.examPlan.url)
        }
    }
}

/// A countdown to the paper when there is a start time; otherwise "Today"
/// or "Tomorrow".
struct ExamDayClock: View {
    let state: ExamDayAttributes.ContentState
    let examDay: Date

    var body: some View {
        if let start = state.startsAt, start > Date() {
            Text(timerInterval: Date()...start, countsDown: true)
                .multilineTextAlignment(.trailing)
        } else {
            Text(Calendar.current.isDateInToday(examDay) ? "Today" : "Tomorrow")
        }
    }
}

struct ExamDayLockView: View {
    let attributes: ExamDayAttributes
    let state: ExamDayAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "graduationcap.fill")
                .font(.title2)
                .foregroundStyle(GlanceStyle.pen)
            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.examName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(state.dueNow == 0 ? "All caught up \u{2013} good luck" : cardWords(state.dueNow) + " for a last look")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 8)
            ExamDayClock(state: state, examDay: attributes.examDay)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}
