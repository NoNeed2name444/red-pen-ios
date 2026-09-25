import BackgroundTasks
import UIKit
import UserNotifications

/// What a set written in the cloud needs to be finished without the screen
/// that asked for it: kept with the job (CloudJobs.recipe) in case the app is
/// closed before the server is done.
struct CloudRecipe: Codable {
    var kind: StudySetKind
    var name: String
    var subject: String
    var count: Int
    var source: SourceDoc?
    /// A textbook's figures, in the order the job's placement counts them.
    var figures: [String]?
    /// Image occlusion cards that go with the written ones.
    var diagramCards: [AnkiCard]?
    var diagramImages: [String]?
    /// The accuracy check it was asked for: "server" (checked in the cloud
    /// job), "device" (a checker on this device), or nil for none.
    var check: String?

    var encoded: Data? { try? JSONEncoder().encode(self) }

    /// The set, from the job's replies - the same parsing the screens use.
    func set(from replies: [String], extra: Data?) -> StudySet? {
        let title = name.trimmingCharacters(in: .whitespaces)
        var set = StudySet(name: title.isEmpty ? "\(subject.isEmpty ? "Generated" : subject) \u{2013} \(kind.cloudNoun)" : title,
                           subject: subject.isEmpty ? "General" : subject, kind: kind)
        switch kind {
        case .mcq:
            guard let questions = try? MedicalGenerate.collectQuestions(replies, count: count) else { return nil }
            set.questions = source.map {
                Provenance.attribute(questions, to: SourceText.Document(pages: $0.pages.map {
                    SourceText.Page(number: $0.number, text: $0.text, recognised: $0.recognised)
                }), name: $0.name)
            } ?? questions
        case .osce:
            guard let stations = try? MedicalGenerate.collectStations(replies, count: count) else { return nil }
            set.osceChecklists = stations
        case .qa:
            set.qaCards = PlainTextImport.parseQA(LectureWriter.collectLines(replies, kind: .qa, count: count).joined(separator: "\n"))
            guard !set.qaCards.isEmpty else { return nil }
        case .anki:
            set.cards = PlainTextImport.parseAnkiQA(LectureWriter.collectLines(replies, kind: .anki, count: count).joined(separator: "\n"))
            guard !set.cards.isEmpty else { return nil }
            if let diagramCards, let diagramImages, !diagramCards.isEmpty {
                set.cards += diagramCards
                set.images = diagramImages
            }
        case .book:
            let placement = extra.flatMap { try? JSONDecoder().decode([[Int]].self, from: $0) } ?? []
            let markdown = LectureWriter.assembleBook(replies, placement: placement)
            guard !markdown.isEmpty else { return nil }
            let kept = BookFigures.compact(markdown, images: figures ?? [])
            set.bookMarkdown = kept.markdown
            set.images = kept.images
        case .narrate:
            return nil
        }
        set.sources = source.map { [$0] } ?? []
        return set
    }
}

private extension StudySetKind {
    var cloudNoun: String {
        switch self {
        case .mcq: return "questions"
        case .osce: return "OSCE stations"
        case .qa: return "cases"
        case .anki: return "cards"
        case .book: return "textbook"
        case .narrate: return "lecture"
        }
    }
}

/// Jobs the server finished while the app was closed become sets in the
/// library, the next time the app is opened - and, where the build allows a
/// background check, a notification says so before then.
@MainActor
enum CloudJobCollector {
    private static var collecting = false

    /// Picks up every job started by an earlier run of the app (this run's
    /// jobs are being watched by the screens that started them).
    static func collect(into store: Store) async {
        guard !collecting else { return }
        collecting = true
        defer { collecting = false }
        let llm = LocalLLMService.shared
        for pending in CloudJobs.pending() where pending.launch != CloudJobs.launch {
            // Asked about only as the identity it was made under: the server
            // keeps jobs per account (or for the owner key), and asking as
            // anyone else finds nothing - which is not the job being gone.
            let bearer: String? = llm.cloudBearer(for: pending.identity)
            // A generation the app was closed on carries its replies with it:
            // made into its set whoever is signed in now, server or no server.
            let kept: Bool = pending.delivered == true && pending.outputs != nil
            if bearer == nil && !kept {
                if CloudJobRules.letGo(started: pending.started, answer: .unreachable, reachable: false) {
                    CloudJobs.remove(pending.id)
                }
                continue
            }
            let endpoint: (base: URL, bearer: String)? = bearer.map { (base: AuthAPI.baseURL, bearer: $0) }
            // this job's verdicts are read by this job's set alone
            let context = CloudJobs.Context(recipe: pending.recipe, delivery: CloudJobs.Delivery())
            await CloudJobs.$context.withValue(context) {
                await collectOne(pending, at: endpoint, into: store)
            }
        }
    }

