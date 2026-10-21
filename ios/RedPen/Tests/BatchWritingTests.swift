// Writing a batch at a time: a failed batch is counted and the run carries
// on, what was written is kept, what is missing is said and can be written
// again on its own (audit #88). No model: the batches are stand-ins.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

/// Runs an async check to its end before the next line (no top-level await,
/// so the globals above stay plain globals).
func run(_ body: @escaping @Sendable () async -> Void) {
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        await body()
        done.signal()
    }
    done.wait()
}

struct Refused: Error, LocalizedError {
    var status: Int
    var errorDescription: String? { "The hosted model refused the request (HTTP \(status))." }
}

let classify: (Error) -> (reason: String, final: Bool) = { error in
    let status = (error as? Refused)?.status
    return ((error as? LocalizedError)?.errorDescription ?? "\(error)", BatchWriting.isFinal(status: status))
}
let noPause: (Int) async throws -> Void = { _ in }

/// `n` lines for round `r`, all new.
func lines(_ n: Int, round r: Int) -> [String] {
    (1...max(1, n)).prefix(n).map { "Front \(r).\($0) | answer" }
}

// MARK: cards: every batch works

run {
    var rounds = 0
    var progress: [Int] = []
    let result = try? await BatchWriting.items(
        wanted: 10, perBatch: 4, patience: 3, classify: classify, pause: noPause,
        onProgress: { done, _ in progress.append(done) }) { round, size, written in
            rounds += 1
            ok(written.count == (round - 1) * 4, "round \(round) is told the \(written.count) written so far")
            return lines(size, round: round)
        }
    ok(result?.items.count == 10, "every batch working: all 10 written")
    ok(rounds == 3, "in three batches of at most four")
    ok(progress == [0, 4, 8], "progress reported before each batch: \(progress)")
    ok(result?.tally.failedBatches == 0, "no batch counted as failed")
    let short = result.flatMap { BatchWriting.shortfall(wanted: 10, written: $0.items.count, tally: $0.tally) }
    ok(short == nil, "and nothing is missing")
}

// MARK: cards: one batch fails, the run carries on

run {
    var asked = 0
    var paused: [Int] = []
    let result = try? await BatchWriting.items(
        wanted: 10, perBatch: 4, patience: 3, classify: classify,
        pause: { n in paused.append(n) }, onProgress: { _, _ in }) { round, size, _ in
            asked += 1
            if round == 2 { throw Refused(status: 503) }
            return lines(size, round: round)
        }
    ok(result != nil, "a failed batch no longer throws the run away")
    ok(result?.items.count == 10, "the run carries on and writes all 10")
    ok(result?.items.first == "Front 1.1 | answer", "keeping the first batch's cards")
    ok(asked == 4, "one more batch makes up for the failed one")
    ok(result?.tally.failedBatches == 1, "the failed batch is counted")
    ok(paused == [1], "with one pause after it: \(paused)")
    let short = result.flatMap { BatchWriting.shortfall(wanted: 10, written: $0.items.count, tally: $0.tally) }
    ok(short == nil, "everything written in the end: nothing to say is missing")
}

// MARK: cards: the model goes down part way

run {
    var asked = 0
    var paused: [Int] = []
    let result = try? await BatchWriting.items(
        wanted: 10, perBatch: 4, patience: 3, classify: classify,
        pause: { n in paused.append(n) }, onProgress: { _, _ in }) { round, size, _ in
            asked += 1
            if round >= 3 { throw Refused(status: 500) }
            return lines(size, round: round)
        }
    ok(result?.items.count == 8, "the model gone after two batches: the 8 written are kept")
    ok(asked == 5, "three failures in a row stop the run (patience 3)")
    ok(paused == [1, 2], "pausing after each failure but the last: \(paused)")
    guard let result else { return }
    let short = BatchWriting.shortfall(wanted: 10, written: result.items.count, tally: result.tally)
    ok(short?.missing == 2, "2 are missing")
    ok(short?.failedBatches == 3, "from 3 failed batches")
    let said = short?.message(noun: "card") ?? ""
    ok(said.hasPrefix("Wrote 8 of 10 cards."), "the student is told how many were written: \(said)")
    ok(said.contains("2 could not be written") && said.contains("3 batches failed"), "how many were lost, and why")
    ok(said.contains("HTTP 500"), "with the model's own reason")
    ok(!said.contains("..") && !said.contains(".)."), "punctuated once")
    ok(said.hasSuffix("Everything written is kept."), "and that nothing written was lost")
    ok(short?.retryTitle(noun: "card") == "Write the missing 2 cards", "the button writes just the missing ones")
}

