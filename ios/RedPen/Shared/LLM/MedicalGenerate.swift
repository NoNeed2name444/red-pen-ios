import Foundation

/// MCQ and OSCE generation through whichever writer is chosen in AI models -
/// Doctor-R1 on the device or a hosted model.
///
/// Same prompts, same batching and the same bar for keeping an answer as the
/// Apple and Gemma paths (MCQPrompt, MCQCoverage, OsceStations are shared), so
/// a set reads the same whichever model wrote it. What differs is that these
/// models have no `@Generable`, so they are asked for JSON and it is parsed
/// here.
enum MedicalGenerate {

    static func mcq(
        sourceText: String, count: Int, subject: String, highYield: Bool,
        using backend: LLMBackend,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [MCQQuestion] {
        let promptSource = String(sourceText.prefix(backend.promptBudgetChars))
        // Vignette Cloud: the server writes the whole set, even with the app closed
        if let cloud = CloudJobs.endpoint(for: backend) {
            let perCall = MCQGenerator.maxQuestionsPerCall
            let instructions = MCQGenerator.buildPrompt(
                sourceText: "{{SOURCE}}", count: perCall, subject: subject, highYield: highYield,
                requestJSONShape: true, alreadyAsked: [MCQCoverage.Asked(stem: "{{ALREADY}}", key: "")])
            var spec = CloudJobs.Spec(
                title: "Writing \(count) questions", mode: "loop", extract: "questions", count: count,
                sources: [promptSource],
                steps: [.init(system: instructions, user: "Write the \(perCall) questions now, as JSON only.",
                              maxTokens: 700 * perCall, temperature: 0.7)])
            if CloudJobs.context?.serverCheck == true {
                spec.check = AccuracyChecker.serverCheck(instruction: AccuracyChecker.mcqInstruction,
                                                         limit: backend.promptBudgetChars)
            }
            let questions = try collectQuestions(try await CloudJobs.run(spec, at: cloud, onProgress: onProgress), count: count)
            // the server's verdicts, where the screen's accuracy check finds them
            for q in questions {
                if let reply = CloudChecks.reply(forKey: CloudChecks.same(q.stem)) {
                    CloudChecks.remember(reply, forOutput: AccuracyChecker.checkText(q))
                }
            }
            return questions
        }
        // a phone model loses the thread on long batches; a hosted one doesn't
        let perCall = backend.isOnDevice ? 3 : MCQGenerator.maxQuestionsPerCall
        var collected: [MCQQuestion] = []
        var asked: [MCQCoverage.Asked] = []
        var consecutiveFailures = 0

        while collected.count < count && consecutiveFailures < 3 {
            try Task.checkCancellation()
            let callCount = min(perCall, count - collected.count)
            onProgress(collected.count, count)
            let instructions = MCQGenerator.buildPrompt(
                sourceText: promptSource, count: callCount, subject: subject,
                highYield: highYield, requestJSONShape: true, alreadyAsked: asked)
            do {
                let reply = try await backend.complete(
                    [.system(instructions), .user("Write the \(callCount) questions now, as JSON only.")],
                    maxTokens: 700 * callCount, temperature: 0.7)
                var kept = 0
                for question in parseQuestions(reply) {
                    let key = question.options[question.correctIndex]
                    guard !MCQCoverage.isRepeat(stem: question.stem, key: key, of: asked) else { continue }
                    collected.append(question)
                    asked.append(MCQCoverage.Asked(stem: question.stem, key: key))
                    kept += 1
                    if collected.count >= count { break }
                }
                consecutiveFailures = kept == 0 ? consecutiveFailures + 1 : 0
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LLMError {
                // a missing key or a refused request will not fix itself on retry
                if case .emptyReply = error { consecutiveFailures += 1 } else { throw error }
            } catch {
                consecutiveFailures += 1
            }
        }
        guard !collected.isEmpty else { throw LLMError.emptyReply }
        return Array(collected.prefix(count))
    }

    static func osce(
        sourceText: String, count: Int, subject: String,
        using backend: LLMBackend,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [OsceChecklist] {
        let wanted = min(count, OsceGenerator.maxStationsTotal)
        let promptSource = String(sourceText.prefix(min(backend.promptBudgetChars, OsceGenerator.maxPromptChars)))
        if let cloud = CloudJobs.endpoint(for: backend) {
            let perCall = OsceGenerator.maxStationsPerCall
            let instructions = OsceGenerator.prompt(sourceText: "{{SOURCE}}", count: perCall,
                                                    subject: subject, alreadyWritten: ["{{ALREADY}}"])
                + "\n\nAnswer with JSON only, in exactly this shape: {\"stations\":[{\"title\":\"...\",\"steps\":[\"...\"]}]}"
            var spec = CloudJobs.Spec(
                title: "Writing \(wanted) stations", mode: "loop", extract: "stations", count: wanted,
                sources: [promptSource],
                steps: [.init(system: instructions,
                              user: "Write the \(perCall) station\(perCall == 1 ? "" : "s") now, as JSON only.",
                              maxTokens: 900 * perCall, temperature: 0.6)])
            if CloudJobs.context?.serverCheck == true {
                spec.check = AccuracyChecker.serverCheck(instruction: AccuracyChecker.osceInstruction,
                                                         limit: backend.promptBudgetChars)
            }
            let stations = try collectStations(try await CloudJobs.run(spec, at: cloud, onProgress: onProgress), count: wanted)
            for station in stations {
                if let reply = CloudChecks.reply(forKey: CloudChecks.same(station.title)) {
                    CloudChecks.remember(reply, forOutput: AccuracyChecker.checkText(station))
                }
            }
            return stations
        }
        var collected: [OsceChecklist] = []
        var titles: [String] = []
        var consecutiveFailures = 0

        while collected.count < wanted && consecutiveFailures < 3 {
            try Task.checkCancellation()
            let callCount = min(OsceGenerator.maxStationsPerCall, wanted - collected.count)
            onProgress(collected.count, wanted)
            let instructions = OsceGenerator.prompt(sourceText: promptSource, count: callCount,
                                                    subject: subject, alreadyWritten: titles)
                + "\n\nAnswer with JSON only, in exactly this shape: {\"stations\":[{\"title\":\"...\",\"steps\":[\"...\"]}]}"
            do {
                let reply = try await backend.complete(
                    [.system(instructions),
                     .user("Write the \(callCount) station\(callCount == 1 ? "" : "s") now, as JSON only.")],
                    maxTokens: 900 * callCount, temperature: 0.6)
                let tidied = OsceStations.tidy(parseStations(reply))
                var kept = 0
                for station in tidied {
                    guard !titles.contains(where: {
                        $0.compare(station.title, options: .caseInsensitive) == .orderedSame
                    }) else { continue }
                    collected.append(station)
                    titles.append(station.title)
                    kept += 1
                    if collected.count >= wanted { break }
                }
                consecutiveFailures = kept == 0 ? consecutiveFailures + 1 : 0
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LLMError {
                if case .emptyReply = error { consecutiveFailures += 1 } else { throw error }
            } catch {
                consecutiveFailures += 1
            }
        }
        guard !collected.isEmpty else { throw OsceGenerator.Trouble.nothingUsable }
        return Array(collected.prefix(wanted))
    }

    // MARK: replies from a cloud job

    /// The questions in a job's replies, repeats dropped as the loop above does.
    static func collectQuestions(_ replies: [String], count: Int) throws -> [MCQQuestion] {
        var collected: [MCQQuestion] = []
        var asked: [MCQCoverage.Asked] = []
        for question in replies.flatMap(parseQuestions) where collected.count < count {
            let key = question.options[question.correctIndex]
            guard !MCQCoverage.isRepeat(stem: question.stem, key: key, of: asked) else { continue }
            collected.append(question)
            asked.append(MCQCoverage.Asked(stem: question.stem, key: key))
        }
        guard !collected.isEmpty else { throw LLMError.emptyReply }
        return collected
    }

    static func collectStations(_ replies: [String], count: Int) throws -> [OsceChecklist] {
        var collected: [OsceChecklist] = []
        for station in OsceStations.tidy(replies.flatMap(parseStations)) where collected.count < count {
            guard !collected.contains(where: {
                $0.title.compare(station.title, options: .caseInsensitive) == .orderedSame
            }) else { continue }
            collected.append(station)
        }
        guard !collected.isEmpty else { throw OsceGenerator.Trouble.nothingUsable }
        return collected
    }

    // MARK: parsing

    private struct RawQuestionSet: Decodable { var questions: [RawQuestion] }
    private struct RawQuestion: Decodable {
        var stem: String
        var options: [String]
        var correctIndex: Int
        var explanation: String
    }

    static func parseQuestions(_ raw: String) -> [MCQQuestion] {
        guard let data = LLMText.jsonObject(in: raw),
              let decoded = try? JSONDecoder().decode(RawQuestionSet.self, from: data) else { return [] }
        return decoded.questions.filter {
            MCQGenerator.isValidQuestion(stem: $0.stem, options: $0.options, correctIndex: $0.correctIndex)
        }.map {
            MCQQuestion(stem: $0.stem, options: $0.options,
                        correctIndex: $0.correctIndex, explanation: $0.explanation)
        }
    }

    private struct RawStations: Decodable { var stations: [RawStation] }
    private struct RawStation: Decodable { var title: String; var steps: [String] }

    static func parseStations(_ raw: String) -> [OsceChecklist] {
        guard let data = LLMText.jsonObject(in: raw),
              let decoded = try? JSONDecoder().decode(RawStations.self, from: data) else { return [] }
        return decoded.stations.map { OsceChecklist(title: $0.title, steps: $0.steps) }
    }
}
