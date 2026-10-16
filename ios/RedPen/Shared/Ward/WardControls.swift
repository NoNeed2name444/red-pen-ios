#if canImport(SwiftUI)
import SwiftUI

/// The semantic tones a chip, an icon square or a ring can take.
/// `.blue` is the accent of the section on show (WardSection.accent), so a
/// control follows the section's hue; `.accent` is a given section's (a
/// mode's own glyph on home). There is no fixed blue: the New badge takes
/// the section's accent like everything else (the owner's rule is no blue
/// outside Questions).
enum WardTone: Equatable {
    case blue, red, green, amber, warning, danger, grey
    case accent(WardSection)

    var color: Color {
        switch self {
        case .blue: return .wardPrimaryInk
        case .accent(let section): return .wardAccent(section)
        case .red: return .wardEcg
        case .green: return .wardSuccess
        case .amber: return .wardBeam
        case .warning: return .wardWarning
        case .danger: return .wardDanger
        case .grey: return .wardInkSecondary
        }
    }

    /// Small text in this tone, on the base or in a well pressed into it
    /// (a chip, a pill). Every tone's words clear 4.5:1 there, in light and
    /// dark, with and without Increase Contrast, but Pager Amber (3.3:1 in
    /// the light scheme), so amber words read in Caution Amber; a glyph
    /// keeps the tone's own colour. WardPaletteTests holds the ratios on
    /// the well, shade included, for every ink here and every section's
    /// accent.
    var ink: Color {
        switch self {
        case .amber, .warning: return .wardWarning
        case .blue, .red, .green, .danger, .grey, .accent: return color
        }
    }
}

extension Color {
    /// A disabled control's words, glyphs and switch track: Biro Grey,
    /// solid (WardControlStates.disabledInk, the one place it is named).
    static var wardDisabledInk: Color { .ward(WardControlStates.disabledInk) }
}

/// Draws the controls inside as held, with no finger on them: the states
/// gallery (WardStatesGallery) shows each control's held look this way.
/// Every face here, and PopTileStyle's, takes it as pressed; a disabled
/// control ignores it, as it ignores a finger. Off everywhere else.
private struct WardShowsPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wardShowsPressed: Bool {
        get { self[WardShowsPressedKey.self] }
        set { self[WardShowsPressedKey.self] = newValue }
    }
}

// MARK: - Parts that can meet a page's cut

/// Where the rows and parts of a page that can meet its cut stand at rest,
/// by view (HomeFit.settledCut): a page that sets `wardPartsProbed` has each
/// `wardPart` under it report its top here, and the page moves its cut up to
/// any top that would leave a sliver over it. Only at rest: a scroll moves
/// every row each step, and must not re-run the page for it.
@MainActor
final class WardPartBook {
    static let shared = WardPartBook()

    /// The page says whether it is at rest (its list at the top, not moving).
    var atRest: @MainActor () -> Bool = { true }
    /// The page's settled cut, in the same global points as the booked tops,
    /// for the loop guard.
    var cut: Double? {
        get { ledger.cut }
        set { ledger.cut = newValue }
    }
    /// Told the sorted tops (global points) whenever they change. Installed
    /// late (the page's .task), so it is told what the book already holds
    /// the moment it arrives: an early publish is not lost.
    var changed: @MainActor ([Double]) -> Void = { _ in } {
        didSet { if !told.isEmpty { changed(told) } }
    }

    struct Part {
        var name: String
        var rect: CGRect
    }

    private var ledger = WardPartLedger<UUID>()
    private var told: [Double] = []

    /// Drops since the preview's reset: removed parts, parts kept below the cut,
    /// and the cut when the last part was kept.
    private(set) var dropsRemoved = 0
    private(set) var dropsKept = 0
    private(set) var lastKeptCut: Double?

    /// Resets drop counts for the preview push-and-back check.
    func resetDropCounts() {
        dropsRemoved = 0
        dropsKept = 0
        lastKeptCut = nil
    }

