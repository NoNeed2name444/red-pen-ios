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

/// "Dump an idea…": a glass capsule standing a little out of the glass. It
/// only slides with the tilt - never leans - so the caret stays steady.
private struct IdeaCaptureField: View {
    @Binding var draft: String
    let capturing: FocusState<Bool>.Binding
    let capture: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Dump an idea\u{2026}", text: $draft)
                .focused(capturing)
                .submitLabel(.done)
                .onSubmit(capture)
                .accessibilityIdentifier("idea-capture")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .glassEffect(.regular, in: .capsule)
        .popOut(.raised, in: Capsule(), cues: .translateOnly)
    }
}

/// Saves what is typed: the screen's one hero while there is text.
private struct IdeaSendButton: View {
    let action: () -> Void

    var body: some View {
        let glass: Glass = Glass.regular.tint(Color.accentColor).interactive()
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .circle)
        .popOut(.hero, in: Circle())
        .hoverEffect(.lift)
        .accessibilityLabel("Save idea")
    }
}

/// With nothing typed: a new idea (Command N), a new page or a new folder.
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
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: .circle)
        .popOut(.raised, in: Circle())
        .hoverEffect(.highlight)
        .accessibilityLabel("Add")
    }
}
