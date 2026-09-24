import SwiftUI

/// "How many?" as a number the student types, rather than a stepper tapped
/// forty times to get from 8 to 48. Anything outside the allowed range is
/// brought back inside it when the field is left, so a generator is never
/// asked for 0 or 5,000.
struct CountField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField("\(range.lowerBound)\u{2013}\(range.upperBound)", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focused)
                .frame(maxWidth: 90)
                .onSubmit(commit)
                .accessibilityHint("Between \(range.lowerBound) and \(range.upperBound)")
        }
        .onAppear { text = String(value) }
        .onChange(of: focused) { _, now in if !now { commit() } }
        .onChange(of: text) { _, typed in
            let digits = typed.filter(\.isNumber)
            if digits != typed { text = digits }
            if let number = Int(digits), range.contains(number) { value = number }
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
}
