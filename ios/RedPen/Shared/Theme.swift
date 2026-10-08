import SwiftUI

// MARK: - Visual identity
//
// Every mode has its own glyph colour and an SF Symbol. Screens sit on the
// soft UI's one matte base (ModeBackdrop), and every surface on them is
// shaped out of it: raised to touch, pressed in when chosen. The controls on
// every screen are Theatre Blue (modeScreen).

extension StudySetKind {
    var tint: Color {
        switch self {
        // each mode's glyph in a palette tone that reads on the base
        case .mcq: return .wardPrimaryInk
        case .anki: return .wardEcg
        case .book: return .wardSuccess
        case .osce: return .wardWarning
        case .narrate: return .wardInkSecondary
        case .cases: return .wardPrimaryInk
        }
    }

    var symbol: String {
        switch self {
        case .mcq: return "checklist.checked"
        case .anki: return "rectangle.on.rectangle.angled"
        case .book: return "book.pages"
        case .osce: return "list.clipboard"
        case .narrate: return "waveform"
        case .cases: return "stethoscope"
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

/// The icon tile used on library rows and screen headers.
struct ModeTile: View {
    let kind: StudySetKind
    var size: CGFloat = 44
    /// The chosen one: pressed into the base, its glyph Theatre Blue.
    var selected = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // A soft tile raised off the base, the mode's glyph in its tone; the
    // glyph alone tells the modes apart, so no wash of colour behind it.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(WardRadius.icon, size * 0.28), style: .continuous)
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(selected ? Color.wardPrimaryInk : kind.tint)
            .frame(width: size, height: size)
            .wardRelief(in: shape, lift: size >= 56 ? .mid : .low, pressed: selected)
            .animation(reduceMotion ? nil : .wardShade(down: selected), value: selected)
            .accessibilityHidden(true)
    }
}

/// A soft coronal glow in `tint`: strongest in the middle, gone at `reach`
/// of the size. At SpaceQuality.full it breathes, 6% either way over 4 s.
struct CoronaGlow: View {
    let tint: Color
    /// Where the glow has faded out, as a fraction of the shorter side.
    var reach: CGFloat = 0.9
    /// The middle's opacity.
    var strength: Double = 0.75
    @Environment(\.spaceQuality) private var quality

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height)
            let colours: [Color] = [tint.opacity(strength), tint.opacity(strength * 0.45), tint.opacity(0)]
            let glow = RadialGradient(colors: colours, center: .center,
                                      startRadius: 0, endRadius: side * reach)
            Rectangle()
                .fill(glow)
                .modifier(CoronaBreath(breathes: quality.isFull))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CoronaBreath: ViewModifier {
    let breathes: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if breathes {
            content.phaseAnimator([false, true]) { view, out in
                view.scaleEffect(out ? 1.06 : 0.94)
            } animation: { _ in
                .easeInOut(duration: 2)
            }
        } else {
            content
        }
    }
}

/// A one-pixel photon-ring edge (the map's orange into white-gold).
enum PhotonRim {
    static var style: AngularGradient {
        let stops: [Gradient.Stop] = PhotonPalette.stops(dark: true)
        return AngularGradient(stops: stops, center: .center, angle: .degrees(-90))
    }
}

/// Each mode's screen: the soft UI's matte base.
struct ModeBackdrop: View {
    let kind: StudySetKind
    var body: some View {
        WardBackground()
    }
}

/// A content card: the reading surface each mode places its question, card
/// or page on, a soft card raised off the base. Readable things never move
/// with the pop-out; only what you can touch leans with it.
struct ContentCard: ViewModifier {
    func body(content: Content) -> some View {
        content.wardCard(padding: 18)
    }
}

extension View {
    func contentCard() -> some View { modifier(ContentCard()) }

    /// Standard chrome for a mode screen: the base under it, and Theatre
    /// Blue controls.
    func modeScreen(_ kind: StudySetKind) -> some View {
        self
            .background(ModeBackdrop(kind: kind))
            .wardControls()
            .environment(\.modeTint, Color.wardPrimaryInk)
    }

    /// Slides up and fades in on first appearance, staggered by `index` so
    /// a list of rows arrives as a cascade rather than all at once.
    func riseIn(index: Int = 0) -> some View { modifier(RiseIn(index: index)) }
}

extension View {
    func capPop(_ pressed: Bool) -> some View {
        modifier(CapPop(pressed: pressed))
    }
}

private struct CapPop: ViewModifier {
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressedAt: Date?

