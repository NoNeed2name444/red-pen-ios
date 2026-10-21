// What has to be true of a line once Vision has read it.
//
// Vision itself is Apple's and is not run here: no picture is drawn and nothing
// is recognised. What IS tested is the one decision Red Pen makes about the
// text afterwards - putting a line that mixes Arabic and English back into the
// order it was written in. The cases are the ones a macOS 26 runner checked
// against live Vision output (red-pen-transcribe's ocr-verify run, ALL PASS).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: a mixed line comes back in visual order and is put right

let recorded = "nasolabial fold ال spare بي malar rash ال"
let expected = "ال malar rash بي spare ال nasolabial fold"
let fixed = RedPenOCR.logicalOrder(recorded)
check("a mixed line is put back in the order it was written",
      fixed == expected, fixed)
check("every word survives, only the order changes",
      fixed.split(separator: " ").sorted() == recorded.split(separator: " ").sorted(), fixed)
check("an English run inside it keeps its own reading order",
      fixed.contains("malar rash") && fixed.contains("nasolabial fold")
        && !fixed.contains("rash malar") && !fixed.contains("fold nasolabial"), fixed)

// The slide writes its prefixes with a tatweel (الـ, بيـ). The tatweel is an
// Arabic letter as far as the reordering goes, so a token carrying one is an
// Arabic token and the line is reordered exactly as it would be without it.
let tatweelRecorded = "nasolabial fold الـ spare بيـ malar rash الـ"
let tatweelExpected = "الـ malar rash بيـ spare الـ nasolabial fold"
let tatweelFixed = RedPenOCR.logicalOrder(tatweelRecorded)
check("a mixed line written with tatweels is put right too",
      tatweelFixed == tatweelExpected, tatweelFixed)
check("the tatweels themselves are kept",
      tatweelFixed.filter { $0 == "\u{640}" }.count == 3, tatweelFixed)
check("a token that is only a tatweel counts as Arabic",
      RedPenOCR.hasArabic("\u{640}"))

// MARK: a line in one script is already right and is left alone

let english = "Discoid rash is the chronic form"
check("a pure English line is unchanged",
      RedPenOCR.logicalOrder(english) == english, RedPenOCR.logicalOrder(english))
let arabic = "الطفح الجلدي المزمن"
check("a pure Arabic line is unchanged (Vision reads it in order)",
      RedPenOCR.logicalOrder(arabic) == arabic, RedPenOCR.logicalOrder(arabic))
check("a single word is unchanged",
      RedPenOCR.logicalOrder("lupus") == "lupus" && RedPenOCR.logicalOrder("الذئبة") == "الذئبة")
check("an empty line is unchanged", RedPenOCR.logicalOrder("") == "")
check("numbers and punctuation alone are not Arabic",
      !RedPenOCR.hasArabic("1. B) 120/80 mmHg"))

// MARK: the languages asked for

check("Arabic and English are both asked for",
      RedPenOCR.languages.contains("ar-SA") && RedPenOCR.languages.contains("en-US"))

print(failures.isEmpty ? "\nALL OCR TESTS PASS"
                       : "\n\(failures.count) OCR TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