// MARK: cards: a failure every batch would meet stops at once

run {
    var asked = 0
    let result = try? await BatchWriting.items(
        wanted: 10, perBatch: 4, patience: 3, classify: classify, pause: noPause,
        onProgress: { _, _ in }) { _, _, _ in
            asked += 1
            throw Refused(status: 402)
        }
    ok(asked == 1, "a model that needs Pro is asked once, not three times")
    ok(result?.items.isEmpty == true, "nothing written")
    ok((result?.lastError as? Refused)?.status == 402, "and its error is kept, for the screen to show as it is")
}

// MARK: cards: every batch fails

run {
    var asked = 0
    let result = try? await BatchWriting.items(
        wanted: 6, perBatch: 6, patience: 3, classify: classify, pause: noPause,
        onProgress: { _, _ in }) { _, _, _ in
            asked += 1
            throw URLError(.notConnectedToInternet)
        }
    ok(asked == 3, "offline: three tries, then the run stops")
    ok(result?.items.isEmpty == true && result?.lastError is URLError, "with the real error kept, not \"nothing usable\"")
}

// MARK: cards: batches that bring nothing new

run {
    let result = try? await BatchWriting.items(
        wanted: 10, perBatch: 4, patience: 3, classify: classify, pause: noPause,
        onProgress: { _, _ in }) { round, size, _ in
            round == 1 ? lines(size, round: 1) : []
        }
    ok(result?.items.count == 4, "a model that runs out of new cards stops after three empty batches")
    guard let result else { return }
    let short = BatchWriting.shortfall(wanted: 10, written: 4, tally: result.tally)
    let said = short?.message(noun: "case") ?? ""
    ok(short?.failedBatches == 0 && said.contains("nothing new"), "and says so, not that a batch failed: \(said)")
    ok(said.hasPrefix("Wrote 4 of 10 cases."), "in the set's own word")
}

// MARK: cards: a batch that brings more than asked

run {
    let result = try? await BatchWriting.items(
        wanted: 5, perBatch: 4, patience: 3, classify: classify, pause: noPause,
        onProgress: { _, _ in }) { round, _, _ in lines(4, round: round) }
    ok(result?.items.count == 5, "never more than asked for")
}

// MARK: cards: a stop is a stop

run {
    var asked = 0
    var stoppedWith: Error?
    do {
        _ = try await BatchWriting.items(
            wanted: 10, perBatch: 4, patience: 3, classify: classify, pause: noPause,
            onProgress: { _, _ in }) { round, size, _ in
                asked += 1
                if round == 2 {
                    // the model reports being stopped as its own error
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw URLError(.cancelled)
                }
                return lines(size, round: round)
            }
    } catch {
        stoppedWith = error
    }
    ok(stoppedWith is CancellationError, "Cancel ends the run as a stop, not as a failed batch")
    ok(asked == 2, "and no batch is asked for after it")
}

// MARK: a textbook: a page that fails leaves a gap, the rest are written

run {
    var asked: [Int] = []
    let result = try? await BatchWriting.pages(
        [0, 1, 2, 3], patience: 3, classify: classify, pause: noPause,
        onProgress: { _, _ in }) { part in
            asked.append(part)
            if part == 1 { throw Refused(status: 504) }
            return "## Page \(part + 1)\n\nText."
        }
    ok(asked == [0, 1, 2, 3], "every page is asked for, after a failed one too")
    ok(result?.pages.keys.sorted() == [0, 2, 3], "the pages that worked are kept")
    ok(result?.missing == [1], "the one that failed is listed")
    guard let result else { return }
    let short = BatchWriting.shortfall(wanted: 4, written: result.pages.count, tally: result.tally, parts: result.missing)
    let said = short?.message(noun: "page") ?? ""
    ok(said.hasPrefix("Wrote 3 of 4 pages.") && said.contains("(Part 2)"), "and named: \(said)")
    ok(short?.retryTitle(noun: "page") == "Write the missing page", "one missing page, one button")
}

