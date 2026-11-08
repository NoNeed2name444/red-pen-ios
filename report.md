# Accuracy model trained-2026-11-08-580

580 items (cross-validated, 5 folds by question) · L2 0.1

| | Log loss | Brier | AUC | Calibration error (ECE) |
|---|---|---|---|---|
| Trained (held-out) | 0.144 | 0.037 | 0.984 | 0.019 |
| Current weights | 0.134 | 0.036 | 0.988 | 0.028 |

**Verified** at P ≥ 0.66: precision 97.3%, recall 92.2% of accurate items (255 items).
**Flagged** at P < 0.61: precision 93.5%, recall 97.4% of wrong items (324 items).

## Calibration (held-out)

| P(accurate) | Items | Mean P | Actually accurate |
|---|---|---|---|
| 0.0–0.1 | 276 | 2.5% | 2.2% |
| 0.1–0.2 | 9 | 13.4% | 11.1% |
| 0.2–0.3 | 6 | 25.3% | 16.7% |
| 0.3–0.4 | 19 | 35.9% | 21.1% |
| 0.4–0.5 | 8 | 44.9% | 50.0% |
| 0.5–0.6 | 5 | 53.2% | 80.0% |
| 0.6–0.7 | 5 | 66.2% | 80.0% |
| 0.7–0.8 | 8 | 75.9% | 62.5% |
| 0.8–0.9 | 24 | 87.3% | 95.8% |
| 0.9–1.0 | 220 | 98.2% | 98.6% |

## By kind of item

| Variant | Items | Flagged | Verified |
|---|---|---|---|
| correct | 269 | 7.8% | 92.2% |
| swapped-key | 188 | 99.5% | 0.5% |
| wrong-everywhere | 123 | 94.3% | 4.9% |

## By exam slice (held-out)

| Slice | Items | AUC | Accurate verified | Wrong flagged |
|---|---|---|---|---|
| usmle-step2-3 | 269 | 0.9804 | 91.3% | 97.2% |
| usmle-step1 | 311 | 0.9858 | 93.0% | 97.6% |

## Management questions, per exam

Each exam's stricter Verified cut-off for management questions ("next best step", "most appropriate treatment") on its style slice, against the shared one.

| Exam | Slice | Strictness | Items | Cut-off | Precision (shared → own) | Accurate verified (shared → own) |
|---|---|---|---|---|---|---|
| step2ck | usmle-step2-3 | 0.5 | 83 | 0.825 | 100.0% → 100.0% | 90.0% → 87.5% |
| step3 | usmle-step2-3 | 0.6 | 83 | 0.858 | 100.0% → 100.0% | 90.0% → 85.0% |
| comlex2 | usmle-step2-3 | 0.5 | 83 | 0.825 | 100.0% → 100.0% | 90.0% → 87.5% |
| plab1 | usmle-step2-3 | 0.3 | 83 | 0.759 | 100.0% → 100.0% | 90.0% → 87.5% |
| mrcp1 | usmle-step2-3 | 0.2 | 83 | 0.726 | 100.0% → 100.0% | 90.0% → 90.0% |
| mrcsA | neetpg-aiims | 0.2 | 0 | 0.726 | - → - | - → - |
| mccqe1 | usmle-step2-3 | 0.4 | 83 | 0.792 | 100.0% → 100.0% | 90.0% → 87.5% |
| amc | usmle-step2-3 | 0.3 | 83 | 0.759 | 100.0% → 100.0% | 90.0% → 87.5% |
| neetpg | neetpg-aiims | 0.1 | 0 | 0.693 | - → - | - → - |
| inicet | neetpg-aiims | 0.1 | 0 | 0.693 | - → - | - → - |
| fmge | neetpg-aiims | 0.1 | 0 | 0.693 | - → - | - → - |
| smle | usmle-step2-3 | 0.2 | 83 | 0.726 | 100.0% → 100.0% | 90.0% → 90.0% |
| dha | usmle-step2-3 | 0.2 | 83 | 0.726 | 100.0% → 100.0% | 90.0% → 90.0% |
| doh | usmle-step2-3 | 0.2 | 83 | 0.726 | 100.0% → 100.0% | 90.0% → 90.0% |
| mohap | usmle-step2-3 | 0.2 | 83 | 0.726 | 100.0% → 100.0% | 90.0% → 90.0% |
| qchp | usmle-step2-3 | 0.2 | 83 | 0.726 | 100.0% → 100.0% | 90.0% → 90.0% |
| omsb | usmle-step2-3 | 0.2 | 83 | 0.726 | 100.0% → 100.0% | 90.0% → 90.0% |
| emle | usmle-step2-3 | 0.2 | 83 | 0.726 | 100.0% → 100.0% | 90.0% → 90.0% |
| ifom | usmle-step2-3 | 0.4 | 83 | 0.792 | 100.0% → 100.0% | 90.0% → 87.5% |

## Weights

| Feature | Weight |
|---|---|
| bias | 4.3633 |
| rule_severe | -5.6917 |
| rule_minor | 2.1615 |
| risk_max | -2.1014 |
| risk_mean | -0.0837 |
| flag_frac | -4.2086 |
| disagree | 0.553 |
| voters | 0.3904 |
| key_disagree | -8.5277 |
| ev_support | -1.1664 |
| ev_contradict | -1.7141 |
| ev_count | 0.0281 |
| source_match | 0 |
| no_source | 0 |
| no_models | 0 |
| kind_mcq | 1.4915 |
| kind_card | -1.4915 |
| kind_case | 0 |
| kind_osce | 0 |
| kind_page | 0 |

**Not better than the current weights: kept the current ones.**

## Notes

- stopped at this run's 60 batches; the next run carries on