    var parts: [UUID: Part] {
        ledger.entries.mapValues { Part(name: $0.name, rect: $0.rect) }
    }

    /// One part's frame: its sighting is always recorded, and it is booked
    /// only while the page is at rest. `reach` is how far its face stands out
    /// above its frame (a row's tile).
    func set(_ id: UUID, name: String, rect: CGRect, reach: CGFloat, scale: CGFloat) {
        if ledger.set(id, name: name, rect: rect, reach: Double(reach), scale: Double(scale),
                      atRest: atRest()) {
            publish()
        }
    }

    /// Books every live sighting again once the page comes to rest.
    func rebook() {
        if ledger.rebook() {
            publish()
        }
    }

    /// A part whose view went away leaves the book.
    func drop(_ id: UUID) {
        let outcome: WardPartLedger<UUID>.Drop = ledger.drop(id, atRest: atRest())
        switch outcome {
        case .removed:
            dropsRemoved += 1
            if atRest() {
                publish()
            }
        case .kept:
            dropsKept += 1
            lastKeptCut = ledger.cut
        case .none:
            break
        }
    }

    /// A new page: what the last one held is gone.
    func clear() {
        if ledger.clear() {
            publish()
        }
    }

    private func publish() {
        let now: [Double] = ledger.tops
        guard now != told else { return }
        told = now
        changed(now)
    }
}

private struct WardPartsProbedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// A page that is moving its cut for its parts (WardPartBook).
    var wardPartsProbed: Bool {
        get { self[WardPartsProbedKey.self] }
        set { self[WardPartsProbedKey.self] = newValue }
    }
}

/// The last frame a `wardPart` saw, kept in a plain object so writing it from
/// geometry never redraws the list.
@MainActor
private final class WardPartSpot {
    var rect: CGRect?
}

private struct WardPartModifier: ViewModifier {
    let name: String
    let reach: CGFloat
    @Environment(\.wardPartsProbed) private var probed
    @Environment(\.displayScale) private var displayScale
    @State private var id = UUID()
    @State private var spot = WardPartSpot()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                spot.rect = rect
                guard probed else { return }
                WardPartBook.shared.set(id, name: name, rect: rect, reach: reach, scale: displayScale)
            }
            .onAppear {
                guard probed, let rect = spot.rect else { return }
                WardPartBook.shared.set(id, name: name, rect: rect, reach: reach, scale: displayScale)
            }
            .onDisappear { WardPartBook.shared.drop(id) }
    }
}

extension View {
    /// This view can meet the page's cut: it reports where it stands, at
    /// rest, to a page that asks (wardPartsProbed). Nothing elsewhere.
    func wardPart(_ name: String, reach: CGFloat = 0) -> some View {
        modifier(WardPartModifier(name: name, reach: reach))
    }
}

/// The buttons: soft capsules raised off the base, 56 points tall, at most
/// 360 points wide on a broad iPad. The kind shows in the label's colour
/// (the section's accent, Chart Ink, Resus Red), never a fill, and the
/// primary stands a step higher; held, a button is pressed into the base;
/// disabled, it sinks to the lowest step and says its word in Biro Grey
/// (Color.wardDisabledInk), solid, so it is told from an enabled one of any
/// kind: the owner wants nothing in the app to look faded. Compact and
/// quiet are the small 44-point ones for a card or a panel: compact says
/// its word in the accent, quiet in Chart Ink.
struct WardButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, compact, quiet }
    var kind: Kind = .primary
    var fills = true

    func makeBody(configuration: Configuration) -> some View {
        WardButtonFace(label: configuration.label, pressed: configuration.isPressed, kind: kind, fills: fills)
    }
}

