import SwiftUI

// MARK: - Visual identity
//
// Every mode has its own colour (the same tints the web app uses for its
// mode chips), an SF Symbol, and a soft gradient. Screens set `.tint(kind.tint)`
// so the glass buttons, progress bars and chips all pick it up, and sit on a
// `ModeBackdrop` — a faint wash of that colour — so Liquid Glass has
// something to refract instead of a flat white sheet.

extension StudySetKind {
    var tint: Color {
        switch self {
        case .mcq: return Color(red: 0.78, green: 0.16, blue: 0.16)     // pen red
        case .anki: return Color(red: 0.31, green: 0.36, blue: 0.86)    // indigo
        case .book: return Color(red: 0.10, green: 0.55, blue: 0.50)    // teal
        case .qa: return Color(red: 0.90, green: 0.49, blue: 0.13)      // amber
        case .osce: return Color(red: 0.20, green: 0.62, blue: 0.35)    // green
        case .narrate: return Color(red: 0.55, green: 0.32, blue: 0.80) // violet
        }
    }

    var symbol: String {
        switch self {
        case .mcq: return "checklist.checked"
        case .anki: return "rectangle.on.rectangle.angled"
        case .book: return "book.pages"
        case .qa: return "stethoscope"
        case .osce: return "list.clipboard"
        case .narrate: return "waveform"
        }
    }

    /// Steps inside the mode's OWN hue, for controls that must be told apart
    /// from one another.
    ///
    /// The four Anki rating buttons used to be red, orange, green and blue -
    /// a traffic light borrowed wholesale from three other modes' identities,
    /// sitting inside an indigo screen. Distinguishing four buttons does not
    /// require four unrelated colours: depth inside one hue does it, and the
    /// screen stays one colour. Anything that carries real meaning of its own
    /// (a right answer, an error) keeps its own colour; this is for controls
    /// that are merely different from each other.
    func step(_ i: Int, of n: Int = 4) -> Color {
        guard n > 1 else { return tint }
        let t = Double(min(max(i, 0), n - 1)) / Double(n - 1)   // 0 ... 1
        return shifted(brightness: 0.34 * (1 - t) - 0.16 * t,
                       saturation: -0.30 * (1 - t))
    }

    /// The same hue, lighter or darker, for washes and quiet states.
    func shifted(brightness: Double, saturation: Double = 0) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(tint).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return tint }
        return Color(hue: Double(h),
                     saturation: min(1, max(0, Double(s) + saturation)),
                     brightness: min(1, max(0, Double(b) + brightness)),
                     opacity: Double(a))
    }

    /// A neighbouring hue, for the second and third colours of a backdrop.
    func hueShifted(_ dh: Double, brightness db: Double = 0) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(tint).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return tint }
        var hue = Double(h) + dh
        hue -= hue.rounded(.down)
        return Color(hue: hue, saturation: Double(s), brightness: min(1, max(0, Double(b) + db)))
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint, tint.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The tinted icon tile used on library rows and screen headers.
struct ModeTile: View {
    let kind: StudySetKind
    var size: CGFloat = 44

