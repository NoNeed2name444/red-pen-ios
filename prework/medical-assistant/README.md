# Medical-student assistant

Offline production-prework scaffolds, delivered inside `red-pen-ios` on
`design/prework-20261006`. Development tools and synthetic integration tests are
verified. These modules use caller-supplied contracts and contain no production
medical dataset or final student-facing content. Live provider calls are excluded
from this completion pass at the user’s request. See `docs/*-completion.md` and
the root `HANDOFF.md` for current evidence and remaining external inputs.

## Layout

- `app/`: reserved for application code after design and architecture approval.
- `data/`: reserved for license-qualified inputs; no content is included.
- `docs/`: integration evidence, decisions, and the prework log.
- `scripts/`: offline preparation checks; no provider calls or orchestration.
- `tests/`: standard-library tests for preparation checks.
- `.github/workflows/`: an explicitly dispatched offline scaffold check.

## Offline checks

Requires Python 3.12+ and Node 24. Core checks need no credentials or providers;
install the pinned tools below to include actual image and browser tests:

```sh
python3 scripts/prework.py
python3 -m unittest discover -s tests -v
```

The private npm manifest exposes the same commands as `npm run check` and
`npm test`. It is provisional tooling metadata, not an application architecture.

## Optional development tooling

Ruff, pre-commit and Pillow are pinned in the development dependency group.
Playwright is pinned by `package-lock.json`. From this directory:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install --group pyproject.toml:dev
.venv/bin/ruff check .
.venv/bin/ruff format --check .
npm ci --ignore-scripts
npx playwright install --with-deps chromium
PATH="$PWD/.venv/bin:$PATH" npm test
npm run test:browser
```

The root `.github/workflows/prework-scaffold.yml` provides a manual-only run
using this nested directory. It does not invoke the orchestrator or live models.
The nested `.pre-commit-config.yaml` can be used with `pre-commit run --config
prework/medical-assistant/.pre-commit-config.yaml --files <changed scaffold Python paths>`
from the repository root. It does not replace native repository hooks.

## Provisional ETL (B2)

`python3 scripts/prework.py etl INPUT.jsonl OUTPUT_DIR --assets ASSET_DIR` processes
local caller-supplied records. Every item requires `id` and `source`; `label` and
`split` are caller values or null. Text uses Unicode NFKC, whitespace normalization,
and a simple nonmedical tokenizer. Optional image standardization requires Pillow
or an injected adapter. Pillow is pinned in the development tools and its real
RGB conversion is tested. A custom adapter can be passed as
`--image-adapter MODULE:FUNCTION --image-adapter-id VERSION`.

Each item's `license` must contain an allowed `id` (CC-BY, versioned CC-BY, or
unrestricted), `verified: true`, `scope: "item"`, matching `item_id`, and nonempty
`evidence` objects with matching `item_id`, `url`, and `terms`. These are external
attestations, not automatic legal verification. Missing/disallowed licenses produce
excluded metadata without copied text/images. Source-level B1 claims never qualify
an item. Output contains content-addressed immutable objects, a versioned manifest,
statistics, exclusion flags, and per-item atomic checkpoints. Repeating an unchanged
run preserves outputs; changed records receive new IDs. No live records were supplied.
Resume keys include the current source image bytes and a versioned adapter ID;
custom image adapters must supply `image_adapter_id`. Excluded items are screened
before image paths are read.

## Provisional annotations (B3)

Serve the modules with `python3 -m http.server 8080 --bind 127.0.0.1` from
this directory, open `http://127.0.0.1:8080/app/annotation.html`, then import the
ETL manifest and a caller-authored schema,
then validate/save labels locally or export JSONL. Browser storage availability is
reported; persistence is local to that browser. Offline authoritative validation:
`python3 scripts/prework.py annotate MANIFEST ANNOTATIONS SCHEMA OUTPUT`.
Schemas deliberately support only explicit `type`, `properties`, `required`,
boolean `additionalProperties`, `items`, and `enum`; unsupported keywords fail
closed. This is a mechanical subset, not a complete JSON Schema implementation.
No Claude label schema or medical labels are supplied or approved.
Browser exports remain provisional and require the offline annotation validator,
which rechecks per-item license attestations even when exclusion flags are empty.

Standalone L0 checks use `python3 scripts/prework.py l0 RECORD.json --schema
SCHEMA.json`. The schema argument is optional only so a missing schema can return
`unresolved` with `passed: false`; it never counts as a pass. Results contain
`status`, `passed`, and `errors`. This checks structure against a caller schema
and does not produce a safety verdict.

Standalone L1 checks use `python3 scripts/prework.py l1 RECORD.json RULES.json`.
Rules are a caller-authored object keyed by flat record field names; each value
may provide finite numeric `min` and/or `max` bounds and an optional exact `unit`.
When a unit is specified, the record field must be an object with numeric `value`
and string `unit` keys; otherwise the field is a number. Missing fields, malformed
rules, booleans, non-finite values, and unit mismatches fail. No numeric range,
unit conversion, clinical threshold, or safety verdict is supplied by this check.

## Provisional external extraction (B4)

