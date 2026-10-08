import SwiftUI

/// Ideas' one bottom container, under the thumb:
///
/// 1. the floating List / Board / Space switcher, with a chevron to fold it
///    away;
/// 2. the capture row: the folded switcher (when it is folded), the
///    "Dump an idea…" field, and one trailing control - Send when there is
///    something to save, otherwise a plus for a new page or folder.
///
/// While the field is being typed in, the switcher folds into the capture
/// row by itself, so only one floating row sits over the keyboard; when
/// typing stops it goes back to however it was left.
struct IdeasBottomBar: View {
    @Binding var modeRaw: String
    @Binding var draft: String
    /// The capture field's focus, owned by IdeasView (Start typing and a
    /// saved idea both put the caret back here).
    let capturing: FocusState<Bool>.Binding
    /// Whether the field has the caret (held a moment after it leaves).
    /// Passed as a value, so this bar is redrawn when it changes.
    let typing: Bool
    let capture: () -> Void
    let newPage: () -> Void
    let newFolder: () -> Void

    @AppStorage("vignette.ideas.switcherCollapsed") private var switcherCollapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showCollapsed: Bool { switcherCollapsed || typing }

    private var hasText: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let change: Animation? = reduceMotion ? nil : .snappy(duration: 0.25)
        VStack(spacing: 10) {
            if !showCollapsed {
                switcher
                    .transition(.opacity)
            }
            captureRow
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .animation(change, value: showCollapsed)
        .animation(change, value: hasText)
    }

    // MARK: the switcher

    private var modeItems: [SwitcherItem<IdeasMode>] {
        IdeasMode.allCases.map { mode in
            SwitcherItem(value: mode, title: mode.title, symbol: mode.symbol, identifier: mode.identifier)
        }
    }

    private var modeBinding: Binding<IdeasMode> {
        let raw = $modeRaw
        return Binding(
            get: { IdeasMode(rawValue: raw.wrappedValue) ?? .list },
            set: { raw.wrappedValue = $0.rawValue }
        )
    }

    /// Folded while typing whatever was stored; opening it while typing puts
    /// the keyboard away, so the strip has room.
    private var collapsedBinding: Binding<Bool> {
        let stored = $switcherCollapsed
        let focus = capturing
        let held: Bool = typing
        return Binding(
            get: { stored.wrappedValue || held },
            set: { now in
                if !now { focus.wrappedValue = false }
                stored.wrappedValue = now
            }
        )
    }

    /// The same switcher in both places: the strip on its own row, or the
    /// circle at the start of the capture row.
    private var switcher: some View {
        FloatingSwitcher(items: modeItems, selection: modeBinding, collapsed: collapsedBinding,
                         toggleIdentifier: "ideasSwitcherToggle")
    }

    // MARK: the capture row

    private var captureRow: some View {
        HStack(spacing: 10) {
            if showCollapsed {
                switcher
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            IdeaCaptureField(draft: $draft, capturing: capturing, capture: capture)
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if hasText {
            IdeaSendButton(action: capture)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else {
            IdeaAddMenu(newIdea: { capturing.wrappedValue = true },
                        newPage: newPage, newFolder: newFolder)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}

/// "Dump an idea…": a soft capsule pressed into the base, as every field is.
private struct IdeaCaptureField: View {
    @Binding var draft: String
    let capturing: FocusState<Bool>.Binding
    let capture: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .foregroundStyle(Color.wardInkSecondary)
                .accessibilityHidden(true)
            TextField("Dump an idea\u{2026}", text: $draft)
                .focused(capturing)
                .submitLabel(.done)
                .onSubmit(capture)
                .accessibilityIdentifier("idea-capture")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .wardInset(in: Capsule())
    }
}

/// Saves what is typed, the screen's main button while there is text: a
/// disc raised as high as the switcher beside it, its bold arrow in Theatre
/// Blue (no fill); pressed, it sinks in.
private struct IdeaSendButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.wardPrimaryInk)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        // a 48-point square rounded by half its side: the disc
        .buttonStyle(PopTileStyle(cornerRadius: 24, plane: .floating))
        .accessibilityLabel("Save idea")
    }
}

/// With nothing typed: a new idea (Command N), a new page or a new folder,
/// from a disc raised as high as the switcher, its plus in Theatre Blue.
private struct IdeaAddMenu: View {
    let newIdea: () -> Void
    let newPage: () -> Void
    let newFolder: () -> Void

    var body: some View {
        Menu {
            Button("New idea", systemImage: "lightbulb", action: newIdea)
                .keyboardShortcut("n", modifiers: .command)
            Button("New page", systemImage: "doc.badge.plus", action: newPage)
            Button("New folder", systemImage: "folder.badge.plus", action: newFolder)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .foregroundStyle(Color.wardPrimaryInk)
        .ideaToolRelief(active: false)
        .accessibilityLabel("Add")
    }
}
