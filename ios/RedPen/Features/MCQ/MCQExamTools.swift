import SwiftUI

// The exam screen's tools, as the real test interfaces have them, shared by
// the MCQ player and the mock paper: the highlighter on the stem, crossing
// out options, the reference ranges sheet, the calculator, and the
// attending's hint.

/// Which of the tool sheets is open.
enum ExamToolSheet: String, Identifiable {
    case labs, calculator
    var id: String { rawValue }
}

/// The tools' items in the screen's More menu: the reference ranges, the
/// calculator, and the highlighter switch - each with its name written out.
struct ExamToolMenuItems: View {
    @Binding var sheet: ExamToolSheet?
    @Binding var highlighting: Bool

    var body: some View {
        let track = ExamTrack.current
        let units: String = LabUnits.conventional(for: track) ? "US units" : "SI units"
        Section("Exam tools") {
            Button { sheet = .labs } label: {
                Label("Lab values (\(units))", systemImage: "testtube.2")
            }
            Button { sheet = .calculator } label: {
                Label("Calculator", systemImage: "plus.forwardslash.minus")
            }
            Button { highlighting.toggle() } label: {
                Label(highlighting ? "Stop highlighting" : "Highlight the stem",
                      systemImage: "highlighter")
            }
        }
    }
}

extension View {
    /// The lab values and calculator sheets, opened from the More menu.
    func examToolSheets(_ sheet: Binding<ExamToolSheet?>) -> some View {
        self.sheet(item: sheet) { which in
            switch which {
            case .labs: LabRangesSheet()
            case .calculator: CalculatorSheet()
            }
        }
    }
}

// MARK: - the highlighter

/// The stem, with the pieces the student marked drawn in highlighter yellow.
/// While `highlighting` is on, each piece is its own button: a tap marks or
/// clears it.
struct HighlightableStem: View {
    let stem: String
    /// The stem as it is shown when nothing is being marked (the slow
    /// reading drill's key words, say).
    let plain: AttributedString
    @Binding var marked: Set<Int>
    let highlighting: Bool

    private static let ink: Color = Color.yellow.opacity(0.45)

    var body: some View {
        let pieces: [String] = StemPieces.split(stem)
        if highlighting {
            editing(pieces)
        } else if marked.isEmpty {
            Text(plain)
        } else {
            Text(Self.painted(pieces, marked: marked))
        }
    }

    private func editing(_ pieces: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Tap a phrase to highlight it", systemImage: "highlighter")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                pieceButton(index: index, piece: piece)
            }
        }
    }

    private func pieceButton(index: Int, piece: String) -> some View {
        let on: Bool = marked.contains(index)
        let fill: Color = on ? Self.ink : Color.primary.opacity(0.04)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if on { marked.remove(index) } else { marked.insert(index) }
        } label: {
            Text(piece.trimmingCharacters(in: .whitespaces))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(fill, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? "Removes the highlight" : "Highlights this phrase")
    }

    static func painted(_ pieces: [String], marked: Set<Int>) -> AttributedString {
        var out = AttributedString()
        for (i, piece) in pieces.enumerated() {
            var part = AttributedString(piece)
            if marked.contains(i) { part.backgroundColor = ink }
            out.append(part)
        }
        return out
    }
}

// MARK: - the attending's hint

/// The hint, once asked for: the next step in the reasoning, never the answer.
struct AttendingHintCard: View {
    let text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Attending\u{2019}s hint", systemImage: "stethoscope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            if let text {
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Thinking it through\u{2026}").foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .transition(.slideFade(.top))
        .accessibilityElement(children: .combine)
    }
}

/// The small Hint button beside Flag: quiet, raised, 44 points tall.
struct HintChip: View {
    let used: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(used ? "Hint shown" : "Hint", systemImage: used ? "lightbulb.fill" : "lightbulb")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(used ? Color.orange : Color.secondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PopPressStyle(plane: .raised, shape: Capsule()))
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
        .disabled(used)
        .accessibilityLabel(used ? "Hint shown" : "Show a hint")
        .accessibilityHint("The next step in the reasoning, without the answer")
    }
}

