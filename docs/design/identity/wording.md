# Wording: from the ward to the exam

> **Reading note.** On 15 Oct the owner asked for wording that fits "an example" more than a hospital ward. We read "an example" as **"an exam"**: Stethoscore prepares students for exams, and the rest of the request is about exam language. If another reading was meant, this inventory still lists every ward-metaphor string in the app.

Written 15 Oct 2026 against `personal` at bc611221. Every file:line below was checked against that commit when this file was written; line numbers move as code changes, so search for the quoted text. No app code changes in this phase; this is the list a later phase applies.

## The rule

- **The exam is the setting; medicine is the content.** Ward words go wherever they dress up the app’s own furniture: the daily plan, the progress screen, the timer, the question screen. They stay wherever they *are* the content: a case’s patient, the OSCE’s talking patient, a clinical score’s own wording, and every safety notice about real patients.
- **Exam vocabulary, plain and warm:** paper, question, station, mark scheme, score, mock, revision, topic, weak topics, results, pass mark, SBA, viva. No role-play and no jargon jokes.
- **One word per thing.** The daily plan is *Today’s revision*. The timer is a *focus session* made of *blocks*. The progress screen is *Results*. What to revise next is *weak topics*.
- **The words already right stay:** Best answer, Timed, Reveal, Step 1 of 8, Finish paper, See results, Spaced review, Due, New, "on track for a pass", "below the pass mark for now", streak.

## Glossary

| Ward term | Exam term | Why |
|---|---|---|
| Today’s ward round (the daily plan) | Today’s revision | It is a revision plan, and "revision" is the word students use for exam preparation. "Start revision" reads as what it does. |
| Bed 1, Bed 2 (rows of the plan) | 1, 2 (spoken "Item 1") | The number keeps the order; nothing is gained by calling a flashcard deck a bed. |
| Patients (the plan’s count) | Items | "3 items · 22 min" counts what is in the plan: decks, pages, stations. |
| No patients waiting | Nothing due | The ordinary revision phrase, and it matches the "Due" chip. |
| Ward round (the focus timer) | Focus session | In a medical app, "round" reads as a ward round. A session is the plain word for sitting down to study. |
| Round 1 of 4 (parts of the timer) | Block 1 of 4 | "Block" is the question-bank and exam word for a timed run of work; "4 blocks sat" keeps the exam’s "sat". |
| Patient 7 of 20 (the question header) | Question 7 of 20 | The thing on screen is a question. The patient lives inside its stem, where the clinical words stay. |
| Next patient | Next question | Pairs with "Finish paper" and "See results", which are already exam words. |
| Patient chart (label over the stem) | Question | With the "Best answer" (SBA) chip beside it, the label says what kind of question it is. |
| Vitals (the progress screen) | Results | An exam ends in results, and "See results" already leads there. Vitals are a patient’s, not a student’s. |
| Needs a consult | Weak topics | The exam phrase for what to revise next; it also names the list on the boards. |
| Sinus · regular, irregular, resting | Steady, Patchy, Resting | "Study rhythm" stays as plain English, and the ECG stays as the brand’s picture; the jargon "Sinus" goes. |
| Ward pocket | Clinical scores | Says what is inside (CURB-65, Wells, NEWS2 and the rest), which is exam content. |
| New admission (making a set) | New set | You are making a set of questions or cards, which the button already calls a New set. |
| Missed points, new patients (twins) | Missed points, asked again | Says what a twin is: the same point, asked again in a new stem. |
| Focus rounds (Health) | Focus blocks | Follows the timer’s new words; each finished block is logged. |

## Inventory

Paths are relative to the repository root. **Test** names the Swift test that asserts the current text; those assertions change in the same commit as the string. Each row was checked against the source line.

