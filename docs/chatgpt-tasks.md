# Tasks for ChatGPT

Small, checkable jobs for ChatGPT (Codex), so Claude's usage goes on the
app's harder work. ChatGPT takes them through the owner's loop: one task at
a time, on the branch aahp/personal, and Claude reviews each result against
the app's own CI (the iOS preview screenshots and the Swift tests).
aahp/personal joins personal only after that review.

The rows are Chat-me's verified audit
(docs/architecture/audit/stethoscore-verified-findings.md). They were
checked against aahp/personal at d7da19a on 9 Oct: many rows the audit
lists as open are already fixed, so every task starts by confirming that
its rows are still open, and says where if one is not.

Every task stays clear of:
- the files personal has changed since the two branches split
  (Features/Notes/*, Onboarding/StudyTips.swift,
  Voice/CommuteModeView.swift, Voice/CommuteSession.swift,
  Shared/Accuracy/AccuracyLedger.swift, Shared/Space/GraphicsQuality.swift),
  so the merge back stays clean;
- the look: Theme.swift, Shared/Ward/* and any restyling, which the
  neumorphic work (#33) owns;
- the Cases screens, which are rebuilt clean-room from
  docs/design/cases-rebuild.md;
- anything outside ios/RedPen/, which the loop cannot change.

## 1. Two labels that say the wrong thing (rows 40 and 34)

- Row 40: the Mixed quiz tile says "20 from every set" but builds 20
  questions in all (StudyCategory.swift:281; the quiz at :409-411). Make it
  "20 across all your sets".
- Row 34, what is left of it: the personal build still shows "Manage or
  cancel" and "Restore purchases" on the Account page
  (AccountView.swift:175-182), with no subscription to manage. Hide both
  when `PersonalBuild.isOn`.

Done when: the tile and the Account page read as above, nothing else
moves, and the iOS preview builds with every shot.

## 2. Re-check the audit's open rows (a report, no app change)

For each row, say whether it is still open on aahp/personal, with the file
and line that shows it; for an open one, the smallest fix and the test file
that covers that code. The report decides the next fix tasks.

Rows: 1, 4, 9, 15, 17, 18, 22, 23, 24, 25, 42, 43, 44, 45, 46, 47, 49, 52,
53, 55, 56, 58, 59, 62, 63, 65, 73, 75, 82, 91, 95. (Row 79, the voice
session's Bluetooth mic, waits on the owner's call.)

Already checked here and fixed: 32, 35, 37, 38, 39 and 122, 48, 50, 54,
60, 64, 74's cloud prompt, 80, 120, 124.

## 3. The on-device recogniser's word list (the rest of row 74)

The cloud transcript now names only the lecture's own terms, but the
on-device recogniser is still given a lupus-only list for every lecture
(LectureTranscriber.swift:139; the list at :169). Give it the
lecture's own terms when the lecture has slides
(`CloudTranscript.lectureTerms`, as LectureImporter.swift:73 does for the
cloud), and no list otherwise; keep the 100-word cap. Make the choice a
small function in CloudTranscript.swift, which has no Apple-only imports,
so the Linux suite can test it. Keep `MedicalTerms` itself:
tools/asr_bench.mjs reads it, and VoiceListener.swift:58 is a separate
question.

Done when: CloudTranscriptTests.swift checks that a lecture whose slides
never mention lupus gets no lupus words and that one without slides gets
no list, and the Swift tests and the iOS preview pass.

## 4. Fixes from task 2's report, one area at a time

One area per task, each with checks added to the test file that already
covers the code: the quiz's re-tests and copies (43, 44, 45, 53); Anki
import and scheduling (55, 56, 59, 63); the OSCE (58, 65); the coverage
check (52).

## What stays with Claude

Data safety and sync (rows 1, 15 to 18, 22 to 25, 46, 73), the 3D map and
Notes, the look, the Cases rebuild, and the Worker (server/; a deploy needs
the owner's word each time).