// MARK: - reference ranges

struct LabRangesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var conventional: Bool = LabUnits.conventional(for: ExamTrack.current)

    var body: some View {
        let found: [LabRange] = LabRanges.search(query)
        NavigationStack {
            List {
                Section {
                    Picker("Units", selection: $conventional) {
                        Text("SI").tag(false)
                        Text("US conventional").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(LabRanges.caveat)
                }
                ForEach(LabRanges.groups, id: \.self) { group in
                    let rows: [LabRange] = found.filter { $0.group == group }
                    if !rows.isEmpty {
                        Section(group) {
                            ForEach(rows) { row in
                                labRow(row)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search lab values")
            .navigationTitle("Lab values")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func labRow(_ row: LabRange) -> some View {
        let value: String = row.value(conventional: conventional)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.name)
            Spacer(minLength: 8)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - calculator

struct CalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var calc = ExamCalculator()

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(calc.display)
                    .scaledFont(44, relativeTo: .largeTitle, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Display, \(calc.display)")
                LazyVGrid(columns: columns, spacing: 10) {
                    Group {
                        key("C", role: .function) { calc.clear() }
                        key("\u{00B1}", role: .function) { calc.negate() }
                        key("%", role: .function) { calc.percent() }
                        opKey(.divide)
                        digitRow([7, 8, 9])
                        opKey(.multiply)
                    }
                    Group {
                        digitRow([4, 5, 6])
                        opKey(.subtract)
                        digitRow([1, 2, 3])
                        opKey(.add)
                    }
                    Group {
                        key("0", role: .digit) { calc.digit(0) }
                        key(".", role: .digit) { calc.dot() }
                        key("", role: .blank) {}
                        key("=", role: .equals) { calc.equals() }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 420)
            .navigationTitle("Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private enum KeyRole { case digit, function, op, equals, blank }

    @ViewBuilder
    private func digitRow(_ digits: [Int]) -> some View {
        ForEach(digits, id: \.self) { d in
            key(String(d), role: .digit) { calc.digit(d) }
        }
    }

    private func opKey(_ op: ExamCalculator.Op) -> some View {
        let on: Bool = calc.pendingOp == op
        return key(op.rawValue, role: on ? .equals : .op) { calc.op(op) }
    }

    @ViewBuilder
    private func key(_ title: String, role: KeyRole, action: @escaping () -> Void) -> some View {
        if role == .blank {
            Color.clear.frame(minHeight: 56)
        } else {
            let fill: Color = Self.fill(role)
            let ink: Color = role == .equals ? Color.white : Color.primary
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                action()
            } label: {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(fill, in: shape)
                    .contentShape(shape)
            }
            .buttonStyle(PopPressStyle(plane: .raised, shape: shape))
        }
    }

    private static func fill(_ role: KeyRole) -> Color {
        switch role {
        case .digit, .blank: return Color.primary.opacity(0.07)
        case .function: return Color.primary.opacity(0.14)
        case .op: return Color.accentColor.opacity(0.2)
        case .equals: return Color.accentColor
        }
    }
}

// MARK: - crossing out

extension View {
    /// Crossing an option out: a long press offers it in a menu, and a
    /// sideways swipe across the option does it directly. VoiceOver gets it
    /// as a named action.
    func strikeOutGestures(struck: Bool, enabled: Bool, toggle: @escaping () -> Void) -> some View {
        let title: String = struck ? "Restore option" : "Cross out option"
        let symbol: String = struck ? "arrow.uturn.backward" : "line.diagonal"
        return self
            .contextMenu {
                if enabled {
                    Button(title, systemImage: symbol, action: toggle)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 28)
                    .onEnded { value in
                        guard enabled else { return }
                        let dx: CGFloat = abs(value.translation.width)
                        let dy: CGFloat = abs(value.translation.height)
                        if dx > 70 && dy < 24 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            toggle()
                        }
                    }
            )
            .accessibilityAction(named: Text(title)) { if enabled { toggle() } }
    }
}