run {
    var asked: [Int] = []
    let result = try? await BatchWriting.pages(
        Array(0..<6), patience: 3, classify: classify, pause: noPause,
        onProgress: { _, _ in }) { part in
            asked.append(part)
            if part >= 2 { throw URLError(.timedOut) }
            return "## Page \(part + 1)"
        }
    ok(asked == [0, 1, 2, 3, 4], "three pages failing in a row stop the asking")
    ok(result?.missing == [2, 3, 4, 5], "the pages not reached are listed with the failed ones")
    guard let result else { return }
    let short = BatchWriting.shortfall(wanted: 6, written: 2, tally: result.tally, parts: result.missing)
    ok(short?.message(noun: "page").contains("(Parts 3, 4, 5 and 6)") == true, "all four named")
    ok(short?.retryTitle(noun: "page") == "Write the missing 4 pages", "and offered again")
}

run {
    var asked = 0
    let result = try? await BatchWriting.pages(
        [0, 1, 2], patience: 3, classify: classify, pause: noPause,
        onProgress: { _, _ in }) { _ in
            asked += 1
            throw Refused(status: 401)
        }
    ok(asked == 1 && result?.missing == [0, 1, 2], "a refused session: asked once, every page listed")
}

// MARK: a textbook: gaps in the draft, filled in place

let draft = ["## Page 1", BatchWriting.gap(part: 1), "## Page 3", BatchWriting.gap(part: 3)].joined(separator: "\n\n")
let filled = BatchWriting.fill(draft, part: 1, with: "## Page 2")
ok(filled == ["## Page 1", "## Page 2", "## Page 3", BatchWriting.gap(part: 3)].joined(separator: "\n\n"),
   "a page written again goes in its gap's place, the other gap left")
ok(BatchWriting.fill(filled, part: 3, with: BatchWriting.gap(part: 3)) == filled, "a page that failed again leaves the draft as it was")
let edited = "## Page 1\n\n## Page 3"
ok(BatchWriting.fill(edited, part: 1, with: "## Page 2") == "## Page 1\n\n## Page 3\n\n## Page 2",
   "a gap edited away: the page is added at the end, never lost")
ok(BatchWriting.fill(edited, part: 1, with: BatchWriting.gap(part: 1)) == edited, "and a failed page adds no gap back")
ok(BatchWriting.fill("  ", part: 0, with: "## Page 1") == "## Page 1", "an empty draft takes the page as it is")
ok(BatchWriting.gap(part: 1).hasPrefix("## Part 2"), "a gap is a page of its own, numbered from one")
ok(BatchWriting.gap(part: 1) != BatchWriting.gap(part: 11), "and no gap is the start of another")

// MARK: the small rules

ok(BatchWriting.isFinal(status: 401) && BatchWriting.isFinal(status: 402) && BatchWriting.isFinal(status: 403),
   "401, 402 and 403 would refuse every batch")
ok(!BatchWriting.isFinal(status: nil) && !BatchWriting.isFinal(status: 404) && !BatchWriting.isFinal(status: 429)
   && !BatchWriting.isFinal(status: 500), "no answer, 404, 429 and 500 are worth the next batch")
ok([0, 1, 2, 3, 4, 9].map { BatchWriting.wait(afterFailuresInARow: $0) } == [0, 1, 2, 4, 8, 8],
   "the pause after failures in a row: 1, 2, 4, then 8 seconds")
ok(BatchWriting.partList([3]) == "Part 4", "one part")
ok(BatchWriting.partList([3, 8]) == "Parts 4 and 9", "two parts")
ok(BatchWriting.partList([0, 1, 2]) == "Parts 1, 2 and 3", "three parts")
var whole = BatchWriting.Tally()
whole.batchReturned(fresh: 3)
ok(BatchWriting.shortfall(wanted: 3, written: 3, tally: whole) == nil, "all written: no shortfall")
ok(BatchWriting.shortfall(wanted: 3, written: 2, tally: whole)?.missing == 1, "one short: one missing")

print(failures == 0 ? "\nALL BATCH WRITING TESTS PASS" : "\n\(failures) BATCH WRITING TEST FAILURE(S)")
exit(failures == 0 ? 0 : 1)
