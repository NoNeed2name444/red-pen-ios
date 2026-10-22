# Wording: from the ward to the exam

> **Reading note.** On 15 Oct the owner asked for wording that fits "an example" more than a hospital ward. We read "an example" as **"an exam"**: Stethoscore prepares students for exams, and the rest of the request is about exam language. If another reading was meant, this inventory still lists the ward-metaphor strings the search below finds.

This reverses `docs/design/targets-2026-10-01.md` §1, which kept “beds, charts, vitals, consults”, on the owner’s word of 15 Oct.

**How the strings were found.** In the app: `git grep -n -i -E '"[^"]*\b(ward round|ward|bed [0-9]|beds?|vitals|consult|pocket|next patient|chart|rounds?|on call|handover|triage|discharge|admit|admission|patients?|sinus|all quiet)[^"]*"' origin/personal -- ios/RedPen ios/StethoscoreWidgets`, plus `ios/project.yml` and `ios/AppResources/Localized`. In the iPad build: `git grep -n -i -E 'ward|bed [0-9]|patients yet|admitted' origin/personal -- tools/playgrounds_stubs`. Each hit was read by hand; case and exam content, symbols and identifiers were left out. Two kinds of hit are deliberately not listed either way: `BedPlan.swift:349`, the placeholder ward “All quiet” on an empty bed, goes with the bed rows it belongs to; and code comments change with their strings.

Written 15 Oct 2026 against `personal` at bc611221, and checked again at 2b7ef11e, which changes nothing under `ios/`. Every file:line below is checked with `git show origin/personal:<path>` each time this file is generated; line numbers move as code changes, so search for the quoted text. No app code changes in this phase; this is the list a later phase applies.

**Built, 22 Oct 2026 (T0125).** The rows marked “Built 22 Oct” are in the app on iOS, with their Android twins in the same change set; the rows not marked wait on the reason given in that change’s result (an owner question, or a file outside it).

## The rule

- **The exam is the setting; medicine is the content.** Ward words go wherever they dress up the app’s own furniture: the daily plan, the progress screen, the timer, the question screen. They stay wherever they *are* the content: a case’s patient, the OSCE’s talking patient, a clinical score’s own wording, and every safety notice about real patients.
- **Exam vocabulary, plain and warm:** paper, question, station, mark scheme, score, mock, revision, topic, weak topics, results, pass mark, SBA (single best answer), viva. No role-play and no jargon jokes.
- **UK English, on purpose.** The words are British (revision, mark scheme, viva, SBA), as the app is. The USMLE track (ExamTrack.swift:67) would say review, answer key, oral exam and “single best answer” in full; if the owner wants a US voice for that track, these are the words to swap.
- **One word per thing.** The daily plan is *Today’s revision*. The timer is a *focus session* made of parts, named by the owner (glossary). The progress screen is *Progress*; *Results* stays the end of a paper. What to revise next is *weak topics*.
- **The words already right stay:** Second try, Timed, Reveal, Step 1 of 8, Finish paper, See results, Spaced review, Due, New, "on track for a pass", "below the pass mark for now", streak.

## Glossary

