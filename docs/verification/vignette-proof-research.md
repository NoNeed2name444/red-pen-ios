# Proving a vignette answer correct, fail-closed

14 October 2026. A research note for Stethoscore's verifier (red-pen-ios, branch `origin/design/verify-mechanisms` at 71e76321). Read-only: nothing was committed.

**The question.** What is the best fail-closed way to prove that the key of a clinical-vignette question is correct, so that a "Verified" mark stays about 99.999% right, without loosening any gate?

**The short answer.** Use a **proof-carrying item with a deterministic checker**. An untrusted model, from any family on any free tier, proposes a structured proof. A small deterministic checker accepts it only when three things hold:

1. Every patient finding is a verbatim span of the vignette, with no negation, hedge or family-history cue near it.
2. Every medical premise is a word-for-word quote that `proof.js` already proves against an official source, or a reviewed, quoted criteria or decision rule from a registry.
3. Every inference applies one of those rules mechanically, and **every distractor is eliminated** in the same way.

Anything the checker cannot decide fails, and the item stays at "Check this". All existing gates stay as they are: three blind families, no dissent, provenance holds, oath grade and sensors. The model checkers, NLI and conformal methods serve only as hold-only sensors or as measurement, never as proof. Coverage will be small, and it is UNKNOWN until a pilot measures it. Public data cannot show 99.999% for vignette Verified as a whole. It can show the checker's soundness at about 10⁻⁵ to 10⁻⁶ scale by mutation and adversarial benches. The owner must agree that a mechanically checked deduction from verbatim premises counts as "proven" (proof-plan.md, item 3).

---

## 0. Where the verifier stands (from the repo)

- `server/accuracy-model.js` `verdict`: Verified needs p ≥ threshold, `clean`, `enough`, `backed` (= `source_proof`), `independent` (3 families), `unanimous`, and, for a question, `solved` (3 blind families reach the key and none goes elsewhere).
- `server/proof.js` `mcqClaims`: it returns `{why:'stem'}` unless the stem is one sentence of 30 words or fewer, has a best-answer cue (`most|first-line|of choice|only|gold standard`) and has no negation. Every vignette therefore stops at `stem`: 88 of the 90 right keys in bench run 38554454303 (why-not-verified.md). `fullyProven` is the only route to `backed`.
- `server/accuracy.js` `UNPROVABLE` gives the honest reason ("cannot be proven word for word"). `server/provenance.js` adds hold-only isnad, rijal, shadh, tafarrud, conflict-of-interest, dabt and ʿilal checks. `server/oath.js` makes a diagnosis or treatment an oath item, which needs a grade-5 source (label, guideline, systematic review).
- Measured so far: the proof gate never proved a mutated statement (0 of 906,828; proof-mutation-bench.md), and 90 of 90 planted wrong keys were kept out. Verified as a whole has no measured accuracy, because nothing reached it (proof-plan.md).
- Without the proof, 26 right keys and 0 wrong keys met every other condition. The proof is the binding gate for vignettes.

The design briefs that bind any answer:

- **§16a DNA rule 1.** Independence multiplies, correlation does not. Each layer's catch rate is measured, not assumed.
- **§16a rule 3.** Fail closed: a sensor that cannot run never counts as "no damage".
- **§17 row 1 (isnad).** A chain per claim: claim → passage → source → retrieval → checker.
- **§17 row 13 (matn).** Check the content separately from the chain.
- **§17 row 17 (tahqiq, no talfiq).** Never build a statement no witness makes, and label a synthesis as one.
- **§17 row 20 ("la adri").** Abstaining is a correct answer.
- **§17 §2 L.** P0 (oath) items rest only on sahih-grade evidence.
- **§22a.** Jev is never a sole verdict or a diagnosis grade, and every gate is tuned on about 300 labels.

---

## 1. Why vignettes resist a quote

A vignette answer is a **deduction**. Patient findings (age, sex, symptoms, signs, labs, timeline) are combined with general medical knowledge ("criteria for X are…", "first-line for X is…", "Y is contraindicated in Z") to reach the best option, and the option is best only because the other options are worse. So no single sentence anywhere states "this 34-year-old with these findings has X".

A proof therefore has three kinds of parts:

| part | what it is | what can prove it word for word |
|---|---|---|
| finding leaves | "temperature 39.2 °C", "pregnant at 30 weeks", "denies chest pain" | **the vignette itself**: an exact span of the stem |
| knowledge leaves | "Duke criteria: …", "X is indicated for Y", "contraindicated in pregnancy" | an official source: `proof.js` (FDA label, MedlinePlus) or a registry rule quoted from a guideline |
| steps | findings + rule ⇒ conclusion; distractor ⇏ | **a mechanical rule application**, or else a model's judgment (not proof) |

Every route below differs only in how it checks the **steps**. The steps are where 99.999% is won or lost.

---

## 2. The routes

For each route: how it works, the evidence, the cost on free tiers, how it fits the gates and the isnad, and how it fails.

### R1. Claim decomposition, then per-claim verification (FActScore, SAFE, VeriScore, MedScore)

