import Combine
import PDFKit
import SwiftUI
import UIKit

// MARK: - Saving
//
// Save to Ideas on a study screen: the button under an explanation, a card's
// back, a case's answer or a finished station; "Save to Ideas" in the menu
// over selected text; and the glass slip that says it is done, with Undo.
// What is saved, and where it is filed, is SaveToIdeas.swift.

/// The one place a save happens, so the button, the selection menu and the
/// slip agree. It holds the idea store the library hands it once it is on
/// screen (LibraryView); until then - a screenshot run, the sign-in - there
/// is nowhere to save, and the buttons stay away.
@MainActor
final class IdeaSaver: ObservableObject {
    static let shared = IdeaSaver()

    /// The slip on show, and which screen shows it.
    @Published private(set) var toast: IdeaToast?
    /// An item already saved, waiting on "Add to existing note?".
    @Published var asking: PendingIdea?
    @Published private(set) var isReady = false

    private weak var notes: NoteStore?

    func attach(_ notes: NoteStore) {
        self.notes = notes
        if !isReady { isReady = true }
    }

    /// Whether this item already has its note.
    func hasNote(for source: NoteSource) -> Bool {
        notes?.note(savedFrom: source) != nil
    }

    /// Saves, or - when this item already has a note - asks first rather
    /// than making a second. `host` is the screen that shows the slip and
    /// the question (saveToIdeasHost).
    func save(_ clip: IdeaClip, host: UUID?) {
        guard let notes else { return }
        if let existing = notes.note(savedFrom: clip.source) {
            asking = PendingIdea(clip: clip, noteID: existing.id, noteTitle: existing.title, host: host)
            return
        }
        create(clip, in: notes, host: host)
    }

    private func create(_ clip: IdeaClip, in notes: NoteStore, host: UUID?) {
        let name: String = SaveToIdeas.folderName(subject: clip.subject)
        let refs: [SaveToIdeas.FolderRef] = notes.folders.map {
            SaveToIdeas.FolderRef(id: $0.id, name: $0.name, parentId: $0.parentId)
        }
        var made: UUID? = nil
        let folderID: UUID
        if let found = SaveToIdeas.folder(named: name, in: refs) {
            folderID = found
        } else {
            let folder: NoteFolder = notes.createFolder(name: name)
            folderID = folder.id
            made = folder.id
        }
        let body: String = SaveToIdeas.body(for: clip)
        let note: Note = notes.create(title: clip.title, body: body, kind: .idea,
                                      folderId: folderID, source: clip.source)
        let message: String = "\u{201C}\(note.title)\u{201D} in \(name)"
        show(IdeaToast(host: host, title: "Saved to Ideas", message: message,
                       undo: .created(note.id, folder: made)))
    }

    /// "Add to existing note": the text goes on the end of the note, unless
    /// the note already has it.
    func addToExisting(_ pending: PendingIdea) {
        asking = nil
        guard let notes, var note = notes.note(pending.noteID) else { return }
        let quoted: String = "\u{201C}\(note.title)\u{201D}"
        guard let grown = SaveToIdeas.appending(pending.clip, to: note.body) else {
            show(IdeaToast(host: pending.host, title: "Already in Ideas",
                           message: quoted + " has this already", undo: nil))
            return
        }
        let before: String = note.body
        note.body = grown
        notes.update(note)
        show(IdeaToast(host: pending.host, title: "Added to your note", message: quoted,
                       undo: .appended(note.id, before: before)))
    }

    /// Puts back what the slip's save did: a new note (and the folder made
    /// for it, if nothing else went in) removed, or an addition taken off.
    func undo() {
        guard let notes, let shown = toast, let undo = shown.undo else { return }
        switch undo {
        case .created(let id, let folder):
            notes.delete(id)
            if let folder, notes.count(in: folder) == 0, notes.subfolders(of: folder).isEmpty {
                notes.deleteFolder(folder)
            }
        case .appended(let id, let before):
            if var note = notes.note(id) {
                note.body = before
                notes.update(note)
            }
        }
        toast = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIAccessibility.post(notification: .announcement, argument: "Undone")
    }

