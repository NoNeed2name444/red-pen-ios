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

### With the free voters that need no key (14 Oct)

The owner asked for free voters that need no key and no sign-up ("make free workers without apis", "use both"). Two kinds were added:

- **Workers AI families through the Worker's own binding.** Three families that no earlier voter belongs to. Each costs a third or less of the pool per check compared with the earlier Workers AI voters. They are not yet measured by the checker bench, so they come last and stand in when an earlier voter fails or the pool runs short. They do not widen the pool. It is still one free pool of about 10,000 neurons a day, shared with speech.
- **Runner voters on GitHub's free CPU.** Two open-weight models of two more families, under MIT and Apache-2.0 (tools/runner-voter/models.json). They answer the ladder's questions blind before the climb. On the owner's bench, one family's answer takes one of the three seats.

What this changes in the cost:

- **One runner seat (the default, `RUNNER_SEATS=1`).** The ladder's third witness comes from the runner rather than the Workers AI pool. The pool is left to the students' checks, and the ladder's daily count is no longer held to about 30 checks by it. The cloud checker still answers each batch, so the dollar column above is unchanged.
- **Two runner seats (`RUNNER_SEATS=2`).** The Google checker and two runner families make the three. The cloud checker is asked only when one of them fails, so the ladder's dollar cost falls to near nothing. Its limits become the runner's CPU time, the Google checker's 1,000 calls a day and the bench's 2,500 items a day. At 600 items a day, the 99.9% rung needs about 5 days at r = 1, and 99.999% about 500 days at r = 1.
- **The questions run out first.** About 2.5% of MedMCQA's training split is readable by the source proof (the dry run of 14 Oct read 947 rows for 24), so about 4,600 questions in all. That is enough for the 99.9% rung only if most of them reach Verified. The rungs after it need the vignette route, or more sources under licences that allow commercial use.
- **The catch.** Small CPU models are weaker witnesses. Raising the seats should follow the ledger on the progress page, which counts each family's blind answers against the gold key, not precede it.

## The owner's answers (14 Oct) and what was done

1. **Deploy**: done (worker-deploy run 38593206448); the provenance holds and the oath check are live.
2. **Target 99.999%, inside the cap**: the proof ladder below climbs 99.9% → 99.99% → 99.999% on its own. The cloud checker stays within CLAUDE_MONTHLY_USD (90); no cap was raised.
3. **The vignette route**: being built on its own branch. The ladder takes vignettes once it is live (`all: true` in tools/proof-ladder/config.json).
4. **Both, with no key** (revised 14 Oct: the owner declined every new key and sign-up): three more Workers AI families through the existing binding, and two runner voters on GitHub's free CPU whose blind answers take a family's seat on the owner's bench (server/runner-voters.js, tools/runner-voter). The two hosted free plans added first were removed.
5. **Labels**: built from public gold-labelled sets with commercial-use licences (tools/label-sets/registry.json). No label comes from a checking model.
6. **The triage model**: an open biomedical NLI model (MIT licence) is the workflow default (tools/jev-standin/default-model.json).

## The layers measured on public gold labels (14 Oct)

These were measured on the label sets in tools/label-sets/registry.json (jev-standin.yml). Each threshold was tuned on half the items by id and is reported on the other half.

| gate (held-out items) | biomedical NLI model (the default), kappa | general NLI model, kappa |
|---|---|---|
| mcq (210) | 0.010 | 0.076 |
| card (222) | -0.009 | -0.036 |
| research (208) | 0.135 | 0.183 |
| claim (195) | 0.007 | 0.197 |
| natural (32) | 0.063 | 0.000 |

Neither model comes near the §22a bar (kappa 0.8 on 200). An open NLI cross-encoder cannot triage medical keys: it gives "the answer is X" almost no entailment either way. The triage stays an ordering of work and never verifies anything.

The oath check (Layer 7) was measured on 400 sentences filed by FDA prescription labels under dosing and safety headings (CC0):

- After the new risk, dosing and monitoring rules: 87.1% recall on the held-out half (lower bound 82.6%), and 89.5% on all 400.
- The 99% bar is not met.
- The seed set still has no false positive.
- In the live path, a proof quote from an oath section makes an item an oath item whatever the text rules say.

## The proof ladder: where progress is recorded

- **What it does.** `.github/workflows/proof-ladder.yml` runs once a day at 02:43 UTC (`tools/proof-ladder/ladder.mjs`). It checks public exam questions with gold keys on the live Worker as the owner's bench: MedMCQA train (Apache-2.0), then MedQA train (CC BY 4.0). These are splits that neither the triage nor the verification bench uses. Each question is used once. Half of them, chosen by id, have a distractor keyed instead of the answer; a Verified distractor counts as an error.
- **Which questions.** Until the vignette route is live, only questions the source proof can read are sent, since no other question can reach Verified. That is about 2.5 to 5% of MedMCQA.
- **The count and the bound.** The ladder counts Verified verdicts and errors among them. It proves the exact one-sided 95% lower bound on Verified's accuracy (Clopper-Pearson; 0.05^(1/n) with no error). The rungs need 2,995, 29,956 and 299,572 Verified with no error. One error costs about 1,900 more at the first rung.
- **The spend.**
  - Free families answer first. The cloud checker is asked only where they fail.
  - The ladder holds itself to `share` dollars a month (60 of the 90; config.json), spread evenly over the month. It reads the month's spend from the Worker's `/costs` and stops for the day when it is ahead of that pace, or within one batch of the cap. That leaves the owner's own checks at least 30 dollars.
  - It takes at most 600 items a day (`maxItems`), under the bench's 2,500 and everyone's 3,000.
- **Where to read it.** `proof-ladder/progress.md` (and `progress.json`, the running state) on the **verification-bench-results** branch, after every run. Each run's summary repeats it.
- **What it needs to run on its own.** GitHub runs a schedule only from the default branch (main). Until proof-ladder.yml is there, a push to `ladder/run`, or the "Run workflow" button once it is listed, starts a day.

## What still needs the owner

1. **No new key or sign-up.** Every voter added on 14 Oct uses the Worker's own binding or a free runner.
2. **The ladder on main**, so its daily schedule runs: merge `.github/workflows/proof-ladder.yml` and `tools/proof-ladder/` to main, or make personal the default branch.
3. **A Worker deploy** (approved 14 Oct; the orchestrator runs it): the `/costs` change, without which the ladder stops before sending anything (fail-closed), plus the new voters and the runner seat.
4. **Oath negatives and the app's own cards**: no public set labels them (registry.json `noPublicGold`). Each needs about 200 marked by a person.
5. **More runner seats**, once the ledger shows the runner families answer as well as the live ones: set RUNNER_SEATS=2 as a Worker variable.
