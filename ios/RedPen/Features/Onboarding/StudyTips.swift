import SwiftUI
#if canImport(TipKit)
import TipKit
#endif

/// The five one-time tips: Turn into…, hold a set for more, Undo after a
/// rating, Study Lens's photo and file scanning, and the Ideas map's theme.
///
/// Each waits until its screen is familiar - opened twice already
/// (TipSightings) - and TipKit then shows it once: closed, it never comes
/// back. None in a screenshot run or the simulator's UI tests (a popover
/// over a button is exactly what a test's tap must not meet), nor with
/// -disableTips.
///
/// On a screen: `.tipSighting(.lens)` counts an opening, and
/// `.studyTip(.lens)` puts the tip over the view it is about.
enum StudyTip {
    case turnInto, holdSet, undo, lens, ideasTheme

    /// The screen whose openings it waits for.
    var screen: TipScreen {
        switch self {
        case .turnInto: return .study
        case .holdSet: return .library
        case .undo: return .review
        case .lens: return .lens
        case .ideasTheme: return .ideas
        }
    }
}

@MainActor
enum StudyTips {
    /// Whether this launch shows tips at all.
    static let allowed: Bool = TipSightings.allowed(
        arguments: ProcessInfo.processInfo.arguments,
        preview: PreviewLaunch.screen != nil || GraphPreview.isOn,
        simulator: FirstRunStore.simulator)

    private static var configured = false

    /// TipKit's store, set up the first time a tip could be wanted rather
    /// than at launch: most launches go straight to studying.
    static func configure() {
        guard allowed, !configured else { return }
        configured = true
        #if canImport(TipKit)
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
        #endif
    }

    /// Whether `tip` may be offered now.
    static func ready(_ tip: StudyTip) -> Bool {
        guard allowed else { return false }
        configure()
        return TipSightings.ready(tip.screen)
    }

    /// The tip is done with: its button was used, so it need not be taught -
    /// even when that happens before the tip was ever due to show.
    static func used(_ tip: StudyTip) {
        guard allowed else { return }
        configure()
        #if canImport(TipKit)
        tip.tip.invalidate(reason: .actionPerformed)
        #endif
    }
}

extension View {
    /// Counts an opening of `screen`, for the tip that waits on it.
    func tipSighting(_ screen: TipScreen) -> some View {
        modifier(TipSightingModifier(screen: screen))
    }

    /// `tip` as a popover over this view, once, when its screen is familiar
    /// (and `when` holds: the thing it teaches is on this screen).
    func studyTip(_ tip: StudyTip, when: Bool = true) -> some View {
        modifier(StudyTipModifier(tip: tip, when: when))
    }

    /// The Ideas map's theme tip, as a small glass card along the top: the
    /// Look button it is about is drawn by the map itself, deep in Ideas.
    /// Only over the 3D map (not List or Board, nor search results) and only
    /// once the map is past its own "how to start" card, which sits in the
    /// same place.
    func ideasThemeTip(when: Bool = true) -> some View {
        modifier(IdeasThemeTipModifier(when: when))
    }
}

private struct TipSightingModifier: ViewModifier {
    let screen: TipScreen

    func body(content: Content) -> some View {
        content.onAppear {
            if StudyTips.allowed { TipSightings.record(screen) }
        }
    }
}

private struct StudyTipModifier: ViewModifier {
    let tip: StudyTip
    let when: Bool
    /// Decided once the view is on screen (after its sighting is counted),
    /// never while it is drawn.
    @State private var ready = false

    func body(content: Content) -> some View {
        #if canImport(TipKit)
        let shown: (any Tip)? = ready ? tip.tip : nil
        return content
            .popoverTip(shown)
            // again when `when` changes: a list row that becomes the first
            .task(id: when) { ready = when && StudyTips.ready(tip) }
        #else
        return content
        #endif
    }
}

private struct IdeasThemeTipModifier: ViewModifier {
    let when: Bool
    @EnvironmentObject private var notes: NoteStore
    /// IdeasView's own switcher (List, Board, Space), read only.
    @AppStorage("vignette.ideas.mode") private var modeRaw: String = IdeasMode.list.rawValue
    @State private var ready = false

    /// The map, and a map past its first-steps card (Graph3DView shows that
    /// card while there are no folders and fewer than 25 notes).
    private var onMap: Bool {
        let space: Bool = modeRaw == IdeasMode.space.rawValue
        let settled: Bool = !notes.folders.isEmpty || notes.notes.count >= 25
        return when && space && settled
    }

    func body(content: Content) -> some View {
        #if canImport(TipKit)
        let shown: Bool = ready && onMap
        return content
            .overlay(alignment: .top) {
                if shown {
                    TipView(IdeasThemeTip())
                        .frame(maxWidth: 520)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
            .task(id: onMap) {
                if onMap { ready = StudyTips.ready(.ideasTheme) }
            }
        #else
        return content
        #endif
    }
}

#if canImport(TipKit)
extension StudyTip {
    var tip: any Tip {
        switch self {
        case .turnInto: return TurnIntoTip()
        case .holdSet: return HoldSetTip()
        case .undo: return UndoRatingTip()
        case .lens: return LensScanTip()
        case .ideasTheme: return IdeasThemeTip()
        }
    }
}

// Every tip is shown once, however it was closed - even the Undo chip's,
// which goes with the chip a few seconds after a rating.

struct TurnIntoTip: Tip {
    var title: Text { Text("Turn it into another mode") }
    var message: Text? {
        Text("More \u{2192} Turn into\u{2026} makes this set cards, questions, a case or audio.")
    }
    var image: Image? { Image(systemName: "arrow.triangle.2.circlepath") }
    var options: [Option] { MaxDisplayCount(1) }
}

struct HoldSetTip: Tip {
    var title: Text { Text("Hold a set for more") }
    var message: Text? {
        Text("Rename it, turn it into another mode, practise reasoning or open its lecture.")
    }
    var image: Image? { Image(systemName: "hand.tap") }
    var options: [Option] { MaxDisplayCount(1) }
}

struct UndoRatingTip: Tip {
    var title: Text { Text("Rated it wrong?") }
    var message: Text? { Text("Undo brings the last card back for a few seconds after each rating.") }
    var image: Image? { Image(systemName: "arrow.uturn.backward") }
    var options: [Option] { MaxDisplayCount(1) }
}

struct LensScanTip: Tip {
    var title: Text { Text("Not at the page?") }
    var message: Text? { Text("Scan a photo or a PDF past paper: every question in it gets a chip.") }
    var image: Image? { Image(systemName: "doc.viewfinder") }
    var options: [Option] { MaxDisplayCount(1) }
}

struct IdeasThemeTip: Tip {
    var title: Text { Text("Change the map\u{2019}s look") }
    var message: Text? {
        Text("In the map, the round Look button switches it between Space, Neurons and Circuit.")
    }
    var image: Image? { Image(systemName: "sparkles") }
    var options: [Option] { MaxDisplayCount(1) }
}
#endif
