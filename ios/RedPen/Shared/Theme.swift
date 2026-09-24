import SwiftUI

// MARK: - Visual identity
//
// Every mode has its own colour (the same tints the web app uses for its
// mode chips), an SF Symbol, and a soft gradient. Screens set `.tint(kind.tint)`
// so the glass buttons, progress bars and chips all pick it up, and sit on a
// `ModeBackdrop` - the one shared AppBackdrop, faintly in that colour - so
// Liquid Glass has something to refract instead of a flat white sheet.

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

    /// The same hue, lighter or darker, for washes and quiet states.
    func shifted(brightness: Double, saturation: Double = 0) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(tint).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return tint }
        return Color(hue: Double(h),
                     saturation: min(1, max(0, Double(s) + saturation)),
                     brightness: min(1, max(0, Double(b) + brightness)),
                     opacity: Double(a))
    }
}

/// The tinted icon tile used on library rows and screen headers.
struct ModeTile: View {
    let kind: StudySetKind
    var size: CGFloat = 44
    /// The chosen one: filled with the mode's colour, symbol in white.
    var selected = false

    // A quiet tile: the mode's symbol in grey on a solid surface. The glossy
    // gradient tiles with coloured shadows put six loud colours on the first
    // screen; the symbol alone tells the modes apart. Solid, not see-through:
    // a translucent fill over the moving backdrop and a tinted row read as
    // two shapes smudged on top of each other.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(width: size, height: size)
            .background(selected ? AnyShapeStyle(kind.tint) : AnyShapeStyle(Color(.secondarySystemBackground)), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(selected ? 0 : 0.08), lineWidth: 0.5))
            .animation(.snappy(duration: 0.25), value: selected)
    }
}

/// Each mode's screen: the shared backdrop, faintly in the mode's colour.
struct ModeBackdrop: View {
    let kind: StudySetKind
    var body: some View {
        AppBackdrop(tint: kind.tint)
    }
}

/// A content card: the reading surface each mode places its question, card
/// or page on. It lies ON the glass (the screen plane): readable things never
/// move with the pop-out, only what you can touch rises out of it. A thin
/// contact line and a lit rim are all the depth it needs.
struct ContentCard: ViewModifier {
    @Environment(\.modeTint) private var tint
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let washAlpha: Double = scheme == .dark ? 0.22 : 0.14
        let wash: [Color] = [tint.opacity(washAlpha), Color.clear]
        let rim: [Color] = [tint.opacity(0.45), Color.white.opacity(0.25), tint.opacity(0.10)]
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            // frosted, so the backdrop's colour comes through, with a wash of
            // the mode's own hue across the top
            .background(.regularMaterial, in: shape)
            .background(LinearGradient(colors: wash, startPoint: .top, endPoint: .center), in: shape)
            .overlay(
                shape.strokeBorder(LinearGradient(colors: rim, startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)       // contact line
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


// MARK: - One layout for every study screen
//
// Quiz, cards, cases, OSCE, textbook and narrate all used to arrange
// themselves a little differently: the main button was on the right in one,
// in the middle in another, and small everywhere; each screen had two or three
// icons of its own in the top corner. Somebody who had learned one screen had
// not learned the next.
//
// Now every one of them is built from the same four pieces:
//
//   - `StudyProgressHeader` at the top: where you are ("3 of 20") and a bar
//   - the content card in the middle, which scrolls
//   - `StudyActionBar` at the bottom, under the thumb, holding ONE big button
//     that does the next thing (Check, Reveal, Next, Rate)
//   - `studyMoreMenu` in the top corner: everything used less often, in one
//     menu with words on every item
//
// and a finished session ends on a `FinishHero`: the result, large, with one
// big button under it.

/// The big button at the bottom of a study screen.
///
/// At least 56 points tall and the full width of the bar, so it can be hit
/// without looking. The text is the headline style, which is 17 points and
/// grows with the reader's own text size setting. The quiet version is for a
/// second choice sitting beside the main one - "Missed it" next to "Knew it",
/// "Back" next to "Next" - so there is never any doubt which is the main one.
///
/// Depth: the primary is the screen's hero - it stands highest out of the
/// glass; the quiet ones are raised, and sit flush inside a floating bar. A
/// pressed or disabled button sinks flat onto the glass. On a wide iPad a
/// filling button stops at 360 points, so a lone primary lands under the
/// right hand instead of stretching across the whole window.
struct BigButtonStyle: ButtonStyle {
    enum Weight { case primary, secondary }
    var weight: Weight = .primary
    /// False for a small companion button ("Back") that should take only the
    /// room its words need, leaving the rest of the bar to the main button.
    var fills = true

    func makeBody(configuration: Configuration) -> some View {
        BigButtonFace(label: configuration.label, isPressed: configuration.isPressed,
                      weight: weight, fills: fills)
    }
}

private struct BigButtonFace: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let weight: BigButtonStyle.Weight
    let fills: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.modeTint) private var tint
    @Environment(\.windowSpan) private var span

    private var primary: Bool { weight == .primary }

    // a button that can't be pressed yet goes grey, rather than staying the
    // screen's colour a little fainter, so "not yet" is unmistakable
    private var fill: Color {
        if !isEnabled { return Color.primary.opacity(0.08) }
        if primary { return tint }
        return tint.opacity(0.14)
    }

    private var ink: Color {
        if !isEnabled { return Color.secondary }
        if primary { return Color.white }
        return tint
    }

    private var edge: Color {
        if primary || !isEnabled { return Color.clear }
        return tint.opacity(0.35)
    }

    private var maxWidth: CGFloat? {
        if !fills { return nil }
        if span == .broad { return 360 }
        return CGFloat.infinity
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let plane: PopOutPlane = primary ? .hero : .raised
        let slabTint: Color? = primary && isEnabled ? tint : nil
        let sunk: Bool = isPressed || !isEnabled
        let scale: CGFloat = isPressed ? 0.97 : 1
        label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 56, maxWidth: maxWidth, minHeight: 56)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(edge, lineWidth: 1))
            .contentShape(shape)
            .scaleEffect(scale)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .popOut(plane, in: shape, tint: slabTint, pressed: sunk)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.lift)
    }
}

