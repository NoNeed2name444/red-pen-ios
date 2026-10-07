# Latest iOS repository document map

Inventory of `repositories/red-pen-ios-latest/docs/` (snapshot referenced by the parent task: `faecd8cdccd92387ac777335588ebc548b0ab106`). The tree contains 25 files, 882,146 bytes and 11,552 lines. The source files are plans, contracts and marketing drafts; status words below are what the documents record, not independent verification of implementation or approval.

Coverage note: every one of the 25 UTF-8 source files below was read in full, using sequential, overlapping-free line chunks; the largest file (`launch/implementation-plan.md`) was read through its final line. Coverage metadata was checked afterward with `wc -lc` and SHA-256. The tree totals 882,146 bytes and 11,551 newline-terminated lines (`wc` line count; the earlier 11,552 figure counted a final unterminated line as a line). `sha256sum` values are available from the source snapshot if byte identity needs to be rechecked; hashes are not used as a substitute for reading.

## Full-read coverage ledger

Each entry records the complete range read, plus the observed byte and line counts. “Full” means the entire file content was inspected, not just headings or a parse result.

| Source path | Read range | Lines | Bytes |
|---|---:|---:|---:|
| `architecture/plans/tasks-5-to-5d.md` | 1–61 | 61 | 8,334 |
| `design/cases-rebuild.md` | 1–155 | 155 | 8,788 |
| `design/targets-2026-10-01.md` | 1–133 | 133 | 9,075 |
| `design/ward-round-rollout.md` | 1–236 | 236 | 25,885 |
| `launch/ambassadors-and-referrals.md` | 1–766 | 766 | 68,326 |
| `launch/api-routes.md` | 1–71 | 71 | 6,498 |
| `launch/app-store-listing.md` | 1–553 | 553 | 44,778 |
| `launch/config-defaults.json` | 1–194 | 194 | 6,962 |
| `launch/designs/A-share-loops.md` | 1–906 | 906 | 66,117 |
| `launch/designs/B-monetisation.md` | 1–819 | 819 | 66,267 |
| `launch/designs/C-retention-surfaces.md` | 1–413 | 413 | 37,053 |
| `launch/designs/D-cost-intelligence.md` | 1–711 | 711 | 55,207 |
| `launch/designs/E-quality-insight.md` | 1–650 | 650 | 46,043 |
| `launch/designs/F-trust-legal-arabic.md` | 1–607 | 607 | 51,190 |
| `launch/implementation-plan.md` | 1–2,160 | 2,160 | 136,304 |
| `launch/launch-checklist.md` | 1–691 | 691 | 59,557 |
| `launch/package-files.tsv` | 1–516 | 516 | 25,861 |
| `launch/pricing.md` | 1–366 | 366 | 37,033 |
| `launch/privacy-and-terms-draft.md` | 1–498 | 498 | 51,311 |
| `launch/reels.md` | 1–538 | 538 | 50,903 |
| `launch/schema/accounts-alters.sql` | 1–14 | 14 | 866 |
| `launch/schema/accounts-indexes.sql` | 1–3 | 3 | 319 |
| `launch/schema/share-store.sql` | 1–17 | 17 | 608 |
| `launch/schema/unified-tables.sql` | 1–424 | 424 | 15,047 |
| `verification/sensor-bench.md` | 1–49 | 49 | 3,814 |

Coverage counts reflect the captured tree at `faecd8cdccd92387ac777335588ebc548b0ab106`. Later changes to those source files require a new read.

## Recorded decisions relevant to integration