| Ward term | Exam term | Why |
|---|---|---|
| Today’s ward round (the daily plan) | Today’s revision | It is a revision plan, and "revision" is the word students use for exam preparation. "Start revision" reads as what it does. |
| Bed 1, Bed 2 (rows of the plan) | 1, 2 (spoken "Item 1") | The number keeps the order; nothing is gained by calling a flashcard deck a bed. |
| Patients (the plan’s count) | **Owner’s choice (15 Oct 2026: “3 to do”):** “3 to do · 22 min”; items and tasks were the other options | Counts what is in the plan: decks, pages, stations. “Items” clashes with exam usage: the NBME, which writes the USMLE, calls one question an “item” (its *Item-Writing Guide*, nbme.org/educators/item-writing-guide), and the app has a USMLE track (ExamTrack.swift:67), so “3 items · 22 min” can read as three questions. “3 tasks · 22 min” and “3 to do · 22 min” avoid that. The rows below write the owner’s “to do”. |
| No patients waiting | Nothing due | The ordinary revision phrase, and it matches the "Due" chip. |
| Ward round (the focus timer) | Focus session | In a medical app, "round" reads as a ward round. A session is the plain word for sitting down to study. |
| Round 1 of 4 (parts of the timer) | **Owner’s choice (15 Oct 2026: “make it block”):** Block (“Block 1 of 4”); Part and Stint were the other options | “Block” clashes three ways: USMLE Step 1 is “divided into seven 60-minute blocks” of up to 40 questions, or from 14 May 2026 fourteen 30-minute blocks of up to 20 (usmle.org/step-exams/step-1), so a 25-minute focus block is not an exam block; in the UK a placement block is weeks long; and on an ECG brand “block” also reads as heart block. “Part 1 of 4” is plain and clashes with nothing; “Stint” is plain but informal. Avoid “Step” too, which is the USMLE’s word and the app’s own “Step 1 of 8”. The rows below write the owner’s “block”. |
| Block 1, Block 2 (the mock exam’s timed parts) | **Owner’s choice (22 Oct 2026):** Part (“Part 1”; “Part 2 of 3” where a total shows) | owner 22 Oct: mock exam blocks become Part. “Block” is the focus timer’s word only, and “Symptom blocks” stays. The word is one constant per platform, `MockFormat.partWord` (ios/RedPen/Shared/Exam/MockPaper.swift, android/app/src/main/java/com/stethoscore/app/quiz/MockPaper.kt); the rows under “The mock exam” below build on it. The real exam’s own “blocks” in a paper’s note (ExamCatalog.swift:262) stay: they are the content. |
| Patient 7 of 20 (the question header) | Question 7 of 20 | The thing on screen is a question. The patient lives inside its stem, where the clinical words stay. |
| Next patient | Next question | Pairs with "Finish paper" and "See results", which are already exam words. |
| Patient chart (label over the stem) | Single best answer | The header already says "Question 7 of 20", so the label names the kind of question; the "Best answer" chip then shows only on a retest ("Second try"). |
| Vitals (the progress screen) | Progress | Not “Results”: that is already the name of the screen “See results” opens at the end of a paper (MCQSummaryView.swift:183). Vitals are a patient’s, not a student’s. |
| Needs a consult | Weak topics | The exam phrase for what to revise next; it also names the list on the boards. |
| Sinus · regular, irregular, resting | Steady, Patchy, Resting | "Study rhythm" stays as plain English, and the ECG stays as the brand’s picture; the jargon "Sinus" goes. |
| Ward pocket | Clinical reference | It holds three tabs, Lab values, Calculators and Scores, so the name covers all three; “Clinical scores” would give “Clinical scores › Scores” and a third meaning for “score”. |
| New admission (making a set) | (no label) | The screen is already titled “New set”, so the small-caps label goes. |
| Missed points, new patients (twins) | Missed points, asked again | Says what a twin is: the same point, asked again in a new stem. |
| Focus rounds (Health) | Follows the timer’s word | Each finished part is logged; English and Arabic follow the owner’s choice above. |
| Not on this ward yet (iPad build) | Not in this build yet | Says what is true: the iPad build leaves the feature out. |

## Inventory

Paths are relative to the repository root. **Test** names the Swift test that asserts the current text; those assertions change in the same commit as the string. Each row was checked against the source line.

