import SwiftUI

/// The popup a chip opens: the question, answered and explained in the way
/// its type needs, with its accuracy badge and a button to keep it.
///
/// - Multiple choice: every option, the right one highlighted, with why it is
///   right and why each other one is wrong.
/// - True or false: the verdict, why, and the statement put right.
/// - Fill in the blank: the sentence filled in, the answer marked.
/// - Calculation: every step with its units, then the result.
/// - Clinical case: the most likely diagnosis, the differential in tiers
///   (HowToReachCard), and the next step.
/// - OSCE: the checklist, in order, and where marks are lost.
struct LensAnswerSheet: View {
    let question: DetectedQuestion
    @ObservedObject var model: LensModel
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var notes: NoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var showModels = false

    private var tint: Color { LensStyle.tint(question.type) }

    private var answer: LensAnswer? {
        if case .done(let a) = model.state(for: question) { return a }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    questionCard
                    stateContent
                }
                .padding(16)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(LibraryBackdrop())
            .navigationTitle(question.type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
        .tint(tint)
        .environment(\.modeTint, tint)
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onAppear { model.answer(question) }
        .sheet(isPresented: $adding) {
            if let answer {
                LensAddSheet(question: question, answer: answer)
                    .environmentObject(store)
                    .environmentObject(notes)
            }
        }
        .sheet(isPresented: $showModels) {
            ModelSettingsView()
                .environmentObject(LocalLLMService.shared)
        }
    }

    // MARK: header and question