- **Brand and product design:** keep the app named Stethoscore via `Brand.name`; remove rank, levels, XP and leaderboards; use the Ward Round language as the app-wide design direction, while keeping the space look for the 3D Ideas map. The owner’s cited approvals are dated 1 October. [design/targets-2026-10-01.md](../../repositories/red-pen-ios-latest/docs/design/targets-2026-10-01.md:1)
- **Ward Round rollout is a plan with unresolved owner choices:** dark appearance is unspecified, launch background colour needs an owner choice, and the 2D Ideas/map boundary needs settling before that batch. The plan says the `design/ward-round` branch was not on origin at its read-only survey, and says no batch past Batch 0 should start before its foundation is available. These are statements in a 1 October plan and need checking against current repo state. [design/ward-round-rollout.md](../../repositories/red-pen-ios-latest/docs/design/ward-round-rollout.md:1)
- **Cases clean-room contract:** the old Cases expression is excluded; use only the new spec and allowed app components/methods. No patient Q&A, typed or spoken, nor history question chips. New naming; no ranks/XP/leaderboards. This spec is explicitly a clean-room boundary, not proof that a particular implementation complied. [design/cases-rebuild.md](../../repositories/red-pen-ios-latest/docs/design/cases-rebuild.md:1)
- **Verification pipeline/task status as recorded:** Task 5 steps 1–3 are marked done; Jev shadow pilot and tuning wait for a Jev key and Pro funds. Task 5b says the licence allowlist/fetcher and pilot pipeline are built. Task 5c says all four steps are done, while explicitly saying Worker switches/breakers and fault-injection changes are not deployed pending owner instruction. Task 5d says named stages and claim gate are built; durable job orchestration needs no change. Folder migration says done, including a personal verifier commit and 170 tests (historical assertion, not independently checked here). [architecture/plans/tasks-5-to-5d.md](../../repositories/red-pen-ios-latest/docs/architecture/plans/tasks-5-to-5d.md:1)
- **Sensor-bench claims:** the 1 October document reports 8,081 questions, 17,107 parity cases, and the reported catches/limitations shown in its result table. Treat these as documented results, not new clinical validation. [verification/sensor-bench.md](../../repositories/red-pen-ios-latest/docs/verification/sensor-bench.md:1)
- **Growth/launch plan status:** the integrated plan is dated 24 September 2026 and describes a future wave sequence, package ownership, launch gates, and owner-only Apple steps. It says its own package work follows W0 seams and subsequent CI gates; it does not establish that those waves shipped. It says its plan wins over source designs A–F when they disagree, but this is a planning rule, not a later owner approval. It also retains Vignette as the planned store name, which conflicts with the later design-target instruction to keep Stethoscore; prefer the later dated owner decision unless another newer source supersedes it. [launch/implementation-plan.md](../../repositories/red-pen-ios-latest/docs/launch/implementation-plan.md:1)
- **Deferred launch choices and operational gates:** the launch checklist, pricing, privacy/legal draft and store listing contain owner actions, legal-review placeholders, ship-gated features and release blockers. Do not represent draft policy, prices, store metadata, or launch readiness as approved/shipped absent separate confirmation. [launch/launch-checklist.md](../../repositories/red-pen-ios-latest/docs/launch/launch-checklist.md:1), [launch/pricing.md](../../repositories/red-pen-ios-latest/docs/launch/pricing.md:1), [launch/privacy-and-terms-draft.md](../../repositories/red-pen-ios-latest/docs/launch/privacy-and-terms-draft.md:1), [launch/app-store-listing.md](../../repositories/red-pen-ios-latest/docs/launch/app-store-listing.md:1)

## Tree inventory

Every path in the captured tree (listed so the parent can cross-check source coverage):

- `architecture/plans/tasks-5-to-5d.md`
- `design/cases-rebuild.md`
- `design/targets-2026-10-01.md`
- `design/ward-round-rollout.md`
- `launch/ambassadors-and-referrals.md`
- `launch/api-routes.md`
- `launch/app-store-listing.md`
- `launch/config-defaults.json`
- `launch/designs/A-share-loops.md`
- `launch/designs/B-monetisation.md`
- `launch/designs/C-retention-surfaces.md`
- `launch/designs/D-cost-intelligence.md`
- `launch/designs/E-quality-insight.md`
- `launch/designs/F-trust-legal-arabic.md`
- `launch/implementation-plan.md`
- `launch/launch-checklist.md`
- `launch/package-files.tsv`
- `launch/pricing.md`
- `launch/privacy-and-terms-draft.md`
- `launch/reels.md`
- `launch/schema/accounts-alters.sql`
- `launch/schema/accounts-indexes.sql`
- `launch/schema/share-store.sql`
- `launch/schema/unified-tables.sql`
- `verification/sensor-bench.md`

The generated `launch/` material contains planned contracts rather than an authoritative current implementation state. The plans also say deployment requires the owner's word, and listing/submission has explicit owner-only actions; no source here authorizes deployment, publishing, outreach, key handling, or external account changes.
