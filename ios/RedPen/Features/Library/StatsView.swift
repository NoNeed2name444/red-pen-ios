import SwiftUI

/// How the studying is going: the streak, and MCQ accuracy subject by subject.
///
/// The point of splitting it by subject is the button at the top. A single
/// overall percentage says "70%" and nothing about what to do next; by
/// subject it says renal is at 48%, and the drill goes straight there,
/// starting with the questions that were got wrong last time.
///
/// Built from the answer history the quiz keeps (Store.answerHistory), so it
/// only knows about questions answered since that history began, and only
/// about sets still in the library.
struct StatsView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var log = StudyLog.shared
    /// The drill being taken, opened without being saved to the library.
    @State private var drill: StudySet?

    var body: some View {
        let stats = store.subjectStats()
        let tried = stats.filter { $0.answered > 0 }
        List {
            Section { overview(tried) }

            if let weakest = tried.first {
                Section {
                    Button {
                        let set = store.drill(subject: weakest.subject)
                        if !set.questions.isEmpty { drill = set }
                    } label: {
                        Label("Drill weakest: \(weakest.subject)", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Up to 20 questions from \(weakest.subject), the ones you got wrong last time first.")
                }
            }

            if stats.isEmpty {
                Section {
                    Text("Make an MCQ set and answer a few questions, and how you are doing in each subject will show here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(stats) { subject in
                        subjectRow(subject)
                            .contextMenu {
                                Button("Drill \(subject.subject)", systemImage: "scope") {
                                    let set = store.drill(subject: subject.subject)
                                    if !set.questions.isEmpty { drill = set }
                                }
                            }
                    }
                } header: {
                    Text("By subject")
                } footer: {
                    Text("Every answer you have checked counts, so a question answered twice counts twice. Weakest first.")
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $drill) { MCQQuizView(set: $0, keepsProgress: false) }
    }

    /// The streak, today, and everything answered so far.
    private func overview(_ tried: [SubjectStats]) -> some View {
        let answered = tried.reduce(0) { $0 + $1.answered }
        let correct = tried.reduce(0) { $0 + $1.correct }
        return HStack(spacing: 0) {
            figure("\(log.streak)", log.streak == 1 ? "day streak" : "days streak",
                   symbol: "flame.fill", color: .orange)
            figure("\(log.today)", "today", symbol: "checkmark.circle.fill", color: .accentColor)
            figure(answered == 0 ? "\u{2013}" : "\(Int((Double(correct) / Double(answered) * 100).rounded()))%",
                   "of \(answered) right", symbol: "target", color: .green)
        }
        .padding(.vertical, 4)
    }

    private func figure(_ value: String, _ caption: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color)
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(caption).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func subjectRow(_ s: SubjectStats) -> some View {
        let color = Self.color(for: s)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.subject).font(.body.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(s.answered == 0 ? "Not tried" : "\(Int((s.accuracy * 100).rounded()))%")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
            }
            AccuracyBar(fraction: s.answered == 0 ? 0 : s.accuracy, color: color)
            Text("\(s.answered) answered \u{00B7} \(s.questions) question\(s.questions == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Green from three in four, amber from half, red below; grey for a
    /// subject not tried yet, which is not the same thing as a bad one.
    private static func color(for s: SubjectStats) -> Color {
        guard s.answered > 0 else { return .secondary }
        switch s.accuracy {
        case 0.75...: return .green
        case 0.5..<0.75: return .orange
        default: return .red
        }
    }
}

/// A thin bar filled to a fraction, in a colour of its own - ThinProgress
/// always takes the screen's tint, and here the colour is the verdict.
private struct AccuracyBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