    private var header: some View {
        HStack(spacing: 8) {
            Label(question.type.chipLabel, systemImage: question.type.symbol)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .liquidGlassChip(tint: tint)
            if let number = question.number {
                Text("Question " + number).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question.stem)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if question.type.hasOptions && answer == nil {
                ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                    LensOptionRow(letter: LensHash.letter(pair.offset), text: pair.element.text,
                                  note: "", state: .plain)
                }
            }
        }
        .contentCard()
    }

    // MARK: the answer

    @ViewBuilder
    private var stateContent: some View {
        switch model.state(for: question) {
        case .done(let a):
            LensAnswerBody(question: question, answer: a, tint: tint)
            LensAccuracyRow(question: question, answer: a)
            if !a.answeredBy.isEmpty {
                Label("Answered by " + a.answeredBy + ". Check anything that matters against your notes.",
                      systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let why):
            failure(why)
        case .loading, .none:
            LensShimmer()
                .accessibilityLabel("Answering")
        }
    }

    private func failure(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(why, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Try again") { model.answer(question, again: true) }
                    .buttonStyle(.glass)
                if why == LensModel.noModel {
                    Button("AI models") { showModels = true }
                        .buttonStyle(.glass)
                }
            }
        }
        .contentCard()
    }

    // MARK: actions

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                adding = true
            } label: {
                Label("Add to\u{2026}", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(answer == nil)
            .accessibilityHint("Keeps this question in Questions, Cards, Cases, OSCE, Ideas or Audio")
            Button {
                model.answer(question, again: true)
            } label: {
                Label("Ask again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .disabled(model.state(for: question) == .loading)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - The answer, by type

struct LensAnswerBody: View {
    let question: DetectedQuestion
    let answer: LensAnswer
    let tint: Color

    var body: some View {
        switch question.type {
        case .mcq, .bestAnswer:
            choice
        case .trueFalse:
            truth
        case .cloze:
            cloze
        case .calculation:
            calculation
        case .clinicalCase:
            clinicalCase
        case .osce:
            osce
        case .shortAnswer, .imageLabel:
            short
        }
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                let i: Int = pair.offset
                let right: Bool = i == answer.correctIndex
                let note: String = answer.optionNotes.indices.contains(i) ? answer.optionNotes[i] : ""
                LensOptionRow(letter: LensHash.letter(i), text: pair.element.text, note: note,
                              state: right ? .right : .wrong)
            }
            explanation(title: "Why " + LensHash.letter(answer.correctIndex ?? 0) + " is right")
            keyPoints(title: "Remember")
        }
    }

    private var truth: some View {
        let isTrue: Bool = answer.verdict ?? false
        let colour: Color = isTrue ? .green : .red
        return VStack(alignment: .leading, spacing: 12) {
            Label(isTrue ? "True" : "False", systemImage: isTrue ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(colour)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(colour.opacity(0.14), in: Capsule())
            if !answer.correction.isEmpty {
                section("Put right") { Text(answer.correction) }
            }
            explanation(title: "Why")
            keyPoints(title: "Remember")
        }
    }

    private var cloze: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Filled in") {
                Text(highlighted(answer.filled.isEmpty ? answer.answer : answer.filled, mark: answer.answer))
            }
            explanation(title: "Why")
        }
    }

    private var calculation: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !answer.steps.isEmpty {
                section("Working") { numbered(answer.steps) }
            }
            resultBox("Answer", answer.answer)
            explanation(title: "Notes")
        }
    }

    private var clinicalCase: some View {
        VStack(alignment: .leading, spacing: 12) {
            resultBox("Most likely diagnosis", answer.diagnosis)
            if !answer.nextStep.isEmpty {
                section("Next step") { Text(answer.nextStep) }
            }
            if let differential = answer.differential {
                HowToReachCard(differential: differential)
            }
            explanation(title: "Reasoning")
        }
    }

    private var osce: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !answer.answer.isEmpty {
                Text(answer.answer).font(.headline)
            }
            section("Checklist, in order") { numbered(answer.steps) }
            explanation(title: "What examiners look for")
            keyPoints(title: "Where marks are lost")
        }
    }

    private var short: some View {
        VStack(alignment: .leading, spacing: 12) {
            resultBox("Answer", answer.answer)
            if question.type == .imageLabel {
                Label("Answered from the question\u{2019}s words only; the picture itself is not sent.",
                      systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            explanation(title: "Why")
            keyPoints(title: "What a marker looks for")
        }
    }

    // MARK: pieces

    @ViewBuilder
    private func explanation(title: String) -> some View {
        if !answer.explanation.isEmpty {
            section(title) { Text(answer.explanation) }
        }
    }

    @ViewBuilder
    private func keyPoints(title: String) -> some View {
        if !answer.keyPoints.isEmpty {
            section(title) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(answer.keyPoints.enumerated()), id: \.offset) { pair in
                        Label(pair.element, systemImage: "circle.fill")
                            .labelStyle(LensBulletStyle())
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            content()
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .contentCard()
    }

    private func resultBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.green.opacity(0.55), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    private func numbered(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(pair.offset + 1)")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(tint)
                        .frame(minWidth: 22, alignment: .trailing)
                    Text(pair.element)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// `text` with `mark` in bold and the screen's colour.
    private func highlighted(_ text: String, mark: String) -> AttributedString {
        var out = AttributedString(text)
        guard !mark.isEmpty, let range = out.range(of: mark, options: .caseInsensitive) else { return out }
        out[range].foregroundColor = tint
        out[range].inlinePresentationIntent = .stronglyEmphasized
        return out
    }
}

/// One option: its letter, its words, and - once answered - whether it is
/// the answer and why.
struct LensOptionRow: View {
    enum Mark { case plain, right, wrong }

    let letter: String
    let text: String
    let note: String
    let state: Mark

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let right: Bool = state == .right
        let colour: Color = right ? .green : .secondary
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(letter)
                    .font(.body.weight(.bold).monospaced())
                    .foregroundStyle(right ? Color.white : Color.primary)
                    .frame(width: 32, height: 32)
                    .background(right ? Color.green : Color.secondary.opacity(0.18), in: Circle())
                    .accessibilityHidden(true)
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if right {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if state == .wrong {
                    Image(systemName: "xmark").foregroundStyle(.secondary).font(.caption.weight(.bold))
                }
            }
            if !note.isEmpty {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(right ? Color.green.opacity(0.14) : Color.clear, in: shape)
        .overlay(shape.strokeBorder(colour.opacity(right ? 0.8 : 0.25), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var parts: [String] = ["Option " + letter + ": " + text]
        if state == .right { parts.append("the answer") }
        if state == .wrong { parts.append("not the answer") }
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: ". ")
    }
}

/// A small dot before a key point.
struct LensBulletStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.scaledFont(5, relativeTo: .body).foregroundStyle(.secondary)
            configuration.title
        }
    }
}

/// Grey bars that shimmer while the answer is written; still under Reduce
/// Motion.
struct LensShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bar(0.9)
            bar(0.75)
            bar(0.95)
            bar(0.6)
            Text("Answering\u{2026}").font(.caption).foregroundStyle(.secondary)
        }
        .contentCard()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }

    private func bar(_ width: CGFloat) -> some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width * width
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.18))
                .overlay(
                    LinearGradient(colors: [.clear, Color.white.opacity(0.45), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * 0.4)
                        .offset(x: phase * w)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: w)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Accuracy

/// The capture's accuracy badge, from the app's accuracy engine: the same
/// grade, the same "why" sheet with its sources, and Check now. The item is
/// built exactly as the saved version will be, so a check made here counts
/// for it once it is kept.
struct LensAccuracyRow: View {
    let question: DetectedQuestion
    let answer: LensAnswer
    @EnvironmentObject private var store: Store
    @ObservedObject private var accuracy = AccuracyStore.shared
    @State private var showing = false
    @State private var message: String?
    @State private var working = false

    var body: some View {
        if let item = LensAccuracy.item(question, answer) {
            let assessment: AccuracyAssessment = accuracy.assessment(of: item)
            let evidence: [AccuracyEvidence] = assessment.record?.evidence ?? []
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button { showing = true } label: {
                        AccuracyBadgeFace(grade: assessment.grade, checking: accuracy.isChecking(item) || working)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accuracy: " + assessment.grade.title)
                    .accessibilityHint("Shows why, the sources, and Report an error")
                    Spacer(minLength: 0)
                    if assessment.grade == .unchecked && !working {
                        Button("Check now") { check(item) }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(evidence.prefix(4), id: \.id) { ref in
                    evidenceLink(ref)
                }
            }
            .contentCard()
            .sheet(isPresented: $showing) {
                AccuracyWhySheet(item: item).environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private func evidenceLink(_ ref: AccuracyEvidence) -> some View {
        let label: String = (ref.source.isEmpty ? "" : ref.source + ": ") + (ref.title.isEmpty ? ref.url : ref.title)
        if let url = URL(string: ref.url), !ref.url.isEmpty {
            Link(destination: url) {
                Label(label, systemImage: "doc.text.magnifyingglass").font(.caption)
            }
        } else {
            Label(label, systemImage: "doc.text").font(.caption)
        }
    }

    private func check(_ item: AccuracyItem) {
        working = true
        message = nil
        Task {
            message = await accuracy.checkNow(item)
            working = false
        }
    }
}

enum LensAccuracy {
    /// The item the accuracy engine checks for a capture, shaped as the
    /// mode it would most likely be kept in.
    @MainActor static func item(_ q: DetectedQuestion, _ a: LensAnswer) -> AccuracyItem? {
        let id: String = "lens-" + LensHash.answerKey(q)
        var item: AccuracyItem? = nil
        switch q.type {
        case .mcq, .bestAnswer, .trueFalse:
            item = LensConversion.question(q, a).map { AccuracyItem.mcq($0) }
        case .osce:
            item = LensConversion.station(q, a).map { AccuracyItem.osce($0) }
        case .clinicalCase:
            item = LensConversion.caseCard(q, a, topic: "General").map { AccuracyItem.qa($0) }
        default:
            item = LensConversion.cards(q, a).first.flatMap { AccuracyItem.card($0) }
        }
        item?.id = id
        return item
    }
}
