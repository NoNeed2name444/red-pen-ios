import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

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
    @Published var library: [StudySet] = [] { didSet { libraryDirty = true; changeCount &+= 1 } }
    @Published var folders: [StudyFolder] = [] { didSet { libraryDirty = true; changeCount &+= 1 } }
    /// In-progress MCQ sessions keyed by set id — the web app's
    /// `resumeBanner` / `el.resumeBtn` state, so a quiz closed halfway can be
    /// picked up where it was left.
    @Published var quizProgress: [UUID: QuizProgress] = [:] { didSet { studyDirty = true; changeCount &+= 1 } }
    /// Half-worked OSCE stations, keyed by set id.
    ///
    /// Kept for the same reason a half-finished quiz is. A station is twenty
    /// steps recalled out loud, and it is the mode most likely to be
    /// interrupted - by a phone call, by the ward, by the app being closed
    /// mid-sentence. Losing the position and starting the station again is the
    /// difference between a tool somebody revises with and one they open once.
    @Published var osceProgress: [UUID: OsceProgress] = [:] { didSet { studyDirty = true; changeCount &+= 1 } }
    /// Where the student had got to in a Cases deck or a textbook, keyed by
    /// set id.
    ///
    /// The textbook is the mode this matters most in: it is the longest thing
    /// in the app, read over days, and being put back on page one for having
    /// closed it is the fastest way to stop using it. One number is enough for
    /// both - which card, or which page.
    @Published var readingProgress: [UUID: ReadingProgress] = [:] { didSet { studyDirty = true; changeCount &+= 1 } }
    /// Questions the student has flagged to come back to, by question id.
    ///
    /// By question rather than by set, so a question flagged in a combined
    /// set or a Mistakes set is the same flag wherever it turns up again.
    @Published var flagged: Set<UUID> = [] { didSet { studyDirty = true; changeCount &+= 1 } }
    /// Every MCQ answer checked, right or wrong, oldest first, by question id.
    ///
    /// The quiz itself forgets a session once it is over; this is what is left
    /// behind, so the Progress screen can say which subject is weakest and
    /// the drill can go straight for the questions that were missed.
    @Published var answerHistory: [UUID: [Bool]] = [:] { didSet { studyDirty = true; changeCount &+= 1 } }
    /// Every checked answer in the order it happened, with its date and how
    /// sure the student was - the recent-accuracy and calibration figures on
    /// the Progress screen. Capped (Store.answerLogDepth), oldest dropped.
    @Published var answerLog: [AnswerEvent] = [] { didSet { studyDirty = true; changeCount &+= 1 } }
    /// Why each question was last got wrong, in the student's words, by
    /// question id.
    @Published var mistakeReasons: [UUID: MistakeNote] = [:] { didSet { studyDirty = true; changeCount &+= 1 } }
    /// The rule sheet: one line to remember per missed question, by question id.
    @Published var ruleSheet: [UUID: StudyRule] = [:] { didSet { studyDirty = true; changeCount &+= 1 } }

    /// The library itself: sets, folders, tombstones. Large - it carries every
    /// picture as base64 - so it is rewritten only when one of those changed.
    private let fileURL: URL
    /// Everything about how the studying is going: resume positions, flags,
    /// the answer history and log, mistake reasons, the rule sheet. Small, and
    /// written on its own, so recording an answer never re-encodes the library.
    private let studyURL: URL

    /// What has changed since the last write. Set by the properties' own
    /// observers, so a change made anywhere - not only through the methods
    /// here - is written by the next save.
    private var libraryDirty = false
    private var studyDirty = false
    /// Moves on every change to anything stored here. Not published (the
    /// properties themselves are); a screen that works figures out of the
    /// store compares it to know when they need working out again.
    private(set) var changeCount = 0
    /// The flagged questions as last worked out, and the changeCount they were
    /// worked out at: the library's rows ask on every redraw.
    var flaggedMemo: (at: Int, picks: [QuestionPick])?
    /// Sets this version of the app could not read, exactly as they were
    /// written (JSON text). Written back with the library every time, so
    /// saving never drops them; a version that can read them takes them back
    /// in (load). Without this, the first save after opening a library with
    /// one set from a newer version deleted that set from the file.
    private(set) var unreadSets: [String] = []
    /// Whether every set in the library file is accounted for - read, or
    /// kept as the text it was written in. False after a file that could not
    /// be read at all: the library is then empty only because it was not
    /// read, and a sweep of the files and pictures "nothing refers to" would
    /// delete every one of them (SourceFiles.sweepUnused, SyncEngine).
    private(set) var readWhole = true
    /// The debounced write waiting to run, if any.
    private var pendingWrite: Task<Void, Never>?
    private var lifecycleObservers: [NSObjectProtocol] = []

    /// Encoding and writing happen here, off the main thread, one at a time
    /// and in order, so a later write can never land before an earlier one.
    private static let writeQueue = DispatchQueue(label: "redpen.store.write", qos: .utility)
    /// How long a save waits for more changes before writing: a quiz records
    /// an answer and saves its position within the same tap.
    private static let saveDelayNanoseconds: UInt64 = 400_000_000

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = dir.appendingPathComponent("redpen-library.json")
        }
        self.studyURL = self.fileURL.deletingLastPathComponent()
            .appendingPathComponent(self.fileURL.deletingPathExtension().lastPathComponent + "-progress.json")
        load()
        observeLifecycle()
    }

    /// Ids of things deleted here, and when. Kept so the deletion can be told
    /// to the other devices; forgotten once every device has been told, which
    /// SyncEngine decides.
    /// Written by Store and StoreSync only - `private(set)` would keep the
    /// sync half out, and it is the half that needs to clear them.
    @Published var tombstones: [UUID: Date] = [:] { didSet { libraryDirty = true; changeCount &+= 1 } }

    // MARK: on disk

    func load() {
        var libraryData: Data?
        var rewrite = false
        if let data = try? Data(contentsOf: fileURL) {
            libraryData = data
            if let file = try? JSONDecoder.redPen.decode(LibraryFile.self, from: data) {
                var sets = file.library
                var unread: [String] = []
                // held from before: tried again, since this may be the
                // version that can read them
                for text in file.unread ?? [] {
                    if let set = try? JSONDecoder.redPen.decode(StudySet.self, from: Data(text.utf8)),
                       !sets.contains(where: { $0.id == set.id }) {
                        sets.append(set)
                        rewrite = true
                    } else {
                        unread.append(text)
                    }
                }
                // A set this version cannot read is left out rather than
                // taking the whole library with it - kept as it was written,
                // so the next save carries it along instead of dropping it.
                if file.skipped > 0 {
                    let kept = Self.entries(of: data, at: file.skippedAt)
                    unread += kept
                    // Rewritten straight away, so the file stops being "partly
                    // unreadable" and is not copied aside again every launch -
                    // but only when every one of them was kept; otherwise the
                    // copy put aside below is where they survive.
                    rewrite = rewrite || kept.count == file.skippedAt.count
                    if kept.count != file.skippedAt.count { readWhole = false }
                    setAside(fileURL, as: "library-partly-unreadable", once: true)
                }
                library = sets
                folders = file.folders
                tombstones = file.tombstones ?? [:]
                unreadSets = unread
            } else {
                // never overwritten unread: the file is put aside first, so a
                // library this version cannot read is still there to recover
                setAside(fileURL, as: "library-unreadable", once: true)
                readWhole = false
            }
        }
        var migrated = false
        if let data = try? Data(contentsOf: studyURL) {
            if let study = try? JSONDecoder.redPen.decode(StudyFile.self, from: data) {
                apply(study)
            } else {
                setAside(studyURL, as: "progress-unreadable", once: true)
            }
        } else if let libraryData,
                  let legacy = try? JSONDecoder.redPen.decode(StudyFile.self, from: libraryData) {
            // written before the two were split: the history is still inside
            // the library file, and moves out on the next write
            apply(legacy)
            migrated = true
        }
        libraryDirty = rewrite
        studyDirty = migrated
        if migrated || rewrite { scheduleWrite() }
    }

    /// Entries of the library file's `library` list, as JSON text - the ones
    /// this version could not read, to be kept as they are.
    private static func entries(of data: Data, at indices: [Int]) -> [String] {
        guard !indices.isEmpty,
              let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = top["library"] as? [Any] else { return [] }
        return indices.compactMap { index -> String? in
            guard list.indices.contains(index), JSONSerialization.isValidJSONObject(list[index]),
                  let one = try? JSONSerialization.data(withJSONObject: list[index]) else { return nil }
            return String(data: one, encoding: .utf8)
        }
    }

    /// Pictures named by sets this version could not read, so a sweep of the
    /// picture cache keeps them.
    var heldPictureNames: Set<String> {
        unreadSets.reduce(into: Set<String>()) { $0.formUnion(BlobRefs.names(mentionedIn: $1)) }
    }

    private func apply(_ study: StudyFile) {
        quizProgress = study.quizProgress
        osceProgress = study.osceProgress
        readingProgress = study.readingProgress
        flagged = study.flagged
        answerHistory = study.answerHistory
        answerLog = study.answerLog
        mistakeReasons = study.mistakeReasons
        ruleSheet = study.ruleSheet
    }

    /// A copy of a file put beside it before anything can write over it.
    ///
    /// `once`: not again for a file that has already been put aside - a
    /// library of hundreds of megabytes copied on every launch fills the
    /// phone. The same size under the same name is taken as the same file.
    private func setAside(_ url: URL, as name: String, once: Bool = false) {
        let folder = url.deletingLastPathComponent()
        if once, let size = Self.size(of: url) {
            let earlier = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            let same = earlier.contains { file in
                file.hasPrefix(name + "-") && Self.size(of: folder.appendingPathComponent(file)) == size
            }
            if same { return }
        }
        let aside = folder.appendingPathComponent("\(name)-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: url, to: aside)
    }

    private static func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    /// Asks for whatever changed to be written, shortly and off the main
    /// thread. Cheap to call on every tap: changes made close together are
    /// written once, and only the file that changed is written at all.
    func save() {
        scheduleWrite()
    }

    /// Writes anything outstanding now - for the moment before the app goes
    /// to the background, and for sync, which must not record a document as
    /// seen before the library holding it is on its way to disk.
    ///
    /// `wait` blocks until the bytes are on disk - only for the app being
    /// ended, when nothing queued would get the chance to run.
    func flush(wait: Bool = false) {
        pendingWrite?.cancel()
        pendingWrite = nil
        write()
        if wait { Self.writeQueue.sync {} }
    }

    /// Writes anything outstanding and returns once it is on disk, without
    /// holding the main thread while it is written - for a caller about to
    /// throw away the only other copy (a cloud job forgotten on the server).
    func flushed() async {
        flush()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            Self.writeQueue.async { done.resume() }
        }
    }

    private func scheduleWrite() {
        guard pendingWrite == nil else { return }
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Store.saveDelayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.pendingWrite = nil
            self.write()
        }
    }

    /// Takes a copy of the changed parts here (cheap: they are values) and
    /// encodes and writes them on the write queue.
    private func write() {
        guard libraryDirty || studyDirty else { return }
        var libraryFile: LibraryFile?
        var studyFile: StudyFile?
        if libraryDirty {
            libraryFile = LibraryFile(library: library, folders: folders, tombstones: tombstones,
                                      unread: unreadSets.isEmpty ? nil : unreadSets)
        }
        if studyDirty {
            var study = StudyFile()
            study.quizProgress = quizProgress
            study.osceProgress = osceProgress
            study.readingProgress = readingProgress
            study.flagged = flagged
            study.answerHistory = answerHistory
            study.answerLog = answerLog
            study.mistakeReasons = mistakeReasons
            study.ruleSheet = ruleSheet
            studyFile = study
        }
        libraryDirty = false
        studyDirty = false
        let job = WriteJob(library: libraryFile, libraryURL: fileURL, study: studyFile, studyURL: studyURL)
        #if canImport(UIKit)
        // a write started just before the app is backgrounded still finishes
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "Saving library", expirationHandler: nil)
        Self.writeQueue.async {
            job.run()
            Task { @MainActor in
                if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            }
        }
        #else
        Self.writeQueue.async { job.run() }
        #endif
    }

    /// Writes anything outstanding when the app leaves the foreground, where
    /// it may be suspended or ended before a delayed write would run.
    private func observeLifecycle() {
        #if canImport(UIKit)
        let names: [Notification.Name] = [UIApplication.didEnterBackgroundNotification,
                                          UIApplication.willTerminateNotification]
        for name in names {
            let ending = name == UIApplication.willTerminateNotification
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush(wait: ending) }
            }
            lifecycleObservers.append(token)
        }
        #endif
    }

    func addSet(_ set: StudySet) {
        library.append(set)
        save()
    }

    func deleteSet(_ id: UUID) {
        let left = library.first { $0.id == id }?.folderId
        library.removeAll { $0.id == id }
        quizProgress[id] = nil
        osceProgress[id] = nil
        readingProgress[id] = nil
        tombstones[id] = Date()
        pruneEmptyFolders(left: [left])
        // and its lecture recording: a file outside the library, tens of
        // megabytes and often of other people's voices, that nothing could
        // reach or remove once the set is gone
        LectureAudio.remove(for: id)
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
    ///
    /// `base` is the set as an editor had it when it started (CardsEditorView,
    /// Narrate's transcript). An editor's save is a whole set written over
    /// whatever is there; if a sync brought the other device's edit to it in
    /// the meantime, that version is kept as a copy beside this one rather
    /// than overwritten - with nothing to tell the sync that anything was
    /// lost, it would be gone on every device.
    func update(_ set: StudySet, base: StudySet? = nil) {
        guard let idx = library.firstIndex(where: { $0.id == set.id }) else { return }
        var incoming = set
        incoming.updatedAt = library[idx].updatedAt
        guard incoming != library[idx] else { return }
        if let base, Self.movedOn(library[idx], since: base) {
            keepConflictCopy(of: library[idx], from: "another device", beside: incoming)
        }
        guard let at = library.firstIndex(where: { $0.id == set.id }) else { return }
        incoming.updatedAt = Date()
        library[at] = incoming
        save()
    }

    /// Whether the library's copy of a set holds something `base` did not -
    /// its stamp aside, and pictures merely filled in by a sync.
    nonisolated static func movedOn(_ current: StudySet, since base: StudySet) -> Bool {
        var now = current
        now.updatedAt = base.updatedAt
        now.images = base.images
        if now != base { return true }
        return !BlobRefs.samePictures(current.images, base.images)
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
        var left: [UUID?] = []
        for idx in library.indices where ids.contains(library[idx].id) {
            left.append(library[idx].folderId)
            library[idx].folderId = folder.id
            library[idx].updatedAt = Date()
        }
        pruneEmptyFolders(left: left)
        save()
        return folder
    }

    /// Moves one set into a folder (or out of every folder with `nil`).
    func move(_ id: UUID, to folderId: UUID?) {
        guard let idx = library.firstIndex(where: { $0.id == id }),
              library[idx].folderId != folderId else { return }
        let left = library[idx].folderId
        library[idx].folderId = folderId
        library[idx].updatedAt = Date()
        pruneEmptyFolders(left: [left])
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

    /// Removes the folders sets just left, if that left them empty - with a
    /// tombstone, like any other deletion, or the other devices keep the
    /// folder for good and an edit to it there brings it back here.
    ///
    /// Only the folders just left, never every empty one: a folder a sync has
    /// brought before its sets (a first sync, part way through) is empty for
    /// a moment and must not be deleted on every device for it.
    private func pruneEmptyFolders(left: [UUID?]) {
        let used = Set(library.compactMap(\.folderId))
        let emptied = Set(left.compactMap { $0 }).subtracting(used)
        guard !emptied.isEmpty else { return }
        let now = Date()
        for id in emptied where folders.contains(where: { $0.id == id }) { tombstones[id] = now }
        folders.removeAll { emptied.contains($0.id) }
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

// MARK: - many sets at once, and the backup's progress

extension Store {
    /// Many sets at once - an Anki package's subdecks, a restored backup -
    /// as ONE change to the library: the list redraws once and the file is
    /// written once, rather than once per set.
    func addSets(_ sets: [StudySet]) {
        guard !sets.isEmpty else { return }
        library.append(contentsOf: sets)
        save()
    }

    /// Everything about how the studying is going, as the progress file
    /// holds it - for a backup (LibraryBackupRunner).
    func studyBackup() -> Data? {
        var study = StudyFile()
        study.quizProgress = quizProgress
        study.osceProgress = osceProgress
        study.readingProgress = readingProgress
        study.flagged = flagged
        study.answerHistory = answerHistory
        study.answerLog = answerLog
        study.mistakeReasons = mistakeReasons
        study.ruleSheet = ruleSheet
        return try? JSONEncoder.redPen.encode(study)
    }

    /// A backup's progress merged into this phone's: nothing here is
    /// overwritten. Positions and notes fill in where there are none, flags
    /// are joined, a longer answer history wins, and the answer log is the
    /// two logs together in date order. `renamed` moves a set's positions to
    /// the id it came back under.
    func mergeStudy(from data: Data, renamed: [UUID: UUID]) {
        guard let study = try? JSONDecoder.redPen.decode(StudyFile.self, from: data) else { return }
        var quiz = quizProgress
        for (id, value) in study.quizProgress where quiz[renamed[id] ?? id] == nil { quiz[renamed[id] ?? id] = value }
        if quiz.count != quizProgress.count { quizProgress = quiz }
        var osce = osceProgress
        for (id, value) in study.osceProgress where osce[renamed[id] ?? id] == nil { osce[renamed[id] ?? id] = value }
        if osce.count != osceProgress.count { osceProgress = osce }
        var reading = readingProgress
        for (id, value) in study.readingProgress where reading[renamed[id] ?? id] == nil { reading[renamed[id] ?? id] = value }
        if reading.count != readingProgress.count { readingProgress = reading }
        let flags: Set<UUID> = flagged.union(study.flagged)
        if flags.count != flagged.count { flagged = flags }
        var history = answerHistory
        for (id, answers) in study.answerHistory where answers.count > (history[id]?.count ?? 0) { history[id] = answers }
        if history != answerHistory { answerHistory = history }
        var seen = Set(answerLog.map { "\($0.questionId)|\($0.date.timeIntervalSince1970)" })
        var log = answerLog
        for event in study.answerLog {
            let key = "\(event.questionId)|\(event.date.timeIntervalSince1970)"
            if seen.insert(key).inserted { log.append(event) }
        }
        if log.count != answerLog.count {
            log.sort { $0.date < $1.date }
            if log.count > Self.answerLogDepth { log.removeFirst(log.count - Self.answerLogDepth) }
            answerLog = log
        }
        var reasons = mistakeReasons
        for (id, note) in study.mistakeReasons where reasons[id] == nil { reasons[id] = note }
        if reasons.count != mistakeReasons.count { mistakeReasons = reasons }
        var rules = ruleSheet
        for (id, rule) in study.ruleSheet where rules[id] == nil { rules[id] = rule }
        if rules.count != ruleSheet.count { ruleSheet = rules }
        save()
    }
}

// MARK: - read-only

extension Store {
    /// The library as last saved, read without a Store: no lifecycle
    /// observers, no migration, no write. For an App Intent's query when
    /// Siri or Shortcuts woke the app with no library on screen - a second
    /// Store there would be a second writer to the same files. Call it off
    /// the main thread: the whole library is decoded.
    nonisolated static func savedLibrary(fileURL: URL? = nil) -> [StudySet] {
        let url: URL
        if let fileURL {
            url = fileURL
        } else {
            let dir: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            url = dir.appendingPathComponent("redpen-library.json")
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let file = try? JSONDecoder.redPen.decode(LibraryFile.self, from: data) else { return [] }
        return file.library
    }
}

// MARK: - the two files

/// The library file. Read tolerantly: a set this version cannot decode is
/// skipped (and counted) instead of failing the whole library.
private struct LibraryFile: Codable {
    var library: [StudySet]
    var folders: [StudyFolder]
    var tombstones: [UUID: Date]?
    /// Sets an earlier run could not read, kept as the JSON they were written
    /// in (Store.unreadSets).
    var unread: [String]?
    /// Sets left out on reading because they could not be decoded.
    var skipped = 0
    /// Where in `library` they were, so they can be kept as written.
    var skippedAt: [Int] = []

    enum CodingKeys: String, CodingKey {
        case library, folders, tombstones, unread
    }

    init(library: [StudySet], folders: [StudyFolder], tombstones: [UUID: Date]?, unread: [String]?) {
        self.library = library
        self.folders = folders
        self.tombstones = tombstones
        self.unread = unread
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let sets = try c.decode([Lossy<StudySet>].self, forKey: .library)
        library = sets.compactMap { $0.value }
        skipped = sets.count - library.count
        skippedAt = sets.indices.filter { sets[$0].value == nil }
        unread = (try? c.decodeIfPresent([String].self, forKey: .unread)) ?? nil
        let kept = (try? c.decodeIfPresent([Lossy<StudyFolder>].self, forKey: .folders)) ?? nil
        folders = (kept ?? []).compactMap { $0.value }
        tombstones = (try? c.decodeIfPresent([UUID: Date].self, forKey: .tombstones)) ?? nil
    }
}

/// The progress file: everything about how the studying is going. Each part
/// is read on its own, so one that cannot be read costs only itself.
///
/// Also read from an old library file, which held all of these at its top
/// level under the same names.
private struct StudyFile: Codable {
    var quizProgress: [UUID: QuizProgress] = [:]
    var osceProgress: [UUID: OsceProgress] = [:]
    var readingProgress: [UUID: ReadingProgress] = [:]
    var flagged: Set<UUID> = []
    var answerHistory: [UUID: [Bool]] = [:]
    var answerLog: [AnswerEvent] = []
    var mistakeReasons: [UUID: MistakeNote] = [:]
    var ruleSheet: [UUID: StudyRule] = [:]

    enum CodingKeys: String, CodingKey {
        case quizProgress, osceProgress, readingProgress, flagged, answerHistory,
             answerLog, mistakeReasons, ruleSheet
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let quiz = (try? c.decodeIfPresent([UUID: QuizProgress].self, forKey: .quizProgress)) ?? nil
        quizProgress = quiz ?? [:]
        let osce = (try? c.decodeIfPresent([UUID: OsceProgress].self, forKey: .osceProgress)) ?? nil
        osceProgress = osce ?? [:]
        let reading = (try? c.decodeIfPresent([UUID: ReadingProgress].self, forKey: .readingProgress)) ?? nil
        readingProgress = reading ?? [:]
        let flags = (try? c.decodeIfPresent(Set<UUID>.self, forKey: .flagged)) ?? nil
        flagged = flags ?? []
        let history = (try? c.decodeIfPresent([UUID: [Bool]].self, forKey: .answerHistory)) ?? nil
        answerHistory = history ?? [:]
        let log = (try? c.decodeIfPresent([Lossy<AnswerEvent>].self, forKey: .answerLog)) ?? nil
        answerLog = (log ?? []).compactMap { $0.value }
        let reasons = (try? c.decodeIfPresent([UUID: MistakeNote].self, forKey: .mistakeReasons)) ?? nil
        mistakeReasons = reasons ?? [:]
        let rules = (try? c.decodeIfPresent([UUID: StudyRule].self, forKey: .ruleSheet)) ?? nil
        ruleSheet = rules ?? [:]
    }
}

/// One element of an array that may not decode; nil when it did not.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// One write, carried to the write queue: the parts that changed, already
/// copied, and where they go. Only value types, so it is safe to hand over.
private struct WriteJob: @unchecked Sendable {
    var library: LibraryFile?
    var libraryURL: URL
    var study: StudyFile?
    var studyURL: URL

    func run() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let library, let data = try? encoder.encode(library) {
            try? data.write(to: libraryURL, options: .atomic)
        }
        if let study, let data = try? encoder.encode(study) {
            try? data.write(to: studyURL, options: .atomic)
        }
    }
}

/// How far into a textbook or a Cases deck somebody had read.
struct ReadingProgress: Codable, Hashable {
    var position: Int
    var savedAt: Date = Date()
}

/// A station part way through: which checklist, which step, and the step each
/// start over happened at so far (`missed`, one entry per start over).
/// `repeatQueue` and `repeatPos` are from the old second pass over missed
/// steps; they are no longer written, only read so older saves still load.
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