extension ButtonStyle where Self == BigButtonStyle {
    /// The one main button: filled with the screen's colour.
    static var bigPrimary: BigButtonStyle { BigButtonStyle() }
    /// A second choice beside the main one: the screen's colour, lightly.
    static var bigSecondary: BigButtonStyle { BigButtonStyle(weight: .secondary) }
    /// A small companion - "Back" - taking only the room its words need.
    static var bigCompanion: BigButtonStyle { BigButtonStyle(weight: .secondary, fills: false) }
}

/// The bar across the bottom of a study screen, where the thumb rests.
///
/// A floating slab of glass that stands out of the screen, holding the
/// screen's main button and, now and then, a small companion beside it.
/// Always at the bottom, so the next step is in the same place on every
/// screen. Attach it with `.studyBar { }` so the content scrolls under it; it
/// still works as the last child of a VStack.
///
/// On a wide iPad the slab hugs its buttons and sits at the trailing edge,
/// under the right hand.
struct StudyActionBar<Content: View>: View {
    private let content: Content
    @Environment(\.windowSpan) private var span

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let broad: Bool = span == .broad
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        let innerCap: CGFloat? = broad ? nil : 700
        let outerCap: CGFloat = broad ? 1000 : 700
        let side: Alignment = broad ? .trailing : .center
        VStack(spacing: 12) { content }
            .padding(12)
            .frame(maxWidth: innerCap)
            .liquidGlassPanel(cornerRadius: 28)
            .popOut(.floating, in: shape)
            .frame(maxWidth: outerCap, alignment: side)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
    }
}

/// The top of a study screen: where you are, and how far there is to go.
///
/// A thin raised slab: it stands a little out of the glass, above the
/// content that scrolls beneath it.
///
/// `status` is the one thing to read ("3 of 20"); `detail` is a quieter second
/// fact ("2 right"); the bar underneath shows the same thing as a length.
/// `accessory` is for the one small control that belongs up here - the
/// station clock, the contents button - and nothing else.
struct StudyProgressHeader<Accessory: View>: View {
    let status: String
    var detail: String?
    var fraction: Double?
    private let accessory: Accessory