private struct WardButtonFace: View {
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let kind: WardButtonStyle.Kind
    let fills: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.windowSpan) private var span
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.wardShowsPressed) private var showsPressed

    /// Held, or drawn held by the states gallery.
    private var down: Bool { pressed || showsPressed }

    private var ink: Color {
        if !enabled { return .wardDisabledInk }
        switch kind {
        case .primary, .compact: return .wardPrimaryInk
        case .secondary, .quiet: return .wardInk
        case .destructive: return .wardDanger
        }
    }
    private var font: Font {
        switch kind {
        case .primary: return .headline.weight(.bold)
        case .secondary, .destructive: return .headline
        case .compact, .quiet: return .subheadline.weight(.semibold)
        }
    }
    private var small: Bool { kind == .compact || kind == .quiet }
    private var maxWidth: CGFloat? {
        if !fills || small { return nil }
        return span == .broad ? 360 : .infinity
    }

    var body: some View {
        let compact: Bool = small
        let height: CGFloat = compact ? 44 : 56
        let shape = RoundedRectangle(cornerRadius: height / 2, style: .continuous)
        // the one main button stands a step higher than the rest
        let lift: WardLift = kind == .primary ? .high : compact ? .low : .mid
        // Small capsules offer at least the padded label's ideal width so
        // toolbar words fit inside their face; expanding labels still take
        // the full width offered by a card.
        Group {
            if compact {
                WardSmallButtonLayout { framedLabel }
            } else {
                framedLabel
            }
        }
            .background {
                // the main button's face is a tier up (a sheet's), so it
                // stands out by a shade as well as by its rim
                WardPressFace(shape: shape, lift: enabled ? lift : .low, pressed: enabled && down,
                              fill: kind == .primary && enabled ? Color.wardRaised : Color.wardSurface)
            }
            .contentShape(shape)
            .animation(reduceMotion ? nil : .wardShade(down: down), value: down)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
            .capPop(enabled && down)
    }

    private var framedLabel: some View {
        label
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(ink)
            .padding(.horizontal, small ? WardSpace.m : WardSpace.xl)
            .padding(.vertical, small ? WardSpace.s : WardSpace.m)
            .frame(minWidth: small ? 44 : 56, maxWidth: maxWidth, minHeight: small ? 44 : 56)
    }

}

private struct WardSmallButtonLayout: Layout {
    private func offer(_ proposal: ProposedViewSize, to subview: LayoutSubview) -> ProposedViewSize {
        ProposedViewSize(
            width: proposal.width.map { max($0, subview.sizeThatFits(.unspecified).width) },
            height: proposal.height
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.reduce(CGSize.zero) { size, subview in
            let child = subview.sizeThatFits(offer(proposal, to: subview))
            return CGSize(width: max(size.width, child.width), height: max(size.height, child.height))
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: offer(proposal, to: subview))
        }
    }
}

extension ButtonStyle where Self == WardButtonStyle {
    static var wardPrimary: WardButtonStyle { WardButtonStyle() }
    static var wardSecondary: WardButtonStyle { WardButtonStyle(kind: .secondary) }
    static var wardDestructive: WardButtonStyle { WardButtonStyle(kind: .destructive) }
    static var wardCompact: WardButtonStyle { WardButtonStyle(kind: .compact) }
    static var wardQuiet: WardButtonStyle { WardButtonStyle(kind: .quiet) }
}

/// A chip that is a button (Sure / Maybe / Guess, why, Flag, Hint, Timed, a
/// choice on the map): WardChip's capsule, raised just off the base, with a
/// 44-point target. Chosen, or held, it is pressed in; chosen, its words
/// take `tone` (the section's accent when it has none) and a solid edge in
/// the same colour goes round it. Disabled, its words go Biro Grey and it
/// lies low; chosen and disabled, it stays pressed in with its edge, so it
/// still reads as chosen. Never a fill.
struct WardChipButtonStyle: ButtonStyle {
    var on = false
    var tone: WardTone?

    func makeBody(configuration: Configuration) -> some View {
        WardChipButtonFace(label: configuration.label, pressed: configuration.isPressed, on: on, tone: tone)
    }
}