**How it works.** A model splits a text into atomic claims, and each claim is checked against retrieved evidence by a model or an NLI step. For a vignette, decompose the explanation (or a model's rationale) into finding → inference claims and check each one.

**Evidence.**

- **FActScore** (Min et al., EMNLP 2023): an automated estimator with "less than a 2% error rate". That figure is the error of the **aggregate score**, not the per-claim accuracy, so it says nothing about any single claim being right. [ACL](https://aclanthology.org/2023.emnlp-main.741) · [arXiv](https://arxiv.org/pdf/2305.14251v1)
- **SAFE** (Wei et al., DeepMind 2024): agreed with crowd annotators on 72% of about 16,000 facts. On 100 disagreements SAFE was right 76% of the time. [arXiv 2403.18802](https://arxiv.org/abs/2403.18802v2)
- **VeriScore** (Song, Kim, Iyyer 2024): checks only "verifiable" claims, and its scores vary across tasks. [arXiv 2406.19276](https://arxiv.org/abs/2406.19276)
- **MedScore** (Huang et al., ACL Findings 2026): condition-aware medical decomposition finds up to 3× more valid facts. Its scores "substantially vary by decomposition method, verification corpus, and backbone LLM". [arXiv 2505.18452](https://arxiv.org/abs/2505.18452) · [ACL](https://aclanthology.org/2026.findings-acl.693/) · [code](https://github.com/Heyuan9/MedScore)
- **MedSNIP** (2026): **USMLE vignettes from MedBullets with physician true/false labels**. The best F1 for catching false claims was **0.431** (GPT-5.4, human snippets) and 0.321 on atoms. Retrieval-augmented verification at τ ≥ 0.90 reached 0.55 to 0.61 F1 at about 61 to 63% coverage. Licensed CC BY 4.0. [arXiv 2609.12884](https://arxiv.org/html/2609.12884v1) · [HF dataset](https://huggingface.co/datasets/MBZUAI/MedSNIP)
- **Decomposition noise** (Hu, Long and Wang, NAACL 2025): decomposition trades accuracy gains against the errors it introduces (context loss, over-fragmenting). [ACL](https://aclanthology.org/2025.naacl-long.320)

**Cost on free tiers.** One decomposition call plus one verification call per claim. A vignette makes 5 to 15 claims, so about 10 to 20 calls per item. That is too many for Workers AI's free 10,000 neurons a day. On Claude it is about $0.05 to $0.15 an item.

**Fit.** Decomposition maps onto the isnad (one chain per claim). But the checker is a model, so the chain ends in model judgment ("wijada", §17 row 19), which `proof.js` deliberately refuses.

**Failure modes.**

- Error detection on vignette claims is far below the bar (F1 0.43).
- Decomposition drops conditions ("in pregnancy").
- Retrieval misses.
- The verifier is correlated with the generator.

**Verdict.** It cannot carry Verified. Its *structure* (atomise and keep conditions) is reused in the recommended route. As a model-run step it is a hold-only sensor.

### R2. Entailment chains, proof trees and medical NLI (EntailmentBank, NLProofS, MedNLI, SciFact, HealthVer)

**How it works.** Build a tree whose leaves are facts and whose internal nodes are entailed by their children. Each step is checked by an NLI model or a verifier.

**Evidence.**

- **EntailmentBank** (Dalvi et al., EMNLP 2021): elementary science, 1,840 trees. The best model's trees were perfect in only **35%** of cases, even when given exactly the relevant sentences. [arXiv 2104.08661](https://arxiv.org/abs/2104.08661)
- Later work trains a step verifier and searches for trees: NLProofS, [arXiv 2205.12443](https://arxiv.org/abs/2205.12443). Human-judged correctness was well above gold-tree matching (58% vs 35.6%), so automatic step scoring is itself unreliable. [arXiv 2211.00614](https://arxiv.org/pdf/2211.00614)
- No medical entailment-tree dataset was found.
- **MedNLI** accuracy is in the high 80s (GPT-4 86.6, Claude-3.5 82.1; GatorTron 90.2). [arXiv 2408.12547](https://arxiv.org/pdf/2408.12547) · [npj DM](https://www.nature.com/articles/s41746-022-00742-2)
  - Access needs PhysioNet credentialing and a data use agreement. [PhysioNet](https://physionet.org/content/mednli/)
- **SciFact** macro-F1 is about 0.88. **HealthVer** is about **0.48 to 0.65** at best (fine-tuned Mistral-7B 65.2; GPT-4o 53.2; GPT-5 42.4). [arXiv 2606.12854](https://arxiv.org/pdf/2606.12854) · [SciTePress](https://www.scitepress.org/Papers/2024/129000/129000.pdf)
- A step verifier for clinical reasoning: **Med-PRM** (EMNLP 2025) verifies each reasoning step against retrieved guidelines and literature. It lifts 8B models by up to 13.5%, to **80.35% on MedQA**, and is "closely aligned" with clinicians in qualitative review. It is a reranker, not a certifier. [ACL](https://aclanthology.org/2025.emnlp-main.837.pdf)
- **SymDiag** (2026) translates chain-of-thought into symbolic constraints and checks each step's satisfiability. [arXiv 2608.08786](https://arxiv.org/pdf/2608.08786)
- **Grading the Graders** (2026): a kernel can check a proof, but the formalisation of the statement (its case coverage) is left unverified. This "completeness blind spot" also appears in diagnosis. [arXiv 2608.19009](https://arxiv.org/pdf/2608.19009)

**Cost.** A DeBERTa-class NLI model runs free on CPU in GitHub Actions. Workers AI has no NLI cross-encoder, so live use needs an LLM call per step.

**Fit.** The tree is exactly the isnad shape (each node a claim with its own chain). The weak link is the step checker.

**Failure modes.**

- NLI errors run at 10⁻¹ to 10⁻², four orders above the bar.
- Negation and number blindness (§22a lists the same for Jev).
- Medical NLI doesn't transfer across domains (MedNLI-tuned models do worse on scientific claims; [HF card](https://huggingface.co/shidey/deberta-v3-mednli-scifact-open-sentence-nli)).

**Verdict.** Keep the **tree** as the proof format. Replace model-judged steps with **rule-instance steps** that a program checks (R4). NLI may only veto.

### R3. Answer-choice elimination: proving every distractor wrong

**How it works.** Turn each option into a statement ("The most likely diagnosis is Y") and prove each distractor false, not just the key true. For "one best answer" this is logically necessary. Without it, a proof of the key's plausibility is not a proof that it is the *best* option.

**Evidence.**

- Models "may perform MCQA by selecting the least incorrect option". When options become true/false statements, accuracy on the false (distractor) statements drops. [arXiv 2402.01349](https://arxiv.org/abs/2402.01349)
- A MedQA true/false variant (250+/250−) exists in ART. [arXiv 2601.05455](https://arxiv.org/pdf/2601.05455)
- **MetaMedQA** (Griot et al., Nature Communications 2025): every model tested rarely chose "none of the above / I don't know" when the right answer was missing (GPT-4o 3.7%), so models cannot be trusted to eliminate. [RePEc](https://ideas.repec.org/a/nat/natcom/v16y2025i1d10.1038_s41467-024-55628-6.html)
- **MedJudgeRAG** (2026) judges each option against evidence. [arXiv 2607.24838](https://arxiv.org/pdf/2607.24838)
- `proof.js` already has the strict half: `statedBy` makes a source that *may* state a distractor stop the proof (`'distractor'`).

**Cost.** One step per distractor: 3 to 4 for MedQA, 9 for MedXpertQA's 10 options.

**Fit.** It is the hadith "no shudhudh" condition (§17 row 7) applied to options: nothing stronger contradicts the key. The VeriDx rule "absence of evidence is not evidence of absence" ([arXiv 2609.14018](https://arxiv.org/html/2609.14018v1)) sets the fail-closed rule. A distractor is eliminated **only by an explicit contrary span** in the vignette, never because a finding is not mentioned.

**Failure modes.**

- Exam distractors are often "plausible but less likely", which is a probabilistic judgment with no explicit contrary finding. Those items cannot be proven, and that is correct (la adri).
- MedXpertQA's 10 options make full elimination rare.

**Verdict.** It is a **required component** of any vignette proof. On its own it is not a route.

### R4. Guideline or criteria proof: matching the vignette against published criteria and decision rules

**How it works.** A registry of formal criteria sets and decision rules (Duke, Light's, Centor, CURB-65, Ottawa ankle, Sepsis-3 SOFA rise, KDIGO AKI stages, FDA label indications and contraindications). Each criterion is tied to a word-for-word quote from its source. The vignette's findings fill the criteria's slots, the rule fires, and its conclusion must equal the key.

**Evidence.**

- **ProCDS** (MICCAI 2025): protocols become Prolog rules and patient data become facts, giving transparent inference. [Springer](https://link.springer.com/chapter/10.1007/978-3-032-05127-1_40)
- **CPGPrompt** tests LLMs applying guideline criteria (single, multiple, exclusion) to vignettes. [arXiv 2601.03475](https://arxiv.org/pdf/2601.03475)
- **MedGUIDE**: LLMs underperform on structured guideline adherence. [OpenReview](https://openreview.net/pdf/07c2a85f2355803fe92312f6a9808c0e5065ddef.pdf)
- **VeriDx** (2026): disease profiles built from 2,563 respiratory guidelines, with obligations scored as satisfied, unresolved or violated. Without profiles its scores halve (D2 0.68 → 0.36). Its acceptance precision was not reported. [arXiv 2609.14018](https://arxiv.org/html/2609.14018v1)
- **MedCalc-Bench** (NeurIPS 2024): 55 calculators, licensed CC-BY-SA 4.0, with step-by-step ground-truth explanations and Python implementations. GPT-4 scored only 50.9%, and severity indices were hardest. [arXiv 2406.12036](https://arxiv.org/pdf/2406.12036) · [GitHub](https://github.com/ncbi-nlp/MedCalc-Bench)
- **The audit that matters most here** (Scalable Stewardship, 2025): at least **27%** of MedCalc-Bench's test labels were wrong or incomputable. On a 50-item physician-checked subset the original labels matched only 20% of the time. The causes were **feature-extraction errors, wrong aggregation code, and questions not answerable from the context**. [arXiv 2512.19691](https://arxiv.org/html/2512.19691)
  - Lesson: the rule engine is easy. The **extraction of findings** and the **transcription of the rule** are where errors enter. Both must be made checkable: span-anchored extraction, and double-transcribed, reviewed rules.
- Guideline access helps models: coherence with HBV guidelines rose from 51% to 91%. [PubMed 40891225](https://pubmed.ncbi.nlm.nih.gov/40891225/)

**Cost.** The checker is pure code with zero marginal cost and runs in the Worker. Proposing the proof (extract spans, pick a rule, map options) takes one LLM call per vignette, done offline. The registry is a one-time human effort: a few hundred rules, each reviewed.

**Fit.** The best fit with the isnad:

- **finding claim** → span of the stem (sama', heard directly) → the item itself → `retrieval: verbatim-span` → checker v1;
- **rule claim** → quoted passage → registry source (rijal grade; oath items need grade 5) → `retrieval: quoted` → `proof.js`;
- **step** → rule id and version → deterministic checker.

The conclusion is a **synthesis**, so §17 row 17 (no talfiq) requires that it be *labelled* as a deduction, never presented as one source's words.

**Failure modes.**

1. A rule transcribed wrongly, or an outdated edition (naskh: Duke 2023 replaced modified Duke). Defence: two independent transcriptions compared mechanically, source worked examples as unit tests, and an edition date in the registry with ʿilal checks (`provenance.js`).
2. Extraction: wrong span, a negated finding, a family member's finding, a past finding. Defence: exact spans plus a deterministic negation, hedge, subject and time window that fails closed.
3. Subjective criteria ("alternative diagnosis less likely than PE" in Wells; "clinical judgment"). Defence: such criteria cannot fire, so the rule cannot complete.
4. Scope (adult vs child, pregnancy). Defence: scope must be met by an explicit span.
5. Coverage: many vignettes ask "most likely" among options that no criteria set separates. They stay unproven.
6. Licensing: US federal guidelines (CDC, NIH, USPSTF, AHRQ) and FDA labels are public domain. StatPearls is CC BY-NC-ND 4.0 ([NCBI](https://ncbi.nlm.nih.gov/books/NBK560662/figure/article-32174.image.f1)), which is a problem for a paid Pro app, and it ranks below grade 5 for oath items in any case. Professional-society guidelines are copyrighted: short quotations with attribution need review.

**Verdict.** It is the **only route whose step checker can be made deterministic**, so it is the backbone of the recommendation.

### R5. Knowledge-graph or UMLS/SNOMED path proofs

**How it works.** Map vignette entities to concepts, then find a path in a KG (disease–symptom, drug–indication, drug–contraindication) from the findings to the answer.

**Evidence.**

- **MedReason** (2025) builds 32,682 thinking paths over **PrimeKG**. It keeps a path only if an LLM judges it relevant, and a CoT only if another LLM can reach the gold answer from it, so its "verification" is model judgment. The 8B model reaches 57.3% on hard benchmarks. [arXiv 2504.00993](https://arxiv.org/abs/2504.00993) · [GitHub](https://github.com/UCSC-VLAA/MedReason)
- DR.KNOWS and RRAG retrieve UMLS paths for diagnosis. [arXiv 2506.05386](https://arxiv.org/pdf/2506.05386)
- A KG edge has no population, dose or condition, and its provenance is usually a database rather than an official sentence.

**Licensing.** UMLS is free, with an individual licence; the SNOMED CT affiliate terms apply, and use in non-member countries must be reported or may carry fees. Clients of a product built on UMLS also need a licence. [NLM FAQ](https://www.nlm.nih.gov/research/umls/faq_main.html) · [SNOMED licensing](https://www.nlm.nih.gov/healthit/snomedct/snomed_licensing.html)

**Cost.** Free for compute, but an offline KG build plus licence paperwork.

**Fit.** In rijal terms an edge is a "majhul" source (weak grade), so it can never be a proof leaf for an oath item.

**Failure modes.**

- Incomplete or outdated edges.
- Paths that exist for wrong answers too (KGs are dense).
- Conditions dropped.

**Verdict.** Use it only as a **synonym and normalisation lexicon** (a curated, small subset) and as a proposer aid. It is never a proof.

### R6. Multi-agent or independent-family agreement

**How it works.** Several models from different families solve the question blind, and agreement counts as evidence. The repo already requires 3 blind families with no dissent.

**Evidence.**

- **Correlated errors** (Kim et al., ICML 2025): across 350+ LLMs, models agree on 60% of the items where both are wrong. Errors converge as models get better. [arXiv 2506.07962](https://arxiv.org/abs/2506.07962)
- **Nine Judges, Two Effective Votes** (Kohli, 2026): 9 frontier models from 7 families on NLI carry **n_eff ≈ 2.18** votes, with mean error φ 0.391. 5.1% of items had all nine judges wrong, against fewer than 1 expected if they were independent. [arXiv 2605.29800](https://arxiv.org/pdf/2605.29800) · [Apple ML](https://machinelearning.apple.com/research/correlated-llm-evaluation-panels)
- **Unanimously Wrong** (2026 preprint): 8 samples of one 8B model, multi-round RAG. **13.4%** of unanimous answers on MedQA were wrong, 17.7% on MMLU-Pro medicine, 22.3% on MedMCQA and **79.0% on MedXpertQA**. Terminal agreement had AUROC ≈ 0.51 for spotting them. [arXiv 2610.07570](https://arxiv.org/html/2610.07570v1)
  - Caveat: same-model samples, not different families. It is an upper bound on how bad agreement can be.
- The repo's own result: 28 right keys and 0 wrong keys had three blind families agree (why-not-verified.md). That is too few to bound anything below about 10%.

**Cost.** This is the existing bottleneck. The third family answers on only 36 of 90 (proof-plan.md).

**Fit.** Tawatur requires independent chains (§17 row 11). LLM families share training data, which is the common-link problem (§17 row 10), so three families are worth fewer than three witnesses.

**Failure modes.** Shared misconceptions, especially at the hard end (79% unanimous-wrong on MedXpertQA), and benchmark-style priors.

**Verdict.** Keep it as a **necessary** gate (it already is) and never treat it as sufficient. It stays in the recommendation unchanged.

### R7. Selective prediction and conformal risk control

**How it works.** Calibrate a score threshold on labelled data so that the error rate among the items you commit to is at most α with probability 1 − δ. Methods include Learn-then-Test, conformal risk control and conformal factuality (dropping low-score sub-claims).

**Evidence.**

- **Conformal factuality** (Mohri and Hashimoto, ICML 2024). [arXiv 2402.10978](https://arxiv.org/abs/2402.10978)
  - Its guarantee is not conditional, and it filters out many true claims (Cherian, Gibbs, Candès, NeurIPS 2024). [arXiv 2406.09714](https://arxiv.org/pdf/2406.09714)
  - **Coherent factuality** (ICLR 2025) extends it to reasoning chains with a deducibility graph, but the graph is model-made and not guaranteed. It reached 90% factuality while keeping about 80% of claims on MATH. [arXiv 2505.17126](https://arxiv.org/html/2505.17126)
- **Learn-then-Test** [arXiv 2110.01052](https://arxiv.org/abs/2110.01052) and **conformal risk control** [arXiv 2208.02814](https://arxiv.org/abs/2208.02814). Conformal abstention for hallucinations: [arXiv 2405.01563](https://arxiv.org/pdf/2405.01563). COIN: [arXiv 2506.20178](https://arxiv.org/pdf/2506.20178).
- In medicine, the stratified LTT of Unanimously Wrong certified 55% coverage at α = 0.15 (9.0% realised risk) on MedQA's unanimous stratum. With n = 875 in-domain calibration items it certified 21.9% coverage at α = 0.10. **Global LTT certified no threshold at all.** [arXiv 2610.07570](https://arxiv.org/html/2610.07570v1)
- **Limits** (Kotte 2026): if the base error μ exceeds α, any distribution-free method must abstain on at least (μ − α)/(1 − α) of inputs. Under cross-dataset shift, static CRC "often violates the target". [arXiv 2606.29054](https://arxiv.org/abs/2606.29054)
- The arithmetic: certifying α = 10⁻⁵ at δ = 0.05 needs about 3/α ≈ **300,000 labelled, exchangeable calibration items with no error among those committed to**, the same rule of three as proof-plan.md. No public medical labelled set is that large or that clean.

**Cost.** The calibration labels cost the same as the bench. Scoring itself is cheap.

**Fit.** It is a **measurement and tiering tool**, not a proof. It fits DNA rule 1 (measure each layer).

**Failure modes.**

- Exchangeability breaks between benchmark vignettes and the app's items.
- Label noise in the calibration set (below).
- Guarantees are marginal, not per item.

**Verdict.** Use it to set and report a **lower tier** ("Checked: error ≤ 1% at 95%"), if the owner wants one, and to design the bench. It cannot reach 10⁻⁵ and must not touch Verified.

### R8. How 2024–2026 medical QA verification papers handle vignettes

| paper | how it handles vignettes | what it proves |
|---|---|---|
| Med-PRM, EMNLP 2025 ([ACL](https://aclanthology.org/2025.emnlp-main.837.pdf)) | step rewards conditioned on retrieved guidelines | ranks reasoning; no certificate |
| MedReason, 2025 ([arXiv](https://arxiv.org/abs/2504.00993)) | KG paths from question entities to answer, LLM-filtered | training data quality |
| VeriDx, 2026 ([arXiv](https://arxiv.org/html/2609.14018v1)) | disease profiles → obligations: satisfied, unresolved, violated; absence ≠ evidence | process quality; no acceptance precision |
| MedSNIP, 2026 ([arXiv](https://arxiv.org/html/2609.12884v1)) | vignette answers split into snippets, physician T/F | error-detection F1 ≤ 0.43 on vignettes |
| MedScore, 2025–26 ([arXiv](https://arxiv.org/abs/2505.18452)) | condition-aware atomic facts | a factuality score, not per-item proof |
| Unanimously Wrong, 2026 ([arXiv](https://arxiv.org/html/2610.07570v1)) | process features plus counter-evidence probe; stratified LTT | a certified abstention rate at α ≥ 0.10 |
| MedCaseReasoning, 2025 ([arXiv](https://arxiv.org/abs/2505.11733)) | 14,489 case-report cases with clinician reasoning statements; "reasoning recall" | best open model recalls 64% of clinician reasoning |
| HuatuoGPT-o1, ACL Findings 2025 ([ACL](https://aclanthology.org/2025.findings-acl.751/)) | an LLM verifier against a known answer | training signal |
| MedFuzz ([arXiv](https://arxiv.org/abs/2406.06573)), MedPerturb ([arXiv](https://arxiv.org/pdf/2506.17163)) | rewritten or perturbed vignettes flip answers | robustness, not proof |

**Finding.** No 2024–2026 paper certifies vignette answers anywhere near 10⁻⁵. Every model-judged verifier reported runs at 10⁻¹ to 10⁻² error. The only designs that aim for soundness are neurosymbolic: ProCDS, SymDiag, VeriDx's profiles, and the clinical-trial matcher with logical verification ([arXiv 2606.20895](https://arxiv.org/pdf/2606.20895)). Their open problem is the same as here: the **formalisation and extraction gap**.

### Ground truth is noisier than the bar

The labels used to measure any route are themselves noisy:

- **MMLU-Redux**: an estimated 6.49% of MMLU questions are erroneous, and 57% of the analysed Virology questions. [arXiv 2406.04127](https://arxiv.org/pdf/2406.04127v1) · [HF](https://huggingface.co/datasets/edinburgh-dawg/mmlu-redux-2.0)
- **MedQA**: Med-Gemini re-rated MedQA for missing information, label errors and ambiguity, and released the relabelling. [arXiv 2404.18416](https://arxiv.org/pdf/2404.18416) · [HF](https://huggingface.co/datasets/katielink/med-gemini-medqa-relabeled)
- A 2026 JMIR study found **41%** of o1's MedQA "errors" were benchmark problems. [JMIR](https://www.jmir.org/2026/1/e90061/PDF)
- **MedCalc-Bench**: at least 27% of test labels are bad (above).

So every "wrong Verified" found on a public set must be adjudicated before it counts, and a run against raw labels cannot even show 99.9%.

---

## 3. How the routes compare against the bar

| route | step checker | error at the step | free-tier cost | can carry Verified? | role |
|---|---|---|---|---|---|
| R1 decomposition + model verify | LLM | 10⁻¹ (F1 0.43 on vignettes) | high | no | hold-only sensor; decomposition shape reused |
| R2 entailment tree + NLI | NLI or LLM | 10⁻¹ to 10⁻² | low offline | no | proof *format*; NLI veto only |
| R3 elimination | depends | – | ×options | – | **mandatory component** |
| R4 criteria and rules | **deterministic code** | set by extraction and transcription; measurable to 10⁻⁵ to 10⁻⁶ | proposer: 1 call offline; checker: free | **yes, on the subset it covers** | **backbone** |
| R5 KG/UMLS path | graph search | unknown; weak provenance | free + licence | no | lexicon and proposer aid |
| R6 family agreement | vote | correlated (n_eff ≈ 2 of 9) | bottleneck today | necessary, not sufficient | keep unchanged |
| R7 conformal and LTT | statistics | certifies only α ≳ 10⁻² with public n | labels | no (lower tier only) | measurement and tiering |

---

## 4. Recommendation: proof-carrying vignettes (R4 + R3 + R2 format), all existing gates kept

### 4.1 The idea

"The proposer is untrusted, the checker is trusted": the de Bruijn criterion and proof-carrying code (Necula, POPL 1997).

- Any free model may write the proof. Being wrong costs only coverage, never accuracy.
- The **checker** is a small, deterministic, fully tested program. It is the only thing whose soundness must be measured, and because it costs nothing to run it can be measured with millions of mutations.
- This is the same move `proof.js` already makes: text, not meaning.

### 4.2 The proof packet (stored with the item, made offline)

```json
{ "v": 1, "item": "<id>", "key": 2,
  "findings": [ { "id": "f1", "at": [112, 131], "text": "temperature of 39.2°C",
                  "slot": "temp_c", "value": 39.2 } , ... ],
  "rules":    [ { "id": "duke-2023-major-1", "ver": "2023-08", "src": "<registry id>" } ],
  "proves":   { "rule": "duke-2023", "uses": ["f1","f3","f4"], "concludes": "infective endocarditis" },
  "eliminates": [ { "option": 0, "rule": "<rule or label quote id>", "uses": ["f7"], "violates": "requires ..." }, ... ] }
```

### 4.3 The checker's fail-closed conditions (`server/vignette-proof.js`, new, pure JS)

The checker returns `{v, ok, why}`. `ok` is true only when **all** of the following hold. Anything else returns a typed `why` and the item stays at "Check this".

1. **The stem is unchanged**: the item's stem hash equals the packet's. A stale packet is refused, the same idea as the CLAUDE.md stale-task rule.
2. **Every finding is a verbatim span.**
   - `stem.slice(at)` equals `text` after `proof.js` `normalize`.
   - There is no negation, hedge or uncertainty cue in a fixed window: "no", "denies", "without", "negative for", "absent", "unremarkable", "rule out", "?", "possible", "suspected".
   - There is no other-subject cue: "mother", "father", "sibling", "family history".
   - There is no past-time cue unless the rule asks for history: "history of", "previously", "years ago".
   - Numbers are parsed by a unit table. Anything `unreadableNumber` refuses is unprovable.
3. **Every slot maps to the rule's antecedent** through a curated, versioned lexicon (`server/lexicon.js`) of exact surface forms per slot. There is no fuzzy matching and no model step. A surface form not in the lexicon means unprovable.
4. **Every rule comes from the registry** (`server/criteria/*.json`), and each entry carries:
   - an id and an edition date;
   - its source as a `provenance.js` rijal entry (grade 5 for a diagnosis or treatment, per `oath.js` and §17 §2 L);
   - a verbatim quote for **each criterion**, re-proven at build time by `proof.js` `provenBy` against the fetched source, with the passage hash pinned;
   - its formal antecedents and conclusion, its population scope, and its exclusions;
   - two independent transcriptions that agree mechanically (dabt, §16a rule 1);
   - the source's own worked examples as unit tests;
   - a reviewer and a date.

   A criterion that needs judgment ("alternative diagnosis less likely", "clinically significant") is marked `judgment: true` and **can never be satisfied**.
5. **The rule fires** on the given findings by deterministic evaluation. The scope (age, sex, pregnancy) must be met by spans.
6. **The conclusion equals the key option**, through `proof.js` `declaratives` and `wordings` or a registered alias, never by model similarity.
7. **Every distractor is eliminated by an explicit contrary span** plus a registry rule or an official quote. Examples:
   - an FDA label's "contraindicated in …" quote, which `proof.js` already proves, plus a span showing that condition;
   - the rule's own declared mutually exclusive outcomes, as with CURB-65's score bands.

   A missing finding never eliminates an option (VeriDx: absence ≠ evidence). One uneliminated distractor fails the whole proof.
8. **No stated contradiction.** `proof.js` `statedBy` must not find a source that may state a distractor, as for questions today.
9. **Budget and cost.** A fixed work budget like `PROOF_CHARS`. Running out gives `budget`, never "ok".

### 4.4 Wiring: a new gate feeding the existing one; nothing loosened

- **`server/proof.js`**: no change to `prove` or `fullyProven`. Export the helpers the checker reuses (`normalize`, `declaratives`, `wordings`, `statedBy` are internal or exported today; export what is missing without changing its behaviour).
- **`server/vignette-proof.js`** (new): `checkVignette(item, packet, officials)` and `vignetteProven(p)`.
- **`server/accuracy.js`**:
  - Where `prove()` returns `why: 'stem'` and the item has a packet, run `checkVignette`.
  - Store it as `signals.vignetteProof`.
  - Add the checker's `why` values to `UNPROVABLE` reasons ("no published rule decides this case", "an option could not be ruled out").
- **`server/accuracy-model.js`**:
  - Add a feature `vignette_proof`. Keep `source_proof` as it is.
  - In `verdict`: `backed = source_proof === 1 || (VIGNETTE_ROUTE && vignette_proof === 1)`.
  - **Every other conjunct stays**: `clean`, `enough`, three `independent` families, `unanimous`, `solved` (3 blind families reach the key, no dissent), the p threshold, and the provenance and oath holds.
  - Add a property test like the 3,000-shape provenance fuzz: with `VIGNETTE_ROUTE` off, the verdicts are identical to today's.
- **`server/switches.js`**: `VIGNETTE_ROUTE` off by default. It is turned on only by the owner's word, after the bench below passes.
- **`server/provenance.js`**: an isnad per step.
  - Finding: claim → stem span → the item → `verbatim-span` → `vignette-proof v1`.
  - Rule: claim → quote → registry source → `quoted` → `proof.js`.
  - The conclusion is marked `synthesis: true` (§17 row 17, no talfiq).
  - A rule whose source has an erratum, a retraction or a newer edition holds the item (ʿilal and naskh, §17 rows 9 and 15).
- **The app** (`AccuracyModel.grade`, "rule for rule"):
  - Mirror the new conjunct in Swift.
  - Add the parity case to `tools/verification-bench/parity.swift` and the Linux suites.
  - Show the reason as "Proven step by step from published criteria", distinct from "Stated word for word", so the student sees which kind of proof it is.
- **The proposer** (`tools/vignette-proposer/`, a GitHub Actions workflow, offline):
  - For bank items, one call per vignette on any free model writes the packet; the checker then runs. Packets are cached with the item, and the Worker only runs the checker.
  - Allowed models: Workers AI's free pool, the existing Google checker under its daily ceiling (never Gemini 3.6 Flash), and Claude within CLAUDE_MONTHLY_USD.
  - The proposer may be **any** model, since it is untrusted; independence is still enforced by the blind-solve gate.
- **Hold-only sensors** (they can only demote):
  - an NLI veto (a DeBERTa-v3 NLI model on CPU in Actions) on each step's text;
  - the existing claim gate (`claims.js`);
  - Jev, per §22a, never as a sole verdict.

### 4.5 Measuring it with public labelled data (tools/verification-bench/vignette-proof-*.mjs)

| bench | data | what it measures | target | scale and cost |
|---|---|---|---|---|
| **B1 mutation soundness** | every accepted packet × mutations (negate a span, change a number across the threshold, swap sex or age or pregnancy, move a span to a family member, swap the key to a distractor, drop a criterion, older rule edition) | checker accepts a mutated proof | **0 of ≥ 300,000** (95% upper bound ≤ 1×10⁻⁵) | deterministic, free; as proof-mutation-bench (906,828) |
| **B2 adversarial wrong keys** | MedQA-USMLE ([HF bigbio/med_qa](https://huggingface.co/datasets/bigbio/med_qa)), MedXpertQA ([GitHub](https://github.com/TsinghuaC3I/MedXpertQA)), CareQA, Medbullets and JAMA CC ([GitHub](https://github.com/HanjieChen/ChallengeClinicalQA)) | ask the proposer to **prove each distractor**; count acceptances | 0 accepted; each acceptance adjudicated (it may expose a bad key) | about 15k vignettes × 3 to 9 distractors ≈ 60k to 100k attempts; free tier at about 1,000 a day over 2 to 3 months |
| **B3 rule engine** | MedCalc-Bench **Verified** rule-based calculators ([GitHub](https://github.com/ncbi-nlp/MedCalc-Bench)) | span-anchored extraction + rule = physician-checked label, or refusal | precision 100% on accepted; refusals counted | about 1,000 test items; free |
| **B4 natural precision and coverage** | the above, adjudicated with Med-Gemini MedQA relabels and MMLU-Redux medical subsets | Verified items with a wrong key; share of right keys reaching Verified | 0 wrong; coverage reported (UNKNOWN today) | gives an honest bound such as "0 of n" |
| **B5 extraction** | MedSNIP and MedBullets atomic claims with physician labels ([HF](https://huggingface.co/datasets/MBZUAI/MedSNIP)) | negation, subject and time window false-accept rate on labelled findings | 0 false accepts | about 5,700 labelled atoms; free |
| **B6 rule transcription** | two independent transcriptions per rule + the source's worked examples | disagreement rate; worked-example failures | 0 before a rule enters | one-off |

**What the numbers can honestly say.**

- B1 and B2 bound the **checker's** false-proof rate. With 300,000 mutations and none accepted, that bound is about 10⁻⁵.
- B4 can show only about "0 of a few thousand" for natural vignette Verified, around 99.9% at 95%, because public vignettes number roughly 20k and coverage is partial.
- The 99.999% claim then rests on a **decomposition**:

  P(wrong Verified) ≤ P(checker unsound) + P(rule wrong or outdated) + P(extraction misread) + P(3 families and the proof all wrong together).

  Each term is measured separately (DNA rule 1). Their independence must itself be checked: does B2 find acceptances where the blind families also agreed?
- This should be written up as proof-plan.md's "what we can honestly say" table. It must never be quoted as a measured 99.999% for Verified.

### 4.6 Cost (free tiers; Claude ≤ $90 a month)

- **Checker**: zero marginal cost. It runs in the Worker's CPU budget: string spans plus rule evaluation, far smaller than `PROOF_CHARS`.
- **Proposer**: about 4k tokens in and 1.5k out per vignette.
  - On the cloud checker's price ($4 per M in, $20 per M out, per proof-plan.md) that is about $0.046 a vignette, or about 1,900 a month at the cap.
  - On free tiers (Workers AI's 10k neurons a day; the Google checker under its ceiling) it is bounded by daily quotas.
  - Packets are made once per bank item and cached, so the app's own items cost one proposal each, ever.
- **Registry**: human time. Start with about 30 to 50 high-yield rules and contraindication patterns.
  - Rules: CURB-65, Centor/McIsaac, Ottawa ankle and knee, Light's, Duke 2023, KDIGO AKI, Sepsis-3.
  - Contraindications: openFDA label sections such as 4 and 5, which `proof.js` already reads.
  - Measure coverage on MedQA before adding more.

### 4.7 What stays fail-closed (the checklist)

- `fullyProven` and the word-for-word route are unchanged. The new route is a separate conjunct-alternative behind a switch that is off by default.
- Three blind families, no dissent, provenance holds, oath grade 5, sensors, and the p threshold are all unchanged and all still required.
- The checker refuses on anything it cannot read: an unknown surface form, a cue in the window, a judgment criterion, a missing elimination, a stale stem hash, an over-budget run, a lookup failure, or a rule edition superseded or under concern.
- Models, NLI, KGs and conformal scores can only **hold back**, never pass.
- An item without a packet, or with a refused one, gets the honest UNPROVABLE reason (la adri).

### 4.8 What needs the owner

1. **Agreement that a mechanically checked deduction from verbatim premises is "proven".** This is item 3 of proof-plan.md and why-not-verified.md option 2, in a stricter form: the step is proven too, not left to the families. The label should be shown differently, as a synthesis (§17 row 17).
2. A clinician (or the owner) to review each registry rule. Without review, a rule cannot enter.
3. The licensing choice: public-domain US federal sources and FDA labels first. StatPearls (NC-ND) and society guidelines need a decision, and UMLS/SNOMED only if the lexicon is drawn from them.
4. Whether to add an LTT-certified lower tier (R7) for the rest. That would be a new tier, not a change to Verified.

### 4.9 Known risks and unknowns

- **Coverage is UNKNOWN.** Many USMLE vignettes are "most likely" judgments that no rule decides. The share of MedQA a rule-plus-elimination proof can cover may be small. The first step is a 500-vignette pilot (B4) before building more rules.
- **The formalisation gap** ([arXiv 2608.19009](https://arxiv.org/pdf/2608.19009)): a wrongly transcribed rule is proven "correctly". B6 plus clinician review is the only defence, and it must be counted in the error budget.
- **Guideline drift**: rules need edition tracking and the ʿilal sweep.
- **Correlation across layers**: if the proposer and the blind families share a misconception, the checker still stops it, because the misconception would need a quoted rule to pass. That is the point of a deterministic checker. Check it in B2.

---

## Sources (beyond those inline)

- Repo: `server/proof.js`, `server/accuracy-model.js`, `server/accuracy.js`, `server/provenance.js`, `server/oath.js`, `server/claims.js`, `docs/verification/why-not-verified.md`, `docs/verification/proof-plan.md`, `tools/verification-bench/datasets.mjs` (origin/design/verify-mechanisms 71e76321).
- Chat-me (origin/personal): `docs/architecture/research/16a-dna-brief.md` §2; `17-islamic-verification-brief.md` §1 rows 1, 3, 6, 7, 9 to 11, 13 to 15, 17, 19 and 20, §2 A to M; `22a-jev-brief.md`.
- Wei et al., *Long-form factuality in LLMs* (SAFE): https://arxiv.org/abs/2403.18802v2
- Min et al., *FActScore*: https://aclanthology.org/2023.emnlp-main.741
- Song et al., *VeriScore*: https://arxiv.org/abs/2406.19276
- Huang et al., *MedScore*: https://arxiv.org/abs/2505.18452
- *MedSNIP*: https://arxiv.org/html/2609.12884v1
- Hu et al., *Decomposition Dilemmas*: https://aclanthology.org/2025.naacl-long.320
- Dalvi et al., *EntailmentBank*: https://arxiv.org/abs/2104.08661
- Yun et al., *Med-PRM*: https://aclanthology.org/2025.emnlp-main.837.pdf
- *VeriDx*: https://arxiv.org/html/2609.14018v1
- *SymDiag*: https://arxiv.org/pdf/2608.08786
- *Grading the Graders*: https://arxiv.org/pdf/2608.19009
- *ProCDS*: https://link.springer.com/chapter/10.1007/978-3-032-05127-1_40
- *CPGPrompt*: https://arxiv.org/pdf/2601.03475
- *MedGUIDE*: https://openreview.net/pdf/07c2a85f2355803fe92312f6a9808c0e5065ddef.pdf
- Khandekar et al., *MedCalc-Bench*: https://arxiv.org/pdf/2406.12036
- *Scalable Stewardship* (MedCalc-Bench audit): https://arxiv.org/html/2512.19691
- *MedReason*: https://arxiv.org/abs/2504.00993
- Kim et al., *Correlated Errors in LLMs*: https://arxiv.org/abs/2506.07962
- Kohli, *Nine Judges, Two Effective Votes*: https://arxiv.org/pdf/2605.29800
- *Unanimously Wrong*: https://arxiv.org/html/2610.07570v1
- Mohri and Hashimoto, *Conformal factuality*: https://arxiv.org/abs/2402.10978
- Cherian et al., *Enhanced conformal*: https://arxiv.org/pdf/2406.09714
- Rubin-Toles et al., *Coherent factuality*: https://arxiv.org/html/2505.17126
- Angelopoulos et al., *Learn then Test*: https://arxiv.org/abs/2110.01052
- *Conformal Risk Control*: https://arxiv.org/abs/2208.02814
- Kotte, *When can CRC certify LLM outputs*: https://arxiv.org/abs/2606.29054
- *LLMs may select the least incorrect option*: https://arxiv.org/abs/2402.01349
- Griot et al., *MetaMedQA*: https://ideas.repec.org/a/nat/natcom/v16y2025i1d10.1038_s41467-024-55628-6.html
- Gema et al., *Are we done with MMLU?*: https://arxiv.org/pdf/2406.04127v1
- Med-Gemini MedQA relabel: https://huggingface.co/datasets/katielink/med-gemini-medqa-relabeled
- Chen et al., *JAMA Clinical Challenge / Medbullets*: https://arxiv.org/abs/2402.18060
- *MedCaseReasoning*: https://arxiv.org/abs/2505.11733
- *MedFuzz*: https://arxiv.org/abs/2406.06573
- Xiong et al., *MedRAG/MIRAGE* (StatPearls, textbooks corpora): https://arxiv.org/abs/2402.13178
- MedNLI access: https://physionet.org/content/mednli/
- Small LLMs for SciFact/HealthVer: https://arxiv.org/pdf/2606.12854
- UMLS licence FAQ: https://www.nlm.nih.gov/research/umls/faq_main.html
- Workers AI pricing (10,000 neurons a day free): https://developers.cloudflare.com/workers-ai/platform/pricing/
