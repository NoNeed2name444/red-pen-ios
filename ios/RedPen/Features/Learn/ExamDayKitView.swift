import SwiftUI

/// The exam-morning kit: pacing checkpoints for the student's paper, how to
/// handle a hard question, what the evidence says about changing an answer,
/// a checklist, and an optional two-minute worry box that is never kept.
///
/// Nothing to learn on this screen, on purpose.
struct ExamDayKitView: View {
    /// Ticks on the checklist, for today only.
    @AppStorage("learn.kit.ticks") private var ticksStore = ""
    @AppStorage("learn.kit.day") private var ticksDay = ""
    /// The worry box. Never saved or sent: @State only, and cleared when the
    /// screen closes.
    @State private var worries = ""
    @FocusState private var writing: Bool

    private static let checklist: [String] = [
        "Photo ID and your exam confirmation",
        "Directions and travel time, with a margin",
        "Water and something to eat at the break",
        "Anything your test centre allows (earplugs, glasses)",
        "Phone off and away before you go in",
    ]

    var body: some View {
        let track: ExamTrack = ExamTrack.current
        // the chosen exam's own paper, when there is one
        let exam: TargetExam? = ExamChoice.current
        let paper: ExamWeekPlanner.Paper = exam.map { ExamWeekPlanner.paper(for: $0) } ?? ExamWeekPlanner.paper(for: track)
        List {
            Section {
                PacingTable(paper: paper)
            } header: {
                Text("Pacing \u{00B7} \(paper.name)")
            } footer: {
                Text(Self.paceNote(paper, seconds: exam?.secondsPerQuestion ?? track.secondsPerQuestion))
            }
            Section("A question you can\u{2019}t crack") {
                tip("flag.fill", "Flag it, pick your best answer now, and move on. Come back at the end with fresh eyes.")
                tip("arrow.triangle.branch", "Rule out what you can. Two options left is a far better guess than five.")
                if let negative = exam?.negativeMarking {
                    tip("hourglass", "\(exam?.shortName ?? "Your exam") marks \(negative): guess when you are down to two options, leave it blank when you have no idea.")
                } else {
                    tip("hourglass", "Never leave one blank: an unanswered question scores nothing.")
                }
            }
            Section {
                tip("arrow.uturn.backward", "Changing an answer helps more often than it hurts in studies of medical exams \u{2014} when you have a reason, such as a detail you misread. Without a reason, leave it.")
            } header: {
                Text("Changing answers")
            }
            Section("Checklist") {
                ForEach(Array(Self.checklist.enumerated()), id: \.offset) { item in
                    checkRow(item.offset, item.element)
                }
            }
            Section {
                TextEditor(text: $worries)
                    .focused($writing)
                    .frame(minHeight: 120)
                    .popEditorRow()
                    .accessibilityLabel("Worry box")
                if !worries.isEmpty {
                    Button("Clear it", systemImage: "trash") { worries = "" }
                        .frame(minHeight: 44)
                }
            } header: {
                Text("Optional: two minutes of worries")
            } footer: {
                Text("Some students find that writing their worries down just before an exam frees their head for the paper; the evidence is mixed, so skip it if it isn\u{2019}t for you. Nothing here is saved or sent, and it is gone when you close this screen.")
            }
        }
        .navigationTitle("Exam-day kit")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onDisappear { worries = "" }
        .onAppear { resetTicksIfNewDay() }
    }

    private static func paceNote(_ paper: ExamWeekPlanner.Paper, seconds: Int) -> String {
        if paper.published {
            let time: String = ExamWeekPlanner.clock(paper.minutes)
            return "\(paper.questions) questions in \(time). Glance at the clock at each checkpoint; ahead or a little behind is fine."
        }
        return "About a question every \(seconds) seconds. Check your own paper\u{2019}s question count and time on your confirmation."
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24).accessibilityHidden(true)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private var ticks: Set<Int> {
        Set(ticksStore.split(separator: ",").compactMap { Int($0) })
    }

    private func checkRow(_ index: Int, _ text: String) -> some View {
        let done: Bool = ticks.contains(index)
        return Button {
            var next = ticks
            if done { next.remove(index) } else { next.insert(index) }
            ticksStore = next.sorted().map(String.init).joined(separator: ",")
            ticksDay = StudyLog.key(for: Date())
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(text).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(done ? [.isSelected] : [])
    }

    private func resetTicksIfNewDay() {
        let today = StudyLog.key(for: Date())
        if ticksDay != today {
            ticksStore = ""
            ticksDay = today
        }
    }
}

/// "By 1:00 be at Q60".
private struct PacingTable: View {
    let paper: ExamWeekPlanner.Paper

    var body: some View {
        let points: [ExamWeekPlanner.Checkpoint] = ExamWeekPlanner.checkpoints(for: paper)
        VStack(spacing: 0) {
            ForEach(points, id: \.minute) { point in
                HStack {
                    Text("By " + ExamWeekPlanner.clock(point.minute))
                        .font(.body.monospacedDigit())
                    Spacer()
                    Text("Q\(point.question)")
                        .font(.body.weight(.semibold).monospacedDigit())
                }
                .frame(minHeight: 36)
                .accessibilityElement(children: .combine)
                if point != points.last { Divider() }
            }
        }
    }
}
