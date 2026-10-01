import Foundation

/// Different ways the same disease walks through the door, so a set of cases
/// on one condition is not the same textbook patient again and again. Each
/// batch of cases is handed its own mix of patient, setting, stage and
/// question, and the mix moves on every batch.
enum CaseVariety {
    static let patients = [
        "a young adult", "a middle-aged adult with comorbidities", "an older patient on several medications",
        "a pregnant or postpartum woman (only if the disease fits)", "a child or adolescent (only if the disease fits)",
        "a patient already on treatment", "a patient from a high-risk group for this disease",
    ]
    static let presentations = [
        "a classic textbook presentation", "an atypical presentation", "an early presentation with subtle signs",
        "a late presentation with a complication", "a presentation set off by a drug or trigger",
        "a finding picked up incidentally on routine tests", "an acute emergency presentation",
        "a flare, relapse or treatment failure",
    ]
    static let settings = ["in general practice", "in the emergency department", "on a medical ward",
                           "in an outpatient clinic", "on a surgical ward", "in intensive care"]
    static let asks = ["asking the most likely diagnosis", "asking the best next investigation",
                       "asking the first-line management", "asking the most likely complication",
                       "asking the underlying mechanism", "asking what must be avoided",
                       "asking how to monitor or follow up"]

    /// `count` different presentations for one batch; `round` moves the mix
    /// along so no two batches start in the same place.
    static func plan(_ count: Int, round: Int) -> [String] {
        (0..<count).map { i in
            let n = round * 7 + i
            return "\(patients[n % patients.count]), \(presentations[(n * 3 + round) % presentations.count]), "
                + "\(settings[(n * 5 + round) % settings.count]), \(asks[(n + round * 2) % asks.count])"
        }
    }
}
