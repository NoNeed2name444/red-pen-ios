import SwiftUI

/// The four places in the app, and nothing else at the top level.
///
/// - Library: the sets and the lectures they came from (LibraryView, as it was)
/// - Practice: every way to study, as a few big cards and one-tap modes
/// - Ideas: the idea dump, with its board and 3D map
/// - Progress: the rings, the streak and the exam countdown
///
/// Settings, account and help are behind the gear on the Library and Progress
/// bars rather than a fifth tab: they are visited now and then, not worked in.
enum AppTab: String, Hashable, CaseIterable {
    case library, practice, ideas, progress
}

/// The app's root once signed in: a tab bar on a phone, and the same four as
/// the sidebar on an iPad (`.sidebarAdaptable`).
///
/// Every tab keeps its own navigation stack, so moving between them never
/// loses what was open in the other.
struct AppTabsView: View {
    /// Always opens on the Library: the UI tests, and people, expect the sets
    /// first.
    @State private var tab: AppTab = .library
    @ObservedObject private var modeSwitch = ModeSwitch.shared

    var body: some View {
        TabView(selection: $tab) {
            Tab("Library", systemImage: "books.vertical.fill", value: AppTab.library) {
                LibraryView()
            }
            Tab("Practice", systemImage: "play.circle.fill", value: AppTab.practice) {
                PracticeTab()
            }
            Tab("Ideas", systemImage: "lightbulb.fill", value: AppTab.ideas) {
                IdeasTab()
            }
            Tab("Progress", systemImage: "chart.bar.fill", value: AppTab.progress) {
                ProgressTab()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewSidebarHeader { sidebarHeader }
        // "Turn into…" from a set opened in another tab: the new set opens
        // (or New set is raised) by the Library, so go there to see it.
        .onChange(of: modeSwitch.opening != nil) { _, now in
            if now { tab = .library }
        }
        .onChange(of: modeSwitch.writing != nil) { _, now in
            if now { tab = .library }
        }
    }

    /// The app's name at the top of the iPad sidebar.
    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Brand.Mark(size: 22, tint: Brand.signal)
            Text(Brand.name).font(.headline)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The tabs other than the Library

/// Practice: its own stack, so a quiz started here comes back here.
struct PracticeTab: View {
    var body: some View {
        NavigationStack {
            PracticeView()
        }
    }
}

/// Ideas: the idea dump (list, board and 3D map), at the top level.
struct IdeasTab: View {
    var body: some View {
        NavigationStack {
            IdeasView()
        }
    }
}

/// Progress: the Analytics page with its rings, the streak and the exam
/// countdown in the bar, the per-subject Progress page one tap away, and the
/// gear.
struct ProgressTab: View {
    @State private var support: SupportPage?
    @State private var showingSubjects = false
    @State private var showingRules = false
    @ObservedObject private var log = StudyLog.shared

    var body: some View {
        NavigationStack {
            AnalyticsView()
                .scrollContentBackground(.hidden)
                .background(LibraryBackdrop())
                .toolbar { toolbarItems }
                .navigationDestination(item: $support) { $0.page }
                .navigationDestination(isPresented: $showingSubjects) { StatsView() }
                .navigationDestination(isPresented: $showingRules) { RuleSheetView() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                SupportMenuItems(chosen: $support)
            } label: {
                Label("Settings and help", systemImage: "gearshape")
            }
            .accessibilityIdentifier("progressMenu")
        }
        ToolbarItem(placement: .principal) {
            ProgressStreakChip(streak: log.streak, examDays: ExamCountdown.days)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("By subject", systemImage: "chart.bar.xaxis") { showingSubjects = true }
                Button("Rule sheet", systemImage: "list.bullet.rectangle") { showingRules = true }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("progressMore")
        }
    }
}

/// "flame 5 · calendar 43 days" in the Progress bar: the streak and the days to the exam,
/// the two numbers worth seeing without scrolling.
struct ProgressStreakChip: View {
    let streak: Int
    let examDays: Int?

    var body: some View {
        HStack(spacing: 10) {
            Label("\(streak)", systemImage: "flame.fill")
                .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
            if let examDays, examDays >= 0 {
                Label(examText(examDays), systemImage: "calendar")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func examText(_ days: Int) -> String {
        if days == 0 { return "Exam day" }
        let plural: String = days == 1 ? "" : "s"
        return "\(days) day\(plural)"
    }

    private var spoken: String {
        var text: String = "\(streak)-day streak"
        if let examDays, examDays >= 0 {
            text += ", " + examText(examDays) + " to the exam"
        }
        return text
    }
}

/// Days until the exam set in AI models → Your exam; nil when none is set.
/// The same reading the Library's Today card makes.
enum ExamCountdown {
    static var days: Int? {
        let stamp: Double = UserDefaults.standard.double(forKey: ExamTrack.dateKey)
        guard stamp > 0 else { return nil }
        let calendar = Calendar.current
        let today: Date = calendar.startOfDay(for: Date())
        let exam: Date = calendar.startOfDay(for: Date(timeIntervalSince1970: stamp))
        return calendar.dateComponents([.day], from: today, to: exam).day
    }
}