    func dismiss(_ id: UUID) {
        if toast?.id == id { toast = nil }
    }

    func stopAsking(host: UUID) {
        if asking?.host == host { asking = nil }
    }

    private func show(_ next: IdeaToast) {
        toast = next
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let spoken: String = next.title + ": " + next.message
        UIAccessibility.post(notification: .announcement, argument: spoken)
    }

    // MARK: which set
    //
    // Plain look-ups over the library, off the actor: the clips the study
    // screens make (SaveToIdeas.clip) call them from anywhere.

    /// The library's set an item lives in: the one it was opened from when
    /// that is in the library; otherwise the first that holds it (a quiz or
    /// a session put together on the spot is nowhere to go back to); the set
    /// as given when none does.
    nonisolated static func home(of itemID: UUID, in set: StudySet, library: [StudySet]) -> StudySet {
        if let same = library.first(where: { $0.id == set.id }) { return same }
        let holder: StudySet? = library.first { holds($0, itemID) }
        return holder ?? set
    }

    /// The set a saved note's chip goes back to: the one it was saved from
    /// when that still holds the item, else any set that does (it may have
    /// been copied, or its first set deleted); nil when it has gone.
    nonisolated static func set(for source: NoteSource, in library: [StudySet]) -> StudySet? {
        let saved: StudySet? = library.first { $0.id == source.setID }
        guard let item = source.itemID else { return saved }
        if let saved, holds(saved, item) { return saved }
        return library.first { holds($0, item) } ?? saved
    }

    private nonisolated static func holds(_ set: StudySet, _ id: UUID) -> Bool {
        if set.questions.contains(where: { $0.id == id }) { return true }
        if set.cards.contains(where: { $0.id == id }) { return true }
        if set.qaCards.contains(where: { $0.id == id }) { return true }
        if set.osceChecklists.contains(where: { $0.id == id }) { return true }
        return set.sources.contains { $0.id == id }
    }
}

/// The slip after a save.
struct IdeaToast: Identifiable, Equatable {
    let id = UUID()
    let host: UUID?
    let title: String
    let message: String
    let undo: IdeaUndo?
}

/// What Undo puts back.
enum IdeaUndo: Equatable {
    /// A new note, and the folder made for it (nil: the folder was there).
    case created(UUID, folder: UUID?)
    /// Text added to a note, with the body as it was.
    case appended(UUID, before: String)
}

/// An item that already has a note, waiting on the question.
struct PendingIdea: Equatable {
    let clip: IdeaClip
    let noteID: UUID
    let noteTitle: String
    let host: UUID?
}

// MARK: - The screen's end of it

private struct IdeaHostKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// The screen whose slip a save inside it shows (saveToIdeasHost).
    var ideaHost: UUID? {
        get { self[IdeaHostKey.self] }
        set { self[IdeaHostKey.self] = newValue }
    }
}

extension View {
    /// Once per study screen: the slip after a save made on it, and the
    /// question when the item is already in Ideas. `id` for a screen that
    /// saves from outside its own body (the lecture reader's selection);
    /// otherwise the screen makes its own.
    func saveToIdeasHost(_ id: UUID? = nil) -> some View {
        modifier(SaveToIdeasHost(given: id))
    }
}

private struct SaveToIdeasHost: ViewModifier {
    let given: UUID?
    @State private var own = UUID()
    @ObservedObject private var saver = IdeaSaver.shared

    private var id: UUID { given ?? own }

    private var mine: IdeaToast? {
        guard let toast = saver.toast, toast.host == id else { return nil }
        return toast
    }

    private var askingHere: Binding<Bool> {
        let here: UUID = id
        return Binding(get: { saver.asking?.host == here },
                       set: { if !$0 { saver.stopAsking(host: here) } })
    }

