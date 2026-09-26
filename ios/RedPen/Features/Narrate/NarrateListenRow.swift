import SwiftUI

/// The small row above the lecture's transport: which section it is in, the
/// way to the one before or after, and the sleep timer.
///
/// The same row for a recording and for the lecture read aloud, so the
/// student meets one set of controls. Small glass chips rather than more big
/// buttons: the transport below is what the thumb looks for, and these are
/// reached for a few times a lecture. With no sections (a short lecture, or
/// one with no headings and no pauses to cut at) only the sleep timer shows.
struct NarrateListenRow: View {
    let sections: [AudioChapter]
    /// The section being heard.
    let current: Int?
    @ObservedObject var sleep: SleepTimer
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPick: (Int) -> Void

    @State private var listing = false

    var body: some View {
        HStack(spacing: 8) {
            if sections.count >= 2 {
                sectionControls
            }
            Spacer(minLength: 0)
            SleepTimerMenu(sleep: sleep, sectioned: sections.count >= 2)
        }
        .font(.subheadline.weight(.semibold))
        .sheet(isPresented: $listing) {
            SectionListSheet(sections: sections, current: current) { onPick($0) }
        }
    }

    private var place: String {
        guard let current else { return "Sections" }
        return "\(current + 1) of \(sections.count)"
    }

    private var sectionControls: some View {
        HStack(spacing: 6) {
            Button(action: onPrevious) { Image(systemName: "backward.end.fill") }
                .buttonStyle(.glass)
                .accessibilityLabel("Previous section")
            Button { listing = true } label: {
                Label(place, systemImage: "list.bullet")
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Sections, \(place)")
            .accessibilityHint("Shows the lecture's sections to jump to")
            Button(action: onNext) { Image(systemName: "forward.end.fill") }
                .buttonStyle(.glass)
                .disabled(current.map { $0 + 1 >= sections.count } ?? false)
                .accessibilityLabel("Next section")
        }
    }
}

/// The sleep timer's chip: a moon, and the time left while it runs.
///
/// Watches the timer on its own, so the countdown ticking once a second
/// rebuilds this chip and nothing else.
struct SleepTimerMenu: View {
    @ObservedObject var sleep: SleepTimer
    /// Whether "End of this section" means more than the end of the lecture.
    var sectioned = true

    private var shown: String {
        sleep.countdown?.label ?? "Sleep"
    }

    var body: some View {
        Menu {
            Picker("Sleep timer", selection: choice) {
                ForEach(SleepChoice.all, id: \.self) { option in
                    Text(name(option)).tag(Optional(option))
                }
            }
            if sleep.running {
                Button("Turn off", systemImage: "xmark") { sleep.cancel() }
            }
        } label: {
            Label(shown, systemImage: sleep.running ? "moon.zzz.fill" : "moon.zzz")
                .monospacedDigit()
                .lineLimit(1)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(sleep.running ? "Sleep timer, \(shown) left" : "Sleep timer")
    }

    private var choice: Binding<SleepChoice?> {
        Binding(get: { sleep.countdown?.choice },
                set: { picked in
                    if let picked { sleep.start(picked) } else { sleep.cancel() }
                })
    }

    private func name(_ option: SleepChoice) -> String {
        if option == .endOfSection && !sectioned { return "End of the lecture" }
        return option.name
    }
}

/// Every section, to jump straight to one. A recording's sections show when
/// they start; the one playing is ticked.
struct SectionListSheet: View {
    let sections: [AudioChapter]
    let current: Int?
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(sections.enumerated()), id: \.offset) { i, section in
                    Button {
                        onPick(i)
                        dismiss()
                    } label: {
                        row(i, section)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ i: Int, _ section: AudioChapter) -> some View {
        let playing: Bool = i == current
        let when: String = section.start.map { LectureAudio.clock($0) } ?? ""
        return HStack(spacing: 12) {
            Text("\(i + 1)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)
            Text(section.title)
                .font(playing ? .body.weight(.semibold) : .body)
                .lineLimit(2)
            Spacer(minLength: 8)
            if !when.isEmpty {
                Text(when)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if playing {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Playing")
            }
        }
        .contentShape(Rectangle())
    }
}
