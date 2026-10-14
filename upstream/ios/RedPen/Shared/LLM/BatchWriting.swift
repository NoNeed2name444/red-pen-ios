import Foundation

/// Writing a set a batch at a time, on this device or with a hosted model,
/// apart from any model, so what happens when a batch fails can be run in a
/// test.
///
/// One failed request used to throw the whole run away: thirty cards
/// written, the next batch timed out, and the student got an error and
/// nothing (audit #88). A failed batch is now counted and the run carries
/// on; what was written is kept; what is missing is said, and can be
/// written again on its own.
enum BatchWriting {

    /// How the batches of one run went.
    struct Tally: Equatable {
        /// Batches whose request failed.
        var failedBatches = 0
        /// Batches in a row that failed or brought nothing new.
        var inARow = 0
        /// Why the last failed batch failed, in words for the student.
        var reason: String?
        /// A failure every later batch would meet too (no key, no Pro, a
        /// session refused): the run stops at once.
        var final = false

        /// A batch came back with `fresh` new items.
        mutating func batchReturned(fresh: Int) {
            inARow = fresh > 0 ? 0 : inARow + 1
        }

        mutating func batchFailed(_ why: String, final: Bool) {
            failedBatches += 1
            inARow += 1
            reason = why
            if final { self.final = true }
        }

        /// Whether the run should stop asking.
        func exhausted(patience: Int) -> Bool {
            final || inARow >= max(1, patience)
        }
    }

    /// What a run did not write, for the screen to say and to offer again.
    struct Shortfall: Equatable, Sendable {
        /// Cards or pages asked for, and written.
        var wanted: Int
        var written: Int
        /// Batches whose request failed.
        var failedBatches: Int
        /// A textbook's parts left unwritten, as indexes into its slices of
        /// the lecture; empty for cards.
        var parts: [Int] = []
        /// Why the last failed batch failed.
        var reason: String? = nil

        var missing: Int { max(0, wanted - written) }

        /// What the student is told. `noun`: "card", "case" or "page".
        func message(noun: String) -> String {
            var said = "Wrote \(written) of \(wanted) \(BatchWriting.plural(noun, wanted))."
            let which = parts.isEmpty ? "" : " (\(BatchWriting.partList(parts)))"
            if failedBatches > 0 {
                let batches = failedBatches == 1 ? "1 batch" : "\(failedBatches) batches"
                said += " \(missing) could not be written\(which): \(batches) failed"
                if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                    said += " \u{2014} " + (reason.hasSuffix(".") ? String(reason.dropLast()) : reason)
                }
                said += "."
            } else {
                said += " The model found nothing new to write for the other \(missing)\(which)."
            }
            return said + " Everything written is kept."
        }

