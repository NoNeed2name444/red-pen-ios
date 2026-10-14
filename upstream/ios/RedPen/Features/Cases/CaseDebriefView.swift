import SwiftUI

/// The debrief, as a discharge summary: missed red flags first in Resus Red,
/// then the diagnosis (right or wrong) with what separates it from the
/// runner-up, the key findings found, the turning point against when the
/// ladder moved, the time and the low-yield steps, and three teaching points
/// with their source. The score is shown with its parts, never as a rank.
///
/// Three things to do with it: cards from what was missed, a note in the
/// Ideas map, and another patient like this one.
struct CaseDebriefView: View {
    let file: CaseFile
    let setID: UUID
    let run: CaseRun
    let again: () -> Void

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var llm: LocalLLMService
    @EnvironmentObject private var gemma: GemmaModel
    @ObservedObject private var saver = IdeaSaver.shared

    @State private var cardsNote: String?
    @State private var anotherNote: String?
    @State private var writing = false
    @State private var writingTask: Task<Void, Never>?
    @State private var ideaHost = UUID()
    @State private var owner = UUID()

    private var debrief: CaseDebrief { CaseDebrief(file: file, run: run) }

    private var set: StudySet? { store.library.first { $0.id == setID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                scoreCard
                if !debrief.missedRedFlags.isEmpty { redFlagsCard }
                diagnosisCard
                findingsCard
                turningCard
                timeCard
                teachingCard
                actionsCard
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .wardScreen()
        .saveToIdeasHost(ideaHost)
        .onDisappear { GenerationCenter.shared.cancel(startedBy: owner) }
    }

    // MARK: the summary

    private var header: some View {
        HStack(spacing: 12) {
            CaseAvatar(initials: file.patient.initials)
            VStack(alignment: .leading, spacing: 2) {
                Text("Discharge summary")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("\(file.patient.ageSex) \u{00B7} \(file.setting.label) \u{00B7} \u{201C}\(file.complaint)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(CaseInk.biro)
                    .lineLimit(3)
            }
        }
    }

    private var scoreCard: some View {
        let score: CaseScore = debrief.score
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                CaseLabel("Score")
                Spacer()
                Text("\(score.total) / 100")
                    .font(.system(.title2, design: .monospaced).weight(.bold))
            }
            ForEach(Array(score.parts.enumerated()), id: \.offset) { _, part in
                HStack {
                    Text(part.label)
                    Spacer()
                    Text("\(part.points) / \(part.of)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(part.points == part.of ? CaseInk.discharge : Color.primary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(part.label): \(part.points) of \(part.of)")
            }
            if score.capped {
                Label("Capped at 60: a must-not-miss red flag was missed.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CaseInk.resus)
            }
        }
        .caseCard()
        .accessibilityElement(children: .contain)
    }

    private var redFlagsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaseLabel("Missed red flags")
            ForEach(debrief.missedRedFlags) { step in
                VStack(alignment: .leading, spacing: 4) {
                    Text((step.mustNotMiss ? "Must not miss \u{00B7} " : "") + step.label)
                        .font(.subheadline.weight(.bold))
                    Text(step.finding)
                    if !step.note.isEmpty {
                        Text(step.note).font(.footnote)
                    }
                }
                .foregroundStyle(CaseInk.resus)
                .accessibilityElement(children: .combine)
            }
        }
        .caseCard()
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CaseInk.resus, lineWidth: 2))
    }

    private var diagnosisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaseLabel("Diagnosis")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: debrief.diagnosisRight ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(debrief.diagnosisRight ? CaseInk.discharge : CaseInk.resus)
                    .accessibilityHidden(true)
                Text(file.diagnosis.name)
                    .font(.title3.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Diagnosis: \(file.diagnosis.name). " + (debrief.diagnosisRight ? "You were right." : "You said \(debrief.chosenDiagnosis)."))
            if !debrief.diagnosisRight {
                Text("You said: \(debrief.chosenDiagnosis)")
                    .font(.subheadline)
                    .foregroundStyle(CaseInk.biro)
            }
            if let other = file.runnerUp, !debrief.separating.isEmpty {
                Text("What tells it from \(other.name):")
                    .font(.subheadline.weight(.semibold))
                ForEach(debrief.separating, id: \.step.id) { item in
                    findingRow(item)
                }
            }
            WardEtch()
            CaseLabel("Next step")
            if let chosen = debrief.chosenNextStep, !debrief.nextStepRight {
                WardOptionRow(letter: AccuracyItem.letter(run.decision?.nextStep ?? 0), text: chosen, mark: .wrong)
                    .accessibilityLabel("Your choice: \(chosen), wrong")
            }
            WardOptionRow(letter: AccuracyItem.letter(file.nextStep.key), text: debrief.rightNextStep, mark: .right)
                .accessibilityLabel("Right next step: \(debrief.rightNextStep)")
            if !file.nextStep.why.isEmpty {
                Text(file.nextStep.why)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = run.decision?.reason, !reason.isEmpty {
                Text("Your reason: \(reason)")
                    .font(.footnote)
                    .foregroundStyle(CaseInk.biro)
            }
        }
        .caseCard()
    }

    private var findingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CaseLabel("Key findings")
                Spacer()
                Text("\(debrief.keyFound) of \(debrief.keyFindings.count) found")
                    .font(.system(.subheadline, design: .monospaced))
            }
            .accessibilityElement(children: .combine)
            ForEach(debrief.keyFindings, id: \.step.id) { item in
                findingRow(item)
            }
        }
        .caseCard()
    }

    private func findingRow(_ item: CaseDebrief.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.found ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.found ? CaseInk.discharge : CaseInk.biro)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.step.label).font(.subheadline.weight(.semibold))
                Text(item.step.finding).font(.subheadline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.step.label): \(item.step.finding). " + (item.found ? "Found." : "Not found."))
    }

    private var turningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CaseLabel("Turning point")
            Text(debrief.turningSaid)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if !run.ladders.isEmpty {
                ladderTrail
            }
        }
        .caseCard()
    }

    /// The lead of the ladder after each step, in order.
    private var ladderTrail: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(run.taken.enumerated()), id: \.offset) { index, taken in
                let lead: String = run.ladders.indices.contains(index) ? (run.ladders[index].first ?? "\u{2014}") : "\u{2014}"
                let right: Bool = file.isDiagnosis(lead)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(taken.at) min")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(CaseInk.biro)
                        .frame(minWidth: 48, alignment: .leading)
                    Text(file.step(taken.stepID)?.label ?? "")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(lead)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(right ? CaseInk.discharge : Color.primary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("After \(file.step(taken.stepID)?.label ?? "a step"), your leading diagnosis was \(lead)")
            }
        }
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CaseLabel("Time")
                Spacer()
                CaseClockPill(used: debrief.minutesUsed, budget: file.budgetMinutes)
            }
            if debrief.lowYield.isEmpty {
                Text("No low-yield steps.")
                    .font(.subheadline)
                    .foregroundStyle(CaseInk.biro)
            } else {
                Text("Low-yield here:")
                    .font(.subheadline.weight(.semibold))
                ForEach(debrief.lowYield) { step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(step.label) \u{00B7} \(step.minutes) min").font(.subheadline.weight(.semibold))
                        if !step.note.isEmpty { Text(step.note).font(.subheadline) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .caseCard()
    }

    private var teachingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CaseLabel("Teaching")
            ForEach(Array(file.teaching.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(CaseInk.theatre)
                        .accessibilityHidden(true)
                    Text(point)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            let cited: String = file.source.cited
            if !cited.isEmpty {
                Text("Source: \(cited)")
                    .font(.footnote)
                    .foregroundStyle(CaseInk.biro)
            }
        }
        .caseCard()
    }

    // MARK: what to do with it

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { makeCards() } label: {
                Label("Make cards from what I missed", systemImage: "rectangle.stack.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.wardSecondary)
            .disabled(debrief.missed.isEmpty)
            .accessibilityHint(debrief.missed.isEmpty ? "Nothing was missed" : "One card for each missed key finding or red flag, into your review")
            if let cardsNote { note(cardsNote) }

            Button { addIdea() } label: {
                Label("Add to the Ideas map", systemImage: "lightbulb")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.wardSecondary)
            .disabled(!saver.isReady)

            CaseLabel("Another patient like this")
            Button { another(sameDiagnosis: true) } label: {
                HStack {
                    if writing { ProgressView().controlSize(.small) }
                    Label("Same diagnosis, a new presentation", systemImage: "person.badge.plus")
                }
            }
            .buttonStyle(.wardSecondary)
            .disabled(writing)
            .accessibilityHint("Writes another patient with \(file.diagnosis.name), presented differently, into this set")
            if let other = file.runnerUp {
                Button { another(sameDiagnosis: false) } label: {
                    Label("The runner-up: \(other.name)", systemImage: "person.2")
                }
                .buttonStyle(.wardSecondary)
                .disabled(writing)
                .accessibilityHint("Writes a patient whose diagnosis is \(other.name) into this set")
            }
            if let anotherNote { note(anotherNote) }

            Button { again() } label: {
                Label("See this patient again", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.wardCompact)
        }
        .caseCard()
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(CaseInk.biro)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One basic card per missed key finding or red flag, into a deck of
    /// their own so they come up in review with the rest.
    private func makeCards() {
        let made: [AnkiCard] = debrief.cards
        guard !made.isEmpty else { return }
        let deckName: String = "Missed in cases"
        if var deck = store.library.first(where: { $0.kind == .anki && $0.name == deckName }) {
            let fronts: Set<String> = Set(deck.cards.map(\.front))
            let fresh: [AnkiCard] = made.filter { !fronts.contains($0.front) }
            deck.cards += fresh
            store.update(deck)
            cardsNote = fresh.isEmpty ? "Those cards are in \u{201C}\(deckName)\u{201D} already."
                                      : "\(fresh.count) card\(fresh.count == 1 ? "" : "s") added to \u{201C}\(deckName)\u{201D}."
        } else {
            var deck = StudySet(name: deckName, subject: set?.subject ?? "General", kind: .anki)
            deck.cards = made
            store.addSet(deck)
            cardsNote = "\(made.count) card\(made.count == 1 ? "" : "s") in a new deck, \u{201C}\(deckName)\u{201D}."
        }
        UIAccessibility.post(notification: .announcement, argument: cardsNote ?? "")
    }

    private func addIdea() {
        let source = NoteSource(kind: .patientCase, setID: setID, itemID: file.id, setName: set?.name ?? "")
        let clip = IdeaClip(title: debrief.ideaTitle, text: debrief.ideaText, source: source,
                            subject: set?.subject ?? file.specialty)
        saver.save(clip, host: ideaHost)
    }

    /// A new patient: the same diagnosis presented differently, or the
    /// runner-up's own case. Written from the set's lecture (or, with none,
    /// from this case's teaching), checked like any other, and added to the set.
    private func another(sameDiagnosis: Bool) {
        anotherNote = nil
        guard let current = set else { return }
        if let busy = GenerationCenter.shared.busy { anotherNote = busy; return }
        guard let writer = CaseMaker.writer(llm: llm, gemma: gemma) else {
            anotherNote = CaseMaker.noWriter(gemma: gemma)
            return
        }
        let pages: [(number: Int, text: String)] = current.sources.flatMap { doc in doc.pages.map { (number: $0.number, text: $0.text) } }
        let source: String = pages.isEmpty ? file.assertedText : CaseMaker.sourceText(pages)
        let lecture: String = current.sources.first?.name ?? file.source.lecture
        var brief = CaseWriting.Brief()
        if sameDiagnosis {
            brief.diagnosis = file.diagnosis.name
            brief.unlike = "\(file.patient.ageSex), \(file.setting.rawValue), \u{201C}\(file.complaint)\u{201D}"
        } else {
            brief.diagnosis = file.runnerUp?.name
        }
        writing = true
        guard let job = GenerationCenter.shared.begin("Writing another patient", total: 1, owner: owner, onCancel: {
            writingTask?.cancel()
            writingTask = nil
            writing = false
        }) else {
            writing = false
            anotherNote = GenerationCenter.shared.busy
            return
        }
        let subject: String = current.subject
        writingTask = Task {
            do {
                let made = try await CaseMaker.write(count: 1, source: source, lecture: lecture, subject: subject,
                                                     brief: brief, using: writer) { done, total in
                    GenerationCenter.shared.update(job, done: done, total: total)
                }
                try Task.checkCancellation()
                await MainActor.run {
                    if var latest = store.library.first(where: { $0.id == setID }) {
                        latest.caseFiles += made.cases
                        store.update(latest)
                    }
                    GenerationCenter.shared.end(job, finished: "Another patient is ready")
                    writing = false
                    anotherNote = "A new patient is waiting in this set\u{2019}s list."
                }
            } catch {
                await MainActor.run {
                    GenerationCenter.shared.end(job)
                    writing = false
                    if !(error is CancellationError) {
                        anotherNote = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
        }
    }
}
