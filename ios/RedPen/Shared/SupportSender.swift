import Foundation
import Combine

/// Delivers what SupportOutbox keeps: question reports to the accuracy
/// engine's POST /accuracy/report (where reports already train the accuracy
/// model), and messages to POST /support/message.
///
/// Both need a signed-in account; without one, or without signal, a report
/// simply waits on the device and goes the next time the app comes to the
/// front (RedPenApp calls `flush()`), or the next time one is sent.
@MainActor
final class SupportSender: ObservableObject {
    static let shared = SupportSender()

    @Published private(set) var outbox = SupportOutbox()
    private var flushing = false
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("support-outbox.json")
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder.sync.decode(SupportOutbox.self, from: data) {
            outbox = stored
        }
    }

    var waiting: Int { outbox.pending.count }

    /// Queues a report of `item` and tries to send it straight away.
    /// Returns what to tell the student.
    func report(_ item: AccuracyItem, reason: SupportReason, note: String) async -> String {
        let json: String? = (try? JSONEncoder.sync.encode(item)).flatMap { String(data: $0, encoding: .utf8) }
        let entry = PendingSupport(kind: .question, reason: reason.rawValue, note: note,
                                   itemJSON: json, createdAt: Date())
        return await queue(entry)
    }

    /// Queues a message to us and tries to send it straight away.
    func contact(_ topic: ContactTopic, message: String) async -> String {
        let entry = PendingSupport(kind: .contact, reason: topic.rawValue, note: message,
                                   itemJSON: nil, createdAt: Date())
        return await queue(entry)
    }

    private func queue(_ entry: PendingSupport) async -> String {
        outbox.add(entry, now: Date())
        save()
        await flush()
        let stillWaiting: Bool = outbox.pending.contains { $0.id == entry.id }
        guard stillWaiting else { return "Sent \u{2014} thank you." }
        if LocalLLMService.shared.cloudToken == nil {
            return "Saved. It will be sent once you\u{2019}re signed in to \(Brand.name)."
        }
        return "Saved. It will be sent when you\u{2019}re back online."
    }

    /// Sends whatever is due. Quiet: nothing on screen depends on it.
    func flush() async {
        guard !flushing else { return }
        let now = Date()
        outbox.prune(now: now)
        let due: [PendingSupport] = outbox.due(now: now)
        guard !due.isEmpty, let token = LocalLLMService.shared.cloudToken else { return }
        flushing = true
        defer { flushing = false }
        for entry in due {
            let status: Int? = await send(entry, token: token)
            switch status {
            case .some(200), .some(400):
                // delivered, or refused for good (unreadable): either way done
                outbox.sent(entry.id)
            case .some(401):
                // signed out on the server: wait for the next sign-in
                outbox.failed(entry.id, now: now)
                save()
                return
            default:
                outbox.failed(entry.id, now: now)
                // a server fault is no moment to ask for a rating
                if status != nil { ReviewPromptRules.noteTrouble() }
            }
        }
        save()
    }

    private func send(_ entry: PendingSupport, token: String) async -> Int? {
        let path: String
        let body: Data?
        switch entry.kind {
        case .question:
            path = "/accuracy/report"
            body = reportBody(entry)
        case .contact:
            path = "/support/message"
            let fields: [String: String] = ["topic": entry.reason, "message": entry.note,
                                            "version": Self.appVersion]
            body = try? JSONEncoder().encode(fields)
        }
        guard let body else { return 400 }
        var request = URLRequest(url: AuthAPI.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 30
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return http.statusCode
    }

    /// {"item": <the item>, "note": "[Wrong answer] ..."} - the body
    /// /accuracy/report already reads.
    private func reportBody(_ entry: PendingSupport) -> Data? {
        guard let json = entry.itemJSON, let data = json.data(using: .utf8),
              let item = try? JSONDecoder.sync.decode(AccuracyItem.self, from: data) else { return nil }
        struct Body: Encodable { var item: AccuracyItem; var note: String }
        return try? JSONEncoder().encode(Body(item: item, note: entry.sentNote))
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private func save() {
        guard let data = try? JSONEncoder.sync.encode(outbox) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