### Home and today’s plan

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 1 | `ios/RedPen/Features/Library/WardHome.swift:422` | Today’s ward round ·  | Today’s revision ·  | The card’s small-caps header; the count follows (BedPlan.swift:373). **Built 22 Oct.** |  |
| 2 | `ios/RedPen/Features/Library/WardHome.swift:473` | Opens this bed | Opens this item | VoiceOver hint on each row. **Built 22 Oct.** |  |
| 3 | `ios/RedPen/Features/Library/WardHome.swift:485` | Starts with bed 1: … | Starts with item 1: … | VoiceOver hint on the start button. **Built 22 Oct.** |  |
| 4 | `ios/RedPen/Features/Library/WardHome.swift:489` | Start ward round | Start revision | The primary button. **Built 22 Oct.** |  |
| 5 | `ios/RedPen/Features/Library/WardHome.swift:585` | Opens Vitals | Opens Progress | VoiceOver hint on the progress tile. |  |
| 6 | `ios/RedPen/Features/Library/WardHome.swift:600` | Vitals | Progress | Spoken label of the progress tile. |  |
| 7 | `ios/RedPen/Features/Library/WardHome.swift:629` | Vitals | Progress | Title of the progress tile. |  |
| 8 | `ios/RedPen/Shared/Learn/BedPlan.swift:157` | Bed 1 · Cardiology | 1 · Cardiology | Row overline. The number keeps the order without the role-play. **Built 22 Oct.** | **BedPlanTests.swift:84** |
| 9 | `ios/RedPen/Shared/Learn/BedPlan.swift:161` | Bed 1, Cardiology. 12 cards due. … | Item 1, Cardiology. 12 cards due. … | Spoken row. **Built 22 Oct.** | **BedPlanTests.swift:107** |
| 10 | `ios/RedPen/Shared/Learn/BedPlan.swift:372` | No patients waiting | Nothing due | The summary when the plan is empty. **Built 22 Oct.** | **BedPlanTests.swift:100** |
| 11 | `ios/RedPen/Shared/Learn/BedPlan.swift:373` | 4 patients · 60 min; 1 patient · 8 min | 4 to do · 60 min; 1 to do · 8 min | The counted noun "patient" goes; the owner’s “to do” (15 Oct) takes no plural. **Built 22 Oct.** | **BedPlanTests.swift:98, :99** |
| 12 | `ios/RedPen/Shared/Learn/BedPlan.swift:379` | Today’s ward round: no patients waiting. | Today’s revision: nothing due. | Spoken summary, empty plan. **Built 22 Oct.** | **BedPlanTests.swift:104** |
| 13 | `ios/RedPen/Shared/Learn/BedPlan.swift:381` | Today’s ward round: 4 patients, about 60 minutes. | Today’s revision: 4 to do, about 60 minutes. | Spoken summary. **Built 22 Oct.** | **BedPlanTests.swift:102** |
| 14 | `ios/RedPen/Shared/Learn/BedPlan.swift:199` | Nothing needs a consult: every subject with 5 or more answers is at 75% or better. | No weak topics: every topic with 5 or more answers is at 75% or better. | Shown on Progress. "Topic" in place of "subject", so the sentence uses one word for one thing. **Built 22 Oct.** | **BedPlanTests.swift:223** |
| 15 | `ios/RedPen/Shared/Learn/BedPlan.swift:204` | Exam day: today’s ward round is your kit alone, so these can wait. | Exam day: today’s revision is your kit alone, so these can wait. | The test checks only the prefix "Exam day", so it passes either way. **Built 22 Oct.** | **BedPlanTests.swift:217 (prefix)** |
| 16 | `ios/RedPen/Shared/Learn/BedPlan.swift:206` | Renal, the weakest, is on today’s ward round automatically. | Renal, the weakest, is in today’s revision automatically. | **Built 22 Oct.** | **BedPlanTests.swift:220** |

### The question screen

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 17 | `ios/RedPen/Features/MCQ/ChartQuiz.swift:18` | Patient 7 of 20 | Question 7 of 20 | The header. A question is a question; the patient is inside its stem. | **ChartQuizTests.swift:18** |
| 18 | `ios/RedPen/Features/MCQ/ChartQuiz.swift:134` | Next patient (in a paper) | Next question | Beside "Finish paper" and "Skip for now", which stay. | **ChartQuizTests.swift:111** |
| 19 | `ios/RedPen/Features/MCQ/ChartQuiz.swift:137` | Next patient | Next question | Beside "See results", which stays. | **ChartQuizTests.swift:109** |
| 20 | `ios/RedPen/Features/MCQ/MCQQuizView.swift:606` | Patient chart | Single best answer | Small-caps label over the stem. The header already says "Question 7 of 20", so the label names the kind of question instead of repeating it. The "Best answer" chip beside it (line 607) would then repeat the label, so it shows only on a retest, as "Second try". The chip is tinted blue today (tone .blue); it should follow the chip rule in routes.md. The comments at ChartQuiz.swift:31 and MCQQuizView.swift:591 ("PATIENT CHART") change with it. | **ChartQuizTests.swift:31** |

