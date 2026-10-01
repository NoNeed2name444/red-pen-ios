// Every AI mode, run for real: the app's own generators and parsers, sent to
// real models, with what came back written to a report.
//
// Not a unit test - models answer differently every time - but proof that
// each path produces something a student could study from, and a record of
// what that looks like. Run by .github/workflows/live-tests.yml, which points
// it at CramDown Cloud (with the owner key) and at the on-device GGUF files
// served by llama.cpp on the runner.
//
// Environment:
//   LIVE_URL, LIVE_KEY, LIVE_WRITER, LIVE_CHECKER, LIVE_LABEL, LIVE_ON_DEVICE (1/0)
//   LIVE_REPORT - where to append the Markdown report

import Foundation

struct WorkerBackend: LLMBackend {
    let url: URL
    let key: String
    let model: String
    let label: String
    let isOnDevice: Bool
    var promptBudgetChars: Int { isOnDevice ? 8_000 : 40_000 }

    func complete(_ turns: [ChatTurn], maxTokens: Int, temperature: Double) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "max_tokens": maxTokens, "temperature": temperature,
            // the app sends on-device models the same way (LLMText.noThinking)
            "messages": (isOnDevice ? LLMText.noThinking(turns) : turns).map { ["role": $0.role.rawValue, "content": $0.text] },
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw LLMError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = ((json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        let text = LLMText.stripThinking(content ?? "")
        guard !text.isEmpty else { throw LLMError.emptyReply }
        return text
    }
}

let env = ProcessInfo.processInfo.environment
let url = URL(string: env["LIVE_URL"] ?? "")!
let key = env["LIVE_KEY"] ?? ""
let label = env["LIVE_LABEL"] ?? "model"
let onDevice = env["LIVE_ON_DEVICE"] == "1"
let writer = WorkerBackend(url: url, key: key, model: env["LIVE_WRITER"] ?? "", label: label, isOnDevice: onDevice)
let checkerURL = URL(string: env["LIVE_CHECKER_URL"] ?? "") ?? url
let checker = WorkerBackend(url: checkerURL, key: key, model: env["LIVE_CHECKER"] ?? "", label: label, isOnDevice: onDevice)
let only = Set((env["LIVE_ONLY"] ?? "").split(separator: ",").map(String.init))
func wanted(_ part: String) -> Bool { only.isEmpty || only.contains(part) }

var report = "\n## \(label)\n\n"
var passed = 0, failed = 0
func record(_ mode: String, _ ok: Bool, _ detail: String, seconds: Double) {
    report += "### \(ok ? "✅" : "❌") \(mode) — \(String(format: "%.0f", seconds)) s\n\n\(detail)\n\n"
    if ok { passed += 1 } else { failed += 1 }
    print("\(ok ? "PASS" : "FAIL") \(mode) (\(Int(seconds)) s)")
}
func timed<T>(_ work: () async throws -> T) async -> (Result<T, Error>, Double) {
    let start = Date()
    do { return (.success(try await work()), Date().timeIntervalSince(start)) }
    catch { return (.failure(error), Date().timeIntervalSince(start)) }
}
func quote(_ text: String, limit: Int = 2_500) -> String {
    "```\n" + String(text.prefix(limit)) + (text.count > limit ? "\n…" : "") + "\n```"
}

// A short, accurate lecture excerpt - the kind of source a student imports.
let lecture = """
Systemic lupus erythematosus (SLE) is a chronic autoimmune disease that mainly affects women of childbearing age, with a female to male ratio of about 9 to 1.

Skin: the malar (butterfly) rash is an erythematous rash over the cheeks and bridge of the nose that spares the nasolabial folds and is worsened by sunlight. Discoid lupus causes chronic scarring plaques with follicular plugging, most often on the scalp, face and ears; unlike the malar rash it can leave permanent scarring and hair loss.

Other features: non-erosive arthritis of the small joints of the hands, oral ulcers (usually painless), serositis (pleurisy or pericarditis), lupus nephritis, and cytopenias including autoimmune haemolytic anaemia, leucopenia and thrombocytopenia.

Antibodies: antinuclear antibody (ANA) is positive in over 95% of patients and is the best screening test, but it is not specific. Anti-double-stranded DNA and anti-Smith antibodies are highly specific; anti-dsDNA levels rise with disease activity, especially nephritis. Complement C3 and C4 fall during active disease. Antiphospholipid antibodies increase the risk of venous and arterial thrombosis and recurrent miscarriage.

Management: all patients should take hydroxychloroquine unless contraindicated, and need annual eye screening for retinal toxicity. Sun protection is advised. Flares are treated with corticosteroids; severe organ involvement such as class III or IV lupus nephritis needs immunosuppression with mycophenolate mofetil or cyclophosphamide.
"""

print("Live model test: \(label)")

// MARK: MCQ
if wanted("mcq") {
    let (result, seconds) = await timed {
        try await MedicalGenerate.mcq(sourceText: lecture, count: 3, subject: "Rheumatology",
                                      highYield: true, using: writer)
    }
    switch result {
    case .success(let questions):
        let letters = ["A", "B", "C", "D", "E"]
        let shown = questions.enumerated().map { i, q in
            "**Q\(i + 1).** \(q.stem)\n" + q.options.enumerated().map { "- \(letters[$0.offset]). \($0.element)" }.joined(separator: "\n")
                + "\n\n*Answer: \(letters[q.correctIndex])* — \(q.explanation)"
        }.joined(separator: "\n\n")
        record("MCQ", !questions.isEmpty, "\(questions.count) question(s), each with 5 options and a valid answer index (the app's own validity rules).\n\n" + shown, seconds: seconds)
    case .failure(let error):
        record("MCQ", false, "Error: \(error.localizedDescription)", seconds: seconds)
    }
}

// MARK: OSCE
if wanted("osce") {
    let (result, seconds) = await timed {
        try await MedicalGenerate.osce(sourceText: lecture, count: 1, subject: "Rheumatology", using: writer)
    }
    switch result {
    case .success(let stations):
        let shown = stations.map { "**\($0.title)**\n" + $0.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") }.joined(separator: "\n\n")
        record("OSCE", !stations.isEmpty && stations.allSatisfy { $0.steps.count >= 3 }, shown, seconds: seconds)
    case .failure(let error):
        record("OSCE", false, "Error: \(error.localizedDescription)", seconds: seconds)
    }
}

// MARK: Anki
if wanted("anki") {
    let (result, seconds) = await timed {
        try await LectureWriter.write(kind: .anki, source: lecture, count: 6, subject: "Rheumatology",
                                      using: writer, onProgress: { _, _ in })
    }
    switch result {
    case .success(let text):
        let cards = PlainTextImport.parseAnkiQA(text)
        let shown = cards.map { "- **\($0.front)** → \($0.bullets.joined(separator: "; "))" }.joined(separator: "\n")
        record("Cards", !cards.isEmpty, "\(cards.count) card(s) parsed by the app's own importer.\n\n" + shown, seconds: seconds)
    case .failure(let error):
        record("Cards", false, "Error: \(error.localizedDescription)", seconds: seconds)
    }
}

// MARK: Cases
var caseCards: [QACard] = []
if wanted("cases") || wanted("patient") {
    let (result, seconds) = await timed {
        try await LectureWriter.write(kind: .qa, source: lecture, count: 4, subject: "Rheumatology",
                                      using: writer, onProgress: { _, _ in })
    }
    switch result {
    case .success(let text):
        caseCards = PlainTextImport.parseQA(text)
        let shown = caseCards.map { "- [\($0.badge)] *\($0.topic)* — \($0.stem)\n  → \($0.answer.joined(separator: "; "))" }.joined(separator: "\n")
        record("Cases", !caseCards.isEmpty, "\(caseCards.count) card(s) parsed by the app's own importer.\n\n" + shown, seconds: seconds)
    case .failure(let error):
        record("Cases", false, "Error: \(error.localizedDescription)", seconds: seconds)
    }
}

// MARK: Textbook
if wanted("book") {
    let (result, seconds) = await timed {
        try await LectureWriter.write(kind: .book, source: lecture, count: 1, subject: "Rheumatology",
                                      using: writer, onProgress: { _, _ in })
    }
    switch result {
    case .success(let text):
        let pages = BookPages.split(text)
        record("Textbook", !pages.isEmpty, "\(pages.count) page(s).\n\n" + quote(text, limit: 1_800), seconds: seconds)
    case .failure(let error):
        record("Textbook", false, "Error: \(error.localizedDescription)", seconds: seconds)
    }
}

// MARK: MedVAL accuracy check - one faithful statement, one planted error
if wanted("check") {
    let faithful = "The malar rash of SLE spares the nasolabial folds and is worsened by sunlight."
    let wrong = "The malar rash of SLE involves the nasolabial folds, always scars, and is best treated with penicillin."
    let (good, s1) = await timed {
        try await AccuracyChecker.check(instruction: "Write a flashcard answer from the source.",
                                        input: lecture, output: faithful, using: checker)
    }
    let (bad, s2) = await timed {
        try await AccuracyChecker.check(instruction: "Write a flashcard answer from the source.",
                                        input: lecture, output: wrong, using: checker)
    }
    func line(_ r: Result<AccuracyVerdict, Error>) -> String {
        switch r {
        case .success(let v): return "\(v.riskTitle) — \(v.findings.map(\.text).joined(separator: " | ").prefix(400))"
        case .failure(let e): return "Error: \(e.localizedDescription)"
        }
    }
    let okGood = (try? good.get())?.passed == true
    let okBad = ((try? bad.get())?.riskLevel ?? 0) >= 3
    record("Accuracy check (MedVAL rubric)", okGood && okBad,
           "Faithful statement → \(line(good))\n\nPlanted error → \(line(bad))\n\n(Pass means the faithful one passed AND the planted error was graded level 3–4.)",
           seconds: s1 + s2)
}

// MARK: Cases - the simulated patient, with every reply checked
if wanted("patient"), let card = caseCards.first(where: { $0.type == .case }) ?? caseCards.first {
    let start = Date()
    let sim = await CaseSimulator(card: card, subject: "Rheumatology", writer: writer, checker: checker)
    await sim.prepare()
    var transcript = ""
    if case .failed(let why) = await sim.phase {
        record("Simulated patient", false, "Case file failed: \(why)", seconds: Date().timeIntervalSince(start))
    } else {
        let file = await sim.caseFile
        transcript += "Case written from: *\(card.stem)*\n\nHidden diagnosis: **\(file.diagnosis)** · checklist items: \(file.checklist.count)\n\n"
        for question in ["Hello, I'm a medical student. What brings you in today?",
                         "Have you noticed any rash, joint pain or mouth ulcers?",
                         "I'd like to examine your skin and joints."] {
            await sim.send(question)
            let messages = await sim.messages
            if let reply = messages.last {
                let v = reply.verdict.map { " _(\($0.riskTitle)\(reply.regenerations > 0 ? ", rewritten \(reply.regenerations)×" : ""))_" } ?? ""
                transcript += "**Doctor:** \(question)\n\n**\(reply.speaker == .examiner ? "Examiner" : "Patient"):** \(reply.text)\(v)\n\n"
            }
        }
        await sim.endInterview()
        await sim.finish(assessment: "Most likely SLE. Differentials: dermatomyositis, rosacea. Check ANA, anti-dsDNA, C3/C4, FBC, urinalysis. Start hydroxychloroquine and sun protection.")
        let covered = await sim.coveredCount
        let total = await sim.caseFile.checklist.count
        let missed = await sim.missed.prefix(6).map { "- [\($0.section.title)] \($0.text)" }.joined(separator: "\n")
        transcript += "Marking: **\(covered) of \(total)** checklist items covered. Missed (first 6):\n\(missed)"
        let replies = await sim.messages.filter { $0.speaker != .doctor }.count
        record("Simulated patient", replies >= 3 && total > 0, transcript, seconds: Date().timeIntervalSince(start))
    }
}

report += "**\(passed) passed, \(failed) failed.**\n"
if let path = env["LIVE_REPORT"] {
    let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    try? (existing + report).write(toFile: path, atomically: true, encoding: .utf8)
}
print(report)