`python3 scripts/prework.py triplets MANIFEST OUTPUT --extractor MODULE:FUNCTION`
loads a caller-supplied trusted Python callback. Each qualified record is passed to
that callback; it must return objects containing nonempty `head`, `relation`, `tail`
strings and `source_ids` citing qualified manifest IDs, including the current item.
The runner rechecks per-item license attestations, validates evidence references,
deduplicates stable triplet IDs, and atomically exports. It supplies no extractor,
relations, entities, provider, or credentials. `data/manifests/triplets.jsonl` is empty.
`python3 scripts/prework.py entity-stub UMLS QUERY` (also `"SNOMED CT"` and `ICD11`)
explicitly returns unresolved without an external adapter; pass
`--adapter MODULE:FUNCTION` to use a configured resolver. No live terminology
lookup has occurred. Callback code is executed only when explicitly configured by its caller.

## Provisional graph/vector plumbing (B5)

`scripts/graph.cypher` contains Neo4j 5 templates for the four requested node kinds
and indexes. It is not an approved database selection or medical ontology.
`python3 scripts/prework.py graph-plan INPUT.json OUTPUT.json` accepts caller-supplied
`nodes`, `relationships`, `vectors`, `relation_types`, and `dimensions`. Nodes carry
`id`, caller-assigned `kind`, and optional `properties`; relationships carry `id`,
`head`, `tail`, caller-assigned `type`, and optional `properties`. Vectors carry
the same node `id` and externally supplied numeric `values`. No embeddings are generated.

The plan validates missing/duplicate IDs, dangling endpoints, mismatched graph/vector
IDs, vector dimensions, and finite values. All data values are parameters; relationship
type tokens are restricted to an explicit caller allowlist and safe identifier syntax.
A content revision accompanies the graph writes and vector upserts. The caller must
apply both stores, read back IDs and revision, and reconcile retries before marking
synchronization complete. `python3 scripts/prework.py graph-check PLAN.json READBACK.json` checks
caller-supplied graph/vector/relationship IDs and revision markers after writes.
It performs no database calls and provides no cross-store transaction guarantee;
it does not verify stored property or embedding values. No graph/vector service or approved relation schema
was supplied; templates have not been executed against Neo4j.

## Verification and application adapter contracts

C3/L2: `observe_negation` and the `l2` CLI require an external detector and cue
configuration. Returned cues must exactly match bounded source-text spans. Missing
configuration is unresolved; no medical negation rules or semantic verdict exist.
C4/L3: `evaluate_grounding` and `l3 INPUT --evaluator MODULE:FUNCTION` require
caller evidence/provenance with exact `source_id` references. The external evaluator
returns `{source_ids, result}`; unknown IDs are refused. Missing evaluator/evidence
is unresolved. No semantic score or grounding verdict is fabricated.
C5/L4: `package_evidence` and `l4 INPUT OUTPUT` mechanically join the claim,
exact source provenance, and caller L0-L3 results into a deterministic evidence
package. Missing layers remain unresolved; L4 is always pending Claude with no
decision. No model is called and no safety/semantic approval is produced.
D1: `app/index.html` and `app/main.js` provide an unstyled shell with injected
routes, isolated state, API transport, and stale-response protection. No routes,
content, or transport are configured by default. `app/design-system.js` is empty.
Module tests run offline with `node --test tests/app.test.mjs`. A caller may serve
the static files with its existing server; no production/server stack was selected.
D2: `createRecords` exposes read-only get/list using caller-selected operations,
an ID field, and injected transport. Missing configuration is unresolved; responses
must contain exact/unique record IDs. No authentication scheme, endpoint, or browser
credentials are provided. Provider credentials remain outside these browser modules.
D3: `bktUpdate` implements the standard posterior plus learning transition from
externally supplied finite `[0,1]` prior/learn/guess/slip values and a boolean
observation. Impossible observations fail without changing state. `createBKT`
requires caller skill IDs/parameters, deduplicates event IDs, and serializes/replays
events with parameter/state consistency checks. No skill taxonomy, mastery
threshold, pedagogical defaults, or clinical interpretation is supplied. `npm test`
and the manual-only workflow now also run the JavaScript tests with Node 24.
E1: `classifyIntent` requires a caller classifier, intent classes, class field,
and external schema. Missing configuration is unresolved; unsupported schema
keywords and classes are refused. No intent taxonomy or model/provider is supplied.
Browser schema validation uses the same documented mechanical keyword subset.
E2: `renderEvidence` renders caller claims/provenance with `textContent`, exact
source/citation references, and unresolved/pending status. Missing layer results
or references remain unresolved; displayed evidence is never marked approved.
It supplies no pedagogical wording, medical safety assessment, or final language.
DOM behavior is covered by module tests and actual Chromium checks; see
`docs/app-completion.md` for exact browser coverage.
E3: `generateMCQ` requires an external generator, question schema, and field map
(`choices`, `choiceId`, `correctIds`). It mechanically checks schema, unique choice
IDs, and nonempty correct IDs referring to those choices. Missing configuration is
unresolved and unsupported schema keywords fail closed. Generated content remains
pending review; no question, answer, taxonomy, or pedagogical defaults are supplied.

Claude decisions remain pending for design, medical safety, pedagogy, schemas,
and architecture. External labels, source-specific license evidence, provider
configuration, and credentials must be supplied before later pipeline work.
Unknown or disallowed licenses must be refused; organization-wide permission
must not replace a content-specific source record. No license judgment is made
by this scaffold.

Store secrets in ignored local environment files. Do not commit patient data,
licensed source material, provider responses, or credentials. The existing
integration documents record earlier blocked setup attempts.