### Progress (today “Vitals”) and weak topics

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 21 | `ios/RedPen/Features/Analytics/AnalyticsView.swift:104` | Vitals | Progress | Screen title. Not "Results": "See results" (ChartQuiz.swift:137) opens a paper’s own Results screen (MCQSummaryView.swift:183), so that name is taken. The UI test already falls back to "Progress" (DesignTourUITests.swift:292). | **DesignTourUITests.swift:291** |
| 22 | `ios/RedPen/Features/Support/SupportCenter.swift:54` | Vitals | Progress | Menu and help name of the same screen. | **DesignTourUITests.swift:291** |
| 23 | `ios/RedPen/Features/Analytics/VitalsParts.swift:199` | Needs a consult | Weak topics | Section header. |  |
| 24 | `ios/RedPen/Features/Library/LibraryCategory.swift:134` | Readiness, study rhythm and what needs a consult | Readiness, study rhythm and weak topics | Subtitle of the Progress entry. |  |
| 25 | `ios/RedPen/Features/Examples/ExamplesHubView.swift:128` | Vitals: rhythm, rings, what needs a consult, trends | Progress: rhythm, rings, weak topics, trends | Examples hub row. |  |
| 26 | `ios/RedPen/Features/Support/ReviewSettingsSection.swift:69` | … “How sure are you?” feeds Vitals. | … “How sure are you?” feeds Progress. | Settings footnote. |  |
| 27 | `ios/RedPen/Shared/Learn/RhythmReading.swift:53` | Sinus · regular | Steady | The rhythm reading of your study days. "Study rhythm" stays: plain English, and the ECG stays the brand’s picture. "Sinus" is ECG jargon used as a joke. | **BedPlanTests.swift:257** |
| 28 | `ios/RedPen/Shared/Learn/RhythmReading.swift:54` | Sinus · irregular | Patchy | As above. |  |
| 29 | `ios/RedPen/Shared/Learn/RhythmReading.swift:55` | Sinus · resting | Resting | As above. |  |
| 30 | `ios/RedPen/Shared/Learn/RhythmReading.swift:77` | Study rhythm, regular. … | Study rhythm, steady. … | The spoken word; :82 joins it into the sentence. | **BedPlanTests.swift:286** |
| 31 | `ios/RedPen/Shared/Learn/RhythmReading.swift:78` | Study rhythm, irregular. … | Study rhythm, patchy. … | As above. |  |

