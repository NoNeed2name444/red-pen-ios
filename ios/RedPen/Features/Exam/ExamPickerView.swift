import SwiftUI

/// Choosing the exam: one primary, optionally a second, and the date. Names
/// only - no flags or logos - grouped by where the exam is sat, each with a
/// line on its format so two similar names are told apart.
struct ExamPickerView: View {
    /// Called when the choice is saved (or skipped from onboarding).
    var onDone: () -> Void = {}
    /// Onboarding shows Skip instead of Cancel.
    var isOnboarding: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var primary: String = ExamChoice.current?.id ?? ""
    @State private var secondary: String = ExamChoice.currentSecondary?.id ?? ""
    @State private var choosingSecond = false
    @AppStorage(ExamTrack.dateKey) private var examDate: Double = 0

    var body: some View {
        List {
            if isOnboarding {
                Section {
                    Text("Questions, study plan, coverage map and mock papers will follow its format and blueprint. You can change it any time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            chosenSection
            ForEach(ExamCatalog.byRegion) { group in
                Section(group.region.title) {
                    ForEach(group.exams) { exam in
                        row(exam)
                    }
                }
            }
            Section {
                Text("Formats and blueprints come from each exam's published outline; where an exam publishes no percentages the weights are our estimate and are marked approximate. Always check the official candidate guide.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle(isOnboarding ? "Which exam are you preparing for?" : "Your exam")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isOnboarding ? "Skip" : "Cancel") { skip() }
                    .accessibilityIdentifier(isOnboarding ? "examOnboardingSkip" : "examPickerCancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(primary.isEmpty && !isOnboarding)
                    .accessibilityIdentifier("examPickerSave")
            }
        }
    }

    @ViewBuilder
    private var chosenSection: some View {
        if let exam = ExamCatalog.exam(primary) {
            Section {
                Toggle("Also preparing for a second exam", isOn: $choosingSecond.animation())
                if choosingSecond {
                    Picker("Second exam", selection: $secondary) {
                        Text("None").tag("")
                        ForEach(ExamCatalog.all.filter { $0.id != exam.id }) { other in
                            Text(other.name).tag(other.id)
                        }
                    }
                }
                DatePicker("Exam date", selection: dateBinding, in: Date()..., displayedComponents: .date)
                if examDate > 0 {
                    Button("Clear the date", role: .destructive) { examDate = 0 }
                }
            } header: {
                Text(exam.name)
            } footer: {
                Text("A second exam counts for 30% of what to study next and of a generated set's topics.")
            }
            .onAppear { choosingSecond = !secondary.isEmpty }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(get: {
            examDate > 0 ? Date(timeIntervalSince1970: examDate) : Date().addingTimeInterval(90 * 86_400)
        }, set: { examDate = $0.timeIntervalSince1970 })
    }

    private func row(_ exam: TargetExam) -> some View {
        let chosen: Bool = exam.id == primary
        let detail: String = ExamPickerView.detail(exam)
        return Button {
            withAnimation(.snappy) {
                primary = exam.id
                if secondary == exam.id { secondary = "" }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exam.name).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("examPick-\(exam.id)")
    }

    /// "200 questions · 4 options · 3.5 h".
    static func detail(_ exam: TargetExam) -> String {
        let q: Int = exam.sections.reduce(0) { $0 + $1.questions }
        let m: Int = exam.sections.reduce(0) { $0 + $1.minutes }
        var parts: [String] = ["\(q) questions", "\(exam.options) options", MockPaperView.hours(m)]
        if !exam.formatConfirmed { parts.append("format unconfirmed") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func save() {
        let chosen: TargetExam? = ExamCatalog.exam(primary)
        let second: TargetExam? = choosingSecond ? ExamCatalog.exam(secondary) : nil
        if chosen != nil || !isOnboarding {
            ExamChoice.choose(primary: chosen, secondary: second)
        } else {
            ExamChoice.markAsked()
        }
        onDone()
        dismiss()
    }

    private func skip() {
        if isOnboarding { ExamChoice.markAsked() }
        onDone()
        dismiss()
    }
}

/// The onboarding question, once, after the terms: "Which exam are you
/// preparing for?" - skippable.
struct ExamOnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ExamPickerView(onDone: onDone, isOnboarding: true)
        }
    }
}

/// Whether the onboarding question has been answered, observed so the root
/// view moves on the moment it is.
@MainActor
final class ExamQuestionStore: ObservableObject {
    @Published private(set) var asked: Bool = ExamChoice.hasAsked()

    func done() {
        ExamChoice.markAsked()
        asked = true
    }
}

/// "Step 2 CK" on a set written for that exam.
struct ExamBadge: View {
    let examId: String?

    var body: some View {
        if let exam = ExamCatalog.exam(examId) {
            Text(exam.shortName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
                .fixedSize()
                .accessibilityLabel("Written for \(exam.name)")
        }
    }
}

extension NewSetPreset {
    /// New set, ready to write MCQs on one area of the chosen exam's blueprint.
    init(blueprintArea title: String, exam: TargetExam) {
        kind = .mcq
        name = "\(exam.shortName): \(title)"
        subject = title
        notes = "Write \(exam.name) questions on \(title), in its format and at its level."
    }
}
