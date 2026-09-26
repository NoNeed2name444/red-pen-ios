import SwiftUI

// The Ward pocket: the lab values sheet grown into three tabs - Lab values,
// Calculators and Scores - opened from any study screen's More menu and from
// the exam plan. The formulas and tables are in Shared/WardPocket.swift and
// Shared/WardPocketScores.swift; this is only how they are shown.
//
// Every screen carries "For learning only - not for patient care" at the
// bottom (App Store guideline 1.4.1): this teaches how a score works, it is
// not a medical device.

/// Which of the Ward pocket's tabs is showing.
enum WardPocketTab: String, CaseIterable, Identifiable {
    case labs, calculators, scores
    var id: String { rawValue }

    var title: String {
        switch self {
        case .labs: return "Lab values"
        case .calculators: return "Calculators"
        case .scores: return "Scores"
        }
    }
}

struct WardPocketSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: WardPocketTab
    /// US conventional units for a USMLE track, SI for every other.
    @State private var conventional: Bool = LabUnits.conventional(for: ExamTrack.current)
    @State private var query: String = ""
    @State private var practice: NewSetPreset?

    init(start: WardPocketTab = .calculators) {
        _tab = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Section", selection: $tab) {
                        ForEach(WardPocketTab.allCases) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("wardPocketTabs")
                    if tab != .scores { WardUnitsPicker(conventional: $conventional) }
                }
                switch tab {
                case .labs: LabRangesSections(query: query, conventional: conventional)
                case .calculators: calculatorRows
                case .scores: scoreRows
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .searchable(text: $query, prompt: Text(searchPrompt))
            .navigationTitle("Ward pocket")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WardCalc.self) { calc in
                WardCalcView(calc: calc, conventional: $conventional, practice: $practice)
            }
            .navigationDestination(for: WardScore.self) { score in
                WardScoreView(score: score, practice: $practice)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .wardDisclaimer()
        }
        .presentationDetents([.large])
        // "Practise this": New set, ready to write questions on it
        .sheet(item: $practice) { NewSetView(preset: $0) }
    }

    private var searchPrompt: String {
        switch tab {
        case .labs: return "Search lab values"
        case .calculators: return "Search calculators"
        case .scores: return "Search scores"
        }
    }

    private func matches(_ name: String) -> Bool {
        let q: String = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }

    @ViewBuilder
    private var calculatorRows: some View {
        let shown: [WardCalc] = WardCalc.calculators.filter { matches($0.title) }
        Section("Calculators") {
            ForEach(shown) { calc in
                NavigationLink(value: calc) {
                    Label(calc.title, systemImage: calc.symbol)
                }
            }
        }
    }

    @ViewBuilder
    private var scoreRows: some View {
        let shown: [WardScoreEntry] = WardScores.entries.filter { matches($0.name) }
        Section("Scores") {
            ForEach(shown) { entry in
                scoreLink(entry)
            }
        }
    }

    @ViewBuilder
    private func scoreLink(_ entry: WardScoreEntry) -> some View {
        switch entry {
        case .table(let score):
            NavigationLink(value: score) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.name)
                    Text(score.purpose).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        case .formula(let calc):
            NavigationLink(value: calc) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(calc.title)
                    Text("Liver disease severity and transplant priority").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - pieces shared by the tabs

/// SI or US conventional units.
struct WardUnitsPicker: View {
    @Binding var conventional: Bool

    var body: some View {
        Picker("Units", selection: $conventional) {
            Text("SI").tag(false)
            Text("US conventional").tag(true)
        }
        .pickerStyle(.segmented)
    }
}

/// "For learning only - not for patient care", a small glass chip at the
/// foot of the screen, always in view.
private struct WardDisclaimer: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Label(WardPocket.disclaimer, systemImage: "graduationcap")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlassChip(tint: .orange)
                .padding(.bottom, 6)
                .accessibilityIdentifier("wardDisclaimer")
        }
    }
}

extension View {
    /// The Ward pocket's learning-only line along the bottom.
    func wardDisclaimer() -> some View { modifier(WardDisclaimer()) }
}