### The focus timer (today “ward round”)

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 32 | `ios/RedPen/Features/Learn/WardRoundView.swift:79` | Start a ward round | Start a focus session |  |  |
| 33 | `ios/RedPen/Features/Learn/WardRoundView.swift:82` | Four rounds of focus with a break between. Everything you study while the clock runs counts on the round, and its minutes count for your streak. | Four blocks of focus with a break between. Everything you study while the clock runs counts towards the session, and its minutes count for your streak. |  |  |
| 34 | `ios/RedPen/Features/Learn/WardRoundView.swift:99` | Start round 1 | Start block 1 |  |  |
| 35 | `ios/RedPen/Features/Learn/WardRoundView.swift:156` | Ward round: … | Focus session: … | VoiceOver label of the floating chip. |  |
| 36 | `ios/RedPen/Features/Learn/WardRoundView.swift:165` | Opens the ward round. Drag to move it to another corner. | Opens the focus session. Drag to move it to another corner. | VoiceOver hint. |  |
| 37 | `ios/RedPen/Features/Learn/WardRoundView.swift:174` | Round 2 ready | Block 2 ready |  |  |
| 38 | `ios/RedPen/Features/Learn/WardRoundView.swift:210` | Ward round | Focus session | Panel title. |  |
| 39 | `ios/RedPen/Features/Learn/WardRoundView.swift:222` | Fold the ward round away | Fold the focus session away | VoiceOver label. |  |
| 40 | `ios/RedPen/Features/Learn/WardRoundView.swift:271` | End round | End block |  |  |
| 41 | `ios/RedPen/Features/Learn/WardRoundView.swift:278` | Start round 2 now | Start block 2 now |  |  |
| 42 | `ios/RedPen/Features/Learn/WardRoundView.swift:281` | Start round 2 | Start block 2 |  |  |
| 43 | `ios/RedPen/Features/Learn/WardRoundView.swift:296` | Stop the ward round | Stop the focus session |  |  |
| 44 | `ios/RedPen/Shared/StudySession.swift:224` | Round 1 of 4 | Block 1 of 4 | Used in the caption, the status line and the alarm title "Round 1 of 4 done". | **WardRoundTests.swift:41, :124** |
| 45 | `ios/RedPen/Shared/StudySession.swift:238` | Round 2 of 4 when you’re ready · … | Block 2 of 4 when you’re ready · … | The test checks the prefix "Round 2 of 4 when you". | **WardRoundTests.swift:56** |
| 46 | `ios/RedPen/Shared/StudySession.swift:240` | Ward round done · 85 min · 3 cards | Focus session done · 85 min · 3 cards |  | **WardRoundTests.swift:93** |
| 47 | `ios/RedPen/Shared/StudySession.swift:262` | 4 rounds sat. Well done. | 4 blocks sat. Well done. | "Sat" is already exam English. |  |
| 48 | `ios/RedPen/Shared/StudySession.swift:263` | Ward round done | Focus session done | Alarm title. | **WardRoundTests.swift:126** |
| 49 | `ios/RedPen/Shared/StudySession.swift:269` | Round 2 of 4 is ready when you are. | Block 2 of 4 is ready when you are. | Alarm body. |  |
| 50 | `ios/RedPen/Shared/StudySession.swift:272` | Round 2 of 4 is ready when you are. | Block 2 of 4 is ready when you are. | Alarm body. |  |
| 51 | `ios/RedPen/Shared/Learn/WardRoundClock.swift:191` | Round 1 of 4 done — take 5 minutes | Block 1 of 4 done — take 5 minutes | Follows StudySession.swift:224. |  |
| 52 | `ios/RedPen/Shared/Learn/WardRoundClock.swift:192` | Break over — round 2 when you’re ready | Break over — block 2 when you’re ready |  |  |
| 53 | `ios/RedPen/Shared/Learn/WardRoundClock.swift:193` | Ward round done — 85 minutes | Focus session done — 85 minutes |  |  |
| 54 | `ios/RedPen/Features/Learn/ExamPlanView.swift:33` | … Minutes on a ward round count for the streak too. … | … Minutes in a focus session count for the streak too. … |  |  |
| 55 | `ios/RedPen/Shared/Platform/StudyFocusFilter.swift:18` | … only study reminders from Stethoscore come through: the ward round, due cards and the daily questions. | … only study reminders from Stethoscore come through: your focus session, due cards and the daily questions. | iOS Focus filter description. |  |
| 56 | `ios/RedPen/Features/Support/PlatformSettingsSection.swift:73` | Log focus rounds to Health | Log focus blocks to Health | Each finished block is logged, so "blocks". |  |
| 57 | `ios/RedPen/Features/Support/PlatformSettingsSection.swift:109` | Finished focus rounds are saved as mindful minutes. Nothing is read from Health. | Finished focus blocks are saved as mindful minutes. Nothing is read from Health. |  |  |
| 58 | `ios/StethoscoreWidgets/WardRoundLiveActivity.swift:30` | 3 cards this ward round | 3 cards this session | Live Activity (outside ios/RedPen). |  |
| 59 | `ios/StethoscoreWidgets/WardRoundLiveActivity.swift:55` | Round 2 of 4 next | Block 2 of 4 next | Live Activity. |  |
| 60 | `ios/StethoscoreWidgets/WardRoundLiveActivity.swift:56` | Ward round done | Focus session done | Live Activity. |  |
| 61 | `ios/StethoscoreWidgets/WardRoundLiveActivity.swift:57` | Round 1 of 4 | Block 1 of 4 | Live Activity. |  |
| 62 | `ios/project.yml:232` | Stethoscore saves your finished focus rounds as mindful minutes in Health, if you turn this on. | Stethoscore saves your finished focus blocks as mindful minutes in Health, if you turn this on. | Health permission text (Info.plist via project.yml). |  |
| 63 | `ios/AppResources/Localized/ar.lproj/InfoPlist.strings:9` | جولات التركيز (“focus rounds”), in the Arabic Health permission text | The owner’s chosen word in Arabic (for “focus sessions”, جلسات التركيز) | The Arabic twin of the row above; it follows whatever word the owner picks for the timer. |  |