    func body(content: Content) -> some View {
        let shown: IdeaToast? = mine
        return content
            .environment(\.ideaHost, id)
            .overlay(alignment: .top) {
                if let shown {
                    SavedIdeaToast(toast: shown,
                                   onUndo: { saver.undo() },
                                   onDismiss: { saver.dismiss(shown.id) })
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: shown?.id)
            // it says what happened and goes by itself; long enough to Undo
            .task(id: shown?.id) {
                guard let showing = shown?.id else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                saver.dismiss(showing)
            }
            .confirmationDialog("Already in Ideas", isPresented: askingHere,
                                titleVisibility: .visible, presenting: saver.asking) { pending in
                Button("Add to existing note") { saver.addToExisting(pending) }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("\u{201C}\(pending.noteTitle)\u{201D} was saved from this \(pending.clip.source.kind.noun). Add this to it?")
            }
    }
}

/// "Saved to Ideas", at the top: a glass slip that stands a little out of
/// the screen and stops nothing, with Undo. A tap elsewhere on it puts it away.
private struct SavedIdeaToast: View {
    let toast: IdeaToast
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                Text(toast.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if toast.undo != nil {
                Button(action: onUndo) {
                    Text("Undo")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityHint("Takes the save back")
                .accessibilityIdentifier("ideaToastUndo")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.undo == nil ? 16 : 4)
        .padding(.vertical, toast.undo == nil ? 12 : 4)
        .frame(maxWidth: 520)
        .liquidGlassPanel(cornerRadius: 18)
        .popOut(.raised, in: shape)
        .contentShape(shape)
        .onTapGesture(perform: onDismiss)
    }
}

// MARK: - The button

/// "Save to Ideas" under what is worth keeping - or "In Ideas" once it is,
/// where a tap offers to add to that note. A labelled capsule, or (compact)
/// a lightbulb on a 44-point disc for a row. Not there until the library has
/// handed over the idea store.
struct SaveToIdeasButton: View {
    let clip: IdeaClip
    var compact: Bool = false
    @ObservedObject private var saver = IdeaSaver.shared
    @Environment(\.ideaHost) private var host

    var body: some View {
        if saver.isReady {
            button
        }
    }

    private var button: some View {
        let saved: Bool = saver.hasNote(for: clip.source)
        let symbol: String = saved ? "checkmark.circle.fill" : "lightbulb"
        let title: String = saved ? "In Ideas" : "Save to Ideas"
        let folder: String = SaveToIdeas.folderName(subject: clip.subject)
        let hint: String = saved
            ? "It has a note already; offers to add this to it"
            : "Keeps this as a note in Ideas, in \(folder)"
        return Button {
            saver.save(clip, host: host)
        } label: {
            if compact {
                disc(symbol, saved: saved)
            } else {
                capsule(symbol, title: title, saved: saved)
            }
        }
        .buttonStyle(PopTileStyle(cornerRadius: 22))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier("saveToIdeas")
    }

    private func disc(_ symbol: String, saved: Bool) -> some View {
        let colour: Color = saved ? Color.green : Color.accentColor
        return Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(colour)
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
    }

    private func capsule(_ symbol: String, title: String, saved: Bool) -> some View {
        let colour: Color = saved ? Color.green : Color.accentColor
        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(colour)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.primary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(.regularMaterial, in: Capsule())
        .contentShape(Capsule())
    }
}

// MARK: - Saving a passage

/// Text that can be read like any other, and selected a word at a time: the
/// menu over a selection has Save to Ideas, which keeps just that passage.
/// Plain SwiftUI text until there is somewhere to save (a screenshot run).
struct SaveableText: View {
    let text: String
    var font: Font = .body
    var style: UIFont.TextStyle = .body
    var lineSpacing: CGFloat = 3
    /// The note a chosen passage makes.
    let clip: (String) -> IdeaClip
    @ObservedObject private var saver = IdeaSaver.shared
    @Environment(\.ideaHost) private var host