        /// The button that writes only what is missing.
        func retryTitle(noun: String) -> String {
            "Write the missing \(missing == 1 ? noun : "\(missing) \(BatchWriting.plural(noun, missing))")"
        }
    }

    /// What a run wrote: nil when it wrote everything asked for.
    static func shortfall(wanted: Int, written: Int, tally: Tally, parts: [Int] = []) -> Shortfall? {
        guard written < wanted || !parts.isEmpty else { return nil }
        return Shortfall(wanted: wanted, written: min(written, wanted), failedBatches: tally.failedBatches,
                         parts: parts, reason: tally.reason)
    }

    /// Whether a request that failed with this HTTP status would fail the
    /// same way for every later batch: a session refused (401, 403), or a
    /// model that needs Pro (402).
    static func isFinal(status: Int?) -> Bool {
        guard let status else { return false }
        return status == 401 || status == 402 || status == 403
    }

    /// Seconds to wait after a failed batch before the next, for a hosted
    /// model (a server that blinks, or asks for a pause): 1, 2, 4, then 8.
    static func wait(afterFailuresInARow n: Int) -> TimeInterval {
        guard n > 0 else { return 0 }
        return min(8, pow(2, Double(n - 1)))
    }

    // MARK: cards

    struct Items {
        var items: [String]
        var tally: Tally
        /// The last failed batch's error: thrown when nothing at all was written.
        var lastError: Error?
    }

    /// Batches until `wanted` items are written, or `patience` batches in a
    /// row bring nothing new.
    ///
    /// `batch(round, size, written)` writes one batch of `size` and returns
    /// only its new items; `round` counts from 1. A batch that throws is
    /// counted and the run carries on; a stop (cancellation, however the
    /// model reports it) ends the run at once. `classify` turns a failure
    /// into words and says whether it is final; `pause` waits after a failure
    /// (given how many in a row).
    static func items(wanted: Int, perBatch: Int, patience: Int,
                      classify: (Error) -> (reason: String, final: Bool),
                      pause: (Int) async throws -> Void,
                      onProgress: (Int, Int) -> Void,
                      batch: (Int, Int, [String]) async throws -> [String]) async throws -> Items {
        var items: [String] = []
        var tally = Tally()
        var lastError: Error?
        var round = 0
        while items.count < wanted && !tally.exhausted(patience: patience) {
            try Task.checkCancellation()
            onProgress(items.count, wanted)
            let size = min(max(1, perBatch), wanted - items.count)
            round += 1
            do {
                let fresh = try await batch(round, size, items)
                tally.batchReturned(fresh: fresh.count)
                items.append(contentsOf: fresh.prefix(wanted - items.count))
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                let failure = classify(error)
                tally.batchFailed(failure.reason, final: failure.final)
                lastError = error
                if !tally.exhausted(patience: patience) { try await pause(tally.inARow) }
            }
        }
        return Items(items: items, tally: tally, lastError: lastError)
    }

    // MARK: a textbook's pages

    struct Pages {
        /// Each written page, by its part.
        var pages: [Int: String]
        /// Parts not written, in order: failed, or not reached once the run stopped.
        var missing: [Int]
        var tally: Tally
        var lastError: Error?
    }

    /// Each part written once, in order. A part that fails is listed and the
    /// run carries on with the next; after `patience` failures in a row the
    /// rest are listed without being asked for.
    static func pages(_ parts: [Int], patience: Int,
                      classify: (Error) -> (reason: String, final: Bool),
                      pause: (Int) async throws -> Void,
                      onProgress: (Int, Int) -> Void,
                      write: (Int) async throws -> String) async throws -> Pages {
        var pages: [Int: String] = [:]
        var missing: [Int] = []
        var tally = Tally()
        var lastError: Error?
        for (n, part) in parts.enumerated() {
            try Task.checkCancellation()
            if tally.exhausted(patience: patience) {
                missing.append(part)
                continue
            }
            onProgress(n, parts.count)
            do {
                pages[part] = try await write(part)
                tally.batchReturned(fresh: 1)
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                let failure = classify(error)
                tally.batchFailed(failure.reason, final: failure.final)
                lastError = error
                missing.append(part)
                if !tally.exhausted(patience: patience) { try await pause(tally.inARow) }
            }
        }
        return Pages(pages: pages, missing: missing, tally: tally, lastError: lastError)
    }

    // MARK: gaps in a textbook draft

    /// What stands in a textbook draft for a part not written, until it is.
    static func gap(part: Int) -> String {
        "## Part \(part + 1): not written yet\n\n> **Not written:** this part of the lecture could not be written. Use \u{201C}Write the missing pages\u{201D} to try again."
    }

    /// The draft with a part's page in its gap's place, or added at the end
    /// when the gap has been edited away. A page that failed again is its
    /// gap, so the draft is left as it was.
    static func fill(_ draft: String, part: Int, with page: String) -> String {
        let hole = BatchWriting.gap(part: part)
        if let range = draft.range(of: hole) {
            return draft.replacingCharacters(in: range, with: page)
        }
        guard page != hole else { return draft }
        let kept = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? page : kept + "\n\n" + page
    }

    // MARK: words

    static func plural(_ noun: String, _ n: Int) -> String {
        n == 1 ? noun : noun + "s"
    }

    /// "Part 4", "Parts 4 and 9", "Parts 1, 2 and 3", from zero-based parts.
    static func partList(_ parts: [Int]) -> String {
        let named = parts.map { String($0 + 1) }
        guard let last = named.last else { return "" }
        if named.count == 1 { return "Part " + last }
        return "Parts " + named.dropLast().joined(separator: ", ") + " and " + last
    }
}
