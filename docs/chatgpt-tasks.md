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
- Row 34, what is left of it: the account line and "Manage or cancel" are
  right now, but the personal build, with no subscription, still shows a
  "Pro" chip on the account card (AccountView.swift:279 and :303, fed by
  `subscriptions.isPro` at :78, which is true whenever the build unlocks
  everything) and offers "Restore purchases" (:181). Let the chip follow
  the real subscription (`subscriptions.access.isPro`), keep the card's
  button as it is, and hide "Restore purchases" when `PersonalBuild.isOn`.

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
(LectureTranscriber.swift:139; the list at :169). LectureImporter already
holds the lecture's own terms (`vocabulary`, from
`CloudTranscript.lectureTerms`, at most 80 words, none without slides; :73)
and sends them to the cloud; pass the same words to
`LectureTranscriber.transcribe` (called at :110) and give the recogniser
those, so a lecture without slides gets no list. Do the picking in a small
function outside the Speech fence, so the Linux suites that compile
LectureTranscriber.swift can test it. Keep `MedicalTerms` itself:
tools/asr_bench.mjs reads it, and VoiceListener.swift:58 is a separate
question.

Done when: CloudTranscriptTests.swift checks that a lecture whose slides
never mention lupus gives the recogniser no lupus words and that one
without slides gives it none, and the Swift tests and the iOS preview pass.

## 4. Fixes from task 2's report, one area at a time

Task 2's report (approved on 9 Oct): of its 31 rows, 26 are fixed on
aahp/personal; 1, 17 and 91 are open, and 4 and 18 partly. Rows 1, 17 and
18 are data safety and sync, which stay with Claude (below). That leaves
two tasks, each with checks added to the test file that already covers
the code:

- Row 4, what is left of it: Spotlight's indexer (`SpotlightIndexer`,
  Shared/AppIntents.swift) now waits for its calls and confirms nothing
  after a cancel, but swallows a failed index or delete call (about :270
  and :275), so those sets still count as indexed; and after a run that
  fails, the next update with the same library sends nothing. Report
  either error as a failed run and free the pending snapshot, so the next
  update sends again. Do the sending in `SpotlightPlan`
  (Shared/Platform/AppLink.swift, Foundation-only), so the Linux suite
  can test it. Tests: Tests/PlatformTests.swift. In the loop since 9 Oct.
- Row 91: the cloud jobs receive each generated item's check results but
  keep only its evidence (Shared/LLM/CloudJobs.swift, about :63 to :66),
  so the accuracy schedule checks the item again
  (Shared/Accuracy/AccuracySchedule.swift, about :46). Hand a finished
  generation check to the schedule by the item's final content hash, with
  its blind-solve and proof details; an incomplete check must still run,
  and nothing may count as checked that was not. AccuracyLedger.swift is
  personal's (above): go through what it already offers. Tests:
  Tests/AccuracyTests.swift.

## What stays with Claude

Data safety and sync (rows 1, 15 to 18, 22 to 25, 46, 73; task 2 found
1, 17 and 18 still open: the library loaded on the main thread at
launch, images kept inline in every snapshot, a write per review rating
and every deck's schedule rebuilt on each sync), the 3D map and
Notes, the look, the Cases rebuild, and the Worker (server/; a deploy needs
the owner's word each time).