### Onboarding, making a set, and the clinical reference

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 64 | `ios/RedPen/Features/Onboarding/FirstRunView.swift:89` | Today’s ward round counts down to it and paces your reviews to be ready on the day. | Today’s revision counts down to it and paces your reviews so you are ready on the day. | **Built 22 Oct.** |  |
| 65 | `ios/RedPen/Features/Onboarding/FirstRunView.swift:114` | Cards and questions a day. Today’s ward round shows how far through today you are. | Cards and questions a day. Today’s revision shows how far through today you are. | **Built 22 Oct.** |  |
| 66 | `ios/RedPen/Features/Library/NewSetView.swift:296` | New admission | (no label) | Small caps over "What do you want to make?". The screen is already titled "New set" (NewSetView.swift:185), so the label goes rather than repeat it. |  |
| 67 | `ios/RedPen/Features/Library/StudyCategory.swift:286` | Missed points, new patients | Missed points, asked again | Twins: a missed point asked again in a new stem. The longer explanation keeps "a different patient" (content). |  |
| 68 | `ios/RedPen/Features/Exam/WardPocketView.swift:61` | Ward pocket | Clinical reference | The reference holds three tabs, Lab values, Calculators and Scores (WardPocketView.swift:19-21), so the name covers all three and leaves "score" to the tab and to your own score. |  |
| 69 | `ios/RedPen/Features/Exam/WardPocketView.swift:223` | Ward pocket: … | Clinical reference: … | The default name of a new MCQ set made from a reference page (NewSetPreset.init(wardPocket:notes:)). |  |
| 70 | `ios/RedPen/Features/Learn/ExamPlanView.swift:71` | Ward pocket | Clinical reference | Row in the exam plan. |  |
| 71 | `ios/RedPen/Shared/Theme.swift:900` | Ward pocket | Clinical reference | Menu item. |  |

### The mock exam (owner, 22 Oct: blocks become Part)

Each row reads `MockFormat.partWord`; the Android twins are in brackets, under `android/app/src/main/java/com/stethoscore/app/`.

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 78 | `ios/RedPen/Shared/Exam/MockPaper.swift:64` | Block 1 | Part 1 | The USMLE track’s sections; the sitting’s “Part 2 of 3” (MockSittingView.swift:213) follows. (quiz/MockPaper.kt:58) **Built 22 Oct.** |  |
| 79 | `ios/RedPen/Shared/Exam/MockPaper.swift:66` | Step 1-style blocks: … | Step 1-style parts: … | The paper’s note. (quiz/MockPaper.kt:59) **Built 22 Oct.** |  |
| 80 | `ios/RedPen/Shared/Exam/MockPaper.swift:67` | USMLE-style, 2 blocks | USMLE-style, 2 parts | The paper’s title. (quiz/MockPaper.kt:60) **Built 22 Oct.** |  |
| 81 | `ios/RedPen/Shared/Exam/ExamCatalog.swift:228` | Block 1 (Step 1, Step 2 CK) | Part 1 | A chosen exam’s sections; its title “Step 1, 2 parts” (ExamFormats.swift:19) and the exam-day kit’s “Step 1 part 1” follow. (exam/ExamCatalog.kt:212, exam/ExamFormats.kt:30) **Built 22 Oct.** |  |
| 82 | `ios/RedPen/Shared/Exam/ExamCatalog.swift:306` | FIP block 1, ACM block 1 | FIP part 1, ACM part 1 | Step 3’s two days. (exam/ExamCatalog.kt:289) **Built 22 Oct.** | **ExamCatalogTests.swift:241** |
| 83 | `ios/RedPen/Features/Mock/MockPaperView.swift:141, :147` | 2 blocks of 40 | 2 parts of 40 | The stepper. (ui/mock/MockPaperScreen.kt:347; its buttons “Fewer parts”, “More parts” at :349, :351) **Built 22 Oct.** |  |

### The iPad build: Swift Playgrounds stand-ins (tools/playgrounds_stubs)

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 72 | `tools/playgrounds_stubs/core/CoreLibrary.swift:46` | No patients yet | No sets yet | The iPad build’s home, empty. A set is what is listed here. |  |
| 73 | `tools/playgrounds_stubs/core/CoreLibrary.swift:47` | Make a set from a lecture and it is admitted here. | Make a set from a lecture and it appears here. |  |  |
| 74 | `tools/playgrounds_stubs/core/CoreLibrary.swift:140` | Bed 1 | 1 | Row overline, as BedPlan.swift:157. |  |
| 75 | `tools/playgrounds_stubs/core/CoreLibrary.swift:152` | Today’s ward round | Today’s revision | Section label, as WardHome.swift:422. |  |
| 76 | `tools/playgrounds_stubs/_common.swift:14` | Not on this ward yet | Not in this build yet | What stands in for a feature the iPad build leaves out. |  |
| 77 | `tools/playgrounds_stubs/core/CoreStandIns.swift:321` | The ward pocket | The clinical reference | Stand-in for the reference, in the build that leaves it out. |  |

## Strings the tests assert on

Change these with their tests in one commit. The test files are in `ios/RedPen/Tests/` except the UI test.

