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

    /// Words are ink (the owner, 23 Oct, D1); a wrong pick's are the faded ink.
    private var textInk: Color {
        switch mark {
        case .wrong: return .wardFadedInk
        case .chosen, .right, .idle, .past: return .wardInk
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
                .font(WardType.face(.callout, weight: .semibold).monospaced())
                .foregroundStyle(letterInk)
                .accessibilityHidden(true)
            Text(text)
                .font(WardType.face(.callout, weight: .regular))
                .foregroundStyle(textInk)
                .strikethrough(struck || mark == .wrong, color: mark == .wrong ? .wardFadedInk : .wardInkSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let symbol {
                if noColour {
                    Text(mark == .right ? "Right" : "Your pick")
                        .font(WardType.face(.caption, weight: .semibold)).foregroundStyle(textInk).accessibilityHidden(true)
                        .transition(.identity)
                }
                Image(systemName: symbol)
                    .font(mark == .wrong ? WardType.face(.caption, weight: .bold) : WardType.face(.title3, weight: .semibold))
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
    @Environment(\.wardModeWash) private var modeWash

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
        // over a mode's wash, see-through: one tone with the ground
        .background(modeWash == nil ? Color.wardBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous))
    }
}

/// The results as a monospaced table - name, value, unit, H or L - with a
/// flagged value and its letter in Resus Red. Each result is built as one
/// accessibility element (`.combine` and a label), read as ChartQuiz.spoken
/// says it: in the wide layout the first cell carries them and the other three
/// cells are hidden (`spokenRow`); in the narrow one the stacked VStack carries
/// them (`combined`). The same two modifiers on the GridRow itself, which the
/// T0241 probe calls "V3", gave four nodes on a Mac, one per cell (see
/// `present`).
/// Until T0249 one `.ignore` element round the whole table read it all, the
/// name cell drew only "Albumin" and the default-size audit flagged that cell,
/// "Text clipped" and "Dynamic Type font sizes are partially unsupported", in
/// all 6 probe passes of runs 43134634665 and 43101491081.
/// When large text leaves the four columns no room, each result is stacked:
/// its name, then its value, unit and flag, as ChartChipsRow stacks its chips
/// (the default-size audit, run 42076348385, found "Albumin" cut in its
/// column at larger sizes).
struct ChartLabsTable: View {
    let labs: [PatientChart.Lab]
    @Environment(\.wardModeWash) private var modeWash

    /// A normal launch has no variant and draws `present`. A probe launch
    /// (`-a11yProbeLabs`, Shared/A11yProbeLabs.swift; T0241) draws another
    /// accessibility shape of the same table, to see which one the audit leaves
    /// unflagged.
    var body: some View {
        if let variant = A11yProbeLabs.variant {
            probe(variant)
        } else {
            present
        }
    }

    /// What a normal launch draws: one spoken line per result
    /// (`ChartQuiz.spoken`), as one accessibility element. In the wide layout
    /// that is `spokenRow`, which labels the first cell and hides the other
    /// three; in the narrow one it is `combined` on the stacked result.
    /// Until T0256 the wide layout put `combined` on the GridRow, the shape the
    /// T0241 probe (Shared/A11yProbeLabs.swift) calls V3. Its Mac run (App
    /// build only_a11y, run 43330961262 on a361a2a5, one lab in the quiz)
    /// showed four staticText nodes, one per cell, each labelled "Albumin 22
    /// g/L, low", and 108 nodes against 105 for V6, which draws one Text per
    /// result; it also flagged one "Text clipped, no element" (issues=1). That
    /// run measured the wide layout only (the four frames share one y); the
    /// narrow layout was not measured.
    /// The `spokenRow` shape has not run on a Mac yet. The same run's V1 (name
    /// cell labelled, the other three hidden, no `.combine`) gave 105 nodes and
    /// 3 issues.
    private var present: some View {
        dressed(ViewThatFits(in: .horizontal) {
            gridOf { spokenRow($0) }
            stackOf { combined(stacked($0), $0) }
        })
    }

    /// One result in the wide layout, as `row` draws it (the same four cells,
    /// fonts, colours and column alignment) with one accessibility element:
    /// the first cell is `combined`, so it carries the spoken label, and the
    /// other three are hidden so they add no node of their own. The modifiers
    /// sit on the cells, not on the GridRow (see `combined`). The value cell
    /// keeps `.gridColumnAlignment` as its last modifier, as `row` has it.
    private func spokenRow(_ lab: PatientChart.Lab) -> some View {
        let value: Color = ChartQuiz.tone(lab.flag) == .danger ? .wardDanger : .wardInk
        return GridRow {
            combined(Text(lab.name).foregroundStyle(Color.wardInk), lab)
            Text(lab.value).fontWeight(.semibold).foregroundStyle(value)
                .accessibilityHidden(true)
                .gridColumnAlignment(.trailing)
            Text(lab.unit).foregroundStyle(Color.wardInkSecondary).accessibilityHidden(true)
            Text(lab.flag?.rawValue ?? "").fontWeight(.bold).foregroundStyle(Color.wardDanger).accessibilityHidden(true)
        }
    }

    private func row(_ lab: PatientChart.Lab) -> some View {
        let value: Color = ChartQuiz.tone(lab.flag) == .danger ? .wardDanger : .wardInk
        return GridRow {
            Text(lab.name).foregroundStyle(Color.wardInk)
            Text(lab.value).fontWeight(.semibold).foregroundStyle(value)
                .gridColumnAlignment(.trailing)
            Text(lab.unit).foregroundStyle(Color.wardInkSecondary)
            Text(lab.flag?.rawValue ?? "").fontWeight(.bold).foregroundStyle(Color.wardDanger)
        }
    }

    /// One result stacked, its words wrapping rather than cut: the name,
    /// then the value, unit and flag.
    private func stacked(_ lab: PatientChart.Lab) -> some View {
        let value: Color = ChartQuiz.tone(lab.flag) == .danger ? .wardDanger : .wardInk
        return VStack(alignment: .leading, spacing: WardSpace.xs) {
            Text(lab.name).foregroundStyle(Color.wardInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: WardSpace.s) {
                // the value and flag are never squeezed: the unit takes the wrap
                Text(lab.value).fontWeight(.semibold).foregroundStyle(value)
                    .fixedSize()
                Text(lab.unit).foregroundStyle(Color.wardInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lab.flag?.rawValue ?? "").fontWeight(.bold).foregroundStyle(Color.wardDanger)
                    .fixedSize()
            }
        }
    }

    // MARK: - The probe's shapes (T0241)
    //
    // Reached only when a launch passes `-a11yProbeLabs <name>`. Each changes
    // accessibility modifiers, the table's child structure or its font's weight
    // from V0 (`present`, above); none changes a word, a colour or a space.

    /// What every shape shares, as `present` has it: font, padding, full width
    /// and the ground.
    private func dressed<Content: View>(_ content: Content,
                                        font: Font = WardType.mono(.subheadline, weight: .regular)) -> some View {
        content
            .font(font)
            .padding(WardSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            // over a mode's wash, see-through: one tone with the ground
            .background(modeWash == nil ? Color.wardBackground : Color.clear,
                        in: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous))
    }

    private func gridOf<Cell: View>(_ cell: @escaping (PatientChart.Lab) -> Cell) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: WardSpace.m, verticalSpacing: WardSpace.s) {
            ForEach(labs.indices, id: \.self) { i in cell(labs[i]) }
        }
    }

    private func stackOf<Cell: View>(_ cell: @escaping (PatientChart.Lab) -> Cell) -> some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            ForEach(labs.indices, id: \.self) { i in cell(labs[i]) }
        }
    }

    /// Both layouts, each result drawn by `row` and `stacked`, as V0 draws them.
    private var plainBoth: some View {
        ViewThatFits(in: .horizontal) {
            gridOf { row($0) }
            stackOf { stacked($0) }
        }
    }

    /// V0's one label: every result as ChartQuiz.spoken says it.
    private var spokenAll: String { labs.map { ChartQuiz.spoken($0) }.joined(separator: ". ") }

    /// V1's grid row, as it was before T0223: the name cell carries the
    /// result's spoken words and the other three cells are hidden.
    private func rowNamed(_ lab: PatientChart.Lab) -> some View {
        let value: Color = ChartQuiz.tone(lab.flag) == .danger ? .wardDanger : .wardInk
        return GridRow {
            Text(lab.name).foregroundStyle(Color.wardInk).accessibilityLabel(ChartQuiz.spoken(lab))
            Text(lab.value).fontWeight(.semibold).foregroundStyle(value)
                .gridColumnAlignment(.trailing).accessibilityHidden(true)
            Text(lab.unit).foregroundStyle(Color.wardInkSecondary).accessibilityHidden(true)
            Text(lab.flag?.rawValue ?? "").fontWeight(.bold).foregroundStyle(Color.wardDanger).accessibilityHidden(true)
        }
    }

    /// V1's stacked result, as it was before T0223: one `.ignore` element.
    private func stackedWhole(_ lab: PatientChart.Lab) -> some View {
        stacked(lab).accessibilityElement(children: .ignore).accessibilityLabel(ChartQuiz.spoken(lab))
    }

    /// A result's part as one element: `.combine` and the spoken label. On a
    /// GridRow, the Mac run described at `present` showed four nodes, one per
    /// cell, each labelled with the whole result. So `present` no longer calls
    /// this on a GridRow: `spokenRow` calls it on the first cell only, and
    /// `present` calls it on the stacked result in the narrow layout. V3 (the
    /// probe's `.combineRows`) still calls it on the GridRow, as that run
    /// measured it.
    private func combined<Part: View>(_ part: Part, _ lab: PatientChart.Lab) -> some View {
        part.accessibilityElement(children: .combine).accessibilityLabel(ChartQuiz.spoken(lab))
    }

    /// V6's words for one result: what the four cells draw, in one string.
    private func words(_ lab: PatientChart.Lab) -> String {
        [lab.name, lab.value, lab.unit, lab.flag?.rawValue ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    @ViewBuilder
    private func probe(_ variant: A11yProbeLabs.Variant) -> some View {
        switch variant {
        case .nameCell:
            dressed(ViewThatFits(in: .horizontal) {
                gridOf { rowNamed($0) }
                stackOf { stackedWhole($0) }
            })
        case .combineTable:
            dressed(plainBoth)
                .accessibilityElement(children: .combine)
        case .combineRows:
            dressed(ViewThatFits(in: .horizontal) {
                gridOf { combined(row($0), $0) }
                stackOf { combined(stacked($0), $0) }
            })
        case .gridOnly:
            dressed(gridOf { row($0) })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenAll)
        case .stackOnly:
            dressed(stackOf { stacked($0) })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenAll)
        case .singleText:
            dressed(VStack(alignment: .leading, spacing: WardSpace.s) {
                ForEach(labs.indices, id: \.self) { i in
                    Text(words(labs[i])).foregroundStyle(Color.wardInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            })
        case .staticTextTrait:
            present
                .accessibilityAddTraits(.isStaticText)
        case .fontNoWeight:
            dressed(plainBoth, font: Font.system(.subheadline, design: .monospaced))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenAll)
        }
    }
}
