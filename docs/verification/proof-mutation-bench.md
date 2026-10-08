# The source proof, tested by changing what sources say

8 October 2026. Run it again: `tools/verification-bench/fetch-proof.sh data && node tools/verification-bench/proof-mutations.mjs --fda data/fda --mlp data/mlp --per-statement 400`.

## The question

An item is Verified only when an official source states each of its claims word for word (server/proof.js). The owner's bar is 99.999%: the proof must not prove what no source states. This bench asks whether it ever does.

## How

92 official sources: 60 openFDA labels (three each for 20 drugs, from acetaminophen to warfarin, including narrow-margin ones: digoxin, heparin, insulin, lithium, methotrexate, warfarin) and 32 MedlinePlus summaries (asthma to tuberculosis). Their 10,940 statements were each proven as they stand, then changed so they mean something else and proven again:

| change | example |
|---|---|
| number | 5 mg to 10, 2.5, 6, 50 or 4 mg |
| unit | mg to mcg or g, mL to L, hours to days or minutes |
| frequency | once to twice daily, daily to weekly |
| route | oral to intravenous, intravenous to subcutaneous |
| negation | "not" taken out, or put in |
| opposite | increase/decrease, adults/children, before/after, with/without, hypo-/hyper-, contraindicated/indicated, mild/severe, and/or (36 pairs) |
| drug | the label's drug named as another of the 20 |
| cut | the first or last 1-3 words left off |
| drop | one word left out |
| swap | two neighbouring words swapped |
| insert | always, only, never, rarely or usually put in |

A changed statement whose words are still some statement of the same source (the proof's spelling, salts aside) is left out: the source does state it. Every other changed statement proven counts as a false proof.

## Results

| measure | result |
|---|---|
| changed statements | **903,657** |
| changes of a statement the proof finds as it stands (one change from a proof) | 144,410 |
| **false proofs** | **0** |
| statements proven as they stand | 1,598 of 10,940 (14.6%) |
| run time | 64 s, on Linux |

| change | cases | of a proven statement | still stated (left out) | false proofs |
|---|---|---|---|---|
| number | 58,191 | 4,561 | 84 | 0 |
| unit | 6,893 | 1,142 | 0 | 0 |
| frequency | 2,088 | 255 | 2 | 0 |
| route | 1,575 | 442 | 0 | 0 |
| negation | 7,740 | 1,280 | 3 | 0 |
| opposite | 26,308 | 4,433 | 4 | 0 |
| drug | 121,023 | 34,564 | 4 | 0 |
| cut | 63,408 | 8,002 | 3,650 | 0 |
| drop | 187,176 | 26,196 | 1,525 | 0 |
| swap | 162,659 | 23,695 | 0 | 0 |
| insert | 266,596 | 39,840 | 0 | 0 |

With none in 903,657, the false-proof rate on these changes is below 3.3 in a million at 95% confidence (the rule of three): 99.9997%. On the 144,410 changes one step from a proof, it is below 21 in a million (99.998%).

## What this does not show

- Only these kinds of change. A statement true only under a heading the claim leaves out, or a wording no rule here makes, is not tested here. proof.js keeps those out by how it reads: heading words travel with each statement, and lead-ins, qualified and taken-back sentences never prove alone. server/tests/proof.test.mjs tests them by hand.
- That a source is right. The proof shows that an official source says it, not that the source is current or correct.
- How much gets Verified. Only 14.6% of statements are proven as they stand, because the rest need their heading, are lead-ins or qualified, or hold more than six claims. Most exam items will show Check this until more of them can be read into claims.
- Labels for more than one drug and MedlinePlus summaries over 40,000 characters are not read.