### Home and today’s plan

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 1 | `ios/RedPen/Features/Library/WardHome.swift:422` | Today’s ward round ·  | Today’s revision ·  | The card’s small-caps header; the count follows (BedPlan.swift:373). |  |
| 2 | `ios/RedPen/Features/Library/WardHome.swift:473` | Opens this bed | Opens this item | VoiceOver hint on each row. |  |
| 3 | `ios/RedPen/Features/Library/WardHome.swift:485` | Starts with bed 1: … | Starts with item 1: … | VoiceOver hint on the start button. |  |
| 4 | `ios/RedPen/Features/Library/WardHome.swift:489` | Start ward round | Start revision | The primary button. |  |
| 5 | `ios/RedPen/Features/Library/WardHome.swift:585` | Opens Vitals | Opens Results | VoiceOver hint on the progress tile. |  |
| 6 | `ios/RedPen/Features/Library/WardHome.swift:600` | Vitals | Results | Spoken label of the progress tile. |  |
| 7 | `ios/RedPen/Features/Library/WardHome.swift:629` | Vitals | Results | Title of the progress tile. |  |
| 8 | `ios/RedPen/Shared/Learn/BedPlan.swift:157` | Bed 1 · Cardiology | 1 · Cardiology | Row overline. The number keeps the order without the role-play. | **BedPlanTests.swift:84** |
| 9 | `ios/RedPen/Shared/Learn/BedPlan.swift:161` | Bed 1, Cardiology. 12 cards due. … | Item 1, Cardiology. 12 cards due. … | Spoken row. | **BedPlanTests.swift:107** |
| 10 | `ios/RedPen/Shared/Learn/BedPlan.swift:372` | No patients waiting | Nothing due | The summary when the plan is empty. | **BedPlanTests.swift:100** |
| 11 | `ios/RedPen/Shared/Learn/BedPlan.swift:373` | 4 patients · 60 min; 1 patient · 8 min | 4 items · 60 min; 1 item · 8 min | The counted noun is "patient"; it becomes "item". | **BedPlanTests.swift:98, :99** |
| 12 | `ios/RedPen/Shared/Learn/BedPlan.swift:379` | Today’s ward round: no patients waiting. | Today’s revision: nothing due. | Spoken summary, empty plan. | **BedPlanTests.swift:104** |
| 13 | `ios/RedPen/Shared/Learn/BedPlan.swift:381` | Today’s ward round: 4 patients, about 60 minutes. | Today’s revision: 4 items, about 60 minutes. | Spoken summary. | **BedPlanTests.swift:102** |
| 14 | `ios/RedPen/Shared/Learn/BedPlan.swift:199` | Nothing needs a consult: every subject with 5 or more answers is at 75% or better. | No weak topics: every subject with 5 or more answers is at 75% or better. | Shown on Results. | **BedPlanTests.swift:223** |
| 15 | `ios/RedPen/Shared/Learn/BedPlan.swift:204` | Exam day: today’s ward round is your kit alone, so these can wait. | Exam day: today’s revision is your kit alone, so these can wait. | The test checks only the prefix "Exam day", so it passes either way. | **BedPlanTests.swift:217 (prefix)** |
| 16 | `ios/RedPen/Shared/Learn/BedPlan.swift:206` | Renal, the weakest, is on today’s ward round automatically. | Renal, the weakest, is in today’s revision automatically. |  | **BedPlanTests.swift:220** |

### The question screen

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 17 | `ios/RedPen/Features/MCQ/ChartQuiz.swift:18` | Patient 7 of 20 | Question 7 of 20 | The header. A question is a question; the patient is inside its stem. | **ChartQuizTests.swift:18** |
| 18 | `ios/RedPen/Features/MCQ/ChartQuiz.swift:134` | Next patient (in a paper) | Next question | Beside "Finish paper" and "Skip for now", which stay. | **ChartQuizTests.swift:111** |
| 19 | `ios/RedPen/Features/MCQ/ChartQuiz.swift:137` | Next patient | Next question | Beside "See results", which stays. | **ChartQuizTests.swift:109** |
| 20 | `ios/RedPen/Features/MCQ/MCQQuizView.swift:606` | Patient chart | Question | Small-caps label over the stem, beside the "Best answer" chip (an SBA). Its chip is tinted blue today (tone .blue); it should follow the mode hue. |  |

