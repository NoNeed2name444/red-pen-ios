import SwiftUI

/// "Turn into…": choosing which mode a set should become.
///
/// Every mode is a tile, with what will happen written on it before it is
/// tapped - "Instant" when the set can simply be rearranged, "Written by AI"
/// when it has to go through the writer. Tapping one does it: an instant set
/// is made and opened straight away, with no screen in between; a written one
/// lands in New set with the mode chosen and the material already in, one tap
/// from Generate. The set it came from is never changed.
///
/// The same sheet serves the long-press menu on a library row and the button
/// on every mode's own screen, so turning works the same from anywhere.
struct TurnIntoPicker: View {
    let source: StudySet

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    /// Every instant conversion, made once when the sheet opens, so each tile
    /// can say how many cards or questions it will give and tapping it has
    /// nothing left to work out.
    private let ready: [StudySetKind: StudySet]
    private let hasLecture: Bool

    init(source: StudySet) {
        self.source = source
        var ready: [StudySetKind: StudySet] = [:]
        for kind in ModeConversion.targets {
            if let made = ModeConversion.convert(source, to: kind) { ready[kind] = made }
        }
        self.ready = ready
        self.hasLecture = ModeConversion.lecture(of: source) != nil
    }

    /// The tiles: every mode a set can become, with this set's own mode among
    /// them (shown, but not choosable) so the grid is the same from anywhere.
    private var kinds: [StudySetKind] {
        ModeConversion.targets.contains(source.kind)
            ? ModeConversion.targets
            : [source.kind] + ModeConversion.targets
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\u{201C}\(source.name)\u{201D} stays as it is. The new set is added beside it, with the same subject and folder.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(kinds) { kind in
                            tile(kind)
                        }
                    }
                }
                .padding(20)
            }
            .accessibilityIdentifier("turnIntoPicker")
            .background(ModeBackdrop(kind: source.kind))
            .navigationTitle("Turn into\u{2026}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// What a tile says will happen.
    private func note(for kind: StudySetKind) -> (text: String, symbol: String) {
        if kind == source.kind { return ("This set", "checkmark") }
        if let made = ready[kind] {
            let n = made.itemCount
            return ("Instant \u{00B7} \(n) \(made.itemNoun)\(n == 1 ? "" : "s")", "bolt.fill")
        }
        return (hasLecture ? "Written by AI from your lecture" : "Written by AI from this set", "sparkles")
    }

    private func tile(_ kind: StudySetKind) -> some View {
        let current = kind == source.kind
        let said = note(for: kind)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button { pick(kind) } label: {
            VStack(alignment: .leading, spacing: 10) {
                ModeTile(kind: kind, size: 40)
                Text(kind.label)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Label(said.text, systemImage: said.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.pressableRow)
        .disabled(current)
        .opacity(current ? 0.5 : 1)
        .accessibilityLabel("\(kind.label). \(said.text)")
        .accessibilityHint(current ? "The mode this set is in now" : "Makes a new set. This one stays as it is.")
        .accessibilityIdentifier("turnInto-\(kind.rawValue)")
    }

    private func pick(_ kind: StudySetKind) {
        guard kind != source.kind else { return }
        if let made = ready[kind] {
            store.addSet(made)
            ModeSwitch.shared.stage(.open(made))
        } else {
            ModeSwitch.shared.stage(.write(NewSetPreset(turning: source, into: kind)))
        }
        // The library acts on the choice once the sheet has gone, so the new
        // set is pushed onto a screen that is really there.
        dismiss()
    }
}

/// Carries a choice made in the picker to the library, which owns the
/// navigation.
///
/// Held back until the sheet has finished closing: pushing a screen, or
/// raising New set, while a sheet is still on its way down is what leaves a
/// navigation stack half-updated.
final class ModeSwitch: ObservableObject {
    static let shared = ModeSwitch()

    enum Choice {
        /// An instant conversion, already in the library: open it.
        case open(StudySet)
        /// A conversion that needs writing: open New set, filled in.
        case write(NewSetPreset)
    }

    /// The set to open, for the library to push.
    @Published var opening: StudySet?
    /// New set, ready to generate, for the library to raise.
    @Published var writing: NewSetPreset?

    private var staged: Choice?

    func stage(_ choice: Choice) { staged = choice }

    /// Called when the picker's sheet has closed.
    func deliver() {
        guard let choice = staged else { return }
        staged = nil
        switch choice {
        case .open(let set): opening = set
        case .write(let preset): writing = preset
        }
    }
}

/// What New set opens with when a set is being turned into another mode by
/// the writer: the mode, a name, and the material.
struct NewSetPreset: Identifiable {
    let id = UUID()
    var kind: StudySetKind
    var name: String
    var subject: String
    var folderId: UUID?
    /// The lecture the set was made from, when it kept one.
    var lecture: ReadSource?
    /// The set's own content as text - used when there is no lecture.
    var notes: String

    init(turning set: StudySet, into kind: StudySetKind) {
        self.kind = kind
        self.name = ModeConversion.name(of: set, as: kind)
        self.subject = set.subject
        self.folderId = set.folderId
        let lecture = ModeConversion.lecture(of: set).map { ReadSource($0) }
        self.lecture = lecture
        self.notes = lecture == nil ? ModeConversion.sourceText(of: set) : ""
    }

    /// The material as one piece of text, for the forms that take text.
    var text: String { lecture?.document.text ?? notes }
}

extension ReadSource {
    /// A kept lecture, read back as if it had just been opened - so the
    /// writer cites the same pages and the accuracy check reads the same text.
    init(_ doc: SourceDoc) {
        self.init(name: doc.name,
                  document: SourceText.Document(pages: doc.pages.map {
                      SourceText.Page(number: $0.number, text: $0.text, recognised: $0.recognised)
                  }),
                  kind: doc.kind,
                  fileBlob: doc.fileBlob)
    }
}

extension View {
    /// Raises the "Turn into…" picker for whichever set `set` holds.
    func turnIntoPicker(for set: Binding<StudySet?>) -> some View {
        sheet(item: set, onDismiss: { ModeSwitch.shared.deliver() }) { source in
            TurnIntoPicker(source: source)
        }
    }

    /// A "Turn into…" button in a mode screen's toolbar, with its picker.
    func turnIntoButton(_ set: StudySet, shown: Bool = true) -> some View {
        modifier(TurnIntoButton(set: set, shown: shown))
    }
}

/// The toolbar button a mode screen shows for "Turn into…".
struct TurnIntoButton: ViewModifier {
    let set: StudySet
    let shown: Bool
    @State private var turning: StudySet?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if shown {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { turning = set } label: {
                            Label("Turn into\u{2026}", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityIdentifier("turnInto")
                    }
                }
            }
            .turnIntoPicker(for: $turning)
    }
}
