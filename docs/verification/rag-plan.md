# Retrieval for proof, and the fact-chain layer (D6)

```
v: 1
id: rag-proof-1016
attempt: 1
status: ready
objective: Make retrieval serve proof (find the official sources and show them), add the owner's
  fact-chain layer for patient stories (D6), and measure each step on a bench whose pass rule is
  fixed below before anything changes. End at tested, benched design branches merged into
  personal. A phase is deployed only after it passes its gates and the independent review
  (the owner's word, 16 Oct; section 7).
base: personal 2b7ef11e. Each later phase starts from personal after the previous phase's merge;
  record that hash in its result.
branches: design/rag-bench (T0), design/official-recall (T1), design/fact-chain (T2),
  design/evidence-filter (T3), design/lecture-passages (T4). T5 and T6 are built only when
  their trigger fires.
accept: A1-A27 below, plus gates G1-G10 (section 5) on every bench run
reply: one AAHP result per phase (v, id, attempt, status, changed, checks, tests, commit,
  diffstat, notes)
```

**Read first.** red-pen-ios CLAUDE.md, then plan.md (the vignette-route entry, :1813-1851), then
server/README.md:30-81, then docs/verification/vignette-proof-research.md §4, then this brief.

**Binding rules.**
- Free only. No paid AI outside Pro (PRO_PAYS), and nothing that needs an API key for a checker.
- Never StatPearls. Never Modal.
- No threshold, weight or verdict() change without the owner.
- The Worker is deployed only on the owner's word. It was given on 16 Oct for each phase that
  passes its gates (section 5) and the independent review, and for nothing else.
- Every stage fails safe within its budget: the safe value, never a better grade.
- Node and Foundation code is tested here first: `tools/preflight.sh` before every push, then
  `tools/ci_status.py`.
- Keep plan.md current in the same commits.
- Commit messages: a plain-English subject, and a body saying why.
- Never force-push. No pull requests.

**Stop and report, instead of improvising, when:**
- a gate fails twice;
- a change to verdict(), the thresholds, MIN_VERIFY_VOTERS or a voter's prompt looks needed;
- a run would spend more than its neuron budget (section 6);
- a file outside the phase's scope must change.

---

## 1. What the engine does now (checked at 2b7ef11e; corrections in bold)

| The draft said | What the code does | Where |
|---|---|---|
| A model rewrites the query (3 queries, 3 drugs) | **Not in checks.** `itemTerms` picks one query, without a model: up to 4 words of the key and 2 of the stem's last sentence (for a card, 5 words of its first line), cut to 60 characters, plus **at most 1 drug**. termsPrompt, parseTerms and gather serve only the chat checker. | accuracy.js:119-135; ai.js:139-145; evidence.js:50-69, :282 |
| Lexical recall: Europe PMC 2, MedlinePlus 1, openFDA by generic name | Right. Europe PMC returns reviews and guidelines of the last 6 years, pageSize 2, abstracts cut to 900 characters. MedlinePlus: retmax 1, 700 characters, plus its HTML for proof. openFDA: limit 1, four sections of 350 characters, plus whole sections when the label is the drug's alone. | evidence.js:160-273 |
| Fusion: concatenation, dedupe by work, up to 7,000 characters | **In checks this is `evidenceFor`, not gather.** It keeps lookup order, dedupes by URL only, cuts each entry to 600 characters, and stops with a `break` at the first entry that passes 1,500 characters. Two Europe PMC abstracts (1,200 characters) therefore end the list, so MedlinePlus and FDA never reach the voters: **167 of 180 bench checks showed exactly 2 entries.** No reranker and no filter: right. | accuracy.js:147-167 |
| The lecture: its first 1,400 characters | **The app chooses the excerpt.** AccuracyStore calls AccuracyText.reference, which calls TextSlicing.nearestPages. That ranks pages by how many distinct words over 3 letters they share with the item: no IDF and no length normalisation, so long pages win. It takes whole pages that fit, else the nearest paragraphs, else the prefix, and cuts to 1,400 characters (sourceLimit). The server cuts again and hashes the result. **Facts outside the chosen 1,400 characters are unseen** by the voters and by the claim gate, which reads only the first 20 sentences. The question's own page reference ("Lupus, p.14") is not used. | AccuracyStore.swift:99-101; AccuracyText.swift:37-43; LLMParsing.swift:216-265; AccuracyItem.swift:41; accuracy.js:792-794; MCQQuestion.swift:16 |
| Two voters, a third on disagreement | **For questions, three blind families vote first.** A failed call is replaced and a slow one hedged. A voter shown the key is asked only about an explanation or a split card. At most 5 calls a batch. README:35-36 is out of date. | accuracy.js:612-680 |
| Rules, claim gate, P(accurate), provenance | Right. The verdict has seven conjuncts: clean, enough, backed, independent, unanimous, solved, and p ≥ 0.85. provenance.js keeps chains (quoted, summary, memory, verbatim-span, deduction) and five holds. | accuracy-model.js:191-226; provenance.js |
| Chat-me's target | §8 wants MedCPT embeddings in pgvector and a MedCPT cross-encoder (plan.md:528-529). **Neither runs in a free Worker.** MedCPT is not on Workers AI and there is no pgvector. MedCPT is public domain (:547), so it can run offline on a CPU runner. The free reranker in the AI binding is @cf/baai/bge-reranker-base: general-domain, 283 neurons per million input tokens, 512-token pairs. The audit's DIVERGENT retrieval (task4:33, the raw assertion as the search term) has a twin here in itemTerms' drift. On medxpertqa:Text-1153, Claude noted that the evidence for an STI-screening question was about peptic ulcer and a biosensor. Self-RAG is "four nodes, trivial to hand-code" (22g:59), with no LangGraph (22g:93). | Chat-me docs/architecture |

