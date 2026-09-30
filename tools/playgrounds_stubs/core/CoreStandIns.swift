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

// MARK: - The pop-out effect (Shared/PopOut.swift): flat here

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
}

enum PopOutField {
    static let rowInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
    static let insets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
}

struct PopTileStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20
    var plane: PopOutPlane = .raised
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let edge: Color = (tint ?? Color.primary).opacity(0.15)
        return configuration.label
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(edge))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

extension ButtonStyle where Self == PopTileStyle {
    static var popTile: PopTileStyle { PopTileStyle() }
}

extension View {
    func popOut<S: InsettableShape>(_ plane: PopOutPlane, in shape: S, tint: Color? = nil,
                                    pressed: Bool = false, cues: PopOutCues = .all) -> some View {
        self
    }

    func popOut(_ plane: PopOutPlane) -> some View { self }

    func deepParallax() -> some View { self }

    func popOutFrozen() -> some View { self }

    func popOutFacePaused() -> some View { self }

    func popOutLifecycle() -> some View { self }

    func studyBar<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let inner: C = content()
        let bar = HStack(spacing: 12) { inner }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
        return safeAreaInset(edge: .bottom, spacing: 0) { bar }
    }

    func popField(cornerRadius: CGFloat = 12, insets: EdgeInsets = PopOutField.insets) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return padding(insets)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: shape)
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
            .background(.regularMaterial, in: shape)
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