private struct WardChipButtonFace: View {
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let on: Bool
    let tone: WardTone?
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.wardShowsPressed) private var showsPressed

    /// The chosen colour: the tone's, or the section's accent.
    private var chosenInk: Color { tone?.ink ?? .wardPrimaryInk }

    private var ink: Color {
        if !enabled { return .wardDisabledInk }
        return on ? chosenInk : .wardInk
    }

    var body: some View {
        let held: Bool = enabled && (pressed || showsPressed)
        // chosen stays pressed in, disabled too
        let down: Bool = on || held
        label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, WardSpace.m)
            .padding(.vertical, WardSpace.s)
            .background {
                WardPressFace(shape: Capsule(), lift: .low, pressed: down)
                    .wardChosenEdge(Capsule(), on, color: chosenInk)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .wardShade(down: down), value: down)
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
            .capPop(held)
    }
}

/// The buttons of a dock, a rail and a switcher: items that sit side by
/// side on a panel, one of them chosen. They follow the states every other
/// control keeps (WardControlStates): unchosen and enabled, the words are
/// Chart Ink; chosen, they take the section's accent and the item stands
/// pressed in with a 2-point accent edge (drawn by the item, which moves one
/// hollow between them: `wardChosenEdge` on it); disabled, Biro Grey; held,
/// the item sinks into the same hollow and the whole button sinks a little
/// (CapPop), not the system's dimming a plain button gives.
struct WardItemButtonStyle<S: InsettableShape>: ButtonStyle {
    var chosen = false
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        WardItemButtonFace(label: configuration.label, pressed: configuration.isPressed, chosen: chosen, shape: shape)
    }
}

private struct WardItemButtonFace<S: InsettableShape>: View {
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let chosen: Bool
    let shape: S
    @Environment(\.isEnabled) private var enabled
    @Environment(\.wardShowsPressed) private var showsPressed

    var body: some View {
        let held: Bool = enabled && (pressed || showsPressed)
        label
            .background {
                // a chosen item already stands in its hollow
                if held && !chosen {
                    WardReliefFace(shape: shape, lift: .low, inset: true)
                        .transition(.identity)
                }
            }
            .capPop(held)
    }
}

/// A button that is a raised panel of its own (the Ideas pill, the list
/// button at the accessibility sizes): raised at rest; pressed in when
/// chosen, with the 2-point accent edge; held, it sinks.
struct WardPanelButtonStyle<S: InsettableShape>: ButtonStyle {
    var chosen = false
    var lift: WardLift = .mid
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        WardPanelButtonFace(label: configuration.label, pressed: configuration.isPressed, chosen: chosen,
                            lift: lift, shape: shape)
    }
}

private struct WardPanelButtonFace<S: InsettableShape>: View {
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let chosen: Bool
    let lift: WardLift
    let shape: S
    @Environment(\.isEnabled) private var enabled
    @Environment(\.wardShowsPressed) private var showsPressed

    var body: some View {
        let held: Bool = enabled && (pressed || showsPressed)
        label
            .background {
                WardPressFace(shape: shape, lift: enabled ? lift : .low, pressed: chosen || held)
                    .wardChosenEdge(shape, chosen)
            }
            .capPop(held)
    }
}