### Results (today “Vitals”) and weak topics

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 21 | `ios/RedPen/Features/Analytics/AnalyticsView.swift:104` | Vitals | Results | Screen title. "See results" already ends a paper (ChartQuiz.swift:137). | **DesignTourUITests.swift:291** |
| 22 | `ios/RedPen/Features/Support/SupportCenter.swift:54` | Vitals | Results | Menu and help name of the same screen. | **DesignTourUITests.swift:291** |
| 23 | `ios/RedPen/Features/Analytics/VitalsParts.swift:199` | Needs a consult | Weak topics | Section header. |  |
| 24 | `ios/RedPen/Features/Library/LibraryCategory.swift:134` | Readiness, study rhythm and what needs a consult | Readiness, study rhythm and weak topics | Subtitle of the Results entry. |  |
| 25 | `ios/RedPen/Features/Examples/ExamplesHubView.swift:128` | Vitals: rhythm, rings, what needs a consult, trends | Results: rhythm, rings, weak topics, trends | Examples hub row. |  |
| 26 | `ios/RedPen/Features/Support/ReviewSettingsSection.swift:69` | … “How sure are you?” feeds Vitals. | … “How sure are you?” feeds Results. | Settings footnote. |  |
| 27 | `ios/RedPen/Shared/Learn/RhythmReading.swift:53` | Sinus · regular | Steady | The rhythm reading of your study days. "Study rhythm" stays: plain English, and the ECG stays the brand’s picture. "Sinus" is ECG jargon used as a joke. | **BedPlanTests.swift:257** |
| 28 | `ios/RedPen/Shared/Learn/RhythmReading.swift:54` | Sinus · irregular | Patchy | As above. |  |
| 29 | `ios/RedPen/Shared/Learn/RhythmReading.swift:55` | Sinus · resting | Resting | As above. |  |
| 30 | `ios/RedPen/Shared/Learn/RhythmReading.swift:82` | Study rhythm, regular. … | Study rhythm, steady. … | Spoken; follows the word above. | **BedPlanTests.swift:286** |

### The focus timer (today “ward round”)

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 31 | `ios/RedPen/Features/Learn/WardRoundView.swift:79` | Start a ward round | Start a focus session |  |  |
| 32 | `ios/RedPen/Features/Learn/WardRoundView.swift:82` | Four rounds of focus with a break between. Everything you study while the clock runs counts on the round, and its minutes count for your streak. | Four blocks of focus with a break between. Everything you study while the clock runs counts towards the session, and its minutes count for your streak. |  |  |
| 33 | `ios/RedPen/Features/Learn/WardRoundView.swift:99` | Start round 1 | Start block 1 |  |  |
| 34 | `ios/RedPen/Features/Learn/WardRoundView.swift:156` | Ward round: … | Focus session: … | VoiceOver label of the floating chip. |  |
| 35 | `ios/RedPen/Features/Learn/WardRoundView.swift:165` | Opens the ward round. Drag to move it to another corner. | Opens the focus session. Drag to move it to another corner. | VoiceOver hint. |  |
| 36 | `ios/RedPen/Features/Learn/WardRoundView.swift:174` | Round 2 ready | Block 2 ready |  |  |
| 37 | `ios/RedPen/Features/Learn/WardRoundView.swift:210` | Ward round | Focus session | Panel title. |  |
| 38 | `ios/RedPen/Features/Learn/WardRoundView.swift:222` | Fold the ward round away | Fold the focus session away | VoiceOver label. |  |
| 39 | `ios/RedPen/Features/Learn/WardRoundView.swift:271` | End round | End block |  |  |
| 40 | `ios/RedPen/Features/Learn/WardRoundView.swift:278` | Start round 2 now | Start block 2 now |  |  |
| 41 | `ios/RedPen/Features/Learn/WardRoundView.swift:281` | Start round 2 | Start block 2 |  |  |
| 42 | `ios/RedPen/Features/Learn/WardRoundView.swift:296` | Stop the ward round | Stop the focus session |  |  |
| 43 | `ios/RedPen/Shared/StudySession.swift:224` | Round 1 of 4 | Block 1 of 4 | Used in the caption, the status line and the alarm title "Round 1 of 4 done". | **WardRoundTests.swift:41, :124** |
| 44 | `ios/RedPen/Shared/StudySession.swift:238` | Round 2 of 4 when you’re ready · … | Block 2 of 4 when you’re ready · … | The test checks the prefix "Round 2 of 4 when you". | **WardRoundTests.swift:56** |
| 45 | `ios/RedPen/Shared/StudySession.swift:240` | Ward round done · 85 min · 3 cards | Focus session done · 85 min · 3 cards |  | **WardRoundTests.swift:93** |
| 46 | `ios/RedPen/Shared/StudySession.swift:262` | 4 rounds sat. Well done. | 4 blocks sat. Well done. | "Sat" is already exam English. |  |
| 47 | `ios/RedPen/Shared/StudySession.swift:263` | Ward round done | Focus session done | Alarm title. | **WardRoundTests.swift:126** |
| 48 | `ios/RedPen/Shared/StudySession.swift:269` | Round 2 of 4 is ready when you are. | Block 2 of 4 is ready when you are. | Alarm body. |  |
| 49 | `ios/RedPen/Shared/StudySession.swift:272` | Round 2 of 4 is ready when you are. | Block 2 of 4 is ready when you are. | Alarm body. |  |
| 50 | `ios/RedPen/Shared/Learn/WardRoundClock.swift:191` | Round 1 of 4 done — take 5 minutes | Block 1 of 4 done — take 5 minutes | Follows StudySession.swift:224. |  |
| 51 | `ios/RedPen/Shared/Learn/WardRoundClock.swift:192` | Break over — round 2 when you’re ready | Break over — block 2 when you’re ready |  |  |
| 52 | `ios/RedPen/Shared/Learn/WardRoundClock.swift:193` | Ward round done — 85 minutes | Focus session done — 85 minutes |  |  |
| 53 | `ios/RedPen/Features/Learn/ExamPlanView.swift:33` | … Minutes on a ward round count for the streak too. … | … Minutes in a focus session count for the streak too. … |  |  |
| 54 | `ios/RedPen/Shared/Platform/StudyFocusFilter.swift:18` | … only study reminders from Stethoscore come through: the ward round, due cards and the daily questions. | … only study reminders from Stethoscore come through: your focus session, due cards and the daily questions. | iOS Focus filter description. |  |
| 55 | `ios/RedPen/Features/Support/PlatformSettingsSection.swift:73` | Log focus rounds to Health | Log focus blocks to Health | Each finished block is logged, so "blocks". |  |
| 56 | `ios/RedPen/Features/Support/PlatformSettingsSection.swift:109` | Finished focus rounds are saved as mindful minutes. Nothing is read from Health. | Finished focus blocks are saved as mindful minutes. Nothing is read from Health. |  |  |
| 57 | `ios/StethoscoreWidgets/WardRoundLiveActivity.swift:30` | 3 cards this ward round | 3 cards this session | Live Activity (outside ios/RedPen). |  |
| 58 | `ios/StethoscoreWidgets/WardRoundLiveActivity.swift:55` | Round 2 of 4 next | Block 2 of 4 next | Live Activity. |  |
| 59 | `ios/StethoscoreWidgets/WardRoundLiveActivity.swift:56` | Ward round done | Focus session done | Live Activity. |  |
| 60 | `ios/StethoscoreWidgets/WardRoundLiveActivity.swift:57` | Round 1 of 4 | Block 1 of 4 | Live Activity. |  |
| 61 | `ios/project.yml:232` | Stethoscore saves your finished focus rounds as mindful minutes in Health, if you turn this on. | Stethoscore saves your finished focus blocks as mindful minutes in Health, if you turn this on. | Health permission text (Info.plist via project.yml). |  |