    func body(content: Content) -> some View {
        let releaseDelay = WardPress.releaseHold(held: pressedAt.map { Date().timeIntervalSince($0) } ?? WardPress.press)
        return content
            .scaleEffect(pressed && !reduceMotion ? WardPress.sinkScale : 1)
            .animation(reduceMotion ? nil : Animation.wardClick(down: pressed)
                .delay(pressed ? 0 : releaseDelay), value: pressed)
            .onChange(of: pressed) { _, down in
                if down {
                    pressedAt = Date()
                }
            }
    }
}

/// A tappable row that gives a touch under the finger, for our custom rows
/// (which draw their own soft tile). Reduce Motion keeps it still and only
/// dims it.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableRowFace(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct PressableRowFace<Label: View>: View {
    let label: Label
    let pressed: Bool

    var body: some View {
        label
            .opacity(pressed ? 0.9 : 1)
            .capPop(pressed)
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

/// A thin progress bar: a beam in a groove pressed into the base, so every
/// mode's progress reads the same way. It fills from the leading edge: the
/// ZStack's `.leading` is the right-hand side right to left, so Arabic
/// fills from the right with nothing more said.
struct ThinProgress: View {
    let fraction: Double

    var body: some View {
        WardGroove(fraction: fraction, tint: .wardBeam, height: 6)
            .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// The animated score ring on the results screens: a Theatre Blue arc in a
/// groove pressed into the base. It reports its score upwards
/// (FinishScoreKey) so a finish around it can celebrate.
struct ScoreRing: View {
    let fraction: Double
    let label: String
    let sublabel: String
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // kept in from the frame's edge, where the finish's raised disc
        // behind it curves away: the groove sits on its flat face
        ZStack {
            WardReliefFace(shape: WardAnnulus(width: 12), lift: .low, inset: true)
                .padding(10)
            Circle()
                .trim(from: 0, to: max(0, min(1, shown)))
                .stroke(Color.wardPrimaryInk, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // clockwise from the top, anticlockwise right to left
                .fillsFromLeading()
                .padding(16)
            VStack(spacing: 2) {
                // digits that roll rather than blink when the label changes,
                // and that keep their width while they do
                Text(label).scaledFont(38, relativeTo: .largeTitle, weight: .semibold, design: .monospaced, maxSize: 52)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(sublabel).font(.footnote.weight(.medium)).foregroundStyle(Color.wardInkSecondary)
            }
        }
        .frame(width: 168, height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(sublabel)")
        .preference(key: FinishScoreKey.self, value: fraction)
        .onAppear {
            if reduceMotion {
                shown = fraction
            } else {
                withAnimation(.spring(response: 1.1, dampingFraction: 0.72)) { shown = fraction }
            }
        }
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
    static let defaultValue: Color = .wardPrimaryInk
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
// Quiz, cards, OSCE, textbook and narrate all used to arrange
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
/// second choice sitting beside the main one - "Start over" next to "I got it",
/// "Back" next to "Next" - so there is never any doubt which is the main one.
///
/// Depth: every button is raised off the base and pressed in while held;
/// the primary stands a step higher and says itself in Theatre Blue. A
/// disabled one sinks low and fades. On a wide iPad a filling button stops
/// at 360 points, so a lone primary lands under the right hand instead of
/// stretching across the whole window.
struct BigButtonStyle: ButtonStyle {
    enum Weight { case primary, secondary }
    var weight: Weight = .primary
    /// False for a small companion button ("Back") that should take only the
    /// room its words need, leaving the rest of the bar to the main button.
    var fills = true

    func makeBody(configuration: Configuration) -> some View {
        WardButtonStyle(kind: weight == .primary ? .primary : .secondary, fills: fills)
            .makeBody(configuration: configuration)
    }
}

extension ButtonStyle where Self == BigButtonStyle {
    /// The one main button: raised highest, its words in Theatre Blue.
    static var bigPrimary: BigButtonStyle { BigButtonStyle() }
    /// A second choice beside the main one: raised, its words in ink.
    static var bigSecondary: BigButtonStyle { BigButtonStyle(weight: .secondary) }
    /// A small companion - "Back" - taking only the room its words need.
    static var bigCompanion: BigButtonStyle { BigButtonStyle(weight: .secondary, fills: false) }
}

/// The bar across the bottom of a study screen, where the thumb rests.
///
/// A soft slab raised high off the base, holding the screen's main button
/// and, now and then, a small companion beside it.
/// Always at the bottom, so the next step is in the same place on every
/// screen. Attach it with `.studyBar { }` so the content scrolls under it; it
/// still works as the last child of a VStack.
///
/// On a wide iPad the slab hugs its buttons and sits at the trailing edge,
/// under the right hand (the left hand, right to left: `.trailing` turns
/// round with the language, as the buttons' order in it does).
struct StudyActionBar<Content: View>: View {
    private let content: Content
    @Environment(\.windowSpan) private var span

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let broad: Bool = span == .broad
        let shape = RoundedRectangle(cornerRadius: WardRadius.bar, style: .continuous)
        let innerCap: CGFloat? = broad ? nil : 700
        let outerCap: CGFloat = broad ? 1000 : 700
        let side: Alignment = broad ? .trailing : .center
        VStack(spacing: 12) { content }
            .padding(12)
            .frame(maxWidth: innerCap)
            .wardRaised(in: shape, lift: .high)
            .frame(maxWidth: outerCap, alignment: side)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
    }
}

/// The top of a study screen: where you are, and how far there is to go.
///
/// A thin soft slab, raised a little off the base above the content that
/// scrolls beneath it.
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
                            .foregroundStyle(Color.wardInkSecondary)
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
        .wardRaised(in: shape, lift: .low)
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
            .foregroundStyle(Color.wardInkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .wardInset(in: Capsule())
    }
}

/// The end of a session: the result, large, and a line saying what it means.
///
/// The screen puts its one main button under this in a `StudyActionBar`, and
/// anything else it offers as smaller buttons below the result.
///
/// A finished session (a score, from `score:` or from a ScoreRing inside the
/// graphic, or the "done" seal) plays the session-complete cue once; a strong
/// one (80% or more) raises a short aurora across the top. Neither ever
/// delays the button under it.
struct FinishHero<Graphic: View>: View {
    let title: String
    let message: String
    /// 0...1 when the session had a score.
    let score: Double?
    /// Whether this finish is a session completed (rather than an empty
    /// state), when there is no score to say so.
    let completes: Bool
    private let graphic: Graphic

    @State private var celebrated = false

    init(title: String, message: String, score: Double? = nil, @ViewBuilder graphic: () -> Graphic) {
        self.title = title
        self.message = message
        self.score = score
        self.completes = score != nil
        self.graphic = graphic()
    }

    fileprivate init(title: String, message: String, score: Double?, completes: Bool, graphic: Graphic) {
        self.title = title
        self.message = message
        self.score = score
        self.completes = completes || score != nil
        self.graphic = graphic
    }

    var body: some View {
        VStack(spacing: 16) {
            // the result stands on a soft disc raised off the base, and leans
            // with the tilt
            graphic
                .popOut(.raised, in: Circle(), cues: [.lean, .edge])
            Text(title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if !message.isEmpty {
                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.wardInkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        // a ScoreRing inside reports its score upwards (FinishScoreKey)
        .backgroundPreferenceValue(FinishScoreKey.self, alignment: .top) { reported in
            let result: Double? = score ?? reported
            let strong: Bool = (result ?? 0) >= 0.8
            let done: Bool = completes || result != nil
            FinishCelebration(strong: strong, completes: done, celebrated: $celebrated)
        }
    }
}

/// Behind a finish: the aurora when it was strong, and the session-complete
/// cue, once.
private struct FinishCelebration: View {
    let strong: Bool
    let completes: Bool
    @Binding var celebrated: Bool

    var body: some View {
        ZStack(alignment: .top) {
            if strong {
                AuroraCurtain()
                    .frame(height: 190)
                    .padding(.horizontal, -18)
                    .offset(y: -18)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .onAppear { if completes { celebrate() } }
        .onChange(of: completes) { _, now in
            if now { celebrate() }
        }
    }

    private func celebrate() {
        guard !celebrated else { return }
        celebrated = true
        SpaceFeedback.play(.complete)
    }
}

extension FinishHero where Graphic == FinishSymbol {
    /// A finish with a big symbol rather than a score ring. The "done" seal
    /// counts as a completed session.
    init(symbol: String, title: String, message: String, score: Double? = nil) {
        let done: Bool = symbol == "checkmark.seal.fill"
        self.init(title: title, message: message, score: score, completes: done,
                  graphic: FinishSymbol(name: symbol))
    }
}

/// The large symbol at the top of a finish screen, in the middle of the
/// raised disc the finish stands it on.
struct FinishSymbol: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .scaledFont(64, relativeTo: .largeTitle, weight: .semibold, maxSize: 96)
            .foregroundStyle(.tint)
            .frame(width: 128, height: 128)
            .accessibilityHidden(true)
    }
}

/// What "Check accuracy" should look at on a study screen: the instruction
/// the item was written to, and the item on screen at the moment of the tap.
struct AccuracyAsk {
    let instruction: String
    let text: () -> String?
    /// The item on screen as the accuracy engine reads it, for Report a
    /// problem; nil falls back to `text`. Unlike `text` it may be given
    /// before an answer is checked: a report shows nothing.
    var item: (() -> AccuracyItem?)?

    init(instruction: String, item: (() -> AccuracyItem?)? = nil, text: @escaping () -> String?) {
        self.instruction = instruction
        self.item = item
        self.text = text
    }

    /// What Report a problem sends: the structured item, else the text on
    /// screen, else the set itself by name.
    func reportItem(in set: StudySet) -> AccuracyItem {
        if let made = item?() { return made }
        let shown: String = text() ?? ""
        let body: String = shown.isEmpty ? "Set: " + set.name : shown
        return AccuracyItem(id: set.id.uuidString, kind: .fact, text: body)
    }
}

/// An item whose verification is being shown.
struct VerifyingItem: Identifiable {
    let id = UUID()
    let item: AccuracyItem
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
    /// Offers the Ward pocket (lab values, calculators, scores); not in a
    /// timed paper.
    var pocket: Bool = true
    let extra: Extra
    @State private var turning: StudySet?
    @State private var showingPocket = false
    /// The item whose verification is shown (AccuracyWhySheet).
    @State private var verifying: VerifyingItem?
    @State private var reporting: QuestionReport?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        extra
                        if let check {
                            Button {
                                // offered once the item is answered (text() is nil
                                // before): the checkers' verdict can show the key
                                if let now = check.text(), !now.isEmpty {
                                    verifying = VerifyingItem(item: check.reportItem(in: set))
                                }
                            } label: {
                                Label("Check accuracy", systemImage: "checkmark.shield")
                            }
                            Button {
                                reporting = QuestionReport(set: set, item: check.reportItem(in: set))
                            } label: {
                                Label("Report a problem", systemImage: "flag")
                            }
                            .accessibilityIdentifier("reportProblem")
                        }
                        if turnInto {
                            Button { turning = set; StudyTips.used(.turnInto) } label: {
                                Label("Turn into\u{2026}", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .accessibilityIdentifier("turnInto")
                        }
                        if pocket {
                            Button { showingPocket = true } label: {
                                Label("Ward pocket", systemImage: "cross.case")
                            }
                            .accessibilityIdentifier("wardPocket")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("studyMore")
                    .accessibilityHint("Other things you can do on this screen")
                    // once, when study screens are familiar (StudyTips)
                    .studyTip(.turnInto, when: turnInto)
                }
            }
            .tipSighting(.study)
            .turnIntoPicker(for: $turning)
            // the verification layer's verdict on it: rules, the checkers'
            // votes, the literature, the fix - checked now if it never was
            .sheet(item: $verifying) { AccuracyWhySheet(item: $0.item, checksWhenUnchecked: true) }
            .sheet(item: $reporting) { QuestionReportSheet(report: $0) }
            .sheet(isPresented: $showingPocket) { WardPocketSheet() }
    }
}

extension View {
    /// The study screen's "More" menu: the screen's own `extra` items, then
    /// Check accuracy (when `check` is given), Turn into (when `turnInto`)
    /// and the Ward pocket (unless `pocket` is false).
    func studyMoreMenu<Extra: View>(for set: StudySet, turnInto: Bool = true, check: AccuracyAsk? = nil,
                                    pocket: Bool = true, @ViewBuilder extra: () -> Extra) -> some View {
        modifier(StudyMoreMenu(set: set, turnInto: turnInto, check: check, pocket: pocket, extra: extra()))
    }

    /// The "More" menu with only the standard items.
    func studyMoreMenu(for set: StudySet, turnInto: Bool = true, check: AccuracyAsk? = nil) -> some View {
        studyMoreMenu(for: set, turnInto: turnInto, check: check) { EmptyView() }
    }
}