extension View {
    /// A chosen control's mark: a solid edge in `color` (the section's
    /// accent) round `shape`, WardControlStates.chosenEdgeWidth wide, at
    /// full strength over the face's own edge. It comes and goes at once,
    /// never fading in.
    func wardChosenEdge<S: InsettableShape>(_ shape: S, _ chosen: Bool,
                                            color: Color = .wardPrimaryInk) -> some View {
        overlay {
            if chosen {
                shape.strokeBorder(color, lineWidth: CGFloat(WardControlStates.chosenEdgeWidth))
                    .transition(.identity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A round button for a glyph (a stepper's minus and plus, a send arrow): a
/// soft circle raised off the base, 44 points across, the glyph in Chart
/// Ink. Chosen, or held, it is pressed in; chosen, the glyph takes the
/// section's accent and a solid edge in the accent goes round it.
/// Disabled, the glyph goes Biro Grey and it lies low; chosen and disabled,
/// it stays pressed in with its edge. Never a fill.
struct WardCircleButtonStyle: ButtonStyle {
    var on = false
    var lift: WardLift = .low

    func makeBody(configuration: Configuration) -> some View {
        WardCircleButtonFace(label: configuration.label, pressed: configuration.isPressed, on: on, lift: lift)
    }
}

private struct WardCircleButtonFace: View {
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let on: Bool
    let lift: WardLift
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.wardShowsPressed) private var showsPressed

    private var ink: Color {
        if !enabled { return .wardDisabledInk }
        return on ? .wardPrimaryInk : .wardInk
    }

    var body: some View {
        let held: Bool = enabled && (pressed || showsPressed)
        // chosen stays pressed in, disabled too
        let down: Bool = on || held
        label
            .font(.body.weight(.semibold))
            .foregroundStyle(ink)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                WardPressFace(shape: Circle(), lift: enabled ? lift : .low, pressed: down)
                    .wardChosenEdge(Circle(), on)
            }
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .wardShade(down: down), value: down)
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.highlight)
            .capPop(held)
    }
}

extension ButtonStyle where Self == WardCircleButtonStyle {
    static var wardCircle: WardCircleButtonStyle { WardCircleButtonStyle() }
}

/// A status chip ("Due", "New", "Weak"): the tone's words in a capsule
/// pressed into the surface, so it reads as a label, not a button.
struct WardChip: View {
    let text: String
    var tone: WardTone = .blue
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small).foregroundStyle(tone.color) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.ink)
        .padding(.horizontal, WardSpace.s)
        .padding(.vertical, WardSpace.xs)
        .wardInset(in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A countdown pill ("Finals in 23 days"): bold Caution Amber words (4.8:1
/// on the base) and a Pager Amber clock in a pressed-in capsule.
struct WardPill: View {
    let text: String
    var symbol: String? = "clock"

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small).foregroundStyle(Color.wardBeam) }
            Text(text)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.wardWarning)
        .padding(.horizontal, WardSpace.m)
        .padding(.vertical, WardSpace.s)
        .wardInset(in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// An exam timer in SF Mono: Resus Red once it is under `warnBelow`, "Time"
/// at zero; hours shown for a paper over an hour (1:05:00). `well: false`
/// drops its own well, for a pill that sits inside a button's face.
struct WardTimerPill: View {
    let seconds: Int
    var warnBelow = 60
    var well = true

    var body: some View {
        let low: Bool = seconds < warnBelow
        let h: Int = seconds / 3600
        let clock: String = h > 0 ? String(format: "%d:%02d:%02d", h, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        let text: String = seconds <= 0 ? "Time" : clock
        let label = Label(text, systemImage: "timer")
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(low ? Color.wardDanger : Color.wardInk)
        if well {
            label
                .padding(.horizontal, WardSpace.m)
                .padding(.vertical, WardSpace.s)
                .wardInset(in: Capsule())
                .contentTransition(.numericText())
        } else {
            label.contentTransition(.numericText())
        }
    }
}

/// A rounded icon square: the glyph in its tone on a soft raised square;
/// chosen, the square is pressed in and the glyph goes Theatre Blue. No ink
/// edge: the row or tile around it is what is tapped.
struct WardIconSquare: View {
    let symbol: String
    var tone: WardTone = .blue
    var size: CGFloat = 40
    var selected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(WardRadius.icon, size * 0.28), style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(selected ? Color.wardPrimaryInk : tone.color)
            .frame(width: size, height: size)
            .wardRelief(in: shape, lift: size >= 56 ? .mid : .low, pressed: selected, control: false)
            .accessibilityHidden(true)
    }
}

/// A switch in soft UI: a track pressed into the base, a raised knob, and
/// the tint in the track only when it is on. The whole row toggles it;
/// VoiceOver hears the system switch. Held, the knob sinks into the track;
/// disabled, an on-track goes Biro Grey and the knob lies flat with a thin
/// Biro Grey edge (WardControlStates), solid, never faded.
struct WardToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        WardToggleFace(configuration: configuration)
    }
}

