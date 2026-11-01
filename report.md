# Accuracy model trained-2026-11-01-480

480 items (cross-validated, 5 folds by question) · L2 0.1

| | Log loss | Brier | AUC | Calibration error (ECE) |
|---|---|---|---|---|
| Trained (held-out) | 0.137 | 0.038 | 0.986 | 0.022 |
| Current weights | 0.127 | 0.036 | 0.991 | 0.027 |

**Verified** at P ≥ 0.48: precision 97.0%, recall 95.0% of accurate items (234 items).
**Flagged** at P < 0.43: precision 95.5%, recall 96.7% of wrong items (244 items).

## Calibration (held-out)

| P(accurate) | Items | Mean P | Actually accurate |
|---|---|---|---|
| 0.0–0.1 | 206 | 2.5% | 2.4% |
| 0.1–0.2 | 16 | 12.0% | 6.3% |
| 0.2–0.3 | 4 | 23.3% | 25.0% |
| 0.3–0.4 | 7 | 37.1% | 42.9% |
| 0.4–0.5 | 14 | 42.5% | 21.4% |
| 0.5–0.6 | 6 | 53.5% | 83.3% |
| 0.6–0.7 | 2 | 64.0% | 50.0% |
| 0.7–0.8 | 7 | 73.5% | 100.0% |
| 0.8–0.9 | 18 | 87.4% | 83.3% |
| 0.9–1.0 | 200 | 98.2% | 99.0% |

## By kind of item

| Variant | Items | Flagged | Verified |
|---|---|---|---|
| correct | 239 | 4.6% | 95.0% |
| swapped-key | 150 | 98.7% | 0.7% |
| wrong-everywhere | 91 | 93.4% | 6.6% |

## By exam slice (held-out)

| Slice | Items | AUC | Accurate verified | Wrong flagged |
|---|---|---|---|---|
| usmle-step2-3 | 221 | 0.9774 | 94.5% | 97.3% |
| usmle-step1 | 259 | 0.9914 | 95.3% | 96.2% |

## Management questions, per exam

Each exam's stricter Verified cut-off for management questions ("next best step", "most appropriate treatment") on its style slice, against the shared one.

| Exam | Slice | Strictness | Items | Cut-off | Precision (shared → own) | Accurate verified (shared → own) |
|---|---|---|---|---|---|---|
| step2ck | usmle-step2-3 | 0.5 | 69 | 0.735 | 97.1% → 100.0% | 97.1% → 91.2% |
| step3 | usmle-step2-3 | 0.6 | 69 | 0.786 | 97.1% → 100.0% | 97.1% → 88.2% |
| comlex2 | usmle-step2-3 | 0.5 | 69 | 0.735 | 97.1% → 100.0% | 97.1% → 91.2% |
| plab1 | usmle-step2-3 | 0.3 | 69 | 0.633 | 97.1% → 100.0% | 97.1% → 91.2% |
| mrcp1 | usmle-step2-3 | 0.2 | 69 | 0.582 | 97.1% → 100.0% | 97.1% → 91.2% |
| mrcsA | neetpg-aiims | 0.2 | 0 | 0.582 | - → - | - → - |
| mccqe1 | usmle-step2-3 | 0.4 | 69 | 0.684 | 97.1% → 100.0% | 97.1% → 91.2% |
| amc | usmle-step2-3 | 0.3 | 69 | 0.633 | 97.1% → 100.0% | 97.1% → 91.2% |
| neetpg | neetpg-aiims | 0.1 | 0 | 0.531 | - → - | - → - |
| inicet | neetpg-aiims | 0.1 | 0 | 0.531 | - → - | - → - |
| fmge | neetpg-aiims | 0.1 | 0 | 0.531 | - → - | - → - |
| smle | usmle-step2-3 | 0.2 | 69 | 0.582 | 97.1% → 100.0% | 97.1% → 91.2% |
| dha | usmle-step2-3 | 0.2 | 69 | 0.582 | 97.1% → 100.0% | 97.1% → 91.2% |
| doh | usmle-step2-3 | 0.2 | 69 | 0.582 | 97.1% → 100.0% | 97.1% → 91.2% |
| mohap | usmle-step2-3 | 0.2 | 69 | 0.582 | 97.1% → 100.0% | 97.1% → 91.2% |
| qchp | usmle-step2-3 | 0.2 | 69 | 0.582 | 97.1% → 100.0% | 97.1% → 91.2% |
| omsb | usmle-step2-3 | 0.2 | 69 | 0.582 | 97.1% → 100.0% | 97.1% → 91.2% |
| emle | usmle-step2-3 | 0.2 | 69 | 0.582 | 97.1% → 100.0% | 97.1% → 91.2% |
| ifom | usmle-step2-3 | 0.4 | 69 | 0.684 | 97.1% → 100.0% | 97.1% → 91.2% |

## Weights

| Feature | Weight |
|---|---|
| bias | 4.8108 |
| rule_severe | -4.1684 |
| rule_minor | 2.0103 |
| risk_max | -1.8473 |
| risk_mean | -0.114 |
| flag_frac | -4.3567 |
| disagree | 0.3588 |
| voters | 0.1126 |
| key_disagree | -8.873 |
| ev_support | -1.2872 |
| ev_contradict | -1.1685 |
| ev_count | -0.0176 |
| source_match | 0 |
| no_source | 0 |
| no_models | 0 |
| kind_mcq | 1.5805 |
| kind_card | -1.5805 |
| kind_case | 0 |
| kind_osce | 0 |
| kind_page | 0 |

**Not better than the current weights: kept the current ones.**

## Notes

- stopped at this run's 60 batches; the next run carries on
