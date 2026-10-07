import SwiftUI
import UIKit

// Only in the Swift Playgrounds core build (make_swiftpm.py --without core):
// stand-ins for the parts of the app the core leaves out, under exactly the
// names and signatures the kept files still use. Each does the least that
// keeps the kept screens working: a placeholder screen, a no-op, or a plain
// version of an effect. The full app never compiles this file.

// MARK: - Diagnostics (Shared/Diagnostics): nothing is recorded in this build

enum DiagKind: String, Codable, CaseIterable {
    case crash, hang, cpu, disk, unclean, error, warning
}

enum DiagArea: String, Codable, CaseIterable {
    case app, ai
    case cloudJobs = "cloud_jobs"
    case transcribe, voice, audio, sync
    case importing = "import"
    case export, graph3d, metal, download, account
    case metricKit = "metrickit"
}

enum Diagnostics {
    static let enabledKey = "vignette.diagnostics.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func record(_ kind: DiagKind, area: DiagArea, message: StaticString,
                       error: Error? = nil, code: Int? = nil) {}

    static func breadcrumb(_ name: StaticString) {}
}

extension View {
    func diagnosticsScreen(_ name: StaticString) -> some View { self }
}

// MARK: - The pop-out effect (Shared/PopOut.swift): the soft relief, still here

enum PopOutPlane: Int, Comparable, Sendable {
    case deep = -1, screen = 0, raised = 1, floating = 2, hero = 3

    static func < (lhs: PopOutPlane, rhs: PopOutPlane) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PopOutCues: OptionSet, Sendable {
    let rawValue: Int
    static let lean = PopOutCues(rawValue: 1)
    static let sheen = PopOutCues(rawValue: 2)
    static let edge = PopOutCues(rawValue: 4)
    static let contact = PopOutCues(rawValue: 8)
    static let all: PopOutCues = [.lean, .sheen, .edge, .contact]
    static let translateOnly: PopOutCues = [.edge, .contact]
    var shapesRelief: Bool { !isDisjoint(with: [.edge, .contact]) }
}

enum PopOutField {
    static let rowInsets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    static let insets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
}

struct PopTileStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20
    var plane: PopOutPlane = .raised
    var tint: Color? = nil
    var selected = false
    var lift: WardLift? = nil

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return configuration.label
            .contentShape(shape)
            .modifier(PopOutReliefStandIn(plane: plane, shape: shape, pressed: configuration.isPressed || selected,
                                          dims: true, chosenLift: lift))
    }
}

/// A surface's relief by its plane, as in the app: a well on the deep
/// plane, raised above the screen plane, pressed in while held, low and
/// faint when disabled (a tile's label too, `dims`).
private struct PopOutReliefStandIn<S: InsettableShape>: ViewModifier {
    let plane: PopOutPlane
    let shape: S
    let pressed: Bool
    var dims = false
    var chosenLift: WardLift? = nil
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let own: WardLift = plane == .hero ? .peak : plane == .floating ? .high : plane == .raised ? .mid : .low
        let lift: WardLift = chosenLift ?? own
        let deep: Bool = plane == .deep
        return content
            .opacity(enabled || !dims ? 1 : 0.55)
            .background {
                if deep {
                    WardReliefFace(shape: shape, lift: lift, inset: true)
                } else if !enabled {
                    WardReliefFace(shape: shape, lift: .low).opacity(0.5)
                } else {
                    WardReliefFace(shape: shape, lift: pressed ? lift.lower : lift, inset: pressed)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: pressed)
    }
}

extension ButtonStyle where Self == PopTileStyle {
    static var popTile: PopTileStyle { PopTileStyle() }
}

extension View {
    @ViewBuilder
    func popOut<S: InsettableShape>(_ plane: PopOutPlane, in shape: S, tint: Color? = nil,
                                    pressed: Bool = false, cues: PopOutCues = .all,
                                    lift: WardLift? = nil) -> some View {
        if plane != .screen && cues.shapesRelief {
            modifier(PopOutReliefStandIn(plane: plane, shape: shape, pressed: pressed, chosenLift: lift))
        } else {
            self
        }
    }

