import SwiftUI

// The Ward Round question screen's pieces (docs/design/targets-2026-10-01.md
// §1): the option row, and the chart's chips, vitals grid and results table;
// its chips that are buttons are WardChipButtonStyle (WardControls). What
// each shows is decided, and tested, in ChartQuiz.

/// An answer option as a soft tile: a plain monospaced letter, then its
/// text. Chosen, the row is pressed into the base with letter and text in the
/// section's accent; once checked (the owner, 15 Oct: "the wrong should be
/// faded and what is right gets the color of the mode used"), the right one
/// is pressed in with its letter and check in the section's accent and its
/// ring in the section's ink, and a wrong pick lies flat on the faded face,
/// ringed, lettered, worded, struck and crossed in the faded ink, so it
/// reads as stepped back, never as lifted or as the right answer (the
/// owner, 16 Oct: "the faded buttons aren't distinguishable from correct
/// answers"). Crossed out, it is struck through and lies low, as
/// do the options neither picked nor right once checked: solid colours, never
/// dimmed. For the quiz and the mock paper.
struct WardOptionRow: View {
    let letter: String
    let text: String
    var mark: ChartQuiz.Mark = .idle
    var struck = false
    /// Differentiate Without Colour: the chosen edge thicker, and right and
    /// wrong said in a word beside their marks.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var noColour

    private var tone: Color? {
        switch mark {
        case .chosen, .right: return .wardPrimaryInk
        case .wrong: return .wardFadedInk
        case .idle, .past: return nil
        }
    }

    private var textInk: Color {
        switch mark {
        case .chosen: return .wardPrimaryInk
        case .wrong: return .wardFadedInk
        case .right, .idle, .past: return .wardInk
        }
    }

    private var letterInk: Color {
        tone ?? .wardInkSecondary
    }

    private var symbol: String? { mark == .right ? "checkmark.circle.fill" : (mark == .wrong ? "xmark" : nil) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.tile, style: .continuous)
        HStack(spacing: WardSpace.m) {
            Text(letter)
                .font(.callout.weight(.semibold).monospaced())
                .foregroundStyle(letterInk)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(textInk)
                .strikethrough(struck || mark == .wrong, color: mark == .wrong ? .wardFadedInk : .wardInkSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let symbol {
                if noColour {
                    Text(mark == .right ? "Right" : "Your pick")
                        .font(.caption.weight(.semibold)).foregroundStyle(letterInk).accessibilityHidden(true)
                        .transition(.identity)
                }
                Image(systemName: symbol)
                    .font(mark == .wrong ? .caption.weight(.bold) : .title3.weight(.semibold))
                    .foregroundStyle(letterInk).accessibilityHidden(true)
                    .transition(.identity)
            }
        }
        .padding(.horizontal, WardSpace.l)
        .padding(.vertical, WardSpace.l)
        .frame(minHeight: 56)
        // a wrong pick lies flat on the faded face, in the faded ink's ring,
        // not pressed in: its face is lighter than the cards at night, and a
        // rim would lift it
        .background {
            WardPressFace(shape: shape,
                          lift: mark == .wrong || ChartQuiz.liesLow(struck: struck, mark: mark) ? .low : .mid,
                          pressed: mark == .chosen || mark == .right,
                          fill: mark == .wrong ? Color.wardFaded : Color.wardSurface,
                          flat: mark == .wrong,
                          edge: mark == .wrong ? Color.wardFadedInk : nil)
        }
        // Differentiate Without Colour: the chosen one also ringed
        .overlay { if noColour && mark == .chosen { shape.strokeBorder(letterInk, lineWidth: 3).transition(.identity) } }
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