    // A quiet tile: the mode's symbol in grey on a soft fill. The glossy
    // gradient tiles with coloured shadows put six loud colours on the first
    // screen; the symbol alone tells the modes apart.
    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// The colour a screen lives in: a slow mesh of three hues over paper (or ink
/// in the dark), drifting so the glass above it always has something to
/// refract. It replaced two faint blobs on flat grey, which read as washed out.
struct LivingBackdrop: View {
    /// The three hues, strongest first.
    let hues: [Color]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        let dark = scheme == .dark
        // strong enough to be colour, not a tint someone has to squint for;
        // the middle stays calm so text on cards reads first
        // half the strength it once had: a backdrop, not the subject
        let o: [Double] = (dark ? [0.55, 0.30, 0.45, 0.28, 0.06, 0.22, 0.42, 0.24, 0.50]
                                : [0.50, 0.28, 0.42, 0.24, 0.04, 0.20, 0.38, 0.22, 0.46]).map { $0 * 0.5 }
        let h = hues + Array(repeating: hues.last ?? .accentColor, count: max(0, 3 - hues.count))
        let colors: [Color] = [
            h[0].opacity(o[0]), h[1].opacity(o[1]), h[2].opacity(o[2]),
            h[1].opacity(o[3]), h[0].opacity(o[4]), h[0].opacity(o[5]),
            h[2].opacity(o[6]), h[0].opacity(o[7]), h[1].opacity(o[8]),
        ]
        let m: Float = drift ? 0.08 : -0.06
        ZStack {
            (dark ? Color(red: 0.06, green: 0.06, blue: 0.08) : Color(red: 0.98, green: 0.97, blue: 0.95))
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + m, 0], [1, 0],
                [0, 0.5 - m], [0.5 + m, 0.45 - m], [1, 0.5 + m],
                [0, 1], [0.5 - m, 1], [1, 1],
            ], colors: colors, smoothsColors: true)
        }
        .ignoresSafeArea()
        // Still. The slow drift was a repeat-forever animation started on
        // appear, and a transaction like that catches whatever else changes
        // at the same moment - lists and text visibly wobbled with it.
    }
}

/// Each mode's screen: its own hue, a neighbour of it, and a lighter partner.
struct ModeBackdrop: View {
    let kind: StudySetKind
    var body: some View {
        LivingBackdrop(hues: [kind.tint, kind.hueShifted(0.07), kind.hueShifted(-0.10, brightness: 0.12)])
    }
}

/// A row's own background: frosted, with the set's colour coming in from the
/// leading edge, so a list reads as coloured cards rather than white strips.
struct TintedRowBackground: View {
    let tint: Color
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0.04)],
                                    startPoint: .leading, endPoint: .trailing))
    }
}

/// A content card: the reading surface each mode places its question, card
/// or page on. Rounded, elevated a touch off the backdrop.
struct ContentCard: ViewModifier {
    @Environment(\.modeTint) private var tint
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            // frosted, so the backdrop's colour comes through, with a wash of
            // the mode's own hue across the top
            .background(.regularMaterial, in: shape)
            .background(LinearGradient(colors: [tint.opacity(scheme == .dark ? 0.22 : 0.14), .clear],
                                       startPoint: .top, endPoint: .center), in: shape)
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [tint.opacity(0.45), .white.opacity(0.25), tint.opacity(0.10)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)       // contact shadow
            .shadow(color: tint.opacity(0.22), radius: 18, y: 10)         // coloured lift
    }
}

extension View {
    func contentCard() -> some View { modifier(ContentCard()) }

    /// Standard chrome for a mode screen: mode tint + tinted backdrop.
    func modeScreen(_ kind: StudySetKind) -> some View {
        self
            .background(ModeBackdrop(kind: kind))
            .tint(kind.tint)
            .environment(\.modeTint, kind.tint)
    }

    /// Slides up and fades in on first appearance, staggered by `index` so
    /// a list of rows arrives as a cascade rather than all at once.
    func riseIn(index: Int = 0) -> some View { modifier(RiseIn(index: index)) }
}

/// A tappable row that squashes a touch under the finger — the tactile
/// feedback Liquid Glass buttons have, for our custom rows.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
extension ButtonStyle where Self == PressableRowStyle {
    static var pressableRow: PressableRowStyle { PressableRowStyle() }
}

struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

/// A thin, rounded, tinted progress bar — replaces the stock `ProgressView`
/// so every mode's progress reads the same way.
struct ThinProgress: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(.tint).frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// The animated score ring on the MCQ results screen.
struct ScoreRing: View {
    let fraction: Double
    let label: String
    let sublabel: String
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: shown)
                // `.tint` rather than the app accent: the ring belongs to the
                // screen it is on, and the accent is whatever mode happens to
                // be the app's default.
                .stroke(.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            VStack(spacing: 2) {
                // digits that roll rather than blink when the label changes,
                // and that keep their width while they do
                Text(label).font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(sublabel).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 168, height: 168)
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.72)) { shown = fraction } }
    }
}