private struct WardToggleFace: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.wardShowsPressed) private var showsPressed
    /// A finger on the row: tracked alongside the tap, never in its way.
    @GestureState private var touching = false

    var body: some View {
        let on: Bool = configuration.isOn
        // held, the knob sinks; a disabled switch ignores the finger
        let held: Bool = enabled && (touching || showsPressed)
        HStack(spacing: WardSpace.m) {
            configuration.label
                // its words go Biro Grey with the track, like every other
                // disabled control's (WardControlStates)
                .foregroundStyle(enabled ? Color.wardInk : Color.wardDisabledInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: on ? .trailing : .leading) {
                // The tint is in the track at once, solid; only the knob
                // moves. Disabled, the on-track is Biro Grey.
                Capsule()
                    .fill(enabled ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.wardDisabledInk))
                    .padding(3)
                    .animation(nil) { $0.opacity(on ? 1 : 0) }
                knob(on: on, held: held)
                    .padding(4)
            }
            .frame(width: 52, height: 32)
            .wardInset(in: Capsule(), control: true)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if enabled { configuration.isOn.toggle() }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: .infinity, maximumDistance: 16)
                .updating($touching) { pressing, state, _ in state = pressing }
        )
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: on)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }

    /// Raised off the well; over the tint its shade goes neutral, since the
    /// base's cool grey would light the blue rather than shade it. Held, it
    /// is pressed in; disabled, it lies flat, its edge in Biro Grey so it
    /// still shows on the well. One knob carries every look, so it slides
    /// across rather than fading out at one end and in at the other; the
    /// look itself changes at once.
    private func knob(on: Bool, held: Bool) -> some View {
        let flat: Bool = !enabled
        let sunk: Bool = !flat && held
        let raised: Bool = !flat && !held
        return ZStack {
            WardReliefFace(shape: Circle(), lift: .low)
                .animation(nil) { $0.opacity(raised && !on ? 1 : 0) }
            Circle()
                .fill(Color.wardSurface.shadow(.drop(color: .black.opacity(0.3), radius: 2, x: 1, y: 1.5)))
                .animation(nil) { $0.opacity(raised && on ? 1 : 0) }
            WardReliefFace(shape: Circle(), lift: .low, inset: true)
                .animation(nil) { $0.opacity(sunk ? 1 : 0) }
            Circle()
                .fill(Color.wardSurface)
                .overlay {
                    Circle().strokeBorder(Color.wardDisabledInk, lineWidth: CGFloat(WardControlStates.knobEdgeWidth))
                }
                .animation(nil) { $0.opacity(flat ? 1 : 0) }
        }
        .frame(width: 24, height: 24)
    }
}

/// The soft progress bar: the label, a groove with the tint filling it and
/// the value under it. Without a fraction it is the system's spinner;
/// VoiceOver hears the system bar.
struct WardProgressViewStyle: ProgressViewStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if let fraction = configuration.fractionCompleted {
            VStack(alignment: .leading, spacing: WardSpace.s) {
                configuration.label
                WardGroove(fraction: fraction)
                configuration.currentValueLabel
                    .font(.caption)
                    .foregroundStyle(Color.wardInkSecondary)
            }
            .accessibilityRepresentation {
                ProgressView(configuration).progressViewStyle(.linear)
            }
        } else {
            ProgressView(configuration).progressViewStyle(.circular)
        }
    }
}

