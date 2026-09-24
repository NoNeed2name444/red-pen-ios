import Foundation
import Combine

/// The library, on this device.
///
/// Everything lives in one JSON file in the app's Documents directory. It is
/// the source of truth for what the student has; SyncEngine reconciles it with
/// the server rather than replacing it, so the app works exactly as well with
/// no account and no signal.
///
/// Two things here exist only for sync's sake, and both are the kind of thing
/// that has to be designed in rather than added later.
///
/// **updatedAt is stamped only on a real change.** Several screens re-save a
/// set on every small interaction; if that counted as an edit, every device
/// would see the whole library move every time somebody opened a deck.
///
/// **Deletions leave a tombstone.** A row that merely vanishes is a row the
/// other device cheerfully uploads again, for ever.
@MainActor
final class Store: ObservableObject {
    @Published var library: [StudySet] = []
    @Published var folders: [StudyFolder] = []
    /// In-progress MCQ sessions keyed by set id — the web app's
    /// `resumeBanner` / `el.resumeBtn` state, so a quiz closed halfway can be
    /// picked up where it was left.
    @Published var quizProgress: [UUID: QuizProgress] = [:]
    /// Half-worked OSCE stations, keyed by set id.
    ///
    /// Kept for the same reason a half-finished quiz is. A station is twenty
    /// steps recalled out loud, and it is the mode most likely to be
    /// interrupted - by a phone call, by the ward, by the app being closed
    /// mid-sentence. Losing the position and starting the station again is the
    /// difference between a tool somebody revises with and one they open once.
    @Published var osceProgress: [UUID: OsceProgress] = [:]
    /// Where the student had got to in a Cases deck or a textbook, keyed by
    /// set id.
    ///
    /// The textbook is the mode this matters most in: it is the longest thing
    /// in the app, read over days, and being put back on page one for having
    /// closed it is the fastest way to stop using it. One number is enough for
    /// both - which card, or which page.
    @Published var readingProgress: [UUID: ReadingProgress] = [:]
    /// Questions the student has flagged to come back to, by question id.
    ///
    /// By question rather than by set, so a question flagged in a combined
    /// set or a Mistakes set is the same flag wherever it turns up again.
    @Published var flagged: Set<UUID> = []
    /// Every MCQ answer checked, right or wrong, oldest first, by question id.
    ///
    /// The quiz itself forgets a session once it is over; this is what is left
    /// behind, so the Progress screen can say which subject is weakest and
    /// the drill can go straight for the questions that were missed.
    @Published var answerHistory: [UUID: [Bool]] = [:]
    /// Every checked answer in the order it happened, with its date and how
    /// sure the student was - the recent-accuracy and calibration figures on
    /// the Progress screen. Capped (Store.answerLogDepth), oldest dropped.
    @Published var answerLog: [AnswerEvent] = []
    /// Why each question was last got wrong, in the student's words, by
    /// question id.
    @Published var mistakeReasons: [UUID: MistakeNote] = [:]
    /// The rule sheet: one line to remember per missed question, by question id.
    @Published var ruleSheet: [UUID: StudyRule] = [:]

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = dir.appendingPathComponent("redpen-library.json")
        }
        load()
    }

    /// Ids of things deleted here, and when. Kept so the deletion can be told
    /// to the other devices; forgotten once every device has been told, which
    /// SyncEngine decides.
    /// Written by Store and StoreSync only - `private(set)` would keep the
    /// sync half out, and it is the half that needs to clear them.
    @Published var tombstones: [UUID: Date] = [:]

    private struct Snapshot: Codable {
        var library: [StudySet]
        var folders: [StudyFolder]
        var quizProgress: [UUID: QuizProgress]? // added later; older files simply lack it
        var tombstones: [UUID: Date]?           // likewise
        var osceProgress: [UUID: OsceProgress]? // likewise
        var readingProgress: [UUID: ReadingProgress]? // likewise
        var flagged: Set<UUID>?                 // likewise
        var answerHistory: [UUID: [Bool]]?      // likewise
        var answerLog: [AnswerEvent]?           // likewise
        var mistakeReasons: [UUID: MistakeNote]? // likewise
        var ruleSheet: [UUID: StudyRule]?       // likewise
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let snapshot = try? JSONDecoder.redPen.decode(Snapshot.self, from: data) else {
            // never overwritten unread: the file is put aside first, so a
            // library this version cannot read is still there to recover
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("library-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: aside)
            return
        }
        library = snapshot.library
        folders = snapshot.folders
        quizProgress = snapshot.quizProgress ?? [:]
        tombstones = snapshot.tombstones ?? [:]
        osceProgress = snapshot.osceProgress ?? [:]
        readingProgress = snapshot.readingProgress ?? [:]
        flagged = snapshot.flagged ?? []
        answerHistory = snapshot.answerHistory ?? [:]
        answerLog = snapshot.answerLog ?? []
        mistakeReasons = snapshot.mistakeReasons ?? [:]
        ruleSheet = snapshot.ruleSheet ?? [:]
    }

    func save() {
        var snapshot = Snapshot(library: library, folders: folders,
                                quizProgress: quizProgress, tombstones: tombstones,
                                osceProgress: osceProgress,
                                readingProgress: readingProgress,
                                flagged: flagged,
                                answerHistory: answerHistory)
        snapshot.answerLog = answerLog
        snapshot.mistakeReasons = mistakeReasons
        snapshot.ruleSheet = ruleSheet
        guard let data = try? JSONEncoder.redPen.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addSet(_ set: StudySet) {
        library.append(set)
        save()
    }

    func deleteSet(_ id: UUID) {
        library.removeAll { $0.id == id }
        quizProgress[id] = nil
        osceProgress[id] = nil
        readingProgress[id] = nil
        tombstones[id] = Date()
        pruneEmptyFolders()
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = library.firstIndex(where: { $0.id == id }), library[idx].name != name
        else { return }
        library[idx].name = name
        library[idx].updatedAt = Date()
        save()
    }

    /// Replaces a set, and stamps it ONLY if something about it really differs.
    ///
    /// Narrate saves the whole set after every corrected word, and the review
    /// screens save after every rating. Treating those as edits would have the
    /// library churning against every other device all day.
    func update(_ set: StudySet) {
        guard let idx = library.firstIndex(where: { $0.id == set.id }) else { return }
        var incoming = set
        incoming.updatedAt = library[idx].updatedAt
        guard incoming != library[idx] else { return }
        incoming.updatedAt = Date()
        library[idx] = incoming
        save()
    }

    func addFolder(name: String) {
        folders.append(StudyFolder(name: name))
        save()
    }

    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        tombstones[id] = Date()
        for idx in library.indices where library[idx].folderId == id {
            library[idx].folderId = nil
            library[idx].updatedAt = Date()
        }
        save()
    }

    // MARK: folders — mirrors createLibFolder() / ungroupLibFolder()

    /// Puts `ids` into a new folder called `name`. Any folder a set leaves
    /// that is now empty is removed, same as the web app's auto-cleanup.
    @discardableResult
    func group(_ ids: Set<UUID>, into name: String) -> StudyFolder {
        let folder = StudyFolder(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Folder" : name)
        folders.append(folder)
        for idx in library.indices where ids.contains(library[idx].id) {
            library[idx].folderId = folder.id
            library[idx].updatedAt = Date()
        }
        pruneEmptyFolders()
        save()
        return folder
    }

    /// Moves one set into a folder (or out of every folder with `nil`).
    func move(_ id: UUID, to folderId: UUID?) {
        guard let idx = library.firstIndex(where: { $0.id == id }),
              library[idx].folderId != folderId else { return }
        library[idx].folderId = folderId
        library[idx].updatedAt = Date()
        pruneEmptyFolders()
        save()
    }

    /// Clears the folder on every member and removes the folder — never
    /// deletes the sets themselves.
    func ungroup(_ folderId: UUID) {
        for idx in library.indices where library[idx].folderId == folderId {
            library[idx].folderId = nil
            library[idx].updatedAt = Date()
        }
        folders.removeAll { $0.id == folderId }
        tombstones[folderId] = Date()
        save()
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }), folders[idx].name != name
        else { return }
        folders[idx].name = name
        folders[idx].updatedAt = Date()
        save()
    }

    private func pruneEmptyFolders() {
        let used = Set(library.compactMap(\.folderId))
        folders.removeAll { !used.contains($0.id) }
    }

    // MARK: combine — mirrors the library's "Combine N selected" flow

    /// Merges two or more sets of the same kind into one new set named
    /// `name`, re-basing every image index into the combined image pool.
    /// The originals are left untouched, as in the web app.
    @discardableResult
    func combine(_ ids: [UUID], name: String) -> StudySet? {
        let members = ids.compactMap { id in library.first { $0.id == id } }
        guard let first = members.first, members.count >= 2,
              members.allSatisfy({ $0.kind == first.kind }) else { return nil }
        var out = StudySet(name: name, subject: first.subject, kind: first.kind)
        for m in members {
            let base = out.images.count
            out.images.append(contentsOf: m.images)
            switch m.kind {
            case .mcq:
                out.questions.append(contentsOf: m.questions.map { q in
                    var q = q; q.id = UUID(); if let i = q.imageIndex { q.imageIndex = i + base }; return q
                })
            case .anki:
                out.cards.append(contentsOf: m.cards.map { c in
                    var c = c; c.id = UUID(); if let i = c.imageIndex { c.imageIndex = i + base }; return c
                })
            case .book:
                out.bookMarkdown += (out.bookMarkdown.isEmpty ? "" : "\n\n") + m.bookMarkdown
            case .qa:
                out.qaCards.append(contentsOf: m.qaCards.map { var c = $0; c.id = UUID(); return c })
            case .osce:
                out.osceChecklists.append(contentsOf: m.osceChecklists.map { var c = $0; c.id = UUID(); return c })
            case .narrate:
                out.narrateSegments.append(contentsOf: m.narrateSegments.map { var s = $0; s.id = UUID(); return s })
            }
        }
        library.append(out)
        save()
        return out
    }

    // MARK: quiz resume — mirrors the web app's resume banner

    func saveProgress(_ progress: QuizProgress, for setId: UUID) {
        quizProgress[setId] = progress
        save()
    }

    func clearProgress(for setId: UUID) {
        guard quizProgress[setId] != nil else { return }
        quizProgress[setId] = nil
        save()
    }

    // MARK: OSCE resume

    func saveOsce(_ progress: OsceProgress, for setId: UUID) {
        osceProgress[setId] = progress
        save()
    }

    func clearOsce(for setId: UUID) {
        guard osceProgress[setId] != nil else { return }
        osceProgress[setId] = nil
        save()
    }

    // MARK: where they had got to in a textbook or a Cases deck

    /// Remembers a position, and only writes when it really moved.
    ///
    /// Both readers save on every turn of the page, and the library file holds
    /// the whole of everything; rewriting it to record the page it already
    /// knew about would be a disk write per tap.
    func saveReading(at position: Int, for setId: UUID) {
        guard readingProgress[setId]?.position != position else { return }
        guard position > 0 else {
            // Back at the beginning is not a position worth keeping, and
            // storing it would leave a row per set that was merely opened.
            if readingProgress[setId] != nil { readingProgress[setId] = nil; save() }
            return
        }
        readingProgress[setId] = ReadingProgress(position: position)
        save()
    }

    func reading(for setId: UUID, count: Int) -> Int {
        guard let saved = readingProgress[setId], saved.position < count else { return 0 }
        return saved.position
    }

    func clearReading(for setId: UUID) {
        guard readingProgress[setId] != nil else { return }
        readingProgress[setId] = nil
        save()
    }
}

