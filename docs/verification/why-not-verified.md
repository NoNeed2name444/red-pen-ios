# Why nothing reached Verified

14 October 2026. From the live verification bench, run 38554454303 (90 hard exam questions, each checked with its true key and with a wrong key planted: 180 checks), its `results.json` on the verification-bench-results branch. Run it again on any run: `node tools/verification-bench/gates.mjs runs/<id>/results.json`; the bench report now ends with the same table.

## What Verified asks for

`server/accuracy-model.js` `verdict`: every one of these, with none missing.

| condition | right keys meeting it (of 90) | wrong keys meeting it (of 90) |
|---|---|---|
| a checker answered | 90 | 90 |
| P(accurate) ≥ 0.85 | 65 | 3 |
| no sensor fired | 90 | 90 |
| three checkers read it | 36 | 38 |
| three model families passed it | 32 | 30 |
| no concern raised, no literature read against it | 77 | 73 |
| three families solving it blind reached the key, none went elsewhere | 28 | 0 |
| **an official source states it word for word** (`proof.js`) | **0** | **0** |

## The finding

1. **The source proof can never pass these questions, by design.** For 88 of the 90 right keys the proof stopped at `stem`: `proof.js` only reads a question whose stem is one sentence of at most 30 words, asking for the one best answer ("most", "first-line", "of choice"), with no negation. Every MedQA, MedXpertQA and CareQA question is a clinical vignette, several sentences about a patient, which no label or MedlinePlus page could state. The other 2 stopped at `no-source`. So 0 of 90 could be Verified however well the checkers did.
2. **Everything else was enough for 26 right keys, and for no wrong one.** Set the proof aside and 26 right keys meet every other condition (the proof is the only one they miss); no wrong key meets them all, because none had three blind families on it. The blind three-family gate is doing its job; it is the proof that holds every right item.
3. **Three families rarely answer at all.** Only 36 of the 90 right keys were read by three checkers (blind solves: 3 families on 36, 2 on 44, 1 on 10). The two Workers AI checkers answered 58 and 43 of the 180 checks; the two Google-family checkers count as one witness; so three families need the cloud checker, the Google one and a Workers AI one to all answer. Even with the proof passed, this would cap Verified near 30%.
4. **The witnesses differ in reliability** (blind solves right: the cloud checker 84.0%, the two Workers AI checkers 82.8% and 74.4%, the light Google checker 69.2%), so three agreeing is rarer on hard questions than on the app's own.

## What changed, and why it is allowed

No threshold moved, no condition was dropped, and the proof is still required: the owner's bar is that Verified is *proven* ("they need to be PROVEN 99.999% right", 7 Oct).

- **An honest reason.** An item the proof can never read (a vignette, a case, a checklist, options that are not statements) used to be told "no official source states it word for word *yet*". It is now told it cannot be proven word for word and stays for a person to check (`server/accuracy.js` `UNPROVABLE`). Islamic brief §1 row 20 ("la adri": not established is an honest answer) and §3 (always record the reason).
- **The bench says what held each check back** (`tools/verification-bench/gates.mjs`, in every bench report). DNA brief §2 rule 1 and improvement 7: each layer's catch rate measured, not assumed.
- **More conditions, never fewer** (item 8, `server/provenance.js`): the chain, registry, common-link, shadh, tafarrud, conflict-of-interest and dabt checks can only hold an item back. A fuzz of 3,000 signal shapes in `server/tests/provenance.test.mjs` finds no item Verified with them that was not Verified without them, so the 0-false-Verified property is kept.

## What would let right items reach Verified (for the owner)

1. **Measure Verified on the app's own kind of item.** The app's generator writes one-sentence questions, cards and facts that the proof can read: on questions made from official sources it proved 8 of 11 (docs/verification/proof-mutation-bench.md). The vignette bench is the right test of "errors caught" (90/90) but cannot show Verified at all. The next live run should check app-shaped items. It needs no change to the verdict, only a new item set.
2. **A route for vignettes, if the owner wants one.** Prove the key's underlying fact ("X is the treatment of choice for Y", stated by the explanation) word for word, and leave the step from the vignette to that fact to three blind families. This would change what "proven" means: the patient story itself would not be proven. Islamic brief §1 row 13 and §2 L support checking the chain and the content separately, but this needs the owner's word. Until then, vignettes stay at Check this.
3. **More families answering.** A fourth free family, or more of Workers AI's daily pool, would lift the 36-of-90 ceiling. The owner chose on 2 Oct not to add providers, so this stays open.
