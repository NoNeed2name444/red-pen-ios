# Verification sensors on real exam questions

Questions: 7781 - CareQA Medicine 857, CareQA Nursing 923, CareQA Pharmacology 869, MedMCQA 1609, MedQA 1273, MedXpertQA 2250

| source | questions | any hit | severe hit |
|---|---|---|---|
| CareQA Medicine | 857 | 5 | 2 |
| CareQA Nursing | 923 | 2 | 2 |
| CareQA Pharmacology | 869 | 0 | 0 |
| MedMCQA | 1609 | 11 | 1 |
| MedQA | 1273 | 12 | 0 |
| MedXpertQA | 2250 | 12 | 1 |

## Clean questions (as published)

| | count | share |
|---|---|---|
| any sensor hit | 42 | 0.5% |
| a severe hit (blocks Verified) | 6 | 0.1% |

| rule:severity | clean questions hit |
|---|---|
| lab-unit:minor | 17 |
| duplicate-option:minor | 15 |
| duplicate-option:severe | 6 |
| dose-notation:minor | 3 |
| non-answer-position:minor | 3 |
| lab-implausible:severe | 2 |

## Planted errors (one per copy)

| error planted | copies | caught | catch rate |
|---|---|---|---|
| wrong-key | 396 | 396 | 100.0% |
| duplicate-key | 7762 | 7762 | 100.0% |
| tenfold-dose (leaves the usual range) | 48 | 48 | 100.0% |
| tenfold-dose (still inside the usual range) | 26 | 0 | 0.0% |
| lab-off-scale | 418 | 392 | 93.8% |
| numbers-disagree | 0 | 0 | n/a |

## Retired practice, new wordings

| | statements | flagged |
|---|---|---|
| retired practice | 20 | 20 (100.0%) |
| modern statements | 20 | 0 (0.0% false alarms) |

## Clean questions with a severe hit (to read by hand)

- careqa:fb644ed4-09d2-4909-9b8f-8110cbf610dc: duplicate-option:severe - Options C and D say the same thing.
- careqa:04942c1b-79e9-4da0-835f-788c04dabab0: duplicate-option:severe - Options C and D say the same thing.
- careqa:dfaacbe8-736c-4d74-bc13-f0db34183268: duplicate-option:severe - Options B and D say the same thing.
- careqa:faf86b41-1e10-490b-946e-955bdc0f1bd4: lab-implausible:severe - hb 6.5 g/l: not a possible haemoglobin in g/l (wrong unit?).
- medmcqa:0447b9a2-22ec-449c-8a23-a52c28ac6b34: duplicate-option:severe, duplicate-option:severe, duplicate-option:severe - Options A and B say the same thing.
- medxpertqa:Text-2184: lab-implausible:severe - albumin: 2.3 g/l: not a possible albumin in g/l (wrong unit?).
