import SwiftUI

/// What the trailing end of New set's bottom slab holds on the current step.
enum NewSetDockPrimary: Equatable {
    /// Step 2, typing or a lecture file: Next, once there is something to
    /// go on with.
    case next(ready: Bool)
    /// Step 2, a set someone shared: the file picker.
    case chooseSaved
    /// Step 3: the floating copy of whichever button makes or saves the set,
    /// shown only while the real one is scrolled out of sight.
    case floating(String?)
}

/// New set's one bottom container, under the thumb.
///
/// Step 1 has none: tapping a kind moves on by itself. On steps 2 and 3 it is
/// one floating glass slab: Back at the leading end, the step's one main
/// button at the trailing end (right thumb). While something is being
/// written, the progress card - with its Cancel, the one way to stop -
/// takes the slab's place, so there is never more than one thing floating
/// at the bottom.
struct NewSetDock: View {
    let step: NewSetStep
    let primary: NewSetDockPrimary
    /// Why the main button cannot be tapped yet, shown above the row.
    let hint: String?
    let back: () -> Void
    let next: () -> Void
    let chooseSaved: () -> Void

    @ObservedObject private var generation = GenerationCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let change: Animation? = reduceMotion ? nil : .snappy(duration: 0.25)
        let running: Bool = generation.job != nil
        let showsSlab: Bool = !running && step != .kind
        ZStack(alignment: .bottom) {
            // draws nothing until a job starts
            GenerationHUD()
            if showsSlab {
                slab
                    .transition(.slideFade(.bottom))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(change, value: showsSlab)
        .animation(change, value: hint)
    }

    private var slab: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return VStack(spacing: 8) {
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 0) {
                backButton
                Spacer(minLength: 12)
                NewSetDockPrimaryButton(primary: primary, next: next, chooseSaved: chooseSaved)
                    .layoutPriority(1)
            }
        }
        .padding(12)
        .liquidGlassPanel(cornerRadius: 28)
        .popOut(.floating, in: shape)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
    }

    private var backButton: some View {
        Button(action: back) {
            Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.bigCompanion)
        // leaving the step while it is writing would lose sight of the work,
        // so Back waits for it
        .disabled(generation.job != nil)
        .accessibilityIdentifier("newSetBack")
    }
}

/// The trailing, main button of the slab.
private struct NewSetDockPrimaryButton: View {
    let primary: NewSetDockPrimary
    let next: () -> Void
    let chooseSaved: () -> Void

    private static let save = KeyboardShortcut("s", modifiers: .command)

    var body: some View {
        switch primary {
        case .next(let ready):
            Button(action: next) {
                Label("Next", systemImage: "arrow.right")
            }
            .buttonStyle(.bigPrimary)
            .disabled(!ready)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("newSetNext")
        case .chooseSaved:
            Button(action: chooseSaved) {
                Label("Choose a file", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bigPrimary)
        case .floating(let id):
            let shortcut: KeyboardShortcut? = id == "create" ? NewSetDockPrimaryButton.save : nil
            FloatingActionButton(expecting: id, shortcut: shortcut)
        }
    }
}

/// One step in "1 Choose - 2 Add - 3 Make": a numbered dot, ticked once the
/// step is done, with its name beside it.
struct NewSetStepDot: View {
    let one: NewSetStep
    let current: NewSetStep
    let tint: Color

    var body: some View {
        let reached: Bool = one <= current
        let done: Bool = one < current
        let fill: Color = reached ? tint : Color.secondary.opacity(0.2)
        let number: Color = reached ? Color.white : Color.secondary
        let caption: Color = one == current ? Color.primary : Color.secondary
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(one.rawValue)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(number)
                }
            }
            Text(one.short)
                .font(.caption.weight(.semibold))
                .foregroundStyle(caption)
                .fixedSize()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
