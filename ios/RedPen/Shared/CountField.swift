import SwiftUI

/// "How many?" as a number the student types, rather than a stepper tapped
/// forty times to get from 8 to 48. Anything outside the allowed range is
/// brought back inside it when the field is left, so a generator is never
/// asked for 0 or 5,000.
///
/// A minus and a plus sit either side of the number, each a full 44-point
/// key, for the small nudge ("one more") that typing is clumsy for. Holding
/// one repeats. The three stand out of the glass together, as one raised
/// slab (popField).
struct CountField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// The minus and plus either side of the number.
    let steppers: Bool

    @State private var text = ""
    @FocusState private var focused: Bool

    init(title: String, value: Binding<Int>, range: ClosedRange<Int>, steppers: Bool = true) {
        self.title = title
        self._value = value
        self.range = range
        self.steppers = steppers
    }

    var body: some View {
        let low: Int = range.lowerBound
        let high: Int = range.upperBound
        let placeholder: String = "\(low)\u{2013}\(high)"
        let hint: String = "Between \(low) and \(high)"
        // with keys, the round keys ARE the slab's ends (a capsule); alone,
        // the number gets the usual room inside its slab
        let side: CGFloat = steppers ? 0 : 12
        let inside = EdgeInsets(top: 0, leading: side, bottom: 0, trailing: side)
        LabeledContent(title) {
            // minus, number and plus stand out of the glass as ONE raised
            // slab, so the keys ride with the field instead of apart from it
            HStack(spacing: 6) {
                if steppers {
                    CountStepButton(symbol: "minus", label: "One fewer", enabled: value > low) { nudge(-1) }
                }
                TextField(placeholder, text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(steppers ? .center : .trailing)
                    .monospacedDigit()
                    .focused($focused)
                    .frame(minWidth: 44, maxWidth: steppers ? 64 : 90, minHeight: 44)
                    .onSubmit(commit)
                    .accessibilityHint(hint)
                if steppers {
                    CountStepButton(symbol: "plus", label: "One more", enabled: value < high) { nudge(1) }
                }
            }
            .popField(cornerRadius: 22, insets: inside)
        }
        .onAppear { text = String(value) }
        .onChange(of: focused) { _, now in if !now { commit() } }
        .onChange(of: text) { _, typed in
            let digits = typed.filter(\.isNumber)
            if digits != typed { text = digits }
            // what the field shows is what is used, even before it is left:
            // out of range is held at the nearest end rather than ignored
            if let number = Int(digits.prefix(9)) { value = min(max(number, range.lowerBound), range.upperBound) }
        }
        .onChange(of: value) { _, new in if !focused { text = String(new) } }
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
    }

    private func commit() {
        let number = Int(text) ?? value
        value = min(max(number, range.lowerBound), range.upperBound)
        text = String(value)
    }

    /// One up or down, kept inside the range; the field shows it at once,
    /// even while it has the caret.
    private func nudge(_ by: Int) {
        let moved: Int = value + by
        let kept: Int = min(max(moved, range.lowerBound), range.upperBound)
        value = kept
        text = String(kept)
    }
}

/// A 44-point minus or plus beside the number: a small round key at one end
/// of the field's raised slab (it rides with the slab, see PopOut.swift's
/// nesting), sinking under the finger and sitting flat once it can go no
/// further. Its own button style,
/// so in a Form row only this key takes the tap, not the whole row.
private struct CountStepButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        // a 44-point face with a 22-point corner is a circle
        let style = PopTileStyle(cornerRadius: 22)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(style)
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
