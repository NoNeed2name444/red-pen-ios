# Proving Verified is 99.999% right

14 October 2026. Plan item #26 (VT3): the owner's bar is that an item marked Verified is *proven* 99.999% right (7 Oct). This note says what proving it takes, what we can honestly claim today, what a run would cost, and what needs the owner.

## How many verdicts

A rate is proven only by a bound, not by a point estimate. With *n* Verified verdicts checked against a known answer and **none wrong**, the one-sided 95% upper bound on the error rate is 1 − 0.05^(1/n) (about 3/n, the rule of three). For the error rate to be below 0.001% (accuracy ≥ 99.999%):

n ≥ ln(0.05) / ln(0.99999) ≈ **299,572 Verified verdicts, with no error at all.**

One error raises that to about 474,000; each further error adds roughly another 150,000. A run checks items, not Verified verdicts: if a fraction *r* of checked items reach Verified, the run must check about 300,000 / *r* items. Each must have a known true answer (a planted wrong key counts too: the property is that a wrong key is never Verified).

Islamic brief §2 L (oath items rest only on top-grade evidence) and Jev brief §22a (any oath miss blocks launch) apply the same logic per layer: a layer's catch rate is measured, never assumed (DNA brief §2 rule 1).

## What we can honestly say now

| evidence | result | 95% one-sided lower bound |
|---|---|---|
| Verified items right (live bench 38554454303) | 0 Verified | **no estimate**: nothing reached Verified (see why-not-verified.md) |
| wrong keys kept out of Verified (same run) | 90 of 90 | 96.7% |
| Flagged items right (same run) | 27 of 27 | 89.5% |
| source proof never proves a changed statement (proof-mutation-bench.md) | 0 of 906,828 | 99.9997% (false proof below 3.3 in a million) |
| oath check catches oath claims (tools/jev-standin/oath-seed.jsonl) | 30 of 30 | 90.5% |
| provenance never adds a Verified (fuzz, server/tests/provenance.test.mjs) | 0 of 3,000 | by construction: it can only hold back |

So the honest claim today is: **the source proof alone meets the bar on synthetic changes; Verified as a whole has no measured accuracy yet.** The proof bound covers one gate on mechanically changed sentences, not real items, and must not be quoted as the accuracy of Verified.

## What the run needs before it can start

1. **Items where Verified is reachable.** The vignette bench cannot produce a single Verified (the proof cannot read a vignette). The run needs app-shaped items (one-sentence questions, cards, facts) with known answers and planted wrong keys. The question bank in tools/question-bank can supply these; at least the true/false of each key must be known.
2. **The new holds live.** provenance.js and oath.js change the verdict; the Worker must run them for the run to measure the app's real verdicts.
3. **Labels for the layers** (Jev brief §22a tuning): 300 per triage gate (50/50 split), 200 for the kappa check, 299 oath positives with no miss for oath recall ≥ 0.99. We have 40 oath seed labels.

## What the run would cost

A check goes in batches of 4 items, about 3 to 5 model calls per batch, and Verified needs three families to answer.

- **Free tiers.** Workers AI's free pool gives about 30 checks a day; the Google checker is capped at 1,000 calls a day (GEMINI_DAILY_CEILING); the owner's bench allowance is 2,500 items a day (OWNER_BENCH_DAILY_LIMIT). The third family is the bottleneck: at 30 checks a day, 300,000 checks would take about 10,000 days. Free tiers alone cannot do it.
- **The cloud checker** is the only family that answers every time. At its price ($4 per million tokens in, $20 out) and about 5,000 tokens in and 2,600 out per batch, a batch costs about $0.07, or about $0.018 per item. The owner's cap (CLAUDE_MONTHLY_USD, 90) buys about 1,250 batches, about **5,000 items a month**. Even if every item reached Verified, 300,000 verdicts would cost about **$5,400** and take **about 60 months** at the cap. With a realistic Verified rate (say a third), triple both.

Conclusion: 99.999% is out of reach at the current cap and free tiers. A defensible staged target within budget:

| target | verdicts with no error | cloud checker cost at r = 1 | months at the cap |
|---|---|---|---|
| 99% | 299 | about $5 | under 1 |
| 99.9% | 2,995 | about $55 | under 1 |
| 99.99% | 29,956 | about $540 | 6 |
| 99.999% | 299,572 | about $5,400 | 60 |

## What the owner must approve

1. **A Worker deploy** with provenance.js and oath.js, so live verdicts carry the new holds (not deployed: needs the owner's word).
2. **The target and the spend**: which row above, and whether to raise CLAUDE_MONTHLY_USD or spread the run over months. No paid run was started for this note.
3. **The vignette route** (why-not-verified.md, option 2): whether a vignette's underlying fact proven word for word, plus three blind families, may count as proven.
4. **A third free family or a larger Workers AI pool**, which the owner set aside on 2 Oct; without it the run depends on the cloud checker.
5. **Labels**: 300 per triage gate, 200 for kappa, 299 oath positives, from the owner or a clinician the owner trusts.
6. **The triage model**: set the repository variable TRIAGE_NLI_MODEL to an open NLI model on the Hugging Face Hub and run the jev-standin workflow by hand.