/// A block of text under a heading: the formula, the note, the source.
private struct WardTextSection: View {
    let title: String
    let text: String

    var body: some View {
        if !text.isEmpty {
            Section(title) {
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

/// "Practise this": opens New set with the calculator or score as its material.
private struct PractiseButton: View {
    let action: () -> Void

    var body: some View {
        Section {
            Button(action: action) {
                Label("Practise this", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("wardPractise")
            .accessibilityHint("Writes exam questions on this with your usual question settings")
        } footer: {
            Text(WardPocket.disclaimerDetail)
        }
    }
}

extension NewSetPreset {
    /// New set, ready to write MCQs on one Ward pocket calculator or score.
    init(wardPocket title: String, notes text: String) {
        kind = .mcq
        name = "Ward pocket: " + title
        subject = title
        notes = text
    }
}

// MARK: - a calculator

struct WardCalcView: View {
    let calc: WardCalc
    @Binding var conventional: Bool
    @Binding var practice: NewSetPreset?
    /// What was typed in each number field, in the units showing.
    @State private var typed: [String: String] = [:]
    @State private var toggles: [String: Bool] = [:]
    @State private var choices: [String: Int] = [:]

    private var hasUnits: Bool {
        calc.fields.contains { field in
            if case .number(let unit) = field.kind { return unit.si != unit.us }
            return false
        }
    }

    var body: some View {
        let outcome: WardOutcome? = calc.compute(values(), us: conventional)
        Form {
            if hasUnits {
                Section { WardUnitsPicker(conventional: $conventional) }
            }
            Section("Values") {
                ForEach(calc.fields) { field in
                    fieldRow(field)
                }
            }
            resultSection(outcome)
            WardTextSection(title: "How it is worked out", text: calc.formula)
            WardTextSection(title: "Keep in mind", text: calc.note)
            WardTextSection(title: "Source", text: calc.source)
            PractiseButton {
                practice = NewSetPreset(wardPocket: calc.title, notes: WardPocket.practiceNotes(for: calc))
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(calc.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: conventional) { was, now in
            retype(from: was, to: now)
        }
        .wardDisclaimer()
    }

    @ViewBuilder
    private func resultSection(_ outcome: WardOutcome?) -> some View {
        Section("Result") {
            if let outcome {
                ForEach(outcome.lines, id: \.self) { line in
                    LabeledContent(line.label) {
                        Text(line.value)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
                if let verdict = outcome.verdict {
                    Text(verdict)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Fill in the values above.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func fieldRow(_ field: WardField) -> some View {
        switch field.kind {
        case .number(let unit):
            numberRow(field, unit: unit)
        case .toggle:
            Toggle(field.label, isOn: toggleBinding(field.id))
        case .choice(let names):
            Picker(field.label, selection: choiceBinding(field.id)) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
        }
    }

    private func numberRow(_ field: WardField, unit: WardUnit) -> some View {
        let unitName: String = unit.name(us: conventional)
        let prompt: String = field.optional ? "optional" : ""
        return HStack(spacing: 8) {
            Text(field.label)
            Spacer(minLength: 8)
            TextField(prompt, text: textBinding(field.id))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(maxWidth: 110)
                .accessibilityLabel(field.label)
            if !unitName.isEmpty {
                Text(unitName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)
            }
        }
    }

    private func textBinding(_ id: String) -> Binding<String> {
        Binding(get: { typed[id] ?? "" }, set: { typed[id] = $0 })
    }

    private func toggleBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { toggles[id] ?? false }, set: { toggles[id] = $0 })
    }

    private func choiceBinding(_ id: String) -> Binding<Int> {
        Binding(get: { choices[id] ?? 0 }, set: { choices[id] = $0 })
    }

    private static func number(_ text: String?) -> Double? {
        guard let text else { return nil }
        let clean: String = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Double(clean)
    }

    /// Everything entered, numbers in SI.
    private func values() -> [String: Double] {
        var out: [String: Double] = [:]
        for field in calc.fields {
            switch field.kind {
            case .number(let unit):
                if let x = Self.number(typed[field.id]) { out[field.id] = unit.toSI(x, us: conventional) }
            case .toggle:
                out[field.id] = (toggles[field.id] ?? false) ? 1 : 0
            case .choice:
                out[field.id] = Double(choices[field.id] ?? 0)
            }
        }
        return out
    }

    /// Switching units rewrites what was typed, so a value keeps its meaning.
    private func retype(from was: Bool, to now: Bool) {
        for field in calc.fields {
            guard case .number(let unit) = field.kind, unit.usPerSI != 1,
                  let x = Self.number(typed[field.id]) else { continue }
            let si: Double = unit.toSI(x, us: was)
            let shown: Double = unit.fromSI(si, us: now)
            let places: Int = abs(shown) >= 100 ? 0 : (abs(shown) >= 10 ? 1 : 2)
            typed[field.id] = WardPocket.format(shown, places: places)
        }
    }
}

// MARK: - a score

struct WardScoreView: View {
    let score: WardScore
    @Binding var practice: NewSetPreset?
    @State private var picks: [String: Int] = [:]

    var body: some View {
        let total: Double = score.total(picks)
        let verdict: WardBand? = score.verdict(picks)
        let choiceItems: [WardItem] = score.items.filter { !$0.isYesNo }
        let yesNoItems: [WardItem] = score.items.filter(\.isYesNo)
        Form {
            Section {
                Text(score.purpose)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(choiceItems) { item in
                Section(item.label) { choicePicker(item) }
            }
            if !yesNoItems.isEmpty {
                Section("Criteria") {
                    ForEach(yesNoItems) { item in
                        yesNoRow(item)
                    }
                }
            }
            Section("Bands") {
                ForEach(score.bands, id: \.self) { band in
                    bandRow(band, on: band == verdict)
                }
            }
            WardTextSection(title: "Keep in mind", text: score.note)
            WardTextSection(title: "Source", text: score.source)
            PractiseButton {
                practice = NewSetPreset(wardPocket: score.name, notes: score.practiceNotes)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle(score.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { picks = [:] }
                    .disabled(picks.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WardScoreTotal(total: total, band: verdict)
        }
        .wardDisclaimer()
    }

    private func pickBinding(_ id: String) -> Binding<Int> {
        Binding(get: { picks[id] ?? 0 }, set: { picks[id] = $0 })
    }

    private func choicePicker(_ item: WardItem) -> some View {
        Picker(item.label, selection: pickBinding(item.id)) {
            ForEach(Array(item.choices.enumerated()), id: \.offset) { index, choice in
                HStack {
                    Text(choice.label)
                    Spacer(minLength: 8)
                    Text(WardScores.points(choice.points))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .tag(index)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func yesNoRow(_ item: WardItem) -> some View {
        let points: String = WardScores.points(item.choices[1].points)
        let on = Binding<Bool>(get: { (picks[item.id] ?? 0) == 1 }, set: { picks[item.id] = $0 ? 1 : 0 })
        return Toggle(isOn: on) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.label).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(points)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bandRow(_ band: WardBand, on: Bool) -> some View {
        let low: String = WardScores.points(band.low)
        let high: String = WardScores.points(band.high)
        let range: String = band.low == band.high ? low : low + "\u{2013}" + high
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(range)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(band.title).font(.subheadline.weight(.semibold))
                Text(band.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(on ? Color.accentColor : Color.primary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The running total and what it means, on a glass panel above the
/// disclaimer.
private struct WardScoreTotal: View {
    let total: Double
    let band: WardBand?

    var body: some View {
        let number: String = WardScores.points(total)
        HStack(alignment: .center, spacing: 14) {
            Text(number)
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .frame(minWidth: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(band?.title ?? "")
                    .font(.headline)
                Text(band?.detail ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlassPanel(cornerRadius: 20, plane: .raised)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.snappy, value: total)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wardScoreTotal")
    }
}
