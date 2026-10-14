// The verification layer's first stage on generated material: a broken item
// is removed with its reason, a red flag is kept and held, and the status
// line says what happened and that the checkers are on the rest.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let good = MCQQuestion(stem: "First-line drug for absence seizures?", options: ["Ethosuximide", "Phenytoin", "Carbamazepine", "Gabapentin"],
                       correctIndex: 0, explanation: "Ethosuximide is first line for absence seizures.")
let noKey = MCQQuestion(stem: "Which nerve supplies deltoid?", options: ["Axillary", "Radial", "Ulnar", "Median"], correctIndex: 7, explanation: "")
let contradicted = MCQQuestion(stem: "Which tissue?", options: ["w", "x", "y", "z"], correctIndex: 0, explanation: "Ans-b. The second.")
let copiedKey = MCQQuestion(stem: "Which infection?", options: ["Measles", "Rubella", "Measles", "Mumps"], correctIndex: 0, explanation: "")
let outdated = MCQQuestion(stem: "The monitor shows asystole. CPR is started. Which drug should be given next?",
                           options: ["Adrenaline 1 mg IV", "Atropine 3 mg IV", "Amiodarone 300 mg IV", "Lidocaine"], correctIndex: 1, explanation: "")

let outcome = VerificationScreen.questions([good, noKey, contradicted, copiedKey, outdated])
check("a sound question is kept", outcome.kept.contains { $0.id == good.id })
check("a question with no key is removed", !outcome.kept.contains { $0.id == noKey.id })
check("one its explanation contradicts is removed", !outcome.kept.contains { $0.id == contradicted.id })
check("one whose key is copied into a distractor is removed", !outcome.kept.contains { $0.id == copiedKey.id })
check("a retired-practice key is kept but held for the checkers", outcome.kept.contains { $0.id == outdated.id } && outcome.held == 1)
check("removals are counted by reason", outcome.removedCount == 3 && outcome.removed.map(\.reason) == ["no answer key", "key contradicted by its explanation", "two identical correct options"],
      "\(outcome.removed)")
let note = VerificationScreen.note(outcome)
check("the note says what happened and what comes next",
      note == " On-device checks: 3 removed (1 no answer key, 1 key contradicted by its explanation, 1 two identical correct options); 1 held for a red flag. The independent checkers are verifying the rest now.", note)
check("a clean set says it passed", VerificationScreen.note(VerificationScreen.questions([good])) == " On-device checks passed. The independent checkers are verifying the rest now.")
check("nothing made, nothing said", VerificationScreen.note(VerificationScreen.questions([])) == "")
let station = OsceChecklist(title: "Cardiac arrest", steps: ["Start CPR", "Give atropine 3 mg for asystole", "Attach the defibrillator"])
let stations = VerificationScreen.stations([station])
check("a station is never removed, only held", stations.kept.count == 1 && stations.held == 1)
let card = AnkiCard(type: .qa, front: "Antidote to heparin?", bullets: ["Protamine sulfate"])
check("a sound card is kept", VerificationScreen.cards([card]).kept.count == 1 && VerificationScreen.cards([card]).held == 0)

print(failures.isEmpty ? "\nALL VERIFICATION SCREEN TESTS PASS" : "\n\(failures.count) VERIFICATION SCREEN TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
