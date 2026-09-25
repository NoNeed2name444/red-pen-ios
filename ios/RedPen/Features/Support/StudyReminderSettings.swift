import SwiftUI

/// The opt-in study reminders, as one Form section: the question of the day
/// (answered A to E from the notification), bedtime lock-in and the morning
/// check. All off until turned on; turning one on asks for notification
/// permission if it has not been given.
///
/// Drop into any settings Form: `StudyReminderSettings()`.
struct StudyReminderSettings: View {
    @EnvironmentObject private var store: Store
    @AppStorage(ReminderSettings.questionKey) private var questionOn = false
    @AppStorage(ReminderSettings.bedtimeKey) private var bedtimeOn = false
    @AppStorage(ReminderSettings.morningKey) private var morningOn = false
    @AppStorage(ReminderSettings.questionTimeKey) private var questionTime = ReminderSettings.defaultQuestionTime
    @AppStorage(ReminderSettings.bedtimeTimeKey) private var bedtime = ReminderSettings.defaultBedtime
    @AppStorage(ReminderSettings.morningTimeKey) private var morningTime = ReminderSettings.defaultMorning
    @State private var denied = false

    var body: some View {
        Section {
            Toggle(isOn: $questionOn) {
                Label("Question of the day", systemImage: "questionmark.bubble")
            }
            if questionOn { timeRow("Time", minutes: $questionTime) }
            Toggle(isOn: $bedtimeOn) {
                Label("Bedtime lock-in", systemImage: "moon.stars")
            }
            if bedtimeOn { timeRow("Bedtime", minutes: $bedtime) }
            Toggle(isOn: $morningOn) {
                Label("Morning check", systemImage: "sunrise")
            }
            if morningOn { timeRow("Time", minutes: $morningTime) }
            if denied {
                Text("Notifications are off for this app. Turn them on in Settings \u{2192} Notifications.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Study reminders")
        } footer: {
            Text("A question from your weakest subject each day, answered right on the notification. In the evening, a calm re-read of the day\u{2019}s misses; the next morning, two minutes on the same ones. Nothing leaves your phone.")
        }
        .onChange(of: questionOn) { _, on in changed(on) }
        .onChange(of: bedtimeOn) { _, on in changed(on) }
        .onChange(of: morningOn) { _, on in changed(on) }
        .onChange(of: questionTime) { _, _ in LearnNotifications.reschedule(store: store) }
        .onChange(of: bedtime) { _, _ in LearnNotifications.reschedule(store: store) }
        .onChange(of: morningTime) { _, _ in LearnNotifications.reschedule(store: store) }
    }

    private func changed(_ on: Bool) {
        Task { @MainActor in
            if on {
                let allowed = await LearnNotifications.requestPermission()
                denied = !allowed
            }
            LearnNotifications.reschedule(store: store)
        }
    }

    /// A time of day, stored as minutes after midnight.
    private func timeRow(_ title: String, minutes: Binding<Int>) -> some View {
        let date = Binding<Date>(
            get: {
                let start = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(byAdding: .minute, value: minutes.wrappedValue, to: start) ?? start
            },
            set: { value in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
        return DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
            .frame(minHeight: 44)
    }
}
