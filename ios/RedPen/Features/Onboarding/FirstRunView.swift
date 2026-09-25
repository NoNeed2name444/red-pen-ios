import SwiftUI

/// The first run, once per account, straight after the recording terms
/// (which stay first): the exam, its date, a daily goal, the study reminders,
/// then an example set or an empty library. Glass pages on the night sky,
/// every one skippable; whatever is left unanswered keeps its default and can
/// be changed in Settings or Mission Control later.
///
/// When it is shown is FirstRun's decision (Shared/FirstRunRules.swift); the
/// UI test that walks it launches with -showOnboarding.
struct FirstRunView: View {
    let accountId: String
    /// Called when the last page is left, however it is left.
    let onDone: () -> Void

    @State private var page: FirstRunPage = .exam

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .exam:
                    ExamPickerView(onDone: { advance() }, isOnboarding: true)
                case .date:
                    FirstRunDatePage(next: { advance() })
                case .goal:
                    FirstRunGoalPage(next: { advance() })
                case .reminders:
                    FirstRunRemindersPage(next: { advance() })
                case .examples:
                    FirstRunExamplesPage(finish: onDone)
                }
            }
            .transition(.opacity)
        }
        .onAppear { FirstRun.start(accountId: accountId) }
    }

    private func advance() {
        guard let next = page.next else {
            onDone()
            return
        }
        withAnimation(.snappy) { page = next }
    }
}

/// The pages, in order.
enum FirstRunPage: Int, CaseIterable {
    case exam, date, goal, reminders, examples

    var next: FirstRunPage? { FirstRunPage(rawValue: rawValue + 1) }

    /// For the test's identifiers: "firstRun-date-next".
    var name: String {
        switch self {
        case .exam: return "exam"
        case .date: return "date"
        case .goal: return "goal"
        case .reminders: return "reminders"
        case .examples: return "examples"
        }
    }

    /// "2 of 5", over each page after the exam's.
    var step: String { "\(rawValue + 1) of \(FirstRunPage.allCases.count)" }
}

// MARK: - The pages

/// Page 2: the exam's date, which Mission Control counts down to.
private struct FirstRunDatePage: View {
    let next: () -> Void
    @AppStorage(ExamTrack.dateKey) private var examDate: Double = 0
    @State private var chosen: Date = FirstRunDatePage.start

    /// The date already set, or three months from now.
    private static var start: Date {
        let stamp: Double = UserDefaults.standard.double(forKey: ExamTrack.dateKey)
        if stamp > 0 { return Date(timeIntervalSince1970: stamp) }
        return Date().addingTimeInterval(90 * 86_400)
    }

    var body: some View {
        FirstRunPageFrame(page: .date, symbol: "calendar",
                          title: "When is your exam?",
                          detail: "Mission Control counts down to it and paces your reviews to be ready on the day.",
                          nextTitle: "Save the date",
                          next: save, skip: next) {
            DatePicker("Exam date", selection: $chosen, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .accessibilityIdentifier("firstRunDatePicker")
        }
    }

    private func save() {
        examDate = chosen.timeIntervalSince1970
        next()
    }
}

/// Page 3: cards and questions a day (DailyGoal).
private struct FirstRunGoalPage: View {
    let next: () -> Void
    @State private var goal: Int = DailyGoal.current

    private static let presets: [Int] = [20, 50, 100, 200]

    var body: some View {
        FirstRunPageFrame(page: .goal, symbol: "target",
                          title: "A daily goal",
                          detail: "Cards and questions a day. Mission Control shows how far through today you are.",
                          nextTitle: "Set \(goal) a day",
                          next: save, skip: next) {
            VStack(spacing: 16) {
                Text("\(goal)")
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
                Stepper("\(goal) a day", value: $goal.animation(.snappy), in: DailyGoal.range, step: 10)
                    .accessibilityIdentifier("firstRunGoalStepper")
                HStack(spacing: 8) {
                    ForEach(FirstRunGoalPage.presets, id: \.self) { value in
                        presetButton(value)
                    }
                }
            }
        }
    }

