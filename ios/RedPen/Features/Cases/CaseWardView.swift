import SwiftUI
import UIKit

/// One patient, from arrival to the decision, and then the debrief.
///
/// Arrival: the clerking note (the history, already taken and written - the
/// patient is never questioned here), the triage strip (age, sex, where they
/// are seen), the arrival observations, the complaint in the patient's words
/// and the time allowed.
/// Work-up: Examine and Test, each action a chip with its minutes;
/// taking one spends them and adds its finding to the clinical note under the
/// strip, newest first. The differential ladder is open at any time - a
/// sheet on iPhone, a sidebar on iPad - and the run is kept after every
/// change, so leaving and coming back carries on where it was.
struct CaseWardView: View {
    let file: CaseFile
    let setID: UUID

    @ObservedObject private var runs = CaseRunStore.shared
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var run: CaseRun
    @State private var arriving: Bool
    @State private var group: CaseStep.Group = .examine
    @State private var showingClerking = false
    @State private var showingLadder = false
    @State private var deciding = false

    init(file: CaseFile, setID: UUID) {
        self.file = file
        self.setID = setID
        let saved: CaseRun? = CaseRunStore.shared.run(for: file)
        _run = State(initialValue: saved ?? CaseRun(caseID: file.id))
        _arriving = State(initialValue: saved == nil || (saved?.taken.isEmpty ?? true))
    }

    private var wide: Bool { widthClass == .regular }

    var body: some View {
        Group {
            if run.isFinished {
                CaseDebriefView(file: file, setID: setID, run: run, again: startAgain)
            } else {
                ward
            }
        }
        .navigationTitle(file.patient.ageSex.isEmpty ? "Patient" : file.patient.ageSex)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: run) { _, now in runs.save(now) }
    }

    // MARK: the ward

    private var ward: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    triage
                    if arriving {
                        clerkingCard
                        arrivalNote
                    } else {
                        clerkingFolded
                        actions
                        clinicalNote
                    }
                }
                .padding(16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            if wide && !arriving {
                WardEtch(vertical: true)
                CaseLadderPanel(file: file, run: $run)
                    .frame(width: 340)
            }
        }
        .wardScreen()
        .studyBar(folds: true) { bottomBar }
        .sheet(isPresented: $showingLadder) {
            NavigationStack {
                CaseLadderPanel(file: file, run: $run)
                    .navigationTitle("Differential")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingLadder = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $deciding) {
            CaseDecisionView(file: file, leading: run.ladder.first ?? "") { decision in
                deciding = false
                decide(decision)
            }
        }
    }

    /// Who the patient is, their observations, what they say and the clock.
    private var triage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                CaseAvatar(initials: file.patient.initials)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if file.patient.age > 0 { WardChip(text: "\(file.patient.age) y", tone: .grey) }
                        if !file.patient.sexLetter.isEmpty {
                            WardChip(text: file.patient.isFemale ? "Female" : "Male", tone: .grey)
                        }
                        WardChip(text: file.setting.label, tone: .blue)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(file.patient.spoken), seen in \(file.setting.label)")
                    if !file.patient.about.isEmpty {
                        Text(file.patient.about)
                            .font(.footnote)
                            .foregroundStyle(CaseInk.biro)
                    }
                }
                Spacer(minLength: 0)
                CaseClockPill(used: run.minutesUsed, budget: file.budgetMinutes)
            }
            if !file.arrival.isEmpty {
                CaseLabel("On arrival")
                CaseVitalsGrid(obs: file.arrival)
            }
            Text("\u{201C}" + file.complaint + "\u{201D}")
                .font(arriving ? .title3 : .body)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("The patient says: " + file.complaint)
        }
        .caseCard()
    }

    /// The history as it was written on admission.
    private var clerkingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaseLabel("Clerking note")
            clerkingParts
        }
        .caseCard()
    }

    /// The same note during the work-up, folded away until wanted.
    private var clerkingFolded: some View {
        DisclosureGroup(isExpanded: $showingClerking) {
            clerkingParts
                .padding(.top, 8)
        } label: {
            CaseLabel("Clerking note")
                .frame(minHeight: 44, alignment: .leading)
        }
        .caseCard(padding: 12)
    }

    private var clerkingParts: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(file.clerking.parts.enumerated()), id: \.offset) { _, part in
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CaseInk.biro)
                    Text(part.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var arrivalNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            CaseLabel("Your shift")
            Text("You have \(file.budgetMinutes) minutes. Every examination and test costs time. Keep a ranked differential as you go, then decide the diagnosis and the next step.")
                .font(.subheadline)
                .foregroundStyle(Color.wardInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .caseCard()
    }

    // MARK: the work-up

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            WardSegmented(selection: $group, options: CaseStep.Group.allCases) { g in
                Text(g.label)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Action")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(file.steps(in: group)) { step in
                    actionChip(step)
                }
            }
        }
        .caseCard()
    }

    private func actionChip(_ step: CaseStep) -> some View {
        let done: Bool = run.hasTaken(step.id)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button { take(step) } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(done ? CaseInk.discharge : CaseInk.theatre)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(done ? CaseInk.biro : Color.wardInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(step.minutes) min")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(CaseInk.biro)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            // raised to be tapped; once taken, pressed into the card
            .wardRelief(in: shape, lift: .low, pressed: done)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(done)
        .accessibilityLabel("\(step.label), \(step.minutes) minute\(step.minutes == 1 ? "" : "s")")
        .accessibilityValue(done ? "Done" : "")
        .accessibilityHint(done ? "" : "Spends the minutes and adds the finding to the note")
    }

    /// What has been found, newest first.
    private var clinicalNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            CaseLabel("Clinical note")
            if run.taken.isEmpty {
                Text("Findings appear here as you ask, examine and test.")
                    .font(.subheadline)
                    .foregroundStyle(CaseInk.biro)
            }
            ForEach(Array(run.taken.reversed()), id: \.stepID) { taken in
                if let step = file.step(taken.stepID) {
                    noteEntry(step, at: taken.at)
                }
            }
        }
        .caseCard()
    }

    private func noteEntry(_ step: CaseStep, at: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.group.label + " \u{00B7} " + step.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CaseInk.biro)
                Spacer(minLength: 8)
                Text("\(at) min")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(CaseInk.biro)
            }
            Text(step.finding)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if !step.results.isEmpty {
                CaseResultsTable(results: step.results)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: the bar at the bottom

    /// The buttons in the study bar: the soft slab raised under the thumb,
    /// as on every study screen.
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if arriving {
                Button { begin() } label: {
                    Label("See the patient", systemImage: "stethoscope")
                }
                .buttonStyle(.wardPrimary)
            } else {
                if !wide {
                    Button { showingLadder = true } label: {
                        Label(ladderTitle, systemImage: "list.number")
                    }
                    .buttonStyle(.wardSecondary)
                    .accessibilityHint("Your ranked working diagnoses")
                }
                Button { deciding = true } label: {
                    Label("Decide", systemImage: "checkmark.seal")
                }
                .buttonStyle(.wardPrimary)
                .accessibilityHint("Confirm the diagnosis and choose the next step")
            }
        }
    }

    private var ladderTitle: String {
        run.ladder.isEmpty ? "Differential" : "Differential (\(run.ladder.count))"
    }

    // MARK: acting

    private func begin() {
        withAnimation(reduceMotion ? nil : .snappy) { arriving = false }
    }

    private func take(_ step: CaseStep) {
        var next: CaseRun = run
        guard next.take(step.id, in: file) else { return }
        withAnimation(reduceMotion ? nil : .snappy) { run = next }
        // the finding, read out, since it lands below the chips
        UIAccessibility.post(notification: .announcement, argument: step.finding)
    }

    private func decide(_ decision: CaseRun.Decision) {
        var next: CaseRun = run
        next.decide(decision, in: file)
        withAnimation(reduceMotion ? nil : .snappy) { run = next }
    }

    private func startAgain() {
        runs.reset(file)
        withAnimation(reduceMotion ? nil : .snappy) {
            run = CaseRun(caseID: file.id)
            arriving = true
            group = .examine
        }
    }
}

