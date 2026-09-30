import Foundation

/// A ready-made AI check for the personal build, so the Syllabus screen shows
/// the merged view - AI verdicts, evidence and suggestions beside the keyword
/// result - the first time it opens, without a cloud call.
///
/// Made from the live keyword result, so its evidence lines match what is
/// actually in the library; every fourth subtopic deliberately disagrees with
/// the keywords, so the "keywords said" note can be seen too. Labelled
/// "Example check" on screen and never saved.
enum CoverageExamples {

    /// How many areas the example covers: enough to scroll through, few
    /// enough that the rest plainly show the keyword result alone.
    static let areaCount = 4

    static func check(for track: ExamTrack, areas: [AreaCoverage]) -> CoverageCheck {
        var verdicts: [String: CoverageVerdict] = [:]
        for area in areas.prefix(areaCount) {
            for (i, sub) in area.subtopics.enumerated() {
                verdicts[sub.id] = verdict(for: sub, disagreeing: i % 4 == 1)
            }
        }
        return CoverageCheck(track: track.rawValue, date: Date(),
                             sources: [CoverageCloudCheck.preferredModel],
                             verdicts: verdicts, isExample: true)
    }

    static func verdict(for sub: SubtopicCoverage, disagreeing: Bool) -> CoverageVerdict {
        let name = sub.subtopic.name.lowercased()
        var status: CoverageVerdict.Status
        switch sub.status {
        case .covered: status = disagreeing ? .thin : .covered
        case .thin: status = disagreeing ? .missing : .thin
        case .notCovered: status = disagreeing ? .thin : .missing
        }
        let reading = sub.evidence - sub.practice
        let evidence: String
        let suggestion: String
        switch status {
        case .covered:
            evidence = "\(sub.practice) questions or cards and \(reading) pages on it"
            suggestion = "Keep it in review; add a few harder questions on \(name)"
        case .thin:
            evidence = sub.evidence > 0
                ? "\(sub.evidence) item\(sub.evidence == 1 ? "" : "s") mention it, mostly in passing"
                : "Touched on inside a broader lecture, with no questions"
            suggestion = "Add about ten exam-style questions on \(name)"
        case .missing:
            evidence = sub.evidence > 0
                ? "The matches are passing mentions, not teaching"
                : "Nothing in the library on \(name)"
            suggestion = "Generate a set on \(name) from a lecture or a brief"
        }
        return CoverageVerdict(status: status, evidence: evidence, suggestion: suggestion)
    }
}