    private func presetButton(_ value: Int) -> some View {
        let picked: Bool = value == goal
        let tint: Color? = picked ? Color.accentColor : nil
        return Button {
            withAnimation(.snappy) { goal = value }
        } label: {
            Text("\(value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(PopTileStyle(cornerRadius: 14, tint: tint))
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("firstRunGoal-\(value)")
    }

    private func save() {
        DailyGoal.current = goal
        next()
    }
}

/// Page 4: the study reminders, the same section as in Settings.
private struct FirstRunRemindersPage: View {
    let next: () -> Void

    var body: some View {
        Form {
            Section {
                FirstRunHeading(symbol: "bell.badge",
                                title: "Reminders",
                                detail: "All off until you turn one on. You can change them in Settings.")
                    .listRowBackground(Color.clear)
            }
            StudyReminderSettings()
        }
        .scrollContentBackground(.hidden)
        .firstRunChrome(page: .reminders, nextTitle: "Next", next: next, skip: next)
    }
}

/// Page 5: an example set to try every mode on, or a library of one's own.
private struct FirstRunExamplesPage: View {
    let finish: () -> Void
    @EnvironmentObject private var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FirstRunHeading(symbol: "sparkles.rectangle.stack",
                                title: "Start with an example?",
                                detail: "Try every mode on a finished set before making your own.")
                choice("Add an example set", symbol: "square.stack.3d.up",
                       detail: "One short set in every mode, in an Examples folder. Delete it any time.",
                       id: "firstRunAddExamples") {
                    SampleData.addExamples(to: store)
                    finish()
                }
                choice("Start empty", symbol: "square.dashed",
                       detail: "Make your first set from a lecture, notes or a photo.",
                       id: "firstRunStartEmpty") {
                    finish()
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(LibraryBackdrop())
        .navigationTitle(FirstRunPage.examples.step)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { finish() }
                    .accessibilityIdentifier("firstRun-examples-skip")
            }
        }
    }

    private func choice(_ title: String, symbol: String, detail: String, id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        }
        .buttonStyle(.popTile)
        .accessibilityIdentifier(id)
    }
}

// MARK: - The frame every page shares

/// A symbol, a title and a line over the page's own controls, on one glass
/// panel.
private struct FirstRunPageFrame<Content: View>: View {
    let page: FirstRunPage
    let symbol: String
    let title: String
    let detail: String
    let nextTitle: String
    let next: () -> Void
    let skip: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FirstRunHeading(symbol: symbol, title: title, detail: detail)
                content()
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .liquidGlassPanel(cornerRadius: 22, plane: .raised)
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .firstRunChrome(page: page, nextTitle: nextTitle, next: next, skip: skip)
    }
}

private struct FirstRunHeading: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    /// The night sky behind, "2 of 5" and Skip at the top, and the page's
    /// main button on the floating glass slab under the thumb.
    func firstRunChrome(page: FirstRunPage, nextTitle: String,
                        next: @escaping () -> Void, skip: @escaping () -> Void) -> some View {
        let bar = StudyActionBar {
            Button(action: next) {
                Text(nextTitle).font(.headline)
            }
            .buttonStyle(.bigPrimary)
            .accessibilityIdentifier("firstRun-\(page.name)-next")
        }
        .frame(maxWidth: 584)
        .frame(maxWidth: .infinity)
        return self
            .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            .background(LibraryBackdrop())
            .navigationTitle(page.step)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: skip)
                        .accessibilityIdentifier("firstRun-\(page.name)-skip")
                }
            }
    }
}

// MARK: - Examples

extension SampleData {
    static let examplesFolderName: String = "Examples - try every mode"

    /// The example sets, one in every mode, in a folder of their own - once:
    /// a personal build (seedPersonalBuild) may already have them.
    @MainActor
    static func addExamples(to store: Store) {
        if store.folders.contains(where: { $0.name == examplesFolderName }) { return }
        let folder = StudyFolder(name: examplesFolderName)
        store.folders.append(folder)
        for sample in sets {
            var copy: StudySet = sample
            copy.id = UUID()
            copy.name = "Example: " + sample.name
            copy.folderId = folder.id
            store.addSet(copy)
        }
    }
}

// MARK: - When

/// Which accounts have finished the first run in this session, observed so
/// the root view moves on the moment the last page is left (see
/// RecordingTermsStore for why this is not a plain @State).
@MainActor
final class FirstRunStore: ObservableObject {
    @Published private(set) var finished: Set<String> = []

    /// Where the UI tests run; the owner's devices never are.
    static let simulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    private static let arguments: [String] = ProcessInfo.processInfo.arguments

    /// Whether this launch shows the pages at all.
    static let allowed: Bool = FirstRun.allowed(
        arguments: arguments,
        preview: PreviewLaunch.screen != nil || GraphPreview.isOn,
        simulator: simulator)

    /// Whether the account still has the pages to see: new to this device
    /// (it agreed to the terms in this run), or on a device that never
    /// answered the exam question, or part way through them.
    func isDue(_ accountId: String, terms: RecordingTermsStore) -> Bool {
        guard FirstRunStore.allowed, !finished.contains(accountId) else { return false }
        let forced: Bool = FirstRunStore.arguments.contains(FirstRun.showArgument)
        let justAgreed: Bool = terms.agreed.contains(accountId)
        return FirstRun.isDue(accountId: accountId, justAgreed: justAgreed,
                              examAsked: ExamChoice.hasAsked(), forced: forced)
    }

    func finish(_ accountId: String) {
        FirstRun.finish(accountId: accountId)
        withAnimation { _ = finished.insert(accountId) }
    }
}
