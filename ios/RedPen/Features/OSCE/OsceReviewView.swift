import SwiftUI

/// OSCE recall drill: work through each checklist's steps in order, one hidden
/// at a time ("what comes next?"), reveal it, then either "I got it" (on to
/// the next step) or "Start over". The steps of a station are done in order,
/// so a missed step ends the attempt: the station goes back to step 1 and the
/// clock back to full, and the miss is kept against that step (`OsceRun`) so
/// the finish can say which steps tripped the student up. When a checklist
/// is got all the way through, move on to the next one in the set.
struct OsceReviewView: View {
    let studySet: StudySet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSpan) private var span
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var llm: LocalLLMService
    /// The station being practised aloud with a spoken patient, while open.
    @State private var spoken: OsceChecklist?

    @State private var checklistIndex: Int
    @State private var revealed = false
    /// Where this station's attempt is, and every start over so far.
    @State private var run: OsceRun
    /// The station clock: when it runs out while running, nil while stopped.
    @State private var clockEndsAt: Date?
    /// What is left on the clock while it is stopped. A station starts with
    /// the time the student's exam gives one - eight minutes for PLAB 2, ten
    /// for a PACES encounter - because practising against the real length is
    /// the only way to learn what fits in it.
    @State private var clockLeft = OsceReviewView.stationSeconds

    init(set studySet: StudySet, startChecklistIndex: Int = 0, startRevealed: Bool = false, startComplete: Bool = false, startMissed: [Int] = []) {
        self.studySet = studySet
        let index: Int = min(startChecklistIndex, max(0, studySet.osceChecklists.count - 1))
        let count: Int = studySet.osceChecklists.indices.contains(index) ? studySet.osceChecklists[index].steps.count : 0
        _checklistIndex = State(initialValue: index)
        _revealed = State(initialValue: startRevealed)
        _run = State(initialValue: OsceRun(stepCount: count, misses: startMissed, complete: startComplete))
    }

    private var checklists: [OsceChecklist] { studySet.osceChecklists }
    private var checklist: OsceChecklist? { checklists.indices.contains(checklistIndex) ? checklists[checklistIndex] : nil }
    private var complete: Bool { run.complete }
    private var currentStepText: String? {
        guard let checklist, checklist.steps.indices.contains(run.stepIndex) else { return nil }
        return checklist.steps[run.stepIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let checklist {
                progressHeader(checklist)
                if complete {
                    completeBody(checklist)
                } else {
                    stepBody(checklist)
                }
            } else {
                ContentUnavailableView("No checklists in this set.", systemImage: "checklist")
            }
        }
        .modeScreen(.osce)
        // The spoken patient, Check accuracy and Turn into, all in the one
        // More menu
        .studyMoreMenu(for: studySet, check: accuracyAsk) {
            if let checklist {
                Button { spoken = checklist } label: {
                    Label("Practise with a spoken patient", systemImage: "person.wave.2")
                }
            }
        }
        .sheet(item: $spoken) { station in
            NavigationStack {
                SpokenStationView(station: station)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { spoken = nil }
                        }
                    }
            }
            .environmentObject(store)
            .environmentObject(llm)
            // a voice screen: the camera stays off while it listens
            .popOutFacePaused()
        }
        .navigationTitle(studySet.subject.isEmpty ? "OSCE" : studySet.subject)
        .diagnosticsScreen("screen:osce_review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: resume)
        // Saved on every change rather than on the way out: a station is
        // usually left by the app being closed or killed, and nothing runs then.
        .onChange(of: run) { old, new in
            remember()
            if new.complete && !old.complete { stopClock() }
        }
        .onChange(of: checklistIndex) { _, _ in remember() }
        // Two gentle taps from the clock: one with a minute left, one at the
        // end, so it can be felt without looking away from the patient.
        // Keyed by the end time, so pausing (which clears it) cancels both.
        .task(id: clockEndsAt) {
            guard let ends = clockEndsAt else { return }
            let untilWarning = ends.timeIntervalSinceNow - 60
            if untilWarning > 0 {
                try? await Task.sleep(for: .seconds(untilWarning))
                guard !Task.isCancelled, clockEndsAt == ends else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            let rest = ends.timeIntervalSinceNow
            if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            guard !Task.isCancelled, clockEndsAt == ends else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            clockEndsAt = nil
            clockLeft = 0
        }
    }

    /// What Check accuracy looks at: the station on screen.
    private var accuracyAsk: AccuracyAsk {
        AccuracyAsk(instruction: "Write an OSCE station checklist, in the order the steps are performed, from the source.") {
            guard let checklist else { return nil }
            let steps: String = checklist.steps.map { "- " + $0 }.joined(separator: "\n")
            return checklist.title + "\n" + steps
        }
    }

    // MARK: station clock

    /// One station's time in the exam the student is sitting.
    nonisolated static var stationSeconds: TimeInterval {
        TimeInterval(ExamTrack.current.stationMinutes * 60)
    }

    /// Start, pause, and - once it has run out - put back to a full station.
    private var stationClock: some View {
        Button(action: toggleClock) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = secondsLeft(at: context.date)
                let running = clockEndsAt != nil
                let symbol: String = running ? "pause.fill" : (left == 0 ? "arrow.counterclockwise" : "play.fill")
                let ink: Color = running && left <= 60 ? Color.red : Color.primary
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.footnote)
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Station clock, \(left / 60) minutes \(left % 60) seconds")
                .accessibilityHint(running ? "Pauses the clock" : (left == 0 ? "Resets the clock" : "Starts the clock"))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .liquidGlassChip(plane: .raised)
        }
        .buttonStyle(.plain)
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
    }

    private func secondsLeft(at date: Date) -> Int {
        let raw = clockEndsAt.map { $0.timeIntervalSince(date) } ?? clockLeft
        return max(0, Int(raw.rounded(.up)))
    }

    private func toggleClock() {
        UISelectionFeedbackGenerator().selectionChanged()
        if clockEndsAt != nil {
            stopClock()
        } else if clockLeft <= 0 {
            clockLeft = Self.stationSeconds
        } else {
            clockEndsAt = Date().addingTimeInterval(clockLeft)
        }
    }

    /// Pauses, keeping whatever time is left.
    private func stopClock() {
        guard let ends = clockEndsAt else { return }
        clockLeft = max(0, ends.timeIntervalSinceNow)
        clockEndsAt = nil
    }

    // MARK: header

    /// "Step 3 of 12", the station's name, and the clock - the one control
    /// that belongs up here, because it is glanced at rather than pressed.
    private func progressHeader(_ checklist: OsceChecklist) -> some View {
        let totalSteps = checklists.reduce(0) { $0 + $1.steps.count }
        let earlier: Int = checklists.prefix(checklistIndex).reduce(0) { $0 + $1.steps.count }
        let here: Int = complete ? checklist.steps.count : run.stepIndex
        let fraction: Double = totalSteps > 0 ? min(1.0, Double(earlier + here) / Double(totalSteps)) : 0
        let status: String
        if complete {
            status = "Station done"
        } else if run.restarts > 0 {
            status = "Step \(run.stepIndex + 1) of \(checklist.steps.count) \u{00B7} attempt \(run.restarts + 1)"
        } else {
            status = "Step \(run.stepIndex + 1) of \(checklist.steps.count)"
        }
        return StudyProgressHeader(status, detail: checklist.title, fraction: fraction) {
            if !complete { stationClock }
        }
    }

    // MARK: step

    private func stepBody(_ checklist: OsceChecklist) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                if revealed, let text = currentStepText {
                    Text(text)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                        .contentCard()
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                } else {
                    Text(promptLine)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                }
                if !revealed && run.stepIndex == 0 {
                    Text(run.restarts == 0
                         ? "Work through the station out loud, in order, revealing each step to check yourself."
                         : "From the top. The steps go in order, so a missed one means starting again.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(16)
            // a start over slides the station back in from the top
            .id(run.restarts)
            .transition(.asymmetric(insertion: .slideFade(.top), removal: .opacity))
            .frame(minHeight: 220)
            .padding(.bottom, 12)
            .readableColumn()
        }
        .studyBar { footer }
    }

    private var promptLine: String {
        return "What comes next? Say it out loud, then tap Reveal."
    }

    /// Reveal; then "Start over" beside the big "I got it", in the same place -
    /// on a wide iPad, Start over under the left hand and I got it under the
    /// right. Only these two: the steps go in order, so a missed step cannot
    /// be carried on from.
    @ViewBuilder
    private var footer: some View {
        if revealed {
            HStack(spacing: 12) {
                Button(action: startOver) {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bigSecondary)
                .keyboardShortcut("r", modifiers: [])
                .accessibilityIdentifier("osceStartOver")
                .accessibilityHint("Back to step 1, with the clock reset")

                if span == .broad { Spacer(minLength: 16) }

                Button(action: gotIt) {
                    Label("I got it", systemImage: "checkmark")
                }
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityIdentifier("osceGotIt")
                .accessibilityHint("On to the next step")
            }
        } else {
            Button { withAnimation(.snappy) { revealed = true } } label: {
                Label("Reveal", systemImage: "eye")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityIdentifier("osceReveal")
        }
    }

    // MARK: complete

    /// The finish: how many steps came back first time, large, and one big
    /// button - on to the next station, named in the message, or Done. Under
    /// the result, the same station practised aloud with a spoken patient.
    private func completeBody(_ checklist: OsceChecklist) -> some View {
        let hasNext: Bool = checklistIndex < checklists.count - 1
        let restarts: Int = run.restarts
        let title: String
        if restarts == 0 {
            title = "All \(checklist.steps.count) steps, first time"
        } else {
            title = restarts == 1 ? "Done after 1 start over" : "Done after \(restarts) start overs"
        }
        let message: String = completeMessage(checklist)
        return ScrollView {
            VStack(spacing: 16) {
                FinishHero(symbol: "checkmark.seal.fill", title: title, message: message)
                // the station worked through: its accuracy, and why
                AccuracyBadge(set: studySet, itemID: checklist.id.uuidString)
                Button { spoken = checklist } label: {
                    Label("Practise it with a spoken patient", systemImage: "person.wave.2")
                }
                .buttonStyle(.bigSecondary)
                .accessibilityHint("Runs this station out loud, with a patient who answers")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .studyBar { completeButtons(hasNext: hasNext) }
    }

    /// What the result means, and where the student goes from here.
    private func completeMessage(_ checklist: OsceChecklist) -> String {
        let recall: String
        let weak = run.weakSteps
        if weak.isEmpty {
            recall = "You recalled every step of \(checklist.title), in order."
        } else {
            let named: [String] = weak.prefix(3).map { entry in
                let times: String = entry.times == 1 ? "" : " (\(entry.times) times)"
                return "step \(entry.step + 1)\(times)"
            }
            recall = "You started over at " + named.joined(separator: ", ") + " - worth another look."
        }
        let nextIndex: Int = checklistIndex + 1
        guard checklists.indices.contains(nextIndex) else {
            return recall + " All stations done!"
        }
        let nextTitle: String = checklists[nextIndex].title
        return recall + " Next up: \(nextTitle)."
    }

    /// Done for now beside the big Next station; or Done alone at the end.
    @ViewBuilder
    private func completeButtons(hasNext: Bool) -> some View {
        if hasNext {
            HStack(spacing: 12) {
                Button("Done for now") { dismiss() }
                    .buttonStyle(.bigCompanion)
                if span == .broad { Spacer(minLength: 16) }
                Button { nextChecklist() } label: {
                    Label("Next station", systemImage: "arrow.right")
                }
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.return, modifiers: [])
            }
        } else {
            Button("Done") { dismiss() }
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    // MARK: logic - OsceRun

    private func gotIt() {
        StudyLog.shared.record()
        withAnimation(.snappy) {
            run.gotIt()
            revealed = false
        }
    }

    /// Back to step 1 with no confirming: the miss is kept against the step,
    /// and the station clock goes back to full (still running if it was).
    private func startOver() {
        StudyLog.shared.record()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        let wasRunning: Bool = clockEndsAt != nil
        clockLeft = Self.stationSeconds
        clockEndsAt = wasRunning ? Date().addingTimeInterval(clockLeft) : nil
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            run.startOver()
            revealed = false
        }
    }

    // MARK: picking the station back up

    /// Restores a saved position, if it still fits the set.
    ///
    /// Only when the screen was opened at the start. A caller that asked for a
    /// particular checklist meant it, and quietly sending them somewhere else
    /// would be the opposite of resuming.
    private func resume() {
        guard checklistIndex == 0, run.stepIndex == 0, !complete, run.misses.isEmpty,
              let saved = store.osceProgress[studySet.id],
              saved.fits(checklists) else { return }
        checklistIndex = saved.checklistIndex
        // An older save could be part way through a second pass over missed
        // steps; that pass no longer exists, so it picks up at the step.
        run = OsceRun(stepCount: checklists[saved.checklistIndex].steps.count,
                      stepIndex: saved.stepIndex, misses: saved.missed)
        revealed = false
    }

    private func remember() {
        // The whole set finished is not a position to come back to; it is the
        // one state where starting again is what somebody wants.
        if complete && checklistIndex >= checklists.count - 1 {
            store.clearOsce(for: studySet.id)
            return
        }
        guard let checklist else { return }
        store.saveOsce(OsceProgress(checklistIndex: checklistIndex,
                                    checklistTitle: checklist.title,
                                    stepIndex: run.stepIndex,
                                    missed: run.misses),
                       for: studySet.id)
    }

    private func nextChecklist() {
        // a new station gets a fresh clock
        clockEndsAt = nil
        clockLeft = Self.stationSeconds
        checklistIndex += 1
        revealed = false
        let count: Int = checklists.indices.contains(checklistIndex) ? checklists[checklistIndex].steps.count : 0
        run = OsceRun(stepCount: count)
    }
}