### Onboarding, making a set, and the clinical scores

| # | File:line | Current | Proposed | Note | Test |
|---|---|---|---|---|---|
| 62 | `ios/RedPen/Features/Onboarding/FirstRunView.swift:89` | Today’s ward round counts down to it and paces your reviews to be ready on the day. | Today’s revision counts down to it and paces your reviews so you are ready on the day. |  |  |
| 63 | `ios/RedPen/Features/Onboarding/FirstRunView.swift:114` | Cards and questions a day. Today’s ward round shows how far through today you are. | Cards and questions a day. Today’s revision shows how far through today you are. |  |  |
| 64 | `ios/RedPen/Features/Library/NewSetView.swift:296` | New admission | New set | Small caps over "What do you want to make?". You are making a set, not admitting anyone. |  |
| 65 | `ios/RedPen/Features/Library/StudyCategory.swift:286` | Missed points, new patients | Missed points, asked again | Twins: a missed point asked again in a new stem. The longer explanation keeps "a different patient" (content). |  |
| 66 | `ios/RedPen/Features/Exam/WardPocketView.swift:61` | Ward pocket | Clinical scores | The reference of CURB-65, Wells and the rest; what it holds is exam content. |  |
| 67 | `ios/RedPen/Features/Exam/WardPocketView.swift:223` | Ward pocket: … | Clinical scores: … | Spoken name of each score page. |  |
| 68 | `ios/RedPen/Features/Learn/ExamPlanView.swift:71` | Ward pocket | Clinical scores | Row in the exam plan. |  |
| 69 | `ios/RedPen/Shared/Theme.swift:900` | Ward pocket | Clinical scores | Menu item. |  |

## Strings the tests assert on

Change these with their tests in one commit. The test files are in `ios/RedPen/Tests/` except the UI test.

