import Foundation

/// What the AI check said about one subtopic.
struct CoverageVerdict: Codable, Hashable {
    enum Status: String, Codable {
        case covered, thin, missing

        /// A status as a model writes it: any case, spaced or not, and the
        /// engine's own "not covered". Nil for anything else, rather than a
        /// guess that could call a gap covered.
        static func read(_ text: String) -> Status? {
            let t = text.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            switch t {
            case "covered", "well covered", "fully covered": return .covered
            case "thin", "partial", "partly covered", "partially covered": return .thin
            case "missing", "not covered", "notcovered", "uncovered", "absent", "none": return .missing
            default: return nil
            }
        }

        /// The same scale as the keyword engine's, so the two can be compared.
        var coverage: CoverageStatus {
            switch self {
            case .covered: return .covered
            case .thin: return .thin
            case .missing: return .notCovered
            }
        }
    }

    var status: Status
    /// What in the library it based that on, in a few words.
    var evidence: String
    /// What to add to close the gap.
    var suggestion: String
}

/// One AI check of one exam's blueprint against the library, kept so it is
/// not paid for again every time the screen opens.
struct CoverageCheck: Codable {
    /// The exam it was run for (ExamTrack's raw value).
    var track: String
    var date: Date
    /// The models that answered, most areas first. Usually one.
    var sources: [String]
    /// By SubtopicCoverage.id ("area/subtopic").
    var verdicts: [String: CoverageVerdict]
    /// Areas whose request failed, so the screen can say the check is partial.
    var failedAreas: [String] = []
    /// A ready-made check shipped with the personal build, not a real one.
    var isExample: Bool = false

    var source: String { sources.first ?? "" }
    /// Whether the model asked for is the one that answered.
    var byPreferredModel: Bool { !sources.isEmpty && sources.allSatisfy { $0 == CoverageCloudCheck.preferredModel } }
}

/// The AI check: each area's subtopics, with a compact digest of the library,
/// sent to Vignette Cloud with a request for strict JSON back.
///
/// It calls the server directly rather than through LLMBackend because the
/// reply says which model actually answered (the server falls back when
/// Gemini 3.1 Pro is not available), and the screen shows that.
///
/// Foundation only; the token is handed in by whoever runs it.
enum CoverageCloudCheck {
    static let preferredModel = "gemini-3.1-pro-preview"
    /// Most characters one request may carry.
    static let requestLimit = 30_000

    /// The friendly name of a model id, for the screen.
    static func displayName(_ model: String) -> String {
        switch model {
        case preferredModel: return "Gemini 3.1 Pro"
        case "": return "the cloud model"
        default: return model
        }
    }

    // MARK: - The prompt

    /// The request for one area: its subtopics, what the keyword engine found,
    /// the library's shape, and the matching items themselves.
    static func prompt(for area: AreaCoverage, exam: ExamTrack, library: [StudySet]) -> String {
        var lines: [String] = []
        lines.append("You are checking how well a medical student's revision library covers the \(exam.title) syllabus, area \"\(area.area.name)\".")
        lines.append("For each subtopic below, judge from the digest whether the library covers it: \"covered\" (enough material, including questions or cards, to revise it for the exam), \"thin\" (mentioned, but too little or reading only), or \"missing\" (nothing on it).")
        lines.append("Judge meaning, not keywords: a question on warfarin reversal covers anticoagulation even if the word is not used, and a passing mention is not coverage.")
        lines.append("Reply with ONLY this JSON and nothing else:")
        lines.append("{\"subtopics\":[{\"id\":\"s1\",\"status\":\"covered\"|\"thin\"|\"missing\",\"evidence\":\"<under 15 words: what in the library shows it>\",\"suggestion\":\"<under 20 words: what to add>\"}]}")
        lines.append("")
        lines.append("SUBTOPICS (id: name - what a keyword search found)")
        for (i, sub) in area.subtopics.enumerated() {
            var found = "nothing"
            if sub.evidence > 0 {
                found = "\(sub.evidence) items, \(sub.practice) of them questions/cards"
            }
            if let accuracy = sub.accuracy {
                let percent = Int((accuracy * 100).rounded())
                found += ", \(percent)% of \(sub.answered) answers right"
            }
            lines.append("s\(i + 1): \(sub.subtopic.name) - \(found)")
        }

        var digest: [String] = []
        digest.append("")
        digest.append("ITEMS THAT MATCHED (tagged with the subtopic that found them)")
        var shown = 0
        var seen = Set<String>()
        for (i, sub) in area.subtopics.enumerated() {
            for sample in sub.samples.prefix(4) where shown < 40 && seen.insert(sample).inserted {
                digest.append("[s\(i + 1)] \(sample)")
                shown += 1
            }
        }
        if shown == 0 { digest.append("(none)") }

        digest.append("")
        digest.append("THE LIBRARY'S SETS (name - subject - kind, size)")
        for set in library.prefix(80) {
            digest.append("\(set.name) - \(set.subject) - \(set.kind.label), \(set.itemCount) \(set.itemNoun)s")
        }

        digest.append("")
        digest.append("LECTURE AND TEXTBOOK PAGES (first line of each)")
        var headings: [String] = []
        var sourcesSeen = Set<UUID>()
        for set in library {
            for source in set.sources where sourcesSeen.insert(source.id).inserted {
                let heads = source.pages.map(\.heading).filter { !$0.isEmpty }
                if !heads.isEmpty { headings.append(source.name + ": " + heads.joined(separator: " | ")) }
            }
            if !set.bookMarkdown.isEmpty {
                headings.append(set.name + ": " + BookPages.split(set.bookMarkdown).map(\.title).joined(separator: " | "))
            }
        }
        digest += headings.isEmpty ? ["(none)"] : headings

        let head = lines.joined(separator: "\n")
        let body = digest.joined(separator: "\n")
        return head + String(body.prefix(max(0, requestLimit - head.count)))
    }