    /// `endpoint` is nil only for a job whose replies were kept with it
    /// (`delivered`), made under an identity this device cannot ask as now.
    private static func collectOne(_ pending: CloudJobs.Pending, at endpoint: (base: URL, bearer: String)?,
                                   into store: Store) async {
        let outputs: [String]
        let checks: [CloudJobs.Verdict]
        var recovered = false
        if pending.delivered == true, let kept = pending.outputs {
            // Handed to the screen that asked for it, which never finished
            // with it: the app was closed while it was being checked or saved.
            outputs = kept
            checks = pending.checks ?? []
            recovered = true
        } else {
            guard let endpoint else { return }
            let status: CloudJobs.Status
            do {
                status = try await CloudJobs.status(pending.id, at: endpoint)
            } catch {
                // Gone from the server (collected elsewhere, or a week old) -
                // but only when the server says so. No signal, a server error
                // or a session that ran out leave the job to be asked about
                // again next time.
                var code: Int?
                if case LLMError.http(let status, _) = error { code = status }
                let answer = CloudJobRules.answer(forFailedStatus: code)
                if CloudJobRules.letGo(started: pending.started, answer: answer, reachable: true) {
                    CloudJobs.remove(pending.id)
                }
                return
            }
            switch status.status {
            case "done":
                guard let fetched = try? await CloudJobs.result(pending.id, at: endpoint) else { return }
                outputs = fetched.outputs
                checks = fetched.checks
            case "failed":
                CloudJobs.remove(pending.id)
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["job-" + pending.id])
                await CloudJobs.forget(pending.id, at: endpoint)
                return
            default:
                return
            }
        }
        CloudChecks.server(checks)
        let recipe: CloudRecipe? = pending.recipe.flatMap { try? JSONDecoder().decode(CloudRecipe.self, from: $0) }
        var made: StudySet?
        var body: String = recovered
            ? "Written in the cloud; the app was closed before it was saved."
            : "Written in the cloud while the app was closed."
        if let recipe, var set = recipe.set(from: outputs, extra: pending.extra) {
            // the accuracy check is never skipped: the server's
            // verdicts, and this device's checker for anything the
            // server could not check
            let note = recipe.check == nil ? "" : await screen(&set, recipe: recipe)
            body += note
            made = set
        } else if let kept = asText(outputs, pending: pending, recipe: recipe) {
            // The replies could not be made into a set (or its recipe could
            // not be read). Kept as text rather than thrown away with the
            // generation that paid for them.
            let meant: String = recipe.map { $0.kind.cloudNoun } ?? "a set"
            body = "Kept as text \u{2014} it could not be turned into \(meant)."
            made = kept
        }
        if let made {
            store.addSet(made)
            // on disk before the server's copy is forgotten below: the
            // library saves on a short delay, and this is the only copy
            await store.flushed()
            AppNotifications.generationFinished("\(made.name) is ready", body: body)
        }
        CloudJobs.remove(pending.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["job-" + pending.id])
        // the server's copy, where this device can still reach it; otherwise
        // it expires there on its own
        if let endpoint { await CloudJobs.forget(pending.id, at: endpoint) }
    }

    /// What the cloud wrote, as a textbook of its own, for replies that could
    /// not be made into the set they were for. Nil when there is nothing.
    private static func asText(_ outputs: [String], pending: CloudJobs.Pending,
                               recipe: CloudRecipe?) -> StudySet? {
        let parts: [String] = outputs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let text: String = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty else { return nil }
        let title: String = recipe.map { $0.name.trimmingCharacters(in: .whitespaces) } ?? ""
        let subject: String = recipe?.subject ?? ""
        let name: String = (title.isEmpty ? pending.title : title) + " (as written)"
        var set = StudySet(name: name, subject: subject.isEmpty ? "General" : subject, kind: .book)
        set.bookMarkdown = text
        set.sources = recipe?.source.map { [$0] } ?? []
        return set
    }

    /// Drops what the checker grades high risk (questions, stations), as the
    /// screens do; returns a note of what it did.
    private static func screen(_ set: inout StudySet, recipe: CloudRecipe) async -> String {
        let source = recipe.source?.pages.map(\.text).joined(separator: "\n\n") ?? ""
        let checker = LocalLLMService.shared.backend(for: .checker)
        let risk: (String) -> Int = { AccuracyChecker.parse($0, checkedBy: "").riskLevel }
        var removed = 0, flagged = 0, unchecked = 0
        var total = 0
        switch set.kind {
        case .mcq:
            set.questions = CloudChecks.cite(set.questions)
            total = set.questions.count
            for q in set.questions {
                if let reply = CloudChecks.reply(forKey: CloudChecks.same(q.stem)) {
                    CloudChecks.remember(reply, forOutput: AccuracyChecker.checkText(q))
                }
            }
            if let checker {
                let screened = await AccuracyChecker.screen(set.questions, source: source, using: checker, onProgress: { _, _ in })
                (set.questions, removed, flagged) = (screened.kept, screened.removed, screened.flagged)
                // one the checker could not reach is kept, and is not a checked one
                unchecked = screened.unchecked
            } else {
                let before = set.questions.count
                set.questions.removeAll { q in CloudChecks.reply(forKey: CloudChecks.same(q.stem)).map { risk($0) >= 4 } ?? false }
                removed = before - set.questions.count
                // only the server's verdicts to go on: one it gave none for was not checked
                unchecked = set.questions.filter { q in CloudChecks.reply(forKey: CloudChecks.same(q.stem)) == nil }.count
            }
        case .osce:
            total = set.osceChecklists.count
            for station in set.osceChecklists {
                if let reply = CloudChecks.reply(forKey: CloudChecks.same(station.title)) {
                    CloudChecks.remember(reply, forOutput: AccuracyChecker.checkText(station))
                }
            }
            if let checker {
                let screened = await AccuracyChecker.screen(set.osceChecklists, source: source, using: checker, onProgress: { _, _ in })
                (set.osceChecklists, removed, flagged) = (screened.kept, screened.removed, screened.flagged)
                unchecked = screened.unchecked
            } else {
                let before = set.osceChecklists.count
                set.osceChecklists.removeAll { s in CloudChecks.reply(forKey: CloudChecks.same(s.title)).map { risk($0) >= 4 } ?? false }
                removed = before - set.osceChecklists.count
                unchecked = set.osceChecklists.filter { s in CloudChecks.reply(forKey: CloudChecks.same(s.title)) == nil }.count
            }
        default:
            // cards, cases and pages: the riskiest part is reported, as on the screens
            if let worst = AccuracyChecker.riskiest(CloudChecks.allReplies) {
                let verdict = AccuracyChecker.parse(worst, checkedBy: "")
                return verdict.passed ? " Checked: \(verdict.riskTitle.lowercased())." : " Checker: \(verdict.riskTitle.lowercased()) \u{2014} read it carefully."
            }
            return ""
        }
        // "Accuracy checked" only for what a checker actually graded
        return MedVAL.screenNote(total: total, removed: removed, flagged: flagged, unchecked: unchecked)
    }

    // MARK: while the app is away

    private static var refreshID: String { (Bundle.main.bundleIdentifier ?? "vignette") + ".jobs" }

    /// A build that declares the identifier gets a background check that
    /// notifies when a job is done; one that cannot (Swift Playgrounds)
    /// schedules a reminder for when the job should be done instead.
    private static var canRefresh: Bool {
        let allowed = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        return allowed.contains(refreshID)
    }

    /// At launch, before the app finishes starting (the system's rule).
    static func registerRefresh() {
        guard canRefresh else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            Task { @MainActor in
                let finished = await checkWhileAway()
                task.setTaskCompleted(success: finished)
                if !CloudJobs.pending().isEmpty { scheduleRefresh() }
            }
        }
    }

    /// Called when the app goes to the background.
    static func appLeft() {
        let running = CloudJobs.pending()
        guard !running.isEmpty else { return }
        if canRefresh { scheduleRefresh() }
        // without a background check: a reminder at the time the job should
        // be done, worked out from how fast it has gone so far
        for job in running where job.done > 0 && job.total > job.done {
            let elapsed = Date().timeIntervalSince(job.started)
            let left = elapsed / Double(job.done) * Double(job.total - job.done) + 60
            let content = UNMutableNotificationContent()
            content.title = job.what + " should be ready"
            content.body = "Open \(Brand.name) to add them to your library."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: "job-" + job.id, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(60, left), repeats: false)))
        }
    }

    /// Back in the app: the reminders are not needed while it is open.
    static func appReturned() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: CloudJobs.pending().map { "job-" + $0.id })
    }

    private static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date().addingTimeInterval(5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Asks the server about each job; a finished one gets its notification
    /// now (the set itself is made when the app opens). True when all are done.
    private static func checkWhileAway() async -> Bool {
        let llm = LocalLLMService.shared
        var allDone = true
        for job in CloudJobs.pending() {
            // already in a screen's hands, or not ours to ask about: nothing to say
            guard job.delivered != true, let bearer = llm.cloudBearer(for: job.identity) else { continue }
            let endpoint = (base: AuthAPI.baseURL, bearer: bearer)
            guard let status = try? await CloudJobs.status(job.id, at: endpoint) else { continue }
            if status.status == "running" { allDone = false; continue }
            guard job.notified != true else { continue }
            // Marked on the record as it is now - and only if it still exists.
            // Collected while this check was out, it is gone and must stay
            // gone: written back, it would announce a set already in the
            // library and keep the background checks running for a week.
            guard CloudJobs.markNotified(job.id) else { continue }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["job-" + job.id])
            let content = UNMutableNotificationContent()
            content.title = status.status == "done"
                ? job.what + " are ready"
                : "Could not finish: \(job.title.lowercased())"
            content.body = status.status == "done" ? "Open \(Brand.name) to see them." : (status.error ?? "Open the app to try again.")
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "job-done-" + job.id, content: content, trigger: nil))
        }
        return allDone
    }
}
