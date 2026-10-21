// Red Pen · how a spoken line is said: the tone for what it is for, the
// patient's tone from what they say, and verdicts in varied words.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: the tones stay the same person

for tone in VoiceTone.allCases {
    check("\(tone): pace within 10% of the voice's own", abs(tone.pace - 1) <= 0.1, "\(tone.pace)")
    check("\(tone): pitch within 6% of the voice's own", abs(tone.pitch - 1) <= 0.06, "\(tone.pitch)")
    check("\(tone): pauses under half a second", tone.before < 0.5 && tone.after < 0.5)
}
check("plain changes nothing", VoiceTone.plain.pace == 1 && VoiceTone.plain.pitch == 1)
check("praise lifts", VoiceTone.praise.pitch > 1 && VoiceTone.praise.pace > 1)
check("a correction is slower and lower than praise",
      VoiceTone.correcting.pace < VoiceTone.praise.pace && VoiceTone.correcting.pitch < VoiceTone.praise.pitch)
check("a correction waits a moment first", VoiceTone.correcting.before > VoiceTone.plain.before)
check("an explanation is unhurried", VoiceTone.explaining.pace < 1)
check("a question leaves the longest room after it",
      VoiceTone.allCases.allSatisfy { VoiceTone.asking.after >= $0.after })
check("a time warning starts at once and is brisk", VoiceTone.alert.before == 0 && VoiceTone.alert.pace > 1)

// MARK: the patient

check("pain is said uneasily", VoiceTone.forPatient("It really hurts when I breathe in.") == .uneasy)
check("fear is said uneasily", VoiceTone.forPatient("I'm quite scared, doctor.") == .uneasy)
check("a curly apostrophe still counts",
      VoiceTone.forPatient("I can\u{2019}t breathe properly.") == .uneasy)
check("capitals still count", VoiceTone.forPatient("The PAIN started yesterday.") == .uneasy)
check("a plain answer is plain", VoiceTone.forPatient("I'm 54 and I work as a teacher.") == .plain)
check("whole words only: painting is not pain", VoiceTone.forPatient("I do painting at weekends.") == .plain)
check("whole words only: soreness of words like 'sorely' does not count",
      VoiceTone.forPatient("I sorely miss walking the dog.") == .plain)

// MARK: varied words

let praise = (0..<VoiceTone.praiseOpeners.count).map { VoiceTone.opener(praise: true, turn: $0) }
check("every praise opener is used in turn", Set(praise).count == VoiceTone.praiseOpeners.count)
check("two right answers in a row are not praised the same way",
      VoiceTone.opener(praise: true, turn: 3) != VoiceTone.opener(praise: true, turn: 4))
check("the openers come round again",
      VoiceTone.opener(praise: false, turn: 0) == VoiceTone.opener(praise: false, turn: VoiceTone.correctionOpeners.count))
check("a negative turn still gives an opener", !VoiceTone.opener(praise: true, turn: -7).isEmpty)

let right = VoiceTone.verdict(praise: true, turn: 0, answer: "B", why: "Because it is.")
check("a right answer: the verdict lifts, then why, unhurried",
      right.count == 2 && right[0].1 == .praise && right[0].0 == "Correct, B." && right[1].1 == .explaining,
      "\(right)")
let wrong = VoiceTone.verdict(praise: false, turn: 0, answer: "warfarin", why: "  ")
check("a wrong answer names the right one, gently, and an empty why is left out",
      wrong.count == 1 && wrong[0].0 == "Not quite. It's warfarin." && wrong[0].1 == .correcting, "\(wrong)")
let bare = VoiceTone.verdict(praise: true, turn: 1, answer: "", why: "")
check("no answer text: just the opener", bare.count == 1 && bare[0].0 == "That's right.", "\(bare)")

print(failures.isEmpty ? "\nALL VOICE TONE TESTS PASS"
                       : "\n\(failures.count) VOICE TONE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
