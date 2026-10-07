# Pipeline and verification completion evidence

This closes the **mechanical scaffold** scope of B2–B5 and C3–C5. It does not claim a medical dataset ingestion, external terminology lookup, deployed graph database, grounding judgment, or L4 decision.

## Implemented scope

- B2: durable atomic per-item ETL checkpoints, content-addressed versions, Unicode normalization and tokenization, optional RGB PNG standardization, source/item license evidence gates, exclusion flags, label/split/statistics fields. Changed image bytes or adapter versions invalidate cache; corrupt objects are rebuilt. CLI now accepts `--image-adapter module:function --image-adapter-id version` while retaining the default Pillow implementation.
- B3: caller-schema annotation validation and atomic JSONL export. Ambiguous or duplicate manifest IDs now fail before export. The separate browser annotation interface remains a caller-schema editor, with no medical labels supplied here.
- B4: caller extractor callbacks produce validated, deduplicated `(head, relation, tail)` records with exact qualified manifest IDs. UMLS/SNOMED CT/ICD11 adapters remain explicit; `entity-stub --adapter module:function` now exposes configured adapters through the CLI instead of always returning unresolved.
- B5: parameterized Cypher node/relationship plans, supplied relation allowlists and embeddings, shared graph/vector IDs and revision stamps. Input order no longer changes the plan revision. New `graph-check PLAN.json READBACK.json` checks supplied node/relationship/vector ID completeness, non-dangling endpoints, duplicates, and revision stamps. It checks synchronization markers, not every stored property or embedding value. It reports `scope: caller_supplied_readback`; it does not connect to a database or prove who supplied the readback. Readback must be scoped to the plan's entities and relationships.
- C3: external cue detector with caller configuration, exact character-span validation, and an explicitly absent semantic verdict.
- C4: external grounding evaluator with exact evidence joins and rejection of citations outside supplied evidence.
- C5: deterministic evidence packages with isolated provenance/layer payloads and L4 always pending for Claude.

## Verification

Run from `prework/medical-assistant`:

```sh
/workspace/tools-venv/bin/python -m unittest discover -s tests -v
/workspace/tools-venv/bin/ruff check scripts/prework.py tests/test_prework.py
/workspace/tools-venv/bin/ruff format --check scripts/prework.py tests/test_prework.py
```

Outcome: **29 tests passed with no skips; Ruff checks/format passed**. `tests/test_prework.py::PipelineCompletionTests.test_synthetic_cli_pipeline_preserves_provenance_and_pending_review` runs the real ETL → annotation → extraction → entity adapter → L2 → L3 → L4 CLI chain and graph-plan → graph-check with temporary synthetic adapters. It asserts that manifest evidence IDs survive extraction/packaging and L4 stays pending. Synthetic image bytes test the adapter boundary; a separate Pillow 11.2.1 test exercises actual RGBA → RGB PNG decoding/encoding, output dimensions, and recovery of a corrupted stored image. No synthetic outputs are installed as real manifests.

Additional coverage verifies interrupted ETL resume, unchanged-file mtimes, changed input/image/adapter versions, corrupted object recovery, source exclusions, traversal/symlink escape rejection, invalid annotations preserving prior exports, exact extraction evidence, malformed spans, missing external evaluators, vector dimensions/finite numbers, parameterized graph writes, missing relationship readbacks and stale revisions.

## External inputs still required for real runs

- Item-specific source evidence and licensed source files. Synthetic fixture attestations are never evidence about IDC/NIH/CBIS-DDSM/LibreTexts/Springer.
- Claude's label schema, terminology mapping choices, cue configuration, relation allowlist, and semantic evaluator decisions.
- Configured extraction/grounding/terminology callbacks and credentials; terminology licensing/access where applicable.
- Caller-selected graph/vector stores, embeddings/dimensions, transaction/upsert execution, and real readback data. This task requested a graph builder scaffold; no database product or deployment architecture was selected.
- Pillow for the default image adapter; custom image adapters remain supported.

No medical claims, design system, final student copy, or approval decisions were authored. No orchestrator was triggered. Assigned routing was Sol 6.1 high; the worker used its inherited model context, and no CLI model switch or escalation was performed.