| Test | Asserts today | Becomes | Source |
|---|---|---|---|
| BedPlanTests.swift:84 | Bed 1 · Cardiology | 1 · Cardiology | `ios/RedPen/Shared/Learn/BedPlan.swift:157` |
| BedPlanTests.swift:107 | Bed 1, Cardiology. 12 cards due. … | Item 1, Cardiology. 12 cards due. … | `ios/RedPen/Shared/Learn/BedPlan.swift:161` |
| BedPlanTests.swift:100 | No patients waiting | Nothing due | `ios/RedPen/Shared/Learn/BedPlan.swift:372` |
| BedPlanTests.swift:98, :99 | 4 patients · 60 min; 1 patient · 8 min | 4 items · 60 min; 1 item · 8 min | `ios/RedPen/Shared/Learn/BedPlan.swift:373` |
| BedPlanTests.swift:104 | Today’s ward round: no patients waiting. | Today’s revision: nothing due. | `ios/RedPen/Shared/Learn/BedPlan.swift:379` |
| BedPlanTests.swift:102 | Today’s ward round: 4 patients, about 60 minutes. | Today’s revision: 4 items, about 60 minutes. | `ios/RedPen/Shared/Learn/BedPlan.swift:381` |
| BedPlanTests.swift:223 | Nothing needs a consult: every subject with 5 or more answers is at 75% or better. | No weak topics: every subject with 5 or more answers is at 75% or better. | `ios/RedPen/Shared/Learn/BedPlan.swift:199` |
| BedPlanTests.swift:217 (prefix) | Exam day: today’s ward round is your kit alone, so these can wait. | Exam day: today’s revision is your kit alone, so these can wait. | `ios/RedPen/Shared/Learn/BedPlan.swift:204` |
| BedPlanTests.swift:220 | Renal, the weakest, is on today’s ward round automatically. | Renal, the weakest, is in today’s revision automatically. | `ios/RedPen/Shared/Learn/BedPlan.swift:206` |
| ChartQuizTests.swift:18 | Patient 7 of 20 | Question 7 of 20 | `ios/RedPen/Features/MCQ/ChartQuiz.swift:18` |
| ChartQuizTests.swift:111 | Next patient (in a paper) | Next question | `ios/RedPen/Features/MCQ/ChartQuiz.swift:134` |
| ChartQuizTests.swift:109 | Next patient | Next question | `ios/RedPen/Features/MCQ/ChartQuiz.swift:137` |
| DesignTourUITests.swift:291 | Vitals | Results | `ios/RedPen/Features/Analytics/AnalyticsView.swift:104` |
| DesignTourUITests.swift:291 | Vitals | Results | `ios/RedPen/Features/Support/SupportCenter.swift:54` |
| BedPlanTests.swift:257 | Sinus · regular | Steady | `ios/RedPen/Shared/Learn/RhythmReading.swift:53` |
| BedPlanTests.swift:286 | Study rhythm, regular. … | Study rhythm, steady. … | `ios/RedPen/Shared/Learn/RhythmReading.swift:82` |
| WardRoundTests.swift:41, :124 | Round 1 of 4 | Block 1 of 4 | `ios/RedPen/Shared/StudySession.swift:224` |
| WardRoundTests.swift:56 | Round 2 of 4 when you’re ready · … | Block 2 of 4 when you’re ready · … | `ios/RedPen/Shared/StudySession.swift:238` |
| WardRoundTests.swift:93 | Ward round done · 85 min · 3 cards | Focus session done · 85 min · 3 cards | `ios/RedPen/Shared/StudySession.swift:240` |
| WardRoundTests.swift:126 | Ward round done | Focus session done | `ios/RedPen/Shared/StudySession.swift:263` |

Also: `ios/UITests/DesignTourUITests.swift:291` opens `menuItem("Vitals")` and falls back to "Progress"; it becomes `menuItem("Results")`. The opening comments of `BedPlanTests.swift`, `ChartQuizTests.swift` and `WardRoundTests.swift` describe the old metaphor; reword them with the strings.

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

## Names in code, not on screen

Type and file names (`WardHome`, `BedPlan`, `WardRoundView`, `WardRoundClock`, `WardPocket`, `ChartQuiz`, `RhythmReading`) and accessibility identifiers (`wardBed-<n>`, `wardRound*`, `wardPocketTabs`, `homeVitals`) are not user-facing. They can stay through the wording change; renaming them is a separate refactor that would also touch the UI tests.