| Test | Asserts today | Becomes | Source |
|---|---|---|---|
| BedPlanTests.swift:84 | Bed 1 · Cardiology | 1 · Cardiology | `ios/RedPen/Shared/Learn/BedPlan.swift:157` |
| BedPlanTests.swift:107 | Bed 1, Cardiology. 12 cards due. … | Item 1, Cardiology. 12 cards due. … | `ios/RedPen/Shared/Learn/BedPlan.swift:161` |
| BedPlanTests.swift:100 | No patients waiting | Nothing due | `ios/RedPen/Shared/Learn/BedPlan.swift:372` |
| BedPlanTests.swift:98, :99 | 4 patients · 60 min; 1 patient · 8 min | 4 to do · 60 min; 1 to do · 8 min | `ios/RedPen/Shared/Learn/BedPlan.swift:373` |
| BedPlanTests.swift:104 | Today’s ward round: no patients waiting. | Today’s revision: nothing due. | `ios/RedPen/Shared/Learn/BedPlan.swift:379` |
| BedPlanTests.swift:102 | Today’s ward round: 4 patients, about 60 minutes. | Today’s revision: 4 to do, about 60 minutes. | `ios/RedPen/Shared/Learn/BedPlan.swift:381` |
| BedPlanTests.swift:223 | Nothing needs a consult: every subject with 5 or more answers is at 75% or better. | No weak topics: every topic with 5 or more answers is at 75% or better. | `ios/RedPen/Shared/Learn/BedPlan.swift:199` |
| BedPlanTests.swift:217 (prefix) | Exam day: today’s ward round is your kit alone, so these can wait. | Exam day: today’s revision is your kit alone, so these can wait. | `ios/RedPen/Shared/Learn/BedPlan.swift:204` |
| BedPlanTests.swift:220 | Renal, the weakest, is on today’s ward round automatically. | Renal, the weakest, is in today’s revision automatically. | `ios/RedPen/Shared/Learn/BedPlan.swift:206` |
| ChartQuizTests.swift:18 | Patient 7 of 20 | Question 7 of 20 | `ios/RedPen/Features/MCQ/ChartQuiz.swift:18` |
| ChartQuizTests.swift:111 | Next patient (in a paper) | Next question | `ios/RedPen/Features/MCQ/ChartQuiz.swift:134` |
| ChartQuizTests.swift:109 | Next patient | Next question | `ios/RedPen/Features/MCQ/ChartQuiz.swift:137` |
| ChartQuizTests.swift:31 | The chip: kindChip(retest: false) == "Best answer", kindChip(retest: true) == "Second try" (ChartQuiz.swift:32) | No chip on a first try; "Second try" on a retest | `ios/RedPen/Features/MCQ/MCQQuizView.swift:606` |
| DesignTourUITests.swift:291 | Vitals | Progress | `ios/RedPen/Features/Analytics/AnalyticsView.swift:104` |
| DesignTourUITests.swift:291 | Vitals | Progress | `ios/RedPen/Features/Support/SupportCenter.swift:54` |
| BedPlanTests.swift:257 | Sinus · regular | Steady | `ios/RedPen/Shared/Learn/RhythmReading.swift:53` |
| BedPlanTests.swift:286 | Study rhythm, regular. … | Study rhythm, steady. … | `ios/RedPen/Shared/Learn/RhythmReading.swift:77` |
| WardRoundTests.swift:41, :124 | Round 1 of 4 | Block 1 of 4 | `ios/RedPen/Shared/StudySession.swift:224` |
| WardRoundTests.swift:56 | Round 2 of 4 when you’re ready · … | Block 2 of 4 when you’re ready · … | `ios/RedPen/Shared/StudySession.swift:238` |
| WardRoundTests.swift:93 | Ward round done · 85 min · 3 cards | Focus session done · 85 min · 3 cards | `ios/RedPen/Shared/StudySession.swift:240` |
| WardRoundTests.swift:126 | Ward round done | Focus session done | `ios/RedPen/Shared/StudySession.swift:263` |
| ExamCatalogTests.swift:241 (Android ExamCatalogTest.kt:213) | the Step 3 paper’s title holds “fip block” | holds “fip part” | `ios/RedPen/Shared/Exam/ExamCatalog.swift:306` |

Also: `ios/UITests/DesignTourUITests.swift:291` opens `menuItem("Vitals")` and falls back to "Progress" at :292; it becomes `menuItem("Progress")`. `ChartQuizTests.swift:31` asserts the chip words "Best answer" and "Second try"; under row 20 the chip shows only on a retest, so the first half of that check changes. The opening comments of `BedPlanTests.swift`, `ChartQuizTests.swift` and `WardRoundTests.swift` describe the old metaphor; reword them with the strings.