## 2. Ruling on verified-why.md (run 38554454303, recomputed from its results.json)

**Confirmed, every count.**
- Right keys: Check this 90/90.
- Wrong keys: Check this 63, Flagged 27.
- No false Verified, and no right item Verified.
- Fails on right keys: backed 90, solved 62, independent 58, enough 54, p 25, unanimous 13, clean 0.
- Commonest combinations: backed only 26; backed + enough + independent + solved 38; all but clean 9; p + enough + backed + independent + solved 7.
- proof.why: stem 88, no-source 2.

**Corrections and additions.**
1. **'stem' is decided before any source is read.**
   - mcqClaims refuses a stem unless it is one sentence of at most 30 words, with a best-answer cue and no negation (proof.js:1971).
   - prove() runs discover() first and returns that refusal before it reads any official text (proof.js:2106-2107).
   - Better literature or retrieval therefore cannot change `backed` for these 88. Europe PMC is never used for proof at all.
2. **`backed` is not the only wall.** 64 of the 90 right keys also fail another conjunct. Only the 26 that fail `backed` alone are the ceiling for any proof route on this run.
3. **The wrong keys are stopped by `solved`, all 90 of them (p fails on 87).** None fails `backed` alone. So this set cannot show whether D6 is sound: D6 must be measured on its own (B1-D6, B2-D6).
4. **The literature is mostly irrelevant, not contradicting.**
   - 372 of 420 votes judged the evidence "none", 48 "supports" and 0 "contradicts".
   - The 13 `unanimous` failures are the voters' own flags, not literature.
5. **"Under three families" is 58, not 54.** 54 had fewer than three voters (`enough`); 58 had fewer than three families (`independent`).
6. **The vignette route is already live.** d2e4b8bf, which turned it on, is inside bc611221, deployed 15 Oct (plan.md:1835-1841). It is inert: no app or bench sends packets, vignette_proof stays 0, and the verdicts are unchanged.

**Root cause.** There are two independent ones.
- **(a) Proof shape.** A vignette is a deduction that no source states word for word. Only a proof-carrying route can back it: the registry rules of the vignette route, or D6 below.
- **(b) Witness coverage.** Too few families answer. That is a neuron and availability problem.
  - A two-item nemotron batch call costs about 240 neurons, against about 40 for qwen3.
  - The bench predates the keyless qwen3, glm and mistral voters (live since 15 Oct).
  - Re-measure on personal before deciding anything there.

**What retrieval can fix.**
- The 'no-source' and 'lookup' misses on items proof can read: 2 here, and a large share of the proof ladder's 382 + 181 "no official source" reasons.
- The official sentences D6 has to quote.
- Prompt size: evidence is about 1,500 of about 5,100 characters per item, so a relevance filter saves neurons and buys a little coverage.

**What retrieval cannot fix.** 'stem', 'kind', `solved`, and the third family.

**The route-on bench belongs in the proof step**, with one correction: the route is already the live default. What is new is attaching packets: v1 from the real proposer where a registry rule fits, v2 from D6. Run it on branch code in proxy mode (T0). Never change a live variable for it.
- The 90 bench items will show close to 0 coverage from the TB-only registry (safety only).
- No route-off control is needed: accuracy-stages.test and the route-off property test already hold "off = before".

## 3. Order by value per cost

