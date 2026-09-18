import Foundation

/// Turning a model's answer into stations worth drilling, and back into the
/// text format the new-set screen already understands.
///
/// Separate from the generator so the judgement can be tested without a model.
/// Everything here is about what makes a checklist usable in an exam: steps
/// that are actions rather than essays, in the order they would be performed,
/// with nothing repeated - because a station that lists "wash your hands"
/// twice teaches the wrong thing and wastes a recall.
enum OsceStations {

    /// Longest a step may be before it stops being a step.
    ///
    /// A checklist item is something an examiner ticks: "Introduce yourself and
    /// confirm the patient's name". Anything much longer is a paragraph, and a
    /// paragraph cannot be recalled word for word or marked off.
    static let maxStepLength = 160
    static let maxSteps = 30

    /// Tidies one station's steps.
    ///
    /// Numbering is stripped because the position IS the number here; a step
    /// stored as "3. Palpate the abdomen" shows as "3." however it is
    /// reordered, and reordering is exactly what editing a station does.
    static func clean(_ steps: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in steps {
            var step = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            step = stripLeadingMarker(step)
            step = step.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard step.count >= 3, step.count <= maxStepLength else { continue }
            // Case-insensitively unique: a model asked twice for the same
            // station tends to return "Wash hands" and "Wash Hands".
            let key = step.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(step)
            if out.count >= maxSteps { break }
        }
        return out
    }

    /// Removes "1.", "1)", "-", "•", "Step 2:" and the like from the front.
    static func stripLeadingMarker(_ step: String) -> String {
        var text = step
        let patterns = [#"^\s*step\s*\d+\s*[:.)-]\s*"#, #"^\s*\d+\s*[:.)-]\s*"#, #"^\s*[-–—•*]\s*"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let found = Range(match.range, in: text) {
                text.removeSubrange(found)
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Whether a station is worth keeping at all.
    ///
    /// Two steps is not a station. A generated one with fewer has usually
    /// misunderstood the source - a slide of learning objectives read as a
    /// procedure - and keeping it puts something meaningless into the drill.
    static func isUsable(_ checklist: OsceChecklist) -> Bool {
        !checklist.title.trimmingCharacters(in: .whitespaces).isEmpty
            && checklist.steps.count >= 3
    }

    /// Cleans and drops the unusable, keeping the order they arrived in.
    static func tidy(_ checklists: [OsceChecklist]) -> [OsceChecklist] {
        var seenTitles = Set<String>()
        var out: [OsceChecklist] = []
        for checklist in checklists {
            var kept = checklist
            kept.title = kept.title.trimmingCharacters(in: .whitespacesAndNewlines)
            kept.title = stripLeadingMarker(kept.title)
            kept.steps = clean(checklist.steps)
            guard isUsable(kept) else { continue }
            let key = kept.title.lowercased()
            guard !seenTitles.contains(key) else { continue }
            seenTitles.insert(key)
            out.append(kept)
        }
        return out
    }

    /// What the model is asked for.
    ///
    /// Here rather than in OsceGenerator so it can be tested: the prompt is
    /// the part most likely to be quietly broken by an edit - a dropped
    /// "already written" list makes every call return the same station - and
    /// checking it needs no model, only the text.
    static func prompt(sourceText: String, count: Int, subject: String,
                       alreadyWritten: [String]) -> String {
        var lines = [
            "You write OSCE station checklists for a medical student revising \(subject.isEmpty ? "clinically" : subject).",
            "",
            "From the source below, write \(count) station checklist\(count == 1 ? "" : "s").",
            "",
            "Each station is a clinical task a student could be examined on: an examination, a procedure, a history, a counselling or handover task.",
            "Each step is one thing the candidate DOES or SAYS, in the order it happens, phrased as an examiner's tick-box.",
            "Write between 6 and 20 steps. Keep every step under 20 words.",
            "Include the marks students actually lose: introducing yourself, consent, exposure, hand hygiene, and saying what you would do to finish.",
            "Use only what the source supports. Do not invent a procedure the source never mentions.",
            "Do not number the steps; the order is the number.",
        ]
        if !alreadyWritten.isEmpty {
            lines.append("")
            lines.append("You have already written these stations - write different ones:")
            lines.append(contentsOf: alreadyWritten.map { "- " + $0 })
        }
        lines.append("")
        lines.append("SOURCE:")
        lines.append(sourceText)
        return lines.joined(separator: "\n")
    }

    /// Back into the "## Station / one step per line" format the new-set screen
    /// parses.
    ///
    /// Generated stations land in the editor as text rather than straight into
    /// a set on purpose: a checklist written by a model is a draft, and the one
    /// person who can tell whether a step belongs in the exam is the student
    /// who sat the teaching. Editing before saving is the whole point.
    static func format(_ checklists: [OsceChecklist]) -> String {
        checklists.map { checklist in
            (["## " + checklist.title] + checklist.steps).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