## Ward words that stay, because they are the content

| File:line | Text | Why it stays |
|---|---|---|
| `ios/RedPen/Features/Cases/CaseWardView.swift:185` | Your shift | A case puts you on a shift with a patient; the ward is the content there. |
| `ios/RedPen/Features/Cases/CaseWardView.swift:149` | Clerking note | The case’s own document. |
| `ios/RedPen/Features/Cases/CaseWardView.swift:295` | See the patient | An action inside the case. |
| `ios/RedPen/Shared/Cases/CaseFile.swift:29` | Ward | A case’s setting, beside Emergency, Clinic and Community. |
| `ios/RedPen/Features/Cases/CaseKit.swift:131` | Discharged · 72 | How a case ends; the score is the case’s mark. |
| `ios/RedPen/Features/Cases/CaseListView.swift:124` | Discharged, score 72 out of 100 | Spoken form of the same. |
| `ios/RedPen/Features/Library/StudyCategory.swift:68` | Your patients | The cases list: these are patients. |
| `ios/RedPen/Features/Library/StudyCategory.swift:79` | No patients yet. | The cases list, empty. |
| `ios/RedPen/Features/Library/StudyCategory.swift:239` | Patient cases | The cases section. |
| `ios/RedPen/Features/Library/NewSetView.swift:525` | Patient cases | Making a case set. |
| `ios/RedPen/Features/Library/NewSetView.swift:536` | Patients to work up against the clock | Making a case set. |
| `ios/RedPen/Features/Library/StudyCategory.swift:262` | Talking patient | The OSCE’s spoken patient. |
| `ios/RedPen/Features/MCQ/MCQQuizView.swift:867` | A new question on the same point, in a different patient, … | Twins: the stem’s patient is content. |
| `ios/RedPen/Shared/WardPocket.swift:18` | For learning only — not for patient care | Safety notice about real patients. |
| `ios/RedPen/Shared/WardPocket.swift:21` | … never use it to make decisions about a real patient. | Safety notice. |
| `ios/RedPen/Features/Account/RecordingTermsView.swift:39` | No patient information. Ever. | Safety notice about recordings. |
| `ios/RedPen/Shared/WardPocketScores.swift:551` | urgent ward-based review by a clinician | A clinical score’s own wording (NEWS2). |
| `ios/RedPen/Features/MCQ/ChartQuiz.swift:134` | Finish paper · Skip for now | Already exam words. |
| `ios/RedPen/Features/MCQ/ChartQuiz.swift:137` | See results | Already exam words. |
| `ios/RedPen/Shared/Learn/RhythmReading.swift:69` | Study on a few days and your rhythm shows here. | Plain English; no ward. |
| `ios/RedPen/Features/Analytics/VitalsParts.swift:27` | Study rhythm · … | Plain English; only the reading after it changes. |
| `ios/RedPen/Shared/Learn/RhythmReading.swift:79` | Study rhythm, resting. … | Already plain English. |
| `ios/RedPen/Features/Cases/CaseDebriefView.swift:61` | Discharge summary | The case’s own document. |
| `ios/RedPen/Features/Cases/CaseDecisionView.swift:56` | Discharge and debrief | How a case ends. |
| `ios/RedPen/Features/Cases/CaseWardView.swift:161` | Clerking note | The case’s own document, as at :149. |
| `ios/RedPen/Shared/Exam/ExamCatalog.swift:262, :285, :308` | … seven 60-minute blocks of up to 40 … | The real exam’s own word for its parts (usmle.org), in the note on how the real exam runs. |
| `ios/RedPen/Shared/Learn/ExamWeekPlanner.swift:230` | USMLE block | The exam-day kit names the real exam’s block it paces, with no exam chosen (Android data/BedPlan.kt:191). |

## Names in code, not on screen

Type and file names (`WardHome`, `BedPlan`, `WardRoundView`, `WardRoundClock`, `WardPocket`, `ChartQuiz`, `RhythmReading`) and accessibility identifiers (`wardBed-<n>`, `wardRound*`, `wardPocketTabs`, `homeVitals`) are not user-facing. They can stay through the wording change; renaming them is a separate refactor that would also touch the UI tests.