/// How far into a textbook or a Cases deck somebody had read.
struct ReadingProgress: Codable, Hashable {
    var position: Int
    var savedAt: Date = Date()
}

/// A station part way through: which checklist, which step, and which steps
/// have been missed so far.
///
/// `checklistTitle` rather than only the index, because a set can be edited
/// between sessions. Resuming by index alone into a set whose stations have
/// been reordered drops somebody into the middle of a different station with
/// their missed steps attached to it, which is worse than starting again.
struct OsceProgress: Codable, Hashable {
    var checklistIndex: Int
    var checklistTitle: String
    var stepIndex: Int
    var missed: [Int]
    var repeatQueue: [Int] = []
    var repeatPos: Int = 0
    var savedAt: Date = Date()

    /// Whether this position still makes sense for the set as it is now.
    func fits(_ checklists: [OsceChecklist]) -> Bool {
        guard checklists.indices.contains(checklistIndex) else { return false }
        let checklist = checklists[checklistIndex]
        guard checklist.title == checklistTitle else { return false }
        guard stepIndex >= 0, stepIndex < max(checklist.steps.count, 1) else { return false }
        return missed.allSatisfy { checklist.steps.indices.contains($0) }
            && repeatQueue.allSatisfy { checklist.steps.indices.contains($0) }
            && (repeatQueue.isEmpty || repeatPos < repeatQueue.count)
    }
}

/// A half-finished MCQ session: which question was up and every answer so
/// far. The (possibly shuffled) question order is kept too, so resuming
/// shows the same options in the same places.
struct QuizProgress: Codable, Hashable {
    var current: Int
    var answers: [MCQAnswer]
    var questionIds: [UUID]
    var optionOrders: [[Int]]
    var savedAt: Date = Date()
}

extension JSONDecoder {
    static let redPen: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let redPen: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