| # | Step | Model call | Neurons | Why here |
|---|---|---|---|---|
| T0 | Bench first: proxy mode, retrieval set R, proof-only bench P | none in the harness. The proxy A run uses the live voters. | about one day's Workers AI pool per A run | Pass rules fixed before any change (16a:346: measure each layer) |
| T1 | **D0** official recall for proof, plus a per-source quota in fusion | none | 0 | Fixes the 1,500-character crowding; gives D6 the label of every option's drug. Cheapest real gain. |
| T2 | **D6** fact chains (the vignette route's real proposer, generalised) | 1 gated call per item | about 13 typical, 20 reserved (qwen3-30b) | The owner's binding requirement, and the only route that can back a vignette |
| T3 | **D1-lite + D3**: BM25 filter, then one keyless corrective rewrite | none | 0 | Cuts the 89% "none" evidence and the prompt size |
| T4 | **D2** lecture passages per claim, on the device | none | 0 | Better claim gate and voter grounding. Never backs anything, so it comes after T1-T3. |
| T5 | D1 model reranker (bge-reranker-base) | 1 binding call per item | about 0.4 real, 1 counted | Only if T3's bench shows a gap (trigger A26) |
| T6 | D5 dense leg (Vectorize) | embedding per query | small | Not now (trigger A27) |

D4 is folded in: proof.js already proves each claim against label sections, and oath.js already demands grade 5. D6 extends that to per-fact proof, and T3 to per-claim evidence.

---

## 4. Phases

### T0. Bench first (branch design/rag-bench; no engine change) [model: none]

**Scope.**
- tools/verification-bench/layer.mjs, gates.mjs
- tools/verification-bench/retrieval-set.mjs (new)
- tools/verification-bench/proof-only.mjs (new)
- .github/workflows/verification-bench.yml (inputs and artefacts only)
- server/tests/bench.test.mjs
- plan.md

**A1. Proxy mode.** `layer.mjs --proxy` runs this branch's checkBatch locally, with the live Worker as a model proxy only.
- env: `BENCH_MODELS=on`, `BENCH_BASE_URL=$WORKER/v1`, `BENCH_API_KEY=$KEY` (derived from the AI_API_KEY secret, as the workflow does now).
- Voters: the live free order as `bench:` pins, e.g. `bench:gemini:gemini-3.5-flash-lite,bench:workers-ai:@cf/openai/gpt-oss-120b,...`.
- The fetcher rewrites each chat call to `{model: 'cramdown-writer', use: <pin>, ground: false, ...}` with `x-bench: 1`, so the Worker's own limits apply: OWNER_BENCH_DAILY_LIMIT, the neuron pool, the Gemini ceiling.
- **Free families only. Never pin `claude:`** (see section 7, item 5).
- Options: `--route on|off` (default on, as live) and `--packets DIR`.
- The `--stub` test stays green offline.

**A2. Retrieval set R.** Labels are mechanical and never come from a model (the owner, 14 Oct: labels never from the checking models). They are committed with their sha256 before T1 starts.
- R-dev (for tuning only): 150 items from the proof ladder's training splits: 100 one-sentence and 50 vignettes (MedMCQA Apache-2.0, MedQA CC-BY-4.0).
- R-test (for reporting): the 90 bench questions (seed 7, 30 per source).
- Labels:
  - 2: an official document is relevant when it is an FDA label whose generic name equals (drugTokens) a drug named in the key or an option, or a MedlinePlus topic whose title or "also called" name equals the key's normalised words or the key's MeSH preferred term (looked up once, keyless, and stored).
  - 1: a passage is on-topic when it holds the key's words (or the stored MeSH term) and at least one content word of the stem's last two sentences.
  - 0: anything else.
- Metrics: official recall@3 and @5, nDCG@5 of what voters are shown, the on-topic share, and lookups per item.

**A3. Proof-only bench P** (0 neurons, network only).
- Items: 600 readable one-sentence items from the ladder's splits (half keyed wrong by `itemOf`), plus the 90 bench questions.
- Runs: itemTerms, then officialFor, then prove() and fullyProven.
- Reports fullyProven and the proof.why histogram, each by truth.

**A4. Baseline on 2b7ef11e**, saved to the verification-bench-results branch, with a summary in plan.md:
- R and P;
- one proxy A run (route on, no packets) with the gates.mjs conditions table;
- neurons per check, from each reply's usage × NEURON_RATES (ai.js:1077), else the Worker's estimate;
- CPU per batch, with process.cpuUsage as in claims.test.mjs:298-346;
- external fetches per batch, counted in the fetcher.

### T1. D0: official recall and fair fusion (branch design/official-recall) [model: none; 0 neurons]

**Scope.**
- server/accuracy.js (itemTerms, evidenceFor, officialFor, a lookup counter)
- server/tests/accuracy.test.mjs, evidence.test.mjs, accuracy-stages.test.mjs
- plan.md

Brief: 17 (rijal: grade the source; §2 L, a dose never on weak evidence); 23e:84 (retrieve from a closed, trusted corpus).

**A5. More official lookups.**
- `itemTerms` returns drugs from the key, each option and the stem: the DRUGS dictionary, DRUG_SUFFIX, and proof.js drugTokens. Up to `MAX_DRUGS_PER_ITEM = 4`, the key's drug first.
- It also returns two MedlinePlus queries: today's focus query and the key option alone.
- The Europe PMC query is unchanged in T1, so this step is isolated.
- officialFor reads every one of these. Lookups are shared within the batch (`seen`).
- `MAX_LOOKUPS_PER_BATCH = 28` external lookups. Beyond it, a lookup is skipped and counted as unread, so proof says 'lookup' and fails closed.

**A6. A fair share in fusion.** evidenceFor takes the best entry of each source first, in the order FDA, then MedlinePlus, then Europe PMC, then a second entry of any source.
- Each entry is cut to `ENTRY_CHARS = 500`. MAX_EVIDENCE_CHARS stays 1,500.
- An entry that does not fit is skipped, not a `break`.

**A7. Tests.**
- Fixtures cover A5 and A6.
- accuracy-stages keeps the same replies, outside calls and cache on its fixed inputs, except the new lookups. List them in the test.
- The worst fixture batch makes 28 lookups or fewer.

**A8. Gates.**
- G1-G10 hold.
- P: wrong keys proven = 0.
- P: 'no-source' + 'lookup' on right keys is no higher than the baseline.
- R-test: official recall@5 is no lower than the baseline.
- List each right item newly refused as 'distractor' (a newly read label states another option). That is proof becoming stricter, not a regression.

### T2. D6: the fact-chain layer (branch design/fact-chain) [model: one gated call]

**Decision (placement).** D6 *is* the vignette route's open item "a real proposer, and the app sending proof packets", generalised. It is not a separate route.
- Same switch (VIGNETTE_ROUTE), same entry point (checkVignette), same features (vignette_proof, vignette_checked), same verdict() untouched, same tiers.
- What it adds:
  - a packet `v: 2`, whose premises may be **general facts**: sentences of an FDA label or a MedlinePlus summary, proven word for word by proof.js, not only registry rules;
  - a closed relation grammar that reads those sentences;
  - a proposer on the server, so the app need not send packets for questions.
- A separate route would need a new switch, feature, verdict branch and owner decision, and would weaken nothing less.
- v1 is untouched.

Briefs:
- vignette-proof-research.md §4.1 (the proposer is untrusted, the checker trusted), §4.3 items 7-9 (an FDA "contraindicated in" quote plus a span rules an option out), R1 (:82, :274: decomposition with a model verifier is only a hold-only sensor);
- Chat-me plan.md:532 (claims as Subject → Relation → Object);
- 17 rows 13 and 17 (the matn is checked apart from the chain; no talfiq: the deduction is labelled a synthesis);
- 16a:160 (layers that differ in mechanism).

**The split.**
- **Givens:** the packet's `findings`, exact spans of the stem as in v1. They are the scenario, never "proven".
- **General facts:** each one sentence quoted verbatim from an official text fetched for this item. Each is atomic by construction, because the grammar parses one relation per sentence.
- **One fact per wrong option** that rules it out.

**A9. server/fact-chain.js (new, pure), reached from checkVignette when `packet.v === 2`.**

Packet v2:
```json
{ "v": 2, "item": "<itemDigest>", "key": 1,
  "findings": [{ "id": "g1", "at": [41, 57], "text": "type 2 diabetes", "slot": null }],
  "facts": [{ "id": "k1", "quote": "<a label sentence, verbatim>", "src": "<official entry url>", "section": "indications_and_usage" }],
  "rules": [{ "id": "<registry rule>", "ver": "1", "uses": ["g2"] }],
  "proves": { "by": "k1", "uses": ["g1"] },
  "eliminates": [{ "option": 0, "by": "k2", "uses": ["g3"] }, { "option": 2, "by": "exclusive" }] }
```

The checker refuses with a typed `why` unless every step below holds. Anything else stays at Check this (17 row 20, la adri).

1. **The packet is for this item:** its digest, key and size, as v1 step 1.
2. **Every finding is an exact span**, with the cue and conflict checks of v1 step 2. A finding with no slot is read literally (proof.js normalize). Every other place its words occur in the stem must lie inside a finding, or the check fails with `conflict`. The owner's "a fact about another patient" and "a negated finding" fail here.
3. **Every fact's quote is proven word for word**, through the proof stage's record (A10), against an official entry fetched for this item.
   - Its licence passes licenceAllows (StatPearls is refused by its pattern).
   - An oath item (oath.js) needs a grade-5 source: a label section or a registry guideline. A MedlinePlus fact (grade 4) backs only a non-oath item (17 §2 L; provenance.js OATH_GRADE).
   - The quote parses **whole** in the closed grammar, `{relation, drug, condition, qualifiers}`, with relations `indicated`, `choice` (drug or treatment of choice, first-line), `contraindicated` and `do-not-use`. An unparsed tail fails with `grammar`.
   - Diagnosis comes only from registry rules (v1 criteria).
4. **Every link is mechanical.**
   - Every condition and qualifier of a used fact is met by a finding: either a lexicon slot read with its criterion (readSays-style op and value), or equal normalised words.
   - Or it is met by the conclusion of a registry rule that fires on findings.
   - Every `uses` entry meets something.
   - Otherwise the check fails with `link`, `qualifier` or `hop`. The owner's "a dropped hop" fails here.
5. **The question asks what the key fact answers.**
   - The question holds a phrase from a closed `FACT_ASKS` list, beside lexicon.js ASKS, mapped to the relation. For example, "most appropriate pharmacotherapy" maps to `indicated` or `choice` with full elimination, and "drug of choice" maps to `choice`.
   - The question is not turned around, hedged or about someone else (v1's tests).
   - The key option names the fact's drug: equal normalised words with the salts dropped, or a registered alias.
   - Otherwise: `asks` or `conclusion`.
6. **Every other option is ruled out by a positive statement.** That is a `contraindicated` or `do-not-use` fact naming that option's drug, with its condition met by a finding; or a registry rule's exclusive outcome or denial (v1).
   - A missing statement never rules anything out (research §4.3 item 7: absence is not evidence).
   - Otherwise: `distractor`. The owner's "a distractor left unruled" fails here.
7. **The explanation and the stem say nothing unproven.**
   - Each explanation sentence must be a used fact's quote, or proven word for word by proof.js on the same officials. Otherwise: `explanation`.
   - A stem sentence with no patient subject that holds a grammar verb ("…is contraindicated in…") is a general claim the chain does not prove. It fails with `stem-claim`.
8. **Limits.** `FACT_WORK = 40000` characters' worth; `MAX_FACTS = 8`; MAX_FINDINGS 24 and MAX_PACKET_CHARS 16,000 as in v1. Over a limit: `budget` or `packet`.

Each new `why` gets a VIGNETTE_REASONS sentence. The chains for provenance.js:
- findings as `verbatim-span`;
- each fact as `quoted`, with its section and source;
- the key as `deduction` with `synthesis: true`.

**A10. Fact proofs, in the proof stage.**
- Each fact's quote is proven by `prove({kind: 'fact', text: quote}, officials)`, unchanged.
- It has its own purse: `FACT_PROOF_CHARS = 24000` a batch, about 1.6 ms at proof.js's 0.065 µs a character. If the purse runs out, the result is `budget` and the item is checked again later.
- The records (quote, url, section, source, licence, grade) are kept in the item's signals together with the packet's digest. describe() passes them to the pure checker, and the checker trusts only these records, never the packet.
- The item hash does not change, because a packet is never part of it (accuracy.js:85-110).
- A cached item whose packet digest differs re-runs only the proof stage. Its votes come from the cache.

**A11. Tiers.**

| Tier | When |
|---|---|
| `proven` (may back Verified) | Only when every fact is a **registry fact** (server/criteria, kind `fact`) and every rule and quoted lexicon entry used is signed off by the owner by content hash (signedOff). A registry fact is admitted after its quote re-proves on the pinned snapshot (tools/criteria/fetch-sources.mjs) and a second, independent transcription of its parse agrees (B6). Its hash is sha256(canonical({quote, source, section, parse})). |
| `checked` | Anything that passes every check but is not `proven` |

- vignetteProven and vignetteChecked keep their meaning.
- accuracy-model.js is not touched (G6).
- The route-off property test stays identical.

**A12. v1 unchanged.**
- vignette-proof.test.mjs and vignette-route.test.mjs pass untouched.
- B1 (vignette-proof-mutations.mjs) still accepts 0 of 300,000 or more.

**A13. The proposer** (server/fact-proposer.js, new, used by stage `propose` and by tools/criteria/proposer.mjs offline). [model: yes]
- **Gate.** The proposer runs only when all of these hold:
  - the item is an MCQ;
  - VIGNETTE_ROUTE is on;
  - `FACT_PROPOSER` is on (switches.js, **off by default**);
  - the item has no accepted packet yet;
  - `verdict(p, {...f, source_proof: 1}) === 'verified'`, that is, everything Verified needs except `backed`.
  On the bench that is 26 of 90 right keys and 0 of 90 wrong keys.
- **Input, at 0 neurons.**
  - Up to `PRESELECT_SENTENCES = 20` numbered sentences, each up to 300 characters, picked by BM25 against the stem and options (`PRESELECT_WORK = 60000` a batch). They come from the indications, contraindications and warnings sections, and from the MedlinePlus summaries, **already fetched for proof** (T1). So there are no extra lookups.
  - Plus the stem, the options and the key. The proposer is untrusted, so it may see the key.
- **Output.** Sentence numbers and stem substrings only, as JSON, with `max_tokens` 400 and temperature 0.
  - The server places each substring by a unique exact match (an ambiguous one is refused) and maps each number to its quote.
  - It writes v1 when a registry rule's alias is the key, and v2 otherwise.
- **Model.** `FACT_PROPOSER_MODEL = workers-ai:@cf/qwen/qwen3-30b-a3b-fp8`, with fallback `workers-ai:@cf/zai-org/glm-4.7-flash`.
- **Budget.** Stage budget 30,000 ms. `FACT_PROPOSER_DAILY_NEURONS = 1000`.
- **Failure.** Any failure means no packet, nothing else.
- **Cache.** The packet is cached with the item's signals.
- **Off.** With FACT_PROPOSER off: the same replies, outside calls and cache as before (accuracy-stages).

**Where the facts come from, at least cost.** One extra call, behind the gate, choosing among sentences the server already holds. **Not from the blind solvers' votes**, for three reasons:
- **The cost.** It would add about 300 output tokens per item for every voter on every item: about 20 neurons for gpt-oss, 41 for nemotron and 9 for qwen3, against about 13 once, on gated items only.
- **The yield.** Blind voters see neither the key nor the official text. They would paraphrase, and a paraphrase cannot be proven word for word.
- **Independence.** It changes the vote prompt and the blind solves, which must stay independent discriminations (16a:160; the accuracy-stages parity test).

**Per-fact status, recorded for every fact.**
- `proven`: by proof.js.
- `unproven`.
- With `FACT_CHECK` on (off by default; [model: one call, glm-4.7-flash, a family other than the proposer's, about 12 neurons]): `supported` or `disputed`, checked against T3's filtered passages. This follows 23e:85 and 23e:177: check that each passage supports its sentence, and measure before it gates anything.
  - `disputed` holds the item.
  - `supported` never backs anything ("models agreeing never stands in for a source").

**Neurons for the proposer** (qwen3, 1,500 tokens in at 4,625 neurons per million, 200 out at 30,475):
- about 6.9 + 6.1 = **13 a gated item**;
- 20 reserved at max_tokens 400, the rest refunded;
- 50 to 75 proposals a day under the cap.

**CPU.** The checker is pure and counted. Preselection, fact proofs and the checker each have their own work budget (above).

**A14. B1-D6: mutation soundness** (tools/verification-bench/fact-chain-mutations.mjs, deterministic, fixture officials, no network).
- At least 300,000 mutations of accepted v2 seed items: 0 accepted.
- The owner's five mutation classes, each its own counted class:
  1. a wrong fact (one word, drug or number changed);
  2. a dropped hop;
  3. a given moved to another person;
  4. a negated finding;
  5. a distractor left unruled.
- Plus: key swapped; a qualifier across its cut-off; population swapped; quote truncated; source swapped to a non-commercial licence or StatPearls; a grade-4 source on an oath item; a stale digest; an unparsed qualifier.
- Neutral edits (a name, an unrelated sentence) keep at least 90% accepted, so the bench cannot pass by refusing everything.

**A15. B2-D6: adversarial** (research §4.5).
- The proposer, through the proxy, tries to prove each planted wrong key of the 90 bench questions: about 1,200 neurons.
- Pass: the checker alone accepts 0.
- Any acceptance is adjudicated, since it may expose a bad gold key.

**A16. Coverage C.**
- The proposer and checker run on the 90 right keys: about 1,200 neurons.
- Report the packets accepted by tier, the items then Checked or Verified with votes, and the histogram of `why`, which picks the next lexicon slots (eGFR, age bands, pregnancy), each reviewed.
- Reported only, never a pass rule: coverage is UNKNOWN (research §4.9) and expected to be small on hard exam vignettes.

**A17. CPU.**
- The worst batch is 4 questions with v2 packets at MAX_FACTS, with explanations. Warm, it may take at most 2 ms more than before.
- Cold is reported, as in claims.test.mjs:337-346.
- No counted budget is exceeded.

**A18. Cases and OSCE stations: hold-only** (after A14-A16 pass).
- The same proposer splits the story into general facts, and proves each word for word or records it unproven. The facts are shown in provenance.
- These items never back anything: there is no closed set of options to rule out, so a conclusion cannot be shown to be the only one, and proof stays 'kind'.
- Test: no case or OSCE verdict can improve.

### T3. D1-lite + D3 (branch design/evidence-filter) [model: none; 0 neurons]

**Scope.**
- server/evidence.js (europePMC pageSize, MeSH and RxNorm lookups)
- server/retrieval.js (new: BM25, floor, quota)
- server/accuracy.js (evidenceFor)
- tests
- plan.md

Briefs: 22g:59 and :93 (grade, then generate or rewrite, hand-coded as typed stages); 23e:84 and 23e:195 ("Not in our sources").

**A19. Filter.**
- Europe PMC pageSize 5. It is still one request.
- Every candidate is scored by BM25 (k1 1.2, b 0.75, IDF over the batch's candidates) against the item, in plain JS. For cards, facts and notes, scoring is per claim (claimsFor, at most MAX_CLAIMS), taking the best passage per claim.
- `RERANK_WORK = 30000` a batch.
- The relevance floor F is chosen on R-dev only, as the lowest score that keeps 95% of label-1 and label-2 passages, and fixed before R-test or A runs. It is a retrieval setting, not a verdict threshold, and the report shows it.
- The A6 quota is kept.
- An error, or running out of budget, falls back to T1's order.

**A20. One corrective rewrite.**
- When nothing passes F, rewrite once: the focus words become the MeSH preferred term (NLM MeSH lookup, keyless), and drugs become RxNorm normalised names (RxNav, keyless).
- Retry once, then show "(none found)". It never fails open.
- The rewrite counts within MAX_LOOKUPS_PER_BATCH and is day-cached.

**A21. Gates.**
- G1-G10 hold.
- R-test: on-topic share +5 points and nDCG@5 +0.05 over T1, else T3 stays unmerged with its numbers.
- Report the share of votes saying "evidence: none", and neurons per check.

### T4. D2: lecture passages, on the device (branch design/lecture-passages) [model: none]

**Change to the draft.** Do this on the phone, in Foundation-only Swift, tested on Linux. Do not do it in the Worker.
- The server sees only 1,400 characters.
- Sending more would grow every request and re-key every cached verdict, since the hash includes the source (accuracy.js:106-110).
- It would also spend Worker CPU.

**Scope.**
- ios/RedPen/Shared/LLM/LLMParsing.swift (TextSlicing)
- ios/RedPen/Shared/Accuracy/AccuracyText.swift, AccuracyStore.swift
- a new suite listed in tools/swift_suites.txt
- plan.md
- tools/playgrounds_cut.py must still pass.

Briefs: 23e:84 (retrieval from a closed, trusted corpus: here, the student's own lecture); 17 row 13 (the claim gate checks the matn against that lecture).

**A22. Passage BM25.**
- Passages are paragraphs, up to 700 characters; longer ones split at sentence ends.
- BM25 (k1 1.2, b 0.75; IDF over the set's passages) is run for each claim of the item: the stem's last sentence plus the key, each explanation sentence, or a card's lines.
- Passages from the page the question cites come first (MCQQuestion.source).
- Headings stay ("doc, page:"). Pack to 1,400 characters.
- Fallbacks: the cited page, then today's behaviour.

**A23. No re-key.** An item that already has a verdict keeps the excerpt it was checked with until it is edited (test). No cached verdict is lost, and no re-check storm spends the pool.

**A24. Fixture lectures** (public-domain text, contradictions planted beyond the old 1,400 characters or on a long page that raw overlap ranks first).
- The relevant sentence falls inside the excerpt +20 points more often than before.
- The claim gate's hard findings are at least as many as before.

### T5. D1 model reranker (conditional) [model: bge-reranker-base, about 0.4 neurons an item]

Brief: Chat-me plan.md:529 (the cross-encoder rerank target); 16a:346 (measure before adopting).

**A25.**
- Offline in Actions, on CPU, run BAAI/bge-reranker-base (MIT, the binding model's weights) and, for reference, the MedCPT cross-encoder (public domain) over R's candidates.
- Adopt only if nDCG@5 on R-test rises by at least 0.05 over T3 **and** the on-topic share rises by at least 5 points.
- If adopted: one binding call per item, at most 8 pairs of up to 512 tokens. NEURON_RATES gets `'@cf/baai/bge-reranker-base': [283, 0]`. It falls back to BM25 order.
- Confirm the live scores on 20 pairs after the owner deploys.

### T6. D5 dense leg: not now

Brief: Chat-me plan.md:528 (the pgvector target); 16a:346 (measure first).

**A26.** Build nothing unless both hold after T1 and T3:
- official recall@5 on R-test is below 0.80;
- an offline prototype (bge-small-en-v1.5 over MedlinePlus health topics, public domain) adds at least 0.10.

Then it goes to the owner, since a Vectorize binding needs a deploy. Reasons for not now:
- the bench shows a proof-shaped problem, not a recall-shaped one;
- StatPearls is excluded;
- no licensed corpus beyond the official sources needs an index.

**A27.** T5 and T6 are recorded in plan.md as untriggered or triggered, with their numbers.

---

## 5. The bench and its pass rule (fixed now, before any change)

**Protocol.**
- **Before:** T0's baseline at 2b7ef11e.
- **After each phase:** the same runs on that phase's branch, with the same settings:
  - seed 7, 30 questions per source, batch 2;
  - route on;
  - the same free voters, pinned in the same order through the proxy.
- **Run schedule:**
  - Proxy A runs: at most one per UTC day, started just after midnight UTC.
  - R, P, B1 and B1-D6: any time; they spend no neurons.
  - B2-D6 and C: on a separate day.

**Gates (all must hold on every run, or the phase is not merged).**

| Gate | Rule |
|---|---|
| G1 | Wrong keys Verified: 0 of 90 |
| G2 | Wrong keys Checked: 0 of 90 |
| G3 | Wrong keys source-proven (A and P): 0 |
| G4 | B1 (v1) and B1-D6: 0 accepts of 300,000 or more each. B2-D6: the checker alone accepts 0. |
| G5 | Right keys Flagged: no more than before |
| G6 | No change to verdict(), DEFAULT_WEIGHTS, the thresholds, MIN_VERIFY_VOTERS or the vote prompt (the git diff of accuracy-model.js shows nothing in :1-240; votePrompt unchanged) |
| G7 | CPU: the worst batch warm takes at most 2 ms more than before; counted budgets never exceeded; cold reported |
| G8 | External fetches per batch of 4: at most 40 (lookups at most 28, plus model calls), against the free plan's 50 |
| G9 | Neurons per check reported (mean and p95); the proposer stays within FACT_PROPOSER_DAILY_NEURONS; one A run uses at most one day's pool |
| G10 | With FACT_PROPOSER off and no packets, the accuracy-stages fixed inputs give the same replies, outside calls and cache, apart from the documented T1 and T3 lookups |

**Value, reported per run.**
- Right keys Verified, Checked and Check this.
- The conditions table (gates.mjs).
- proof.why by truth (A and P).
- R metrics.
- Calibration of P(accurate): Brier score and a 5-bin reliability table, by truth.
- Coverage C.
- The share of votes saying "evidence: none".
- Families answering per check, since voter availability varies from day to day: compare value numbers with it beside them.
- Each phase's own value rule is in A8, A21, A24, A25 and A26.

**Honesty.**
- 0 of 90 wrong keys bounds the false-Verified rate only at about 3.3% (95%, rule of three).
- The soundness claim rests on B1 and B2: 0 of 300,000 is about 1×10⁻⁵ (research §4.5).
- Never quote 99.999% for Verified.

## 6. Cost: neurons, CPU, subrequests

| Step | Model call | Neurons | CPU (counted) | External fetches |
|---|---|---|---|---|
| T1 lookups and quota | none | 0 | trivial | at most 28 a batch (4 PMC, 8 MLP, 16 FDA) |
| T2 checker and fact proofs | none | 0 | FACT_WORK 40k, FACT_PROOF_CHARS 24k a batch | 0 (reuses T1's officials) |
| T2 proposer (gated, off by default) | qwen3-30b, fallback glm-4.7-flash | about 13 (20 reserved); at most 1,000 a day | PRESELECT_WORK 60k a batch | 0 (an AI binding call) |
| T2 FACT_CHECK (off by default, hold-only) | glm-4.7-flash | about 12 | parse at most 2k characters | 0 |
| T3 filter and rewrite | none | 0 | RERANK_WORK 30k a batch | the rewrite counts within the 28 |
| T4 lecture | none (on device) | 0 | phone | 0 |
| T5 reranker | bge-reranker-base | about 0.4 real, 1 counted (the ledger rounds up) | small | 0 (binding) |
| Bench A run (proxy) | live voters | up to one day's pool (about 9,000) | n/a | n/a |
| B2-D6 + C | proposer | about 2,400 | n/a | n/a |

## 7. The owner's decisions (16 Oct)

1. **Deploy.** "if they pass then go": each phase is deployed from personal once it passes its gates (section 5) and the independent review. That word covers nothing else.
2. **FACT_PROPOSER on.** "its ok": switched on once A14-A16 pass. It spends up to 1,000 neurons a day of the shared pool, about 13 per gated question.
3. **D6's grade.** "make it checked and the human step optional for later as it takes so much money and effort":
   - A fully proven fact chain backs **Checked**, with no per-fact review. The facts are word for word, the steps mechanical, and the grammar and its benches are the review.
   - **Verified** still needs every fact to be a registry fact, its parse transcribed twice, its quote re-proven on a pinned snapshot, and the owner's sign-off by content hash (the rule set for the CDC rules, 14 Oct). That sign-off is optional and later: no sign-off screen or endpoint is built now. The content-hash binding stays, so a later sign-off needs no rework.
   - Why not Verified at once: TIER_MEANINGS.verified (accuracy-model.js:235) promises "every step was checked". A sentence's parse is a new kind of step, and only a review makes it a checked one.
   - Facts backed only by literature and checker agreement never back a tier ("models agreeing never stands in for a source"). Widening Checked to them would change its definition.
4. **Licences.**
   - USPSTF stays out of the registry (Chat-me plan.md:555: not free for commercial use).
   - openFDA: T1 multiplies label lookups. A free OPENFDA_API_KEY allows 120,000 a day against 1,000 per address (evidence.js:111-114). The owner adds it as a Worker secret after the current tasks; until then every bench and phase stays within the keyless limit.
5. **Side finding.** The owner key could pin `claude:` on /v1/chat/completions (ai.js:97-101, :273-275), which skipped the CLAUDE_MONTHLY_USD hold that askClaudeVoter keeps (ai.js:239-259). design/claude-cap refuses that pin; it reaches personal after its review. The proxy bench never pins Claude.
6. **Coverage track (not retrieval).** The third family is a pool problem. Re-measure on personal with the keyless voters first; that is the T0 baseline.

## 8. Changes to the draft

- **D0 added, and first.** The blocker for proof is official recall and the 1,500-character crowding, not ranking.
- **D1:** lexical (BM25) and a quota before any model. MedCPT is not in the binding, so bge-reranker-base comes only behind a measured trigger (T5). The threshold is fixed on R-dev, never on the bench.
- **D2:** on the phone, not the Worker; the cited page used as metadata; no re-key of checked items.
- **D3:** kept as one hand-coded rewrite (MeSH/RxNorm, keyless) inside T3's state, failing closed. It is not a separate loop.
- **D4:** mostly exists (proof.js label sections, oath.js grade 5). The rest is D6's per-fact proof and T3's per-claim evidence.
- **D5:** not now, behind a fixed trigger.
- **Proof:** add P (proof-only, 0 neurons), proxy mode (branch code without a deploy), B1-D6 and B2-D6 for soundness, and the route-on run with packets. Gates are fixed in section 5.
- **D6** (the owner's): placed as the vignette route generalised, with a gated server-side proposer.

## 9. Sources cited

**red-pen-ios**
- server/accuracy.js, evidence.js, proof.js, vignette-proof.js, lexicon.js, oath.js, provenance.js, accuracy-model.js, ai.js, switches.js:121-127, wrangler.toml:150-154
- plan.md:1773-1851
- docs/verification/why-not-verified.md, vignette-proof-research.md (§4.1-§4.9, R1 :82 and :274)
- tools/verification-bench/layer.mjs, vignette-proof-mutations.mjs; tools/criteria/stub-proposer.mjs; tools/proof-ladder/ladder.mjs

**Chat-me**
- docs/architecture/handoff/plan.md §8 (:528-529, :532, :547, :555)
- audit/task4-chat-me-audit.md:33
- research/16a-dna-brief.md:160, :346-347
- 17-islamic-verification-brief.md rows 13, 17, 20 and §2 L
- 22a-jev-brief.md (Jev never the sole verdict)
- 22f-fail-safe-brief.md (AI/ML fail-safes, :89)
- 22g-langgraph-brief.md:59, :93
- 23e-askmed-brief.md:84-85, :177, :195

**Bench run 38554454303 (verification-bench-results)**
- right: 26 fail only backed; wrong: 0 fail only backed, and solved fails on all 90
- votes on the evidence: none 372, supports 48, contradicts 0
- 167 of 180 checks showed 2 evidence entries