/// The app's backdrop: Clean Sheet in light, Midnight navy in dark, with the
/// mode's tint washed over the top when there is one.
struct AppBackdrop: View {
    let tint: Color?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ground: Color = scheme == .dark
            ? Color(red: 10 / 255, green: 22 / 255, blue: 40 / 255)
            : Color(red: 0.965, green: 0.973, blue: 0.98)
        ZStack {
            ground
            if let tint {
                LinearGradient(colors: [tint.opacity(scheme == .dark ? 0.18 : 0.10), Color.clear],
                               startPoint: .top, endPoint: .center)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sync (Persistence/SyncEngine): the personal build skips it

final class SyncEngine: ObservableObject {
    enum Status: Equatable {
        case idle
        case syncing
        case offline
        case failed(String)
        case needsPro
        case needsLibraryChoice
    }

    @Published private(set) var status: Status = .idle
    @Published var copiesKept = 0
    @Published var lastSyncedAt: Date? = nil

    var setsKeptHere: Int { 0 }

    func syncNow() async {}
    func chooseLibrary(addToAccount: Bool) async {}
    func addKeptSets() async {}
    func forgetEverythingSynced(libraryNowBelongsTo owner: String? = nil) {}
}

// MARK: - Screens this build leaves out

struct LinkDeviceView: View {
    var joinOnly: Bool = false

    var body: some View { NotInThisBuild(feature: "Linking another device") }
}

struct ModelSettingsView: View {
    var body: some View { NotInThisBuild(feature: "Model settings") }
}

struct RuleSheetView: View {
    var body: some View { NotInThisBuild(feature: "The rule sheet") }
}

struct SpokenStationView: View {
    let station: OsceChecklist

    var body: some View { NotInThisBuild(feature: "Spoken OSCE practice") }
}

struct NarrateReviewView: View {
    let studySet: StudySet

    init(set studySet: StudySet, startIndex: Int = 0, startPlaying: Bool = false,
         startFinished: Bool = false, startFixing: Int? = nil) {
        self.studySet = studySet
    }

    var body: some View { NotInThisBuild(feature: "Audio lectures") }
}

struct PictureFromPhotoView: View {
    let initialFiles: [URL]

    init(initialFiles: [URL] = []) {
        self.initialFiles = initialFiles
    }

    var body: some View { NotInThisBuild(feature: "Picture cards from photos") }
}

/// The reasoning card under a question (Features/Reasoning): nothing here.
struct HowToReachCard: View {
    let differential: DifferentialTiers
    var lecture: String? = nil

    var body: some View { EmptyView() }

    static func lectureLabel(for text: String, in set: StudySet) -> String? { nil }
}

struct CaseStationClock: View {
    var body: some View { EmptyView() }
}

/// The case's composer without the voice: the field and a Send button.
struct CaseVoiceButtons<Field: View>: View {
    let hasDraft: Bool
    let onSend: () -> Void
    private let field: Field

    init(simulator: CaseSimulator, hasDraft: Bool, onSend: @escaping () -> Void,
         @ViewBuilder field: () -> Field) {
        self.hasDraft = hasDraft
        self.onSend = onSend
        self.field = field()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            field
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(!hasDraft)
            .accessibilityLabel("Send")
        }
    }
}

struct DrawFromMemoryButton: View {
    let set: StudySet
    let imageIndex: Int
    let caption: String

    var body: some View { EmptyView() }
}

extension View {
    func commuteModeSheet(isPresented: Binding<Bool>) -> some View { self }

    func guessFirst(_ set: StudySet) -> some View { self }
}

// MARK: - Helpers the kept code calls by name

extension PassMark {
    /// The chosen exam's rough pass mark, or the track's (Shared/Exam/ExamFormats.swift).
    static func typical(for exam: TargetExam?, track: ExamTrack) -> Double {
        exam?.passMark ?? typical(for: track)
    }
}

enum MockPaperView {
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

/// Where the covers of a picture card go (Shared/OcclusionFilter.swift).
enum OcclusionCovers {
    static let targetRGB: (red: Double, green: Double, blue: Double) = (0.93, 0.45, 0.09)
    static let otherRGB: (red: Double, green: Double, blue: Double) = (0.56, 0.58, 0.62)
    static let drawPadding: CGFloat = 0
    static let drawMinimum: CGFloat = 6

    static func others(for card: AnkiCard, in deck: [AnkiCard]) -> [OcclusionBox] {
        var found: [OcclusionBox] = card.siblings
        if found.isEmpty, let index = card.imageIndex {
            for other in deck where other.id != card.id && other.type == .occlusion
                && other.imageIndex == index {
                if let box = other.occlusion { found.append(box) }
            }
        }
        var kept: [OcclusionBox] = []
        for box in found {
            if let target = card.occlusion, overlapShare(box, target) > 0.5 { continue }
            if kept.contains(box) { continue }
            kept.append(box)
        }
        return kept
    }

    static func overlapShare(_ a: OcclusionBox, _ b: OcclusionBox) -> Double {
        let w = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
        let h = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
        guard w > 0, h > 0 else { return 0 }
        let smaller = min(a.w * a.h, b.w * b.h)
        return smaller > 0 ? (w * h) / smaller : 0
    }

    static func rect(for box: OcclusionBox, in frame: CGRect, padding: CGFloat,
                     minimum: CGFloat, pixelScale: CGFloat = 1) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        var r = CGRect(x: frame.minX + CGFloat(box.x) * frame.width,
                       y: frame.minY + CGFloat(box.y) * frame.height,
                       width: CGFloat(box.w) * frame.width,
                       height: CGFloat(box.h) * frame.height)
        r = r.insetBy(dx: -padding, dy: -padding)
        if r.width < minimum { r = r.insetBy(dx: -(minimum - r.width) / 2, dy: 0) }
        if r.height < minimum { r = r.insetBy(dx: 0, dy: -(minimum - r.height) / 2) }
        r = r.intersection(frame)
        guard !r.isNull, r.width > 0, r.height > 0 else { return .zero }
        let s = max(pixelScale, 1)
        let minX = (r.minX * s).rounded(.down) / s
        let minY = (r.minY * s).rounded(.down) / s
        let maxX = (r.maxX * s).rounded(.up) / s
        let maxY = (r.maxY * s).rounded(.up) / s
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Figures in a lecture's pages (Shared/FigureFinder.swift): none are found
/// in this build, so imports carry their text and pictures only.
enum FigureFinder {
    struct Found {
        var figure: OcclusionBox
        var cards: [AnkiCard]
    }

    static func read(_ image: CGImage, imageIndex: Int,
                     question: String = "What is labelled here?",
                     pageBands: Bool = true) -> Found? {
        nil
    }
}

/// The recording transcriber's line shape (Shared/LectureTranscriber.swift),
/// which the narrate segments are built from.
enum LectureTranscriber {
    struct Word: Equatable {
        var text: String
        var start: Double
        var end: Double
    }

    struct Line: Equatable {
        var text: String
        var start: Double
        var end: Double
        var words: [Word]
    }
}

/// Which window is in front (Shared/AppIntentsRouting.swift): there is one.
final class AppRouter {
    static let shared = AppRouter()

    func isFront(_ id: UUID) -> Bool { true }
}

extension Store {
    /// The picks for these questions, in this order (Shared/Learn/LearnStore.swift).
    func picks(ids: [UUID]) -> [QuestionPick] {
        let wanted = Set(ids)
        let found = mcqPicks { wanted.contains($0.question.id) }
        let byID = Dictionary(found.map { ($0.question.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }
}

// MARK: - Anki packages (Shared/ApkgImport.swift): not read in this build

struct AnkiProgress: Equatable {
    var due: Date
    var intervalDays: Double
    var reviews: Int
    var lapses: Int
    var suspended: Bool
}

enum AnkiNoteText {
    struct Deck {
        var progress: [UUID: AnkiProgress] = [:]
    }

    struct PlannedSet {
        var name: String
        var folder: String?
        var deck: Deck = Deck()
    }

    static func studySet(_ planned: PlannedSet, subject: String, folderId: UUID?, now: Date = Date(),
                         picture: (String) -> String?) -> StudySet {
        var set = StudySet(name: planned.name, subject: subject, kind: .anki)
        set.folderId = folderId
        set.createdAt = now
        return set
    }
}

enum ApkgImport {
    struct Package {
        var sets: [AnkiNoteText.PlannedSet] = []
        var media: [String: URL] = [:]
        var format = "Anki package"
        var noteCount = 0
        var ankiCardCount = 0
        var madeCards = 0
        var skippedNotes = 0
        var pictureCount = 0
        var picturesLeftOut = 0
        var occlusionCardsLeftOut = 0
        var tagCount = 0
        var deckCount = 0

        func discard() {}
    }

    enum Failure: LocalizedError {
        case empty
        case notInThisBuild

        var errorDescription: String? {
            switch self {
            case .empty: return "There were no cards in that deck."
            case .notInThisBuild: return "Anki decks open in the full app; this build leaves the Anki reader out."
            }
        }
    }

    static func read(_ url: URL) throws -> Package {
        throw Failure.notInThisBuild
    }
}
