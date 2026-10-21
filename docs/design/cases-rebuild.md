# Cases, rebuilt from scratch

The owner, 1 October 2026, 10:30 PM Cairo: "i want to rebuild cases from scratch as some features in
it actually belong to another person so they have copyrights".

The old Cases code is removed first, on its own branch: the Cases set kind, talk-to-the-patient, clue
cases, and every conversion, stub and mention. This file is the only starting point for the new one.

## Clean-room rules

Copyright covers code, text, prompts, artwork and detailed screen designs, not the general idea of
practising on patient cases. So the rebuild shares no expression with the old one:

- Whoever builds it works only from this spec, the rest of the app (the Ward kit, PatientChart,
  ChartQuiz, the generators, the verification layer, the card and Ideas-map APIs), Apple's
  documentation and the published methods under Sources.
- They do not read the removed files, their git history (`git log -p`, `git show` of older
  commits, older branches), or documents that describe the old Cases: docs/launch/*, the audit rows
  about Cases, QACardsView, CaseChatView or ClueCaseView, and the launch reels.
- New names throughout. None of QACard, QACardsView, CaseSimulator, CaseChatView, CaseVoiceBar,
  ClueCaseView or CaseVariety comes back. New prompts, new wording, new layout.
- Every commit body says "Cases rebuild (clean room)".
- The owner named the other person's feature (2 Oct): "the cases where you ask a question and the
  patient answers accordingly". So nothing here lets the student question the patient and get the
  patient's answer: no conversation, typed or spoken, and no history-question chips either. The
  history comes already written, as the clerking note on arrival.

## What a case is

A patient the student works up against the clock, from arrival to a decision, and then a debrief
that shows what mattered. It trains what exam MCQs cannot:
- choosing what to examine and test, and in what order, from a written history;
- noticing the finding that should change your mind;
- not missing what kills.
It follows the key-features approach (Page & Bordage) and illness scripts (Schmidt & Rikers).

## The screens, in the Ward Round language

1. **Case list (a Cases set).** One patient card per case:
   - initials avatar, age and sex, setting, and the complaint in a few words;
   - a state: New, Seen (a run in progress), or Discharged with the last score.
2. **Arrival.**
   - The clerking note: the history as a doctor wrote it on admission (presenting complaint,
     history of it, past history, drugs, social), read, not asked for.
   - A triage strip: chips for age, sex and setting, then the arrival vitals in the ChartQuiz vitals
     grid, flagged by AccuracyRules ranges.
   - The complaint in the patient's own words, in quotation marks.
   - A clock pill: the time budget for the case (for example "20 min").
3. **Work-up.** Two action groups (the history is already in the clerking note, never asked for):
   - **Examine**, **Test**.
   - Each action is a chip with its cost in minutes. Tapping one spends the minutes and adds its
     finding to a running clinical note under the triage strip, newest first, with test values in
     the ChartQuiz results table (H/L flags).
   - An action already taken is ticked and cannot be taken again.
   - Past the budget the clock turns Resus Red, but the student may carry on: the debrief counts it.
4. **The differential ladder.**
   - Up to three ranked working diagnoses, open at any time: a bottom sheet on iPhone, a sidebar on
     iPad.
   - Picked from the case's candidate list (its differentials plus distractors, shuffled) or typed
     (matched against the accepted names).
   - The ladder is saved after every action, so the debrief can show how it moved. Nothing nags the
     student to update it.
5. **Decision.** The leading diagnosis (the top of the ladder, confirmed), then the next step as a
   single best answer from four or five options (WardOptionRow), then an optional one-line reason.
6. **Debrief: a discharge summary.**
   - Missed red flags first, in Resus Red.
   - The diagnosis, right or wrong, with the findings that separate it from the runner-up.
   - The key findings found, out of all of them.
   - The turning point: the action after which the right diagnosis should have led, and when the
     student's ladder actually put it first (or that it never did).
   - Time used against the budget. Low-yield actions are listed, each with why it added little here.
   - Three teaching points with their source (the lecture and page).
   - **Make cards from what I missed:** one basic card per missed key finding or red flag, into the
     student's review.
   - **Add to the Ideas map.**
   - **Another patient like this:** a new case with the same diagnosis presented differently, or the
     runner-up's case.

## Score (out of 100, shown with its parts, never as a rank)

| part | points |
|---|---|
| Diagnosis right | 30 |
| Next step right | 20 |
| Key findings found | 25, in proportion |
| Red flags found | 15, in proportion |
| Time | 10: full within the budget with at most one low-yield action; 2 off per further low-yield action; 5 off over budget |

- Any missed must-not-miss red flag caps the total at 60.
- No XP, levels, ranks or leaderboards.

## The case file

```
CaseFile        id, title, specialty, setting (emergency | ward | clinic | community),
                patient (age, sex, a few words about them), complaint (their words), clerking (the written history),
                arrival [Obs], budgetMinutes, steps [CaseStep], diagnosis (name, accepted names),
                differentials [Differential], turningStep (a step id), nextStep (options, key, why),
                teaching [String] (three), source (lecture and pages), verification state
CaseStep        id, group (examine | test), label, finding, minutes,
                value (key | useful | low), redFlag, mustNotMiss, results [LabResult]
Differential    name, accepted names, supportedBy [step id], againstBy [step id]
CaseRun         case id, started, taken [(step id, at)], ladders [[name]] (one after each step),
                decision (diagnosis, next step, reason), finished, score parts
```

A new set kind `cases`, raw value "cases". The removed kind's "qa" sets are skipped when loading.

## Writing cases from the student's material

- **Input.** A lecture or chapter, as for the other modes, and a count.
- **Writers.** The same as question generation: Apple's on-device model with a @Generable schema for
  the case file, Gemma when Apple's model is unavailable, the cloud writer for Pro. The prompt is
  written new for this spec.
- **Structure checks** (Foundation only, unit-tested) before a case can be played:
  - 8 to 20 steps, covering both groups;
  - at least two key steps;
  - the diagnosis is among the differentials, and every differential has a supporting step;
  - the turning step is a key step;
  - the budget covers the key steps plus about 30 percent;
  - next-step options pass MCQGenerator.lengthBalanced;
  - numbers in findings and results pass AccuracyRules (lab ranges, doses, retired practice).
- **The verification layer.** Each case file is checked as an item. Its asserted text is the
  complaint, the findings, the diagnosis, the next step and the teaching points. A Flagged case is
  held (AccuracyHolds), never shown.

## Where it lives

- Folder Features/Cases/. Logic in Foundation-only files: the case file, checks, scoring, ladder
  history. Each has tests in a new suite "cases" registered in tools/swift_suites.txt.
- The views on the Ward kit.
- The Playgrounds variants must still build (tools/playgrounds_cut.py).
- Accessibility:
  - VoiceOver labels on every action, finding and rung;
  - Dynamic Type, 44-point targets;
  - Reduce Motion respected.
- Built on design/cases. The App build there is the compile check. No screenshots until the owner
  asks.

## Not in the first build

- Never: questioning the patient and getting answers, in any form (the other person's feature).
- Clue-by-clue reveal scoring: not planned.
- On-call sessions with several patients at once.

## Sources (methods and ideas, not text)

- Page G, Bordage G. The Medical Council of Canada's key features project: a more valid written
  examination of clinical decision-making skills. Acad Med 1995;70:104. PMID 7865034.
- Schmidt HG, Rikers RM. How expertise develops in medicine: knowledge encapsulation and illness
  script formation. Med Educ 2007;41:1133. PMID 18004989.
- Cook DA, Triola MM. Virtual patients: a critical literature review and proposed next steps. Med
  Educ 2009;43:303. PMID 19335571.
- Bowen JL. Educational strategies to promote clinical diagnostic reasoning. N Engl J Med
  2006;355:2217. PMID 17124019.