/// The app's segmented control: a soft capsule raised off the base, the
/// chosen segment pressed into it with its label in the section's accent
/// and a solid edge in the accent round it. Held, a segment sinks into the
/// capsule; disabled, its words go Biro Grey (the system never dims it),
/// and the chosen one stays pressed in with its edge.
struct WardSegmented<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    let options: [Value]
    @ViewBuilder let label: (Value) -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let chosen: Bool = option == selection
                Button {
                    selection = option
                } label: {
                    label(option)
                }
                .buttonStyle(WardSegmentStyle(chosen: chosen))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(4)
        .wardRaised(in: Capsule(), lift: .low, control: true)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// One segment of WardSegmented, a Ward face rather than the system's plain
/// button, so held is a sink and disabled is Biro Grey, never dimmed.
private struct WardSegmentStyle: ButtonStyle {
    let chosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        WardSegmentFace(label: configuration.label, pressed: configuration.isPressed, chosen: chosen)
    }
}

private struct WardSegmentFace: View {
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let chosen: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.wardShowsPressed) private var showsPressed

    private var ink: Color {
        if !enabled { return .wardDisabledInk }
        return chosen ? .wardPrimaryInk : .wardInk
    }

    var body: some View {
        let held: Bool = enabled && (pressed || showsPressed)
        // chosen stays pressed in, disabled too
        let down: Bool = chosen || held
        label
            .font(.subheadline.weight(chosen ? .semibold : .regular))
            .contentTransition(.identity)
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, WardSpace.m)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background {
                // a well pressed into the capsule, there at once
                if down {
                    WardReliefFace(shape: Capsule(), lift: .low, inset: true, fill: Color.wardWell)
                        .wardChosenEdge(Capsule(), chosen)
                        .transition(.identity)
                }
            }
            .contentShape(Capsule())
            .capPop(held)
    }
}

/// A section's small-caps label, with an optional trailing link ("See all").
struct WardSectionLabel<Trailing: View>: View {
    let text: String
    private let trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(text).wardSmallCaps().accessibilityAddTraits(.isHeader)
            Spacer()
            trailing.font(.subheadline.weight(.semibold)).foregroundStyle(Color.wardPrimaryInk)
        }
    }
}

extension WardSectionLabel where Trailing == EmptyView {
    init(_ text: String) { self.init(text) { EmptyView() } }
}

/// A row: icon square, a small-caps overline ("BED 1 · Cardiology"), the
/// title, a detail line, a chip and a chevron. At the accessibility text
/// sizes the icon goes above the words and the chip under them, so the words
/// keep the row's whole width.
struct WardRow: View {
    let symbol: String
    var tone: WardTone = .blue
    var overline: String?
    let title: String
    var detail: String?
    var chip: (text: String, tone: WardTone)?
    var chevron = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                inline
            }
        }
        .padding(.vertical, WardSpace.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var inline: some View {
        HStack(spacing: WardSpace.m) {
            WardIconSquare(symbol: symbol, tone: tone)
            words
            Spacer(minLength: WardSpace.s)
            if let chip { WardChip(text: chip.text, tone: chip.tone).wardPart("the \(chip.text) chip") }
            if chevron { chevronMark }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            HStack {
                WardIconSquare(symbol: symbol, tone: tone)
                Spacer(minLength: WardSpace.s)
                if chevron { chevronMark }
            }
            words
            if let chip { WardChip(text: chip.text, tone: chip.tone).wardPart("the \(chip.text) chip") }
        }
    }

    private var words: some View {
        // 2, under the scale's 4: the home's three beds and Start ward round
        // have to end above New set
        VStack(alignment: .leading, spacing: 2) {
            if let overline { Text(overline).wardSmallCaps() }
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.wardInk)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(Color.wardInkSecondary) }
        }
        .multilineTextAlignment(.leading)
    }

    private var chevronMark: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.wardInkSecondary)
            .accessibilityHidden(true)
    }
}
#endif
