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
}

/// The buttons: 56 points tall, 14-point corners, at most 360 points wide on
/// a broad iPad; a disabled one goes Biro Grey so "not yet" is unmistakable.
struct WardButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, compact }
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

    private var fill: Color {
        if !enabled { return Color.wardHairline }
        switch kind {
        case .primary: return .wardPrimary
        case .destructive: return .wardDanger
        case .secondary, .compact: return .wardSurface
        }
    }
    private var ink: Color {
        if !enabled { return .wardInkSecondary }
        switch kind {
        case .primary, .destructive: return .wardOnPrimary
        case .secondary, .compact: return .wardPrimaryInk
        }
    }
    private var maxWidth: CGFloat? {
        if !fills || kind == .compact { return nil }
        return span == .broad ? 360 : .infinity
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.button, style: .continuous)
        let compact: Bool = kind == .compact
        let edge: Color = (kind == .secondary || compact) && enabled ? .wardHairline : .clear
        label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(ink)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 8 : 12)
            .frame(minWidth: compact ? 44 : 56, maxWidth: maxWidth, minHeight: compact ? 44 : 56)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(edge, lineWidth: 1))
            .contentShape(shape)
            .opacity(pressed ? 0.85 : 1)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: pressed)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
    }
}

extension ButtonStyle where Self == WardButtonStyle {
    static var wardPrimary: WardButtonStyle { WardButtonStyle() }
    static var wardSecondary: WardButtonStyle { WardButtonStyle(kind: .secondary) }
    static var wardDestructive: WardButtonStyle { WardButtonStyle(kind: .destructive) }
    static var wardCompact: WardButtonStyle { WardButtonStyle(kind: .compact) }
}

/// A status chip ("Due", "New", "Weak"): the tone's colour on a 12% wash.
struct WardChip: View {
    let text: String
    var tone: WardTone = .blue
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tone.color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A countdown pill ("Finals in 23 days") in Pager Amber.
struct WardPill: View {
    let text: String
    var symbol: String? = "clock"

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.wardOnPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.wardBeam, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// An exam timer in SF Mono: Resus Red once it is under `warnBelow`, "Time"
/// at zero.
struct WardTimerPill: View {
    let seconds: Int
    var warnBelow = 60

    var body: some View {
        let low: Bool = seconds < warnBelow
        let text: String = seconds <= 0 ? "Time" : String(format: "%d:%02d", seconds / 60, seconds % 60)
        Label(text, systemImage: "timer")
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(low ? Color.wardDanger : Color.wardInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.wardSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(low ? Color.wardDanger.opacity(0.4) : Color.wardHairline, lineWidth: 1))
            .contentTransition(.numericText())
    }
}

/// A rounded icon square in a tone: the glyph in the tone on a 12% wash.
struct WardIconSquare: View {
    let symbol: String
    var tone: WardTone = .blue
    var size: CGFloat = 40
    var selected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(WardRadius.icon, size * 0.28), style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(selected ? Color.wardOnPrimary : tone.color)
            .frame(width: size, height: size)
            .background(selected ? Color.wardPrimary : tone.color.opacity(0.12), in: shape)
            .accessibilityHidden(true)
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
/// title, a detail line, a chip and a chevron.
struct WardRow: View {
    let symbol: String
    var tone: WardTone = .blue
    var overline: String?
    let title: String
    var detail: String?
    var chip: (text: String, tone: WardTone)?
    var chevron = true

    var body: some View {
        HStack(spacing: WardSpace.m) {
            WardIconSquare(symbol: symbol, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                if let overline { Text(overline).wardSmallCaps() }
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.wardInk)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(Color.wardInkSecondary) }
            }
            Spacer(minLength: WardSpace.s)
            if let chip { WardChip(text: chip.text, tone: chip.tone) }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.wardInkSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, WardSpace.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
#endif
