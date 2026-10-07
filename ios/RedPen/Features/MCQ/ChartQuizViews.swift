import SwiftUI

// The Ward Round question screen's pieces (docs/design/targets-2026-10-01.md
// §1): the option row, and the chart's chips, vitals grid and results table;
// its chips that are buttons are WardChipButtonStyle (WardControls). What
// each shows is decided, and tested, in ChartQuiz.

/// An answer option as a soft row: its letter in a small well, then its
/// text. Chosen, the row is pressed into the base with its letter in Theatre
/// Blue; once checked, the right one is pressed in with a Discharge Green
/// letter and check, a wrong pick with a Resus Red letter and cross - the
/// colour on the letter and the mark only. Crossed out, it is struck through
/// and dimmed. For the quiz and the mock paper.
struct WardOptionRow: View {
    let letter: String
    let text: String
    var mark: ChartQuiz.Mark = .idle
    var struck = false
    @ScaledMetric(relativeTo: .body) private var badge: CGFloat = 32

    private var tone: Color? {
        switch mark {
        case .chosen: return .wardPrimaryInk
        case .right: return .wardSuccess
        case .wrong: return .wardDanger
        case .idle, .past: return nil
        }
    }

    private var letterInk: Color {
        if let tone { return tone }
        return mark == .past ? .wardInkSecondary : .wardInk
    }

    private var symbol: String? { mark == .right ? "checkmark.circle.fill" : (mark == .wrong ? "xmark.circle.fill" : nil) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.button, style: .continuous)
        HStack(spacing: WardSpace.m) {
            Text(letter)
                .font(.body.weight(.bold).monospaced())
                .foregroundStyle(letterInk)
                .frame(width: badge, height: badge)
                .wardInset(in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(mark == .past ? Color.wardInkSecondary : Color.wardInk)
                .strikethrough(struck, color: .wardInkSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let symbol {
                Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(letterInk).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .wardRelief(in: shape, lift: .mid, pressed: tone != nil)
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