/// The colour of the screen a view finds itself on.
///
/// `.tint` already carries this for controls, but some things - a glass chip,
/// for one - need a real `Color` rather than a shape style, and reaching for
/// `Color.accentColor` there is what left a red "0 reviewed" chip sitting in
/// the middle of the indigo Anki screen: the accent is the app's colour, not
/// the screen's.
private struct ModeTintKey: EnvironmentKey {
    static let defaultValue: Color = StudySetKind.mcq.tint
}

extension EnvironmentValues {
    var modeTint: Color {
        get { self[ModeTintKey.self] }
        set { self[ModeTintKey.self] = newValue }
    }
}


/// One readable column, for a screen that might be on an iPad.
///
/// The first attempt narrowed only the question card, which left the card
/// tucked inside a column of full-width answer rows - the card looked cramped
/// precisely because everything around it was not. A screen reads as one thing
/// when every part of it shares a measure, so this constrains the whole column
/// and gives it more air on a wide screen, where a phone's tight rhythm looks
/// mean rather than efficient.
/// How wide the app's WINDOW is - not the screen.
///
/// On iPad the two are rarely the same. The app can be a third of the screen in
/// Split View, a narrow Slide Over panel over something else, or a free window
/// the student has dragged to any size at all, and iPadOS 26 lets all three
/// change under the app while it is running. A size class only says "compact"
/// or "regular" and crosses that line late, which is how a 640-point window
/// ends up trying to show two columns and a sidebar of its own.
///
/// So the layout asks for the number. `windowSpan` is measured once at the root
/// and handed down; everything that has to decide between one column and two,
/// or how wide a line of text may run, reads it.
enum WindowSpan: Comparable {
    /// Slide Over, or a phone: one thing at a time, and nothing held back.
    case slim
    /// A half-and-half Split View: still one column, but text needs a measure.
    case middling
    /// Most of an iPad: the sets list can stay beside what is open.
    case broad

    init(width: CGFloat) {
        // 700 is where two columns stop being a squeeze: the sidebar's own
        // minimum is 300, and what is left has to hold a question at a
        // readable size rather than four words to the line.
        switch width {
        case ..<540: self = .slim
        case ..<700: self = .middling
        default: self = .broad
        }
    }

    /// Whether the sets list and the open set can share the window.
    var splits: Bool { self == .broad }
}

private struct WindowSpanKey: EnvironmentKey {
    static let defaultValue = WindowSpan.slim
}

extension EnvironmentValues {
    var windowSpan: WindowSpan {
        get { self[WindowSpanKey.self] }
        set { self[WindowSpanKey.self] = newValue }
    }
}

/// Measures the window the app is actually in and publishes it downwards.
struct MeasuringWindow: ViewModifier {
    @State private var span: WindowSpan = .slim

    func body(content: Content) -> some View {
        content
            .environment(\.windowSpan, span)
            .background {
                // A background rather than a GeometryReader around the content:
                // a reader would offer its children the whole space and flatten
                // the layout inside it.
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                        let now = WindowSpan(width: w)
                        if now != span { span = now }
                    }
            }
    }
}

/// One measure for a line of text, whatever shape the window is in.
///
/// The first version keyed off the size class, so a half-width Split View was
/// told it was a phone and let questions run the full width of the pane, while
/// a full-screen iPad and a slightly-narrower one behaved quite differently for
/// no reason the student could see. The rule now is the same everywhere: text
/// stops at the limit, and only when there is genuinely room to spare does it
/// get the extra breathing space around it.
struct ReadableColumn: ViewModifier {
    @Environment(\.windowSpan) private var span
    var limit: CGFloat = 700

    private var roomy: Bool { span > .slim }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: limit, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, roomy ? 8 : 0)
            .padding(.top, roomy ? 10 : 0)
    }
}

extension View {
    func readableColumn(_ limit: CGFloat = 700) -> some View {
        modifier(ReadableColumn(limit: limit))
    }

    /// Put this once, at the root of a screen that cares how big its window is.
    func measuringWindow() -> some View { modifier(MeasuringWindow()) }
}
