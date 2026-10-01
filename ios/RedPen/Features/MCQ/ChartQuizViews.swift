import SwiftUI

// The Ward Round question screen's pieces (docs/design/targets-2026-10-01.md
// §1): chips that are buttons, the option row, and the chart's chips, vitals
// grid and results table. What each shows is decided, and tested, in ChartQuiz.

/// A chip that is a button (Sure / Maybe / Guess, why, Flag, Hint, Timed):
/// WardChip's capsule with a 44-point target. Chosen, it fills Theatre Blue,
/// or lights in `tone` when it has one.
struct WardChipButtonStyle: ButtonStyle {
    var on = false
    var tone: WardTone?

    private var ink: Color { on ? (tone?.color ?? .wardOnPrimary) : .wardInk }
    private var fill: Color { on ? (tone?.color.opacity(0.14) ?? .wardPrimary) : Color.wardInkSecondary.opacity(0.10) }

    func makeBody(configuration: Configuration) -> some View {
        let pressed: Bool = configuration.isPressed
        return configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(fill, in: Capsule())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.96 : 1)
            .opacity(pressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: pressed)
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
    }
}

/// An answer option as a rounded row: its letter in a circle, then its text.
/// Chosen, Theatre Blue; once checked, the right one Discharge Green with a
/// check and a wrong pick Resus Red with a cross. Crossed out, it is struck
/// through and dimmed. For the quiz and the mock paper.
struct WardOptionRow: View {
    let letter: String
    let text: String
    var mark: ChartQuiz.Mark = .idle
    var struck = false
    @ScaledMetric(relativeTo: .body) private var badge: CGFloat = 32

    private var tone: Color? {
        switch mark {
        case .chosen: return .wardPrimary
        case .right: return .wardSuccess
        case .wrong: return .wardDanger
        case .idle, .past: return nil
        }
    }

    /// On green and red the surface colour reads in light and dark alike.
    private var letterInk: Color {
        switch mark {
        case .chosen: return .wardOnPrimary
        case .right, .wrong: return .wardSurface
        case .idle: return .wardInk
        case .past: return .wardInkSecondary
        }
    }

    private var symbol: String? { mark == .right ? "checkmark.circle.fill" : (mark == .wrong ? "xmark.circle.fill" : nil) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.button, style: .continuous)
        let edge: Color = tone ?? .wardHairline
        let wash: Color = (tone ?? Color.clear).opacity(0.10)
        HStack(spacing: WardSpace.m) {
            Text(letter)
                .font(.body.weight(.bold).monospaced())
                .foregroundStyle(letterInk)
                .frame(width: badge, height: badge)
                .background(tone ?? Color.wardInkSecondary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(mark == .past ? Color.wardInkSecondary : Color.wardInk)
                .strikethrough(struck, color: .wardInkSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let symbol {
                Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(edge).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .background(wash, in: shape)
        .background(Color.wardSurface, in: shape)
        .overlay(shape.strokeBorder(edge, lineWidth: tone == nil ? 1 : 1.5))
        .wardShadow()
        .opacity(ChartQuiz.faded(struck: struck, mark: mark) ? 0.45 : 1)
    }
}

/// Who the patient is - "34 y", "Male", "3 wk" - in a row, or stacked when
/// large text leaves no room for one.
struct ChartChipsRow: View {
    let chips: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WardSpace.s) { items }
            VStack(alignment: .leading, spacing: WardSpace.xs) { items }
        }
        .accessibilityElement(children: .combine)
    }

    private var items: some View {
        ForEach(chips, id: \.self) { chip in WardChip(text: chip, tone: .grey) }
    }
}

/// The vital signs as observations (ObsValue) on a Ward White panel: SF Mono
/// values, one high or low in Resus Red with its arrow.
struct ChartVitalsGrid: View {
    let vitals: [PatientChart.Vital]
    @ScaledMetric(relativeTo: .body) private var column: CGFloat = 92

    var body: some View {
        let columns: [GridItem] = [GridItem(.adaptive(minimum: column), spacing: WardSpace.m, alignment: .topLeading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: WardSpace.m) {
            ForEach(vitals.indices, id: \.self) { i in
                let flag: ObsValue.Flag? = vitals[i].flag.map { $0 == .high ? ObsValue.Flag.high : .low }
                ObsValue(label: vitals[i].label, value: vitals[i].value, flag: flag)
                    .accessibilityLabel(ChartQuiz.spoken(vitals[i]))
            }
        }
        .padding(WardSpace.m)
        .background(Color.wardBackground, in: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous))
    }
}

/// The results as a monospaced table - name, value, unit, H or L - with a
/// flagged value and its letter in Resus Red. Each row is read whole.
struct ChartLabsTable: View {
    let labs: [PatientChart.Lab]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: WardSpace.m, verticalSpacing: WardSpace.s) {
            ForEach(labs.indices, id: \.self) { i in row(labs[i]) }
        }
        .font(.system(.subheadline, design: .monospaced))
        .padding(WardSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wardBackground, in: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous))
    }

    private func row(_ lab: PatientChart.Lab) -> some View {
        let value: Color = ChartQuiz.tone(lab.flag) == .danger ? .wardDanger : .wardInk
        return GridRow {
            Text(lab.name).foregroundStyle(Color.wardInk).accessibilityLabel(ChartQuiz.spoken(lab))
            Text(lab.value).fontWeight(.semibold).foregroundStyle(value)
                .gridColumnAlignment(.trailing).accessibilityHidden(true)
            Text(lab.unit).foregroundStyle(Color.wardInkSecondary).accessibilityHidden(true)
            Text(lab.flag?.rawValue ?? "").fontWeight(.bold).foregroundStyle(Color.wardDanger).accessibilityHidden(true)
        }
    }
}