    init(_ status: String, detail: String? = nil, fraction: Double? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.status = status
        self.detail = detail
        self.fraction = fraction
        self.accessory = accessory()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status)
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                accessory
            }
            if let fraction {
                ThinProgress(fraction: fraction)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 700)
        // frosted rather than glass, so the glass chips in `accessory` are
        // not glass on glass
        .background(.regularMaterial, in: shape)
        .popOut(.raised, in: shape)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
    }
}

extension StudyProgressHeader where Accessory == EmptyView {
    init(_ status: String, detail: String? = nil, fraction: Double? = nil) {
        self.init(status, detail: detail, fraction: fraction) { EmptyView() }
    }
}

/// A small grey "optional" tag, for a question the student can happily skip -
/// how sure they were, why an answer was wrong - so nobody thinks they are
/// stuck until they answer it.
struct OptionalTag: View {
    var body: some View {
        Text("optional")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

/// The end of a session: the result, large, and a line saying what it means.
///
/// The screen puts its one main button under this in a `StudyActionBar`, and
/// anything else it offers as smaller buttons below the result.
struct FinishHero<Graphic: View>: View {
    let title: String
    let message: String
    private let graphic: Graphic

    init(title: String, message: String, @ViewBuilder graphic: () -> Graphic) {
        self.title = title
        self.message = message
        self.graphic = graphic()
    }

    var body: some View {
        VStack(spacing: 16) {
            // the result stands a touch out of the screen and leans with the
            // tilt; it is not pressable, so no slab or sheen
            graphic
                .popOut(.raised, in: Circle(), cues: [.lean])
            Text(title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            if !message.isEmpty {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }
}

extension FinishHero where Graphic == FinishSymbol {
    /// A finish with a big symbol rather than a score ring.
    init(symbol: String, title: String, message: String) {
        self.init(title: title, message: message) { FinishSymbol(name: symbol) }
    }
}

/// The large symbol at the top of a finish screen.
struct FinishSymbol: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 64, weight: .semibold))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}

/// What "Check accuracy" should look at on a study screen: the instruction
/// the item was written to, and the item on screen at the moment of the tap.
struct AccuracyAsk {
    let instruction: String
    let text: () -> String?
}

/// The one "More" menu in a study screen's top corner.
///
/// Before this, each screen put its extras straight into the toolbar as bare
/// icons - Turn into, Check accuracy, Quiz me, a spoken patient - so the top
/// corner of some screens was a row of four symbols with no words. They are
/// all here now, each with its name written out. `extra` is for the screen's
/// own items and comes first; Check accuracy and Turn into follow.
private struct StudyMoreMenu<Extra: View>: ViewModifier {
    let set: StudySet
    let turnInto: Bool
    let check: AccuracyAsk?
    let extra: Extra
    @State private var turning: StudySet?
    @State private var request: AccuracyRequest?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        extra
                        if let check {
                            Button {
                                if let now = check.text(), !now.isEmpty {
                                    request = AccuracyRequest(set: set, instruction: check.instruction, text: now)
                                }
                            } label: {
                                Label("Check accuracy", systemImage: "checkmark.shield")
                            }
                        }
                        if turnInto {
                            Button { turning = set } label: {
                                Label("Turn into\u{2026}", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .accessibilityIdentifier("turnInto")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("studyMore")
                    .accessibilityHint("Other things you can do on this screen")
                }
            }
            .turnIntoPicker(for: $turning)
            .sheet(item: $request) { AccuracyCheckSheet(request: $0) }
    }
}

extension View {
    /// The study screen's "More" menu: the screen's own `extra` items, then
    /// Check accuracy (when `check` is given) and Turn into (when `turnInto`).
    func studyMoreMenu<Extra: View>(for set: StudySet, turnInto: Bool = true, check: AccuracyAsk? = nil,
                                    @ViewBuilder extra: () -> Extra) -> some View {
        modifier(StudyMoreMenu(set: set, turnInto: turnInto, check: check, extra: extra()))
    }

    /// The "More" menu with only the standard items.
    func studyMoreMenu(for set: StudySet, turnInto: Bool = true, check: AccuracyAsk? = nil) -> some View {
        studyMoreMenu(for: set, turnInto: turnInto, check: check) { EmptyView() }
    }
}