    var body: some View {
        if saver.isReady {
            let here: UUID? = host
            let make: (String) -> IdeaClip = clip
            IdeaSelectableText(text: text, style: style, lineSpacing: lineSpacing) { picked in
                IdeaSaver.shared.save(make(picked), host: here)
            }
        } else {
            Text(text)
                .font(font)
                .lineSpacing(lineSpacing)
        }
    }
}

/// A read-only UITextView: SwiftUI's own text selects all of itself or
/// nothing, and a passage is the point. The edit menu gets "Save to Ideas"
/// in front of Copy and the rest while `onSave` is set.
struct IdeaSelectableText: UIViewRepresentable {
    let text: String
    var style: UIFont.TextStyle = .body
    var lineSpacing: CGFloat = 3
    var onSave: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
        // wraps to the width it is given rather than asking for one line's
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onSave = onSave
        // rebuilt only when the words or the text size change, so a redraw
        // of the screen does not drop a selection being made
        let size: String = String(describing: context.environment.dynamicTypeSize)
        let key: String = size + "|" + text
        guard context.coordinator.shown != key else { return }
        context.coordinator.shown = key
        view.attributedText = styled(for: view.traitCollection)
    }

    private func styled(for traits: UITraitCollection) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let font: UIFont = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let offered: CGFloat = proposal.width ?? 320
        let width: CGFloat = offered.isFinite && offered > 0 ? offered : 320
        let limit = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let fit: CGSize = uiView.sizeThatFits(limit)
        return CGSize(width: width, height: ceil(fit.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSave: ((String) -> Void)?
        var shown: String = ""

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let onSave, range.length > 0 else { return nil }
            let whole: NSString = (textView.text ?? "") as NSString
            guard NSMaxRange(range) <= whole.length else { return nil }
            let picked: String = whole.substring(with: range)
            guard !picked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let image: UIImage? = UIImage(systemName: "lightbulb")
            let save = UIAction(title: "Save to Ideas", image: image) { _ in onSave(picked) }
            return UIMenu(children: [save] + suggestedActions)
        }
    }
}

/// A PDFView whose selection menu has "Save to Ideas", with the page the
/// selection starts on (from 1).
final class IdeaPDFView: PDFView {
    var onSaveSelection: ((String, Int) -> Void)?

    /// The reader's passage saver as the menu's action; nil (no menu item)
    /// without one, or before there is anywhere to save.
    static func saver(_ passage: IdeaPassageSaver?) -> ((String, Int) -> Void)? {
        guard let passage, IdeaSaver.shared.isReady else { return nil }
        return passage.save
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, onSaveSelection != nil else { return }
        let words: String = currentSelection?.string ?? ""
        guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let image: UIImage? = UIImage(systemName: "lightbulb")
        let save = UIAction(title: "Save to Ideas", image: image) { [weak self] _ in
            self?.saveSelection()
        }
        let group = UIMenu(options: .displayInline, children: [save])
        builder.insertChild(group, atStartOfMenu: .root)
    }

    private func saveSelection() {
        guard let selection = currentSelection, let words = selection.string else { return }
        let first: PDFPage? = selection.pages.first
        let index: Int = first.flatMap { document?.index(for: $0) } ?? 0
        onSaveSelection?(words, index + 1)
    }
}

// MARK: - The backlink

/// A saved note's way back: "Question · Cardiology" on a glass chip, opening
/// the question in its set (AppLink.openItem, which the library acts on the
/// way a search result is opened).
struct NoteSourceChip: View {
    let source: NoteSource

