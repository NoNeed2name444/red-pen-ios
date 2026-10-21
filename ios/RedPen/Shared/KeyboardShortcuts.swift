import SwiftUI

extension View {
    /// A bare number key as the shortcut for this button - 1 for the first
    /// option, 2 for the second - for an iPad with a keyboard attached.
    ///
    /// Bare, with no Command: somebody working through a quiz at a desk has a
    /// hand resting on the number row, and holding Command for every answer
    /// is the kind of thing that stops a shortcut being used. Only 1 to 9
    /// exist as single keys, so anything past the ninth simply has none.
    @ViewBuilder
    func numberKey(_ number: Int) -> some View {
        if (1...9).contains(number), let digit = String(number).first {
            keyboardShortcut(KeyEquivalent(digit), modifiers: [])
        } else {
            self
        }
    }
}