    // MARK: - The request

    /// Sends one prompt and returns the reply's text and the model that
    /// wrote it.
    static func send(_ prompt: String, token: String) async throws -> (content: String, source: String) {
        guard let url = URL(string: AuthAPI.baseURL.absoluteString + "/v1/chat/completions") else {
            throw AuthAPI.Failure.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 180
        let body: [String: Any] = [
            "model": "cramdown-writer",
            "prefer": preferredModel,
            "max_tokens": 4000,
            "temperature": 0.2,
            "messages": [["role": "user", "content": prompt]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthAPI.Failure.offline
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let message = (object?["message"] as? String) ?? (object?["error"] as? String)
            switch code {
            case 401, 403: throw AuthAPI.Failure.signedOut
            case 402: throw AuthAPI.Failure.needsPro(message ?? "The cloud check is part of Pro.")
            case 404: throw AuthAPI.Failure.notConfigured
            case 429: throw AuthAPI.Failure.tooManyTries
            default: throw AuthAPI.Failure.server(message ?? "The cloud check did not answer.")
            }
        }
        let choices = object?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String, !content.isEmpty else {
            throw AuthAPI.Failure.server("The cloud check sent back nothing.")
        }
        let source = (object?["source"] as? String) ?? (object?["model"] as? String) ?? ""
        return (content, source)
    }

    // MARK: - The reply

    /// The verdicts in a reply, keyed the way the screen looks them up.
    /// Tolerates a reply wrapped in a code fence or with words around it;
    /// subtopics it does not recognise, or leaves out, are skipped.
    static func parse(_ content: String, for area: AreaCoverage) -> [String: CoverageVerdict] {
        guard let open = content.firstIndex(of: "{"), let close = content.lastIndex(of: "}"),
              open < close,
              let data = String(content[open...close]).data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = object["subtopics"] as? [[String: Any]] else { return [:] }
        var out: [String: CoverageVerdict] = [:]
        for entry in list {
            guard let id = entry["id"] as? String,
                  let number = Int(id.lowercased().replacingOccurrences(of: "s", with: "")),
                  area.subtopics.indices.contains(number - 1),
                  let raw = entry["status"] as? String,
                  let status = CoverageVerdict.Status.read(raw)
            else { continue }
            out[area.subtopics[number - 1].id] = CoverageVerdict(
                status: status,
                evidence: (entry["evidence"] as? String) ?? "",
                suggestion: (entry["suggestion"] as? String) ?? "")
        }
        return out
    }

    // MARK: - Kept checks

    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Coverage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(for track: ExamTrack) -> URL? {
        folder?.appendingPathComponent("check-\(track.rawValue).json")
    }

    /// The last check run for an exam, if any.
    static func load(for track: ExamTrack) -> CoverageCheck? {
        guard let url = file(for: track), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CoverageCheck.self, from: data)
    }

    static func save(_ check: CoverageCheck, for track: ExamTrack) {
        guard !check.isExample, let url = file(for: track),
              let data = try? JSONEncoder().encode(check) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
