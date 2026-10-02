import PDFKit
import SwiftUI

// Only in the Swift Playgrounds core builds: Save to Ideas
// (Shared/Ideas/SaveToIdeasUI.swift) is left out, so the study screens show
// no save button and the lecture reader no "Save to Ideas" menu. What a note
// remembers of where it came from (NoteSource, SaveToIdeas.swift) stays, so
// links and the notes core2 brings back read the same as in the full app.

@MainActor
final class IdeaSaver {
    static let shared = IdeaSaver()

    func save(_ clip: IdeaClip, host: UUID?) {}
}

struct SaveToIdeasButton: View {
    let clip: IdeaClip
    var compact: Bool = false

    var body: some View { EmptyView() }
}

struct SaveableText: View {
    let text: String
    var font: Font = .body
    var style: UIFont.TextStyle = .body
    var lineSpacing: CGFloat = 3
    let clip: (String) -> IdeaClip

    var body: some View {
        Text(text)
            .font(font)
            .lineSpacing(lineSpacing)
    }
}

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

final class IdeaPDFView: PDFView {
    var onSaveSelection: ((String, Int) -> Void)?

    static func saver(_ passage: IdeaPassageSaver?) -> ((String, Int) -> Void)? { nil }
}

struct LecturePassageText: View {
    let text: String
    let page: Int

    var body: some View {
        Text(text)
            .font(.body)
            .textSelection(.enabled)
    }
}

extension View {
    func saveToIdeasHost(_ id: UUID? = nil) -> some View { self }
}

extension SaveToIdeas {
    private static func standIn(_ kind: NoteSource.Kind, item: UUID, in set: StudySet) -> IdeaClip {
        let source = NoteSource(kind: kind, setID: set.id, itemID: item, setName: set.name)
        return IdeaClip(title: set.name, text: "", source: source, subject: set.subject)
    }

    static func clip(question item: MCQQuestion, in set: StudySet, library: [StudySet]) -> IdeaClip {
        standIn(.question, item: item.id, in: set)
    }

    static func clip(card item: AnkiCard, in set: StudySet, library: [StudySet]) -> IdeaClip {
        standIn(.card, item: item.id, in: set)
    }

    static func clip(station item: OsceChecklist, weak: Set<Int>, in set: StudySet,
                     library: [StudySet]) -> IdeaClip {
        standIn(.osce, item: item.id, in: set)
    }

    static func clip(passage text: String, page: Int, of lecture: SourceDoc, in set: StudySet) -> IdeaClip {
        standIn(.lecture, item: lecture.id, in: set)
    }
}