    var body: some View {
        Button {
            AppRouter.shared.open(.openItem(source))
        } label: {
            Label(source.chipLabel, systemImage: source.kind.symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(minHeight: 32)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("From " + source.chipLabel)
        .accessibilityHint("Opens it where it is in your library")
        .accessibilityIdentifier("noteSourceChip")
    }
}

extension View {
    /// The backlink chip under a note's editor, when the note was saved
    /// from studying. It follows the note the editor was opened on.
    func noteSourceChip(noteID: UUID) -> some View {
        modifier(NoteSourceInset(noteID: noteID))
    }
}

private struct NoteSourceInset: ViewModifier {
    let noteID: UUID
    @EnvironmentObject private var notes: NoteStore

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if let source = notes.note(noteID)?.source {
                NoteSourceChip(source: source)
                    .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - What each screen saves

/// The clips the study screens save, made from the app's own items. The
/// source names the library's set the item lives in (IdeaSaver.home), so a
/// question saved from a quiz put together on the spot still goes back to a
/// set that is there.
extension SaveToIdeas {
    private static func origin(_ kind: NoteSource.Kind, item: UUID, in set: StudySet,
                               library: [StudySet]) -> (source: NoteSource, subject: String) {
        let home: StudySet = IdeaSaver.home(of: item, in: set, library: library)
        let source = NoteSource(kind: kind, setID: home.id, itemID: item, setName: home.name)
        return (source, home.subject)
    }

    /// A question: its stem, the right answer and the explanation.
    static func clip(question item: MCQQuestion, in set: StudySet, library: [StudySet]) -> IdeaClip {
        let at = origin(.question, item: item.id, in: set, library: library)
        let key: Int = item.correctIndex
        let answer: String? = item.options.indices.contains(key) ? item.options[key] : nil
        return question(stem: item.stem, answer: answer, explanation: item.explanation,
                        source: at.source, subject: at.subject)
    }

    /// A card's back. A picture card with no words on its front is named
    /// after the label it hides.
    static func clip(card item: AnkiCard, in set: StudySet, library: [StudySet]) -> IdeaClip {
        let at = origin(.card, item: item.id, in: set, library: library)
        let blank: Bool = item.front.trimmingCharacters(in: .whitespaces).isEmpty
        let hidden: String = item.type == .occlusion && blank ? (item.bullets.first ?? "") : ""
        let front: String = item.type == .cloze ? "" : (hidden.isEmpty ? item.displayFront : hidden)
        return card(front: front, cloze: item.clozeText, bullets: item.bullets, why: item.why,
                    source: at.source, subject: at.subject)
    }

    /// A Cases card: its topic or stem, and the answer points.
    static func clip(caseCard item: QACard, in set: StudySet, library: [StudySet]) -> IdeaClip {
        let at = origin(.caseCard, item: item.id, in: set, library: library)
        return caseCard(topic: item.topic, stem: item.stem, answer: item.answer,
                        source: at.source, subject: at.subject)
    }

    /// An OSCE station worked through, the steps started over at marked.
    static func clip(station item: OsceChecklist, weak: Set<Int>, in set: StudySet,
                     library: [StudySet]) -> IdeaClip {
        let at = origin(.osce, item: item.id, in: set, library: library)
        return osce(title: item.title, steps: item.steps, weak: weak,
                    source: at.source, subject: at.subject)
    }

    /// A passage of a lecture, at its page.
    static func clip(passage text: String, page: Int, of lecture: SourceDoc, in set: StudySet) -> IdeaClip {
        let source = NoteSource(kind: .lecture, setID: set.id, itemID: lecture.id,
                                page: max(1, page), setName: set.name)
        return passage(text, lecture: lecture.name, source: source, subject: set.subject)
    }
}

// MARK: - Passages of a lecture

/// What the lecture reader does with a passage chosen on one of its pages:
/// set by the reader (SourcePreviewView) when the lecture's set is known,
/// read by the PDF pages and the text pages under it.
struct IdeaPassageSaver {
    let save: (String, Int) -> Void
}

private struct IdeaPassageKey: EnvironmentKey {
    static let defaultValue: IdeaPassageSaver? = nil
}

extension EnvironmentValues {
    var ideaPassage: IdeaPassageSaver? {
        get { self[IdeaPassageKey.self] }
        set { self[IdeaPassageKey.self] = newValue }
    }
}

/// A lecture page's words: selectable with "Save to Ideas" in the menu when
/// the reader can save a passage, plain selectable text otherwise.
struct LecturePassageText: View {
    let text: String
    let page: Int
    @Environment(\.ideaPassage) private var passage
    @ObservedObject private var saver = IdeaSaver.shared

    var body: some View {
        if let passage, saver.isReady {
            let at: Int = page
            IdeaSelectableText(text: text) { picked in passage.save(picked, at) }
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