    func popOut(_ plane: PopOutPlane) -> some View {
        popOut(plane, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func deepParallax() -> some View { self }

    func popOutFrozen() -> some View { self }

    func popOutFacePaused() -> some View { self }

    func popOutLifecycle() -> some View { self }

    func studyBar<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let bar = StudyActionBar(content: content)
        return safeAreaInset(edge: .bottom, spacing: 0) { bar }
    }

    func popField(cornerRadius: CGFloat = 12, insets: EdgeInsets = PopOutField.insets) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return padding(insets)
            .frame(minHeight: 44)
            .wardInset(in: shape)
    }

    func popFieldRow(cornerRadius: CGFloat = 12) -> some View {
        popField(cornerRadius: cornerRadius)
            .listRowBackground(Color.clear)
            .listRowInsets(PopOutField.rowInsets)
    }

    func popEditor(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return scrollContentBackground(.hidden)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minHeight: 44)
            .wardInset(in: shape)
    }

    func popEditorRow(cornerRadius: CGFloat = 12) -> some View {
        popEditor(cornerRadius: cornerRadius)
            .listRowBackground(Color.clear)
            .listRowInsets(PopOutField.rowInsets)
    }
}

extension Color {
    /// The same colour with its brightness lowered by `amount` (0...1).
    func darkened(_ amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        let lowered: Double = Double(b) - amount
        let brightness: Double = min(1, max(0, lowered))
        return Color(hue: Double(h), saturation: Double(s), brightness: brightness, opacity: Double(a))
    }
}

// MARK: - The space theme (Shared/Space): a calm flat backdrop instead

enum SpaceQuality: Int, Comparable, Sendable {
    case still = 0
    case reduced = 1
    case full = 2

