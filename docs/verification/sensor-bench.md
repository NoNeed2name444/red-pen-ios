# The verification layer's sensors, tested on real exam questions

1 October 2026. Run it again: `tools/verification-bench/fetch.sh data && node tools/verification-bench/sensors.mjs data/*.json --out out`, then `tools/verification-bench/parity.sh out/cases.json` for the app's copy.

## What was tested

The sensors are the layer's first, deterministic stage: the same code on the Worker (server/accuracy-rules.js) and on the phone (AccuracyRules.swift). They were run on 8,081 real published questions, from basic to expert level:

| source | level | questions |
|---|---|---|
| MedMCQA validation | Indian PG entrance | 1,609 |
| MedQA test | USMLE | 1,273 |
| MedXpertQA Text test | expert, 17 specialty boards | 2,450 |
| CareQA (English) | Spain's specialist-training exam: medicine, pharmacology, nursing | 2,749 |

Each question was then copied with one known error planted in what it asserts (stem, keyed answer, explanation). Retired practice was tested in 20 new wordings, with 20 correct modern statements alongside.

## Results

| test | result |
|---|---|
| real questions with a severe flag | 6 of 8,081 (0.07%); all 6 read by hand and **all are genuine defects in the published questions** (duplicated options, albumin in g/L, Hb 6.5 g/L) |
| real questions with any flag | 43 (0.5%), almost all genuine (Hb in mg/dL, bilirubin in g/dL, duplicated distractors) |
| wrong answer key (explanation argues for another option) | 396 / 396 caught |
| a distractor copied over the key | 8,061 / 8,061 caught |
| tenfold dose that leaves the drug's usual range | 51 / 51 caught |
| tenfold dose still inside the usual range | 0 / 27: a range cannot see these; the model checkers judge them |
| a result off by 10-100x | 425 / 451 caught (94.2%) |
| retired practice, new wordings | 20 / 20 caught, 0 / 20 false alarms |
| the app's copy against the Worker's | identical on all 17,107 cases |

## What the test found and fixed

Before these fixes the sensors had blind spots and false alarms that only real questions showed:

- The explanation reader missed the formats exam banks use ("Ans-a.", "Answer- A.", "Ans. is 'd' i.e."), so a wrong key went unseen: 0 of these were catchable before, 396 of 396 after.
- Options that differ only by sign, arrow or Greek letter ("CD 23+"/"CD 23-", "p<0.05"/"p>0.05", "↓TSH ↑T4"/"↓TSH ↓T4", "α-"/"β-synuclein") were called duplicates: severe false alarms on specialist questions.
- Urine, vaginal, gastric, dental and CSF results were judged against blood ranges (urine pH 5.7 "impossible").
- A drug level was read as a dose (serum digoxin 3.7 ng/mL); a combination product's strength was given to one of its drugs; in a list ("metformin, and prednisone 5 mg") one drug's dose was given to another.
- "Pre-albumin" was read as albumin.
- A question's distractors were judged as if asserted (a deliberately false option, "Naloxone 50 mg will block heroin for 24 hours", flagged as a dosing error). Only the stem, keyed answer and explanation are judged now (DNA brief: strand discrimination).
- Retired practice: "between 80 and 110 mg/dL" and "not vigorous" were missed; "preferred to ipecac" and "without routine suction" were false alarms; "atropine rather than adrenaline" slipped through.
- Missing units and doses: calcium in mEq/L, lactate in mg/dL, paediatric paracetamol and ceftriaxone, sub-antimicrobial doxycycline 20 mg, sublingual fentanyl.

Each fix is held by a case in server/tests/rule-vectors.json, which the server and the app both run.

## What the sensors cannot do

They catch the errors they are built for. A wrong key that no explanation contradicts, a wrong fact in plausible numbers, a wrong but in-range dose: those are the model stages' work (blind re-solve, two model families, evidence), measured separately on hard questions.
