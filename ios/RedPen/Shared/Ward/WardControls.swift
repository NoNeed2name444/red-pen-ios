#if canImport(SwiftUI)
import SwiftUI

/// The semantic tones a chip, an icon square or a ring can take.
enum WardTone {
    case blue, red, green, amber, warning, danger, grey

    var color: Color {
        switch self {
        case .blue: return .wardPrimaryInk
        case .red: return .wardEcg
        case .green: return .wardSuccess
        case .amber: return .wardBeam
        case .warning: return .wardWarning
        case .danger: return .wardDanger
        case .grey: return .wardInkSecondary
        }
    }

    /// Small text in this tone, on the base or in a well pressed into it.
    /// Every tone clears 4.5:1 there but Pager Amber (3.3:1 in the light
    /// scheme), so amber words read in Caution Amber; a glyph keeps the
    /// tone's own colour.
    var ink: Color {
        switch self {
        case .amber, .warning: return .wardWarning
        case .blue, .red, .green, .danger, .grey: return color
        }
    }
}

/// The buttons: soft capsules raised off the base, 56 points tall, at most
/// 360 points wide on a broad iPad. The kind shows in the label's colour
/// (Theatre Blue, Chart Ink, Resus Red), never a fill, and the primary
/// stands a step higher; held, a button is pressed into the base; disabled,
/// it sinks to the lowest step and says its word in Chart Ink, as solid as
/// any other button: the owner wants nothing in the app to look faded.
/// Compact and quiet are the small 44-point ones for a card or a panel:
/// compact says its word in Theatre Blue, quiet in Chart Ink.
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

    private var ink: Color {
        if !enabled { return .wardInk }
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
                WardPressFace(shape: shape, lift: enabled ? lift : .low, pressed: enabled && pressed)
            }
            .contentShape(shape)
            .animation(reduceMotion ? nil : .wardShade(down: pressed), value: pressed)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
            .capPop(pressed)
    }

    private var framedLabel: some View {
        label
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(ink)
            .padding(.horizontal, small ? 14 : 20)
            .padding(.vertical, small ? 8 : 12)
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
/// take `tone` (Theatre Blue when it has none). Never a fill.
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

    private var ink: Color {
        if !enabled { return .wardInk }
        if on { return tone?.ink ?? .wardPrimaryInk }
        return .wardInk
    }

    var body: some View {
        let down: Bool = on || pressed
        label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                WardPressFace(shape: Capsule(), lift: .low, pressed: enabled && down)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .wardShade(down: down), value: down)
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
            .capPop(pressed)
    }
}

/// A round button for a glyph (a stepper's minus and plus, a send arrow): a
/// soft circle raised off the base, 44 points across, the glyph in Chart
/// Ink. Chosen, or held, it is pressed in a lift nearer the base; chosen,
/// the glyph is Theatre Blue. Never a fill.
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

    private var ink: Color {
        if !enabled { return .wardInk }
        if on { return .wardPrimaryInk }
        return .wardInk
    }

    var body: some View {
        let down: Bool = on || pressed
        label
            .font(.body.weight(.semibold))
            .foregroundStyle(ink)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                WardPressFace(shape: Circle(), lift: enabled ? lift : .low, pressed: enabled && down)
            }
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .wardShade(down: down), value: down)
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.highlight)
            .capPop(pressed)
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
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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
/// VoiceOver hears the system switch.
struct WardToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        WardToggleFace(configuration: configuration)
    }
}

private struct WardToggleFace: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let on: Bool = configuration.isOn
        HStack(spacing: WardSpace.m) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: on ? .trailing : .leading) {
                // The tint is in the track at once, solid; only the knob
                // moves.
                Capsule()
                    .fill(.tint)
                    .padding(3)
                    .animation(nil) { $0.opacity(on ? 1 : 0) }
                knob(on: on)
                    .padding(4)
            }
            .frame(width: 52, height: 32)
            .wardInset(in: Capsule(), control: true)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if enabled { configuration.isOn.toggle() }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: on)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }

    /// Raised off the well; over the tint its shade goes neutral, since the
    /// base's cool grey would light the blue rather than shade it. One knob
    /// carries both looks, so it slides across rather than fading out at one
    /// end and in at the other; the look itself changes at once.
    private func knob(on: Bool) -> some View {
        ZStack {
            WardReliefFace(shape: Circle(), lift: .low)
                .animation(nil) { $0.opacity(on ? 0 : 1) }
            Circle()
                .fill(Color.wardSurface.shadow(.drop(color: .black.opacity(0.3), radius: 2, x: 1, y: 1.5)))
                .animation(nil) { $0.opacity(on ? 1 : 0) }
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
            VStack(alignment: .leading, spacing: 6) {
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
/// chosen segment pressed into it with its label in Theatre Blue.
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
                        .font(.subheadline.weight(chosen ? .semibold : .regular))
                        .contentTransition(.identity)
                        .foregroundStyle(chosen ? Color.wardPrimaryInk : Color.wardInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if chosen { WardReliefFace(shape: Capsule(), lift: .low, inset: true).transition(.identity) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(4)
        .wardRaised(in: Capsule(), lift: .low, control: true)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
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
            if let chip { WardChip(text: chip.text, tone: chip.tone) }
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
            if let chip { WardChip(text: chip.text, tone: chip.tone) }
        }
    }

    private var words: some View {
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
