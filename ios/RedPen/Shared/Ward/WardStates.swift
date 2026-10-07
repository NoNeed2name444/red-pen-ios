#if canImport(SwiftUI)
import SwiftUI

/// Nothing here yet: an icon square, a title, a line saying what to do, and
/// the buttons that do it.
struct WardEmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    var message: String?
    var tone: WardTone = .blue
    private let actions: Actions

    init(symbol: String, title: String, message: String? = nil, tone: WardTone = .blue,
         @ViewBuilder actions: () -> Actions) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.tone = tone
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: WardSpace.m) {
            WardIconSquare(symbol: symbol, tone: tone, size: 56)
            Text(title)
                .font(WardType.title)
                .foregroundStyle(Color.wardInk)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.wardInkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: WardSpace.s) { actions }
                .padding(.top, WardSpace.xs)
        }
        .padding(WardSpace.xl)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }
}

extension WardEmptyState where Actions == EmptyView {
    init(symbol: String, title: String, message: String? = nil, tone: WardTone = .blue) {
        self.init(symbol: symbol, title: title, message: message, tone: tone) { EmptyView() }
    }
}

/// A line of news across a screen ("Offline: changes wait for a
/// connection"), in a tone, with an optional action at its end.
struct WardBanner: View {
    var tone: WardTone = .blue
    var symbol: String = "info.circle.fill"
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous)
        HStack(alignment: .firstTextBaseline, spacing: WardSpace.s) {
            Image(systemName: symbol).foregroundStyle(tone.color).accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.wardInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.wardPrimaryInk)
            }
        }
        .padding(WardSpace.m)
        .background(tone.color.opacity(0.12), in: shape)
        .overlay(shape.strokeBorder(tone.color.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Rows on one card, each divided from the next by an inset hairline.
struct WardGroupedCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { i in
                    rows[i].padding(.horizontal, WardSpace.gutter)
                    if i < rows.count - 1 {
                        Rectangle().fill(Color.wardHairline).frame(height: 1)
                            .padding(.leading, WardSpace.gutter + 52)
                    }
                }
            }
        }
        .padding(.vertical, WardSpace.xs)
        .wardCard(padding: 0)
    }
}

/// A bar for a score: Resus Red under half, Caution Amber under three
/// quarters, Discharge Green above. The number is said, never only shown in
/// a colour.
struct WardProgressBar: View {
    let value: Double
    var label: String?

    static func tone(_ value: Double) -> WardTone {
        value < 0.5 ? .danger : value < 0.75 ? .warning : .green
    }

    var body: some View {
        let v: Double = max(0, min(1, value))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.wardHairline)
                Capsule().fill(Self.tone(v).color).frame(width: v * geo.size.width)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: v)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Score")
        .accessibilityValue("\(Int((v * 100).rounded())) percent")
    }
}

/// A white tile: the icon top left, the title and a detail line under it.
struct WardTile: View {
    let symbol: String
    var tone: WardTone = .blue
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            WardIconSquare(symbol: symbol, tone: tone, size: 36)
            Spacer(minLength: 0)
            Text(title).font(.headline).foregroundStyle(Color.wardInk).multilineTextAlignment(.leading)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(Color.wardInkSecondary).multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .wardCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// A chip that filters: Theatre Blue when on, white with a hairline when off.
struct WardFilterChip: View {
    let text: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(text)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.wardOnPrimary : Color.wardInk)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(selected ? Color.wardPrimary : Color.wardSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.wardHairline, lineWidth: 1))
            // the chip draws 36 points tall; the tap target is the full 44
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    /// A text field on Clean Sheet with a hairline edge.
    func wardField() -> some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous)
        return self
            .padding(.horizontal, WardSpace.m)
            .padding(.vertical, 10)
            .background(Color.wardSurface, in: shape)
            .overlay(shape.strokeBorder(Color.wardHairline, lineWidth: 1))
    }
}
#endif