    static func < (lhs: SpaceQuality, rhs: SpaceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var isFull: Bool { self == .full }

    static func current() -> SpaceQuality { .still }
}

private struct SpaceQualityKey: EnvironmentKey {
    static let defaultValue: SpaceQuality = .still
}

extension EnvironmentValues {
    var spaceQuality: SpaceQuality {
        get { self[SpaceQualityKey.self] }
        set { self[SpaceQualityKey.self] = newValue }
    }
}

enum SpaceCue {
    case correct, wrong, reveal, liftOff, complete
}

/// The quiet cues: haptics only, no sound and no sky.
enum SpaceFeedback {
    static func play(_ cue: SpaceCue) {
        DispatchQueue.main.async {
            switch cue {
            case .correct, .complete:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .wrong:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .reveal, .liftOff:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}

enum SpaceWarp {
    static func liftOff() {
        SpaceFeedback.play(.liftOff)
    }
}

extension View {
    /// Keeps the space sounds quiet while a screen records or speaks
    /// (Shared/Space/SpaceFeedback.swift): there are no sounds here.
    func spaceSoundsHushed() -> some View { self }
}

enum PhotonPalette {
    static func colour(_ c: SIMD3<Float>) -> Color {
        Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }

    static var ember: Color { colour(GraphArt.ember) }
    static var orange: Color { colour(GraphArt.orange) }
    static var gold: Color { colour(GraphArt.gold) }
    static var whiteHot: Color { colour(GraphArt.whiteHot) }
    static let deepGold = Color(red: 0.86, green: 0.58, blue: 0.08)

    static func stops(dark: Bool) -> [Gradient.Stop] {
        let top: Color = dark ? whiteHot : deepGold
        let high: Color = dark ? gold : Color(red: 0.93, green: 0.52, blue: 0.05)
        return [
            Gradient.Stop(color: ember, location: 0),
            Gradient.Stop(color: orange, location: 0.35),
            Gradient.Stop(color: high, location: 0.72),
            Gradient.Stop(color: top, location: 1)
        ]
    }
}

/// The arc of a progress ring, filled to `fraction`.
struct PhotonArc: View {
    let fraction: Double
    let lineWidth: CGFloat

    var body: some View {
        let shown: CGFloat = CGFloat(max(0, min(1, fraction)))
        let gradient = AngularGradient(gradient: Gradient(stops: PhotonPalette.stops(dark: true)), center: .center)
        Circle()
            .trim(from: 0, to: shown)
            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(lineWidth / 2)
    }
}

struct AuroraCurtain: View {
    static let playFor: TimeInterval = 2.5

    var body: some View {
        Color.clear
    }
}

struct FinishScoreKey: PreferenceKey {
    static let defaultValue: Double? = nil

    static func reduce(value: inout Double?, nextValue: () -> Double?) {
        if let next = nextValue() { value = next }
    }
}

/// The app's backdrop: the Ward Round grid ground.
struct AppBackdrop: View {
    let tint: Color?

    var body: some View {
        WardBackground()
    }
}

// MARK: - Screens this build leaves out
// SyncEngine, LinkDeviceView and ModelSettingsView live in core-shell-out:
// core3 brings the real ones back and must not also compile these.

struct RuleSheetView: View {
    var body: some View { NotInThisBuild(feature: "The rule sheet") }
}

/// The ward pocket (Features/Exam/WardPocketView.swift): calculators and scores.
struct WardPocketSheet: View {
    var body: some View { NotInThisBuild(feature: "The ward pocket") }
}

/// SI or US conventional units, for the exam's lab values sheet.
struct WardUnitsPicker: View {
    @Binding var conventional: Bool

    var body: some View {
        Picker("Units", selection: $conventional) {
            Text("SI").tag(false)
            Text("US conventional").tag(true)
        }
        .pickerStyle(.segmented)
    }
}

/// The one-time tips (Features/Onboarding/StudyTips.swift): none in this build.
enum StudyTip {
    case turnInto, holdSet, undo, lens, ideasTheme
}

enum TipScreen {
    case study, library, review, lens, ideas
}

@MainActor
enum StudyTips {
    static func used(_ tip: StudyTip) {}
}

extension View {
    func tipSighting(_ screen: TipScreen) -> some View { self }
    func studyTip(_ tip: StudyTip, when: Bool = true) -> some View { self }
}

/// The reasoning card under a question (Features/Reasoning): nothing here.
struct HowToReachCard: View {
    let differential: DifferentialTiers
    var lecture: String? = nil

    var body: some View { EmptyView() }
}

// MARK: - Helpers the kept code calls by name
// guessFirst and Store.picks live in core-shell-out: core3 brings the real
// Learn files back, which declare both.

extension PassMark {
    /// The chosen exam's rough pass mark, or the track's (Shared/Exam/ExamFormats.swift).
    static func typical(for exam: TargetExam?, track: ExamTrack) -> Double {
        exam?.passMark ?? typical(for: track)
    }
}

/// A mock paper (Features/Mock). The exam picker asks for the length in
/// words (hours); the shell, once it is back, also opens the paper itself.
struct MockPaperView: View {
    var body: some View { NotInThisBuild(feature: "A mock paper") }

    static func hours(_ minutes: Int) -> String {
        let h: Int = minutes / 60
        let m: Int = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}

enum OcclusionExample {
    static func seed(into store: Store) async {}
}

/// Which window is in front (Shared/AppIntentsRouting.swift): there is one.
final class AppRouter {
    static let shared = AppRouter()

    func isFront(_ id: UUID) -> Bool { true }
}

// MARK: - Cases (Features/Cases): the patients are not in this build; a
// Cases set's file (Shared/Cases/CaseFile.swift) still loads and syncs

struct CaseListView: View {
    let set: StudySet
    var body: some View { NotInThisBuild(feature: "Cases") }
}

struct CaseMakeSection: View {
    @Binding var subject: String
    let name: String
    let step: NewSetStep
    var presetText: String = ""
    var presetName: String = ""
    let onMade: (StudySet) -> Void

    var body: some View {
        Section { Text("Writing cases is not in this build. The full app has it.") }
    }
}

enum CaseSamples {
    static let all: [CaseFile] = []
}

/// A cloud job of cases finished while the app was closed is kept as text.
enum CaseWriting {
    static func collect(_ replies: [String], count: Int, lecture: String = "") -> [CaseFile] { [] }
}

enum CaseChecks {
    static func screen(_ files: [CaseFile]) -> (kept: [CaseFile], dropped: [(title: String, why: [String])]) { (files, []) }
    static func note(kept: Int, dropped: Int) -> String { "" }
}