/// The differential ladder: up to three working diagnoses, the leading one
/// first, picked from the case's list or typed. Nothing here asks the
/// student to keep it up to date; the run copies it after every step.
struct CaseLadderPanel: View {
    let file: CaseFile
    @Binding var run: CaseRun
    @State private var typed = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CaseLabel("Your ladder")
                if run.ladder.isEmpty {
                    Text("Up to three working diagnoses, the most likely first. Change them whenever you like.")
                        .font(.subheadline)
                        .foregroundStyle(CaseInk.biro)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(run.ladder.enumerated()), id: \.element) { index, name in
                    rung(index, name)
                }
                CaseLabel("Add a diagnosis")
                HStack(spacing: 8) {
                    TextField("Type a diagnosis", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit(addTyped)
                    Button("Add", action: addTyped)
                        .buttonStyle(.wardCompact)
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if run.ladder.count >= CaseRun.rungs {
                    Text("The ladder is full: a new diagnosis takes the bottom rung.")
                        .font(.caption)
                        .foregroundStyle(CaseInk.biro)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(pickable, id: \.self) { name in
                        Button { add(name) } label: {
                            Text(name)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 10)
                                .wardRaised(in: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous), lift: .low)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Adds it to your ladder")
                    }
                }
            }
            .padding(16)
        }
        .wardScreen()
    }

    /// The case's list, less what is on the ladder already.
    private var pickable: [String] {
        file.candidates.filter { name in !run.ladder.contains { CaseNames.same($0, name) } }
    }

    private func rung(_ index: Int, _ name: String) -> some View {
        let leading: Bool = index == 0
        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(leading ? Color.wardPrimaryInk : Color.wardInkSecondary)
                .frame(width: 32, height: 32)
                .wardInset(in: Circle())
                .accessibilityHidden(true)
            Text(name)
                .font(.body.weight(leading ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Rung \(index + 1) of \(run.ladder.count): \(name)" + (leading ? ", leading" : ""))
            iconButton("chevron.up", "Move up", enabled: index > 0) { change { $0.move(name, up: true) } }
            iconButton("chevron.down", "Move down", enabled: index < run.ladder.count - 1) { change { $0.move(name, up: false) } }
            iconButton("xmark", "Remove", enabled: true) { change { $0.remove(name) } }
        }
        .caseCard(padding: 8)
    }

    private func iconButton(_ symbol: String, _ label: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? CaseInk.theatre : Color.wardInkSecondary.opacity(0.5))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func change(_ edit: (inout CaseRun) -> Void) {
        var next: CaseRun = run
        edit(&next)
        withAnimation(reduceMotion ? nil : .snappy) { run = next }
    }

    private func add(_ name: String) {
        change { $0.add(name, in: file) }
    }

    private func addTyped() {
        let name: String = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        add(name)
        typed = ""
    }
}
