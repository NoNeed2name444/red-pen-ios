# Rootstock-OS Raw Source Gathering

## Repository identity

Pending. The starred-repository query could not complete, so no repository identity has been established.

## Query

Command:

```sh
gh api /user/starred --paginate --jq '.[] | select(.name | test("rootstock"; "i")) | .full_name'
```

Result: exit code 1. Exact error:

```text
Get "https://api.github.com/user/starred?per_page=100": proxyconnect tcp: dial tcp 172.31.0.93:8080: socket: operation not permitted
```

No raw source was collected. No repository identity, license, or assessment is recorded.

---

# Rootstock-OS Raw Source Gathering

## Repository identity and pinned source

- Starred repository match: `Mazhron/rootstock-os` (64 entries in the public starred-list response; exact case-insensitive name match).
- Repository URL: `https://github.com/Mazhron/rootstock-os.git`
- Pinned HEAD: `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Checkout path: `/workspace/vendor/rootstock-os`
- Captured documentation: all 29 tracked Markdown, TXT, and LICENSE files in the checkout below, including README, license, contributing guide, design notes, methods, rules, and skills.
- No assessment or integration was performed.

## Tracked file tree at pinned HEAD

```text
0 - READ ME FIRST.md
CLICKER_DESIGN_NOTES.md
CONTRIBUTING.md
FLAGS.md
GODOT_FIELD_NOTES.md
HOOKS_METHOD.md
INTENT_METHOD.md
LESSONS.md
LICENSE
README.md
REPORTING_METHOD.md
SECURITY_METHOD.md
SKILLS.md
SUBAGENT_METHOD.md
UPGRADES.md
WIKI_METHOD.md
WORKFLOW_METHOD.md
WORKSTATION_METHOD.md
hooks/README.txt
hooks/_hooklib.py
hooks/bash_guard.py
hooks/brief_guard.py
hooks/delegation_auditor.py
hooks/diet_guard.py
hooks/fanout_guard.py
hooks/format_guard.py
hooks/hygiene_guard.py
hooks/lesson_advisor.py
hooks/pre_compact.py
hooks/preserve_guard.py
hooks/prompt_gauge.py
hooks/session_end.py
hooks/session_start.py
hooks/settings.json
hooks/stop_tick.py
hooks/verify_advisor.py
reference tools/_ledger.py
reference tools/backup_push.py
reference tools/big_reads.py
reference tools/check_claude_md.py
reference tools/check_wiki_links.py
reference tools/checkpoint.py
reference tools/cold_shelf.py
reference tools/core_diet.py
reference tools/correction_log.py
reference tools/delete_grant.py
reference tools/export_tag_index.py
reference tools/format_lint.py
reference tools/guard_replay.py
reference tools/intent_log.py
reference tools/intent_report.py
reference tools/law_gaps.py
reference tools/ledger_trends.py
reference tools/lesson_log.py
reference tools/open_questions.py
reference tools/purpose_audit.py
reference tools/readme_audit.py
reference tools/readme_lint.py
reference tools/refresh_kit.py
reference tools/retire.py
reference tools/rootstock_update_check.py
reference tools/route_index.py
reference tools/run_all.py
reference tools/security_audit.py
reference tools/standup.py
reference tools/systems_audit.py
reference tools/usage_report.py
reference tools/usage_window.py
reference tools/version_hint.py
reference tools/wiki_heat.py
reference tools/workstation_survey.py
rules/wiki.md
skills/brief/SKILL.md
skills/checkpoint/SKILL.md
skills/correct/SKILL.md
skills/flag/SKILL.md
skills/intent/SKILL.md
skills/preserve/SKILL.md
skills/runaway/SKILL.md
skills/ship/SKILL.md
skills/standup/SKILL.md
```

## Manifest and examples paths

No files named `package.json`, `pyproject.toml`, `requirements.txt`, `Cargo.toml`, `go.mod`, `package-lock.json`, or `manifest.json` occur in this checkout. No `examples/`, `architecture/`, or `docs/` directory is present at this pinned HEAD; relevant root-level design and method documents are included below.

## Raw documentation files

### `0 - READ ME FIRST.md`

- Source: `0 - READ ME FIRST.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 8274
- SHA-256: `4cadab93beca15cd875cda553fcf0cc4634b71b72c04fb1f138802361ef37960`

```text
# READ ME FIRST - the kit's front door (an install runbook, read once)

PURPOSE: The kit's front door: walks a receiving Claude through the install
  in order (ask the CEO first, then the wiki, reporting and session
  rituals, the delegation company, the skills and hooks, the companions,
  the optional boards) by POINTING at each method file's bootstrap
  section, so the operating system lands the same way every time.
INTENT: the methods encode lessons already paid for, so a receiving Claude
  installs them in order instead of improvising a different architecture.
  This file is NOT a CLAUDE.md and never loads per session: it is read
  once, at install, then the project's own lean CLAUDE.md takes over
  (WIKI_METHOD.md "The hot core and the sub-indexes" says how big that is).

Search keys: bootstrap, new project setup, kit install, read me first,
  front door, install order.

You have been handed ROOTSTOCK, a portable operating system for running a
software project with Claude, distilled from a shipped project (Everwood,
2026). Four pillars: a token-cheap KNOWLEDGE WIKI, a scripted REPORTING
discipline, a DELEGATION company of sub-agents, and SESSION RITUALS
packaged as skills; hooks make the laws mechanical. Install it in order,
asking the STEP 0 questions first. Do not improvise a different
architecture.

Roles: the person who gave you this kit is the CEO; you are the MANAGER;
sub-agents you spawn are EMPLOYEES. The full kit assumes git, Python 3 and
Claude Code; without one of them the install is PARTIAL and every skip is
recorded in the install stamp (see MISSING PREREQUISITES).

## STEP 0 - ask the CEO before building anything

1. Project name, language/engine, repo location (git init if needed).
2. WHO MANAGES: which Claude model is the manager, which are employees
   (SUBAGENT_METHOD.md forbids assuming).
3. One workstation or several (ledgers and day files stamp per machine).
4. Which domain files apply: GODOT_FIELD_NOTES.md (Godot),
   CLICKER_DESIGN_NOTES.md (idle/clicker); otherwise keep them unindexed
   in reference/ as examples of what such files become.
5. UPDATE POLICY for future kit concepts: ask / auto / relevant / never
   (default ask; lives in the install stamp; the CEO changes it by saying so).

THE BROWNFIELD RULE (an existing project): inventory first, ADOPT what
already plays each role under its own name, PROPOSE the install as a plan,
and touch no existing file before the CEO's explicit yes. Production-
sensitive files are untouchable without a named go-ahead.

MISSING PREREQUISITES: no git means skip the push/checkpoint-push steps and
the update check; not Claude Code means skip the skills shelf, the
transcript-mined last exchange and the usage sheet (the checkpoint writes
the exchange into the day file by hand). Record each skip in the stamp
("| no-git | no-skills").

## STEP 1 - the wiki (WIKI_METHOD.md, "Bootstrapping a NEW project")

Everything else is indexed into it, so it comes first: the project's
CLAUDE.md as THE POINTER CORE (the project in a paragraph, how to read,
how to verify, the laws no hook enforces, ONE pointer to the master
index; under Anthropic's 200-line target, the lint fails past 200 lines
or 2,000 tokens and warns past 1,500: WIKI_METHOD.md "The hot core and
the sub-indexes"; the origin lands ~900 tokens), docs/index/
MASTER_INDEX.md (the one door: every topic file, root file, sub-index and
rule, one line each), .claude/rules/ path-scoped rules for what only
matters while one part of the codebase is open (copy rules/wiki.md from
the kit; write the project's own code and text rules with a `paths:`
field), docs/systems/ topic files, docs/index/ sub-indexes for what falls
out of the core, the lint (reference tools/check_claude_md.py) and the
mover (reference tools/core_diet.py) in the check group. Copy the portable
MDs to the repo root and index each with one line in the master index.
Create WORKFLOWS.md
(WORKFLOW_METHOD.md) the day the first two-step process exists. Stamp the
install: "Rootstock vX.Y installed <date> | updates: <policy>" in the
project's CLAUDE.md itself (version: UPGRADES.md).

## STEP 2 - reporting + session rituals (REPORTING_METHOD.md, bootstrap)

docs/history/ + the runner; from "reference tools/" (they work; adapt
paths, do not rewrite): standup.py (the digest + THE LAST EXCHANGE mined
verbatim from the harness transcripts), checkpoint.py (the counter + the
protocol), the daily log (days/ + days_index.txt), usage_report.py (the
weighted sheet + THE DAILY LINE), rootstock_update_check.py wired into
standup, run_all.py (THE LOOP LAW: every habitual script is called by
it). Day one: a baseline run in a ledger. Then WORKSTATION.md from the
survey (WORKSTATION_METHOD.md; workstation_survey.py in the check group).

## STEP 3 - the delegation company (SUBAGENT_METHOD.md, bootstrap)

SUBAGENTS.md from the STEP 0 answers (org chart, the laws, a first
assignments table, an empty ledger); delegate something small the same
day to prove stamp -> brief -> verify -> ledger end to end; the stamp
carries the WORKFLOW line (WORKFLOW_METHOD.md) and the INTENT line
(INTENT_METHOD.md).

## STEP 4 - the skills shelf and the hooks (SKILLS.md, HOOKS_METHOD.md)

Copy skills/ to .claude/skills/ and SKILLS.md to the root; the nine
rituals call the tools from steps 1-3, so they go live last. THE SKILLS
RULE: a ritual born or amended updates its skill in the same batch.
Then the hooks: copy hooks/ to tools/hooks/, merge the settings template
into .claude/settings.json, fill the bash guard's PROJECT RULES from the
STEP 0 laws, run every --selftest, pipe-test one real call
(HOOKS_METHOD.md's tiers say what each guard refuses and why; only the
CEO edits safety wiring). Then the loops that measure the loop, each in
its method file: the learning loop (WIKI_METHOD.md), the intent loop
(INTENT_METHOD.md), the format law + the purpose audit (CONTRIBUTING.md),
the README gate (only if this project publishes a fact-derived README),
and the lesson loop (LESSONS.md at the root, hooks/lesson_advisor.py,
reference tools/lesson_log.py: the one right way is read before the
first try and a lesson is asked for the moment a turn shows trial and
error; hooks/README.txt has the steps).
THE ROUTE LINE (kit v1.33): reference tools/route_index.py beside it; the
prompt hook then names the WORKFLOWS entry and the tool a prompt already
has before the first tool call.

## STEP 5 - optional boards (adopt when the CEO wants them)

A TOKEN_IDEAS.md savings board; a NEXT_STEPS.md roadmap with attribution
and a FUTURE_FEATURES.md pin board; a public CHANGELOG fed by readable
commit subjects. If STEP 0 said the project has a backend, a key, an
env file, a database or user accounts: SECURITY_METHOD.md's bootstrap
(the audit script, the workflow entry, the ship question) before the
first public release (a URL, a store listing, a showcase post); if it
said none, write the exemption in the systems
index and move on.

## DEFINITION OF DONE

standup.py runs clean and prints the core's size; check_claude_md.py
passes (the core under 200 lines and inside its token budget, every rule
by path, the master index complete); the format lint passes and FLAGS.md
flags every kit thing;
SUBAGENTS.md has one real ledger line; the skills answer to their slash
commands; the first commit is in. From then on: every write grows the
wiki, every repeatable action becomes a script, every result lands in a
ledger, every batch ships, every arc checkpoints.

One law to carry verbatim (THE CONTRADICTION RULE): if the CEO asks for
something that contradicts a rule they previously set, FLAG it and get
explicit confirmation - never silently comply, never silently refuse.

## UPDATING AN EXISTING INSTALL

Never reinstall, never copy kit files over project files. Open UPGRADES.md
(the graft log), read the entries newer than the project's install stamp,
act per the CEO's update policy, graft each chosen CONCEPT onto the
project's own files in its own names, bump the stamp.

See also: UPGRADES.md (the graft protocol); CONTRIBUTING.md (the format
  law); WIKI_METHOD.md, REPORTING_METHOD.md, SUBAGENT_METHOD.md, SKILLS.md,
  HOOKS_METHOD.md, WORKFLOW_METHOD.md, WORKSTATION_METHOD.md,
  INTENT_METHOD.md, LESSONS.md (the files this door points at).
```

### `CLICKER_DESIGN_NOTES.md`

- Source: `CLICKER_DESIGN_NOTES.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 12415
- SHA-256: `1955bc76dcfd794f74b77f1726588d9c7951dc065c345d89d2d276af06921bb9`

```text
# Clicker / Idle Design Notes

PURPOSE: Genre knowledge earned building Everwood, written portably: cost
  curve shapes, clicking and auto-click patterns, progression gating, the
  prestige economy, offline progress, feedback economics, balance telemetry,
  and the tooling workflow, so it carries to the next clicker or idle game.
INTENT: The three-layer rule: engine facts live in GODOT_FIELD_NOTES.md,
  genre patterns live here, game-specific detail lives in that game's own
  docs, one home per fact.

Genre knowledge earned building Everwood, written PORTABLY: what carries to
the next clicker/idle game, with Everwood only as the worked example. The
three-layer rule: engine facts live in GODOT_FIELD_NOTES.md, genre patterns
live HERE, game-specific detail lives in that game's own docs.

---

## Cost curves (the shapes, and when each feels right)
Tags: design, economy | Pick curve shapes deliberately, and always compare cumulative costs across currencies

The full toolkit, all worth exposing as data on every upgrade:

- **Plain exponential** `base x growth^level` (growth ~1.1-1.7): the
  workhorse for in-run upgrades. Low growth = long satisfying chains.
- **Tier bands**: every N levels stacks another multiplier on top of the
  smooth curve. Long (50+) chains get harder in VISIBLE STEPS instead of
  one smooth wall - players see the band boundary coming and push for it.
- **Smooth ramp**: the multiplier itself grows each level
  (`growth + ramp x levels_owned`, e.g. x2, x2.5, x3...). Super-exponential;
  ends a chain fast. Good for "few, weighty" purchases - dangerous as a
  default (see the parity lesson).
- **Banded meta curve** `base x growth^floor(level / band)`: flat stretches
  then jumps. This is how a 500-level prestige upgrade stays reachable
  without a hyper-exponential chain making level 40 the real cap.
- **Dual-currency prices** (two banks, optionally separate growths per
  currency) make one purchase pull on two economies at once.

**THE PARITY LESSON (learned the hard way):** always compare CUMULATIVE
curves across currencies the player can substitute. Everwood's permanent
upgrades hit 3.3M meta-currency by level 16 while the ENTIRE 50-level
in-run chain cost 3M run-currency - so no rational player would ever buy
permanent. If a permanent and a run version scale identically, permanent is
strictly better (pay once, own forever) - so perm should be consciously
steeper or higher-based, by a chosen margin, not by accident of formula.

**Coupled knobs bite.** When two systems read a min/max of two tunables
(Everwood: natural sprouts charge `min(sprout_cost, fertile_threshold)`),
retuning one silently drags the other. Document every coupling next to the
knobs, and retune them together.

**Everything data-driven from day one.** Twice we had to migrate hardcoded
cost systems into resources so tools could edit them. Starting data-driven
is free; migrating later costs a day each time.

## Clicking and auto-clicking
Tags: design | Teach clicking first, batch auto-click rate but keep per-target feedback intact

- **The taught verb is CLICK.** Holding/auto-fire is an UPGRADE the player
  earns - never teach "hold" first, or the upgrade means nothing.
- **Batch the RATE, never the footprint.** An auto-clicker at 16/s with a
  visual cap draws 4 pulses/s, each carrying 4 clicks' worth of power by
  math - totals identical, draw cost quartered. But every target the pulse
  touches still shows ITS OWN number with the batch folded in: players
  notice missing feedback immediately (a real report). Manual clicks are
  never batched.
- **AOE clicks earn on the whole footprint**, so a wider-reach upgrade
  visibly increases income per click, not just coverage.
- **Bank clicks on slow targets.** Progress-toward-a-thing (clicks toward a
  free birth, vitality toward a sprout) should be MONOTONIC and shown on
  the target - a click that visibly banked is never a wasted click.

## Progression, gating, and discovery
Tags: design | Pace discovery with mystery slots and inline unlock hints, never silent walls

- **Mystery rows** ("??? - unlocks after N Rebirths") pace discovery across
  prestiges; never show the name or effect early. In-shop chains
  (requires / requires-N-levels / requires-MAXED) sequence within a run.
- **Locked things say HOW to unlock, inline** ("locked - requires 1 level of
  Stronger Pulse"). A lock without a path is just frustration.
- **Shelf order: buyable first, mysteries soonest-first.** The next goal is
  always visible at the top of the fog.
- **Playtest mode bypasses every gate**, and tests get their own bypass
  lever - both standing, or gates make iteration miserable.
- **Every number is a baseline, not a constant**: meta progression retunes
  run numbers at run start, so nothing balance-relevant is inlined in logic.

## The prestige economy
Tags: design, economy | Reward two different sources, snapshot on disaster, weight value at earn time

- **Two currencies from two DIFFERENT sources** keeps prestige interesting:
  one from lifetime accumulation (a % of everything earned - note: ALL
  earned, not unspent, so spending during a run is never punished at the
  payout), one from a CENSUS of what is alive/standing at the moment of
  prestige - rewarding a built ecosystem, not just a big number.
- **Weight value at EARN TIME, not payout time.** Bank earnings into
  buckets stamped with the difficulty active when earned; the payout sums
  buckets x their own multipliers. This kills the classic exploit of
  flipping to max difficulty right before prestiging.
- **Snapshot on disaster.** When a catastrophe strikes, bank the payout the
  player COULD have taken that morning - they can always prestige on their
  pre-disaster peak. Removes the "lost everything" sting without removing
  the loss.
- **First-arrival bonuses** (a grant the first time each species/feature
  appears in a run) reward breadth, not just depth.
- **Permanently owned = owned.** A meta-bought starting level grants its
  unlocks (tools, modes) at run start exactly like an in-run purchase; the
  run's shop continues from that level at that level's price.
- **Measure the loop, don't guess it.** Scripted probes told us: first
  prestige ~x1.8 power and -44% clicks to the same milestone; by prestige
  #3 a single upgrade line plateaus (~x9.7) because one basket saturates -
  later prestiges need the SHOP'S BREADTH to keep compounding. Design meta
  shops so depth hands off to breadth.
- Keep a capped **prestige history ledger** from day one - the stats page
  and the balance passes both want it.

## Offline progress
Tags: design, economy | Pace-based offline earn, capped hours, is cheap and exploit-resistant

The shape that worked: while away, earn a FRACTION of the run's recent
income PACE - a slow EMA sampled during play and saved with the campaign -
at base X% per real hour, +Y% per meta level, with an HOURS CAP (base ~8h,
extendable by its own upgrade) so a months-old save cannot detonate the
economy, a minimum-gap so relaunch-spam earns nothing, and a "while you
were away" report card on return. Pace-based (not state-simulated) offline
is cheap, exploit-resistant, and reads fair.

## Feedback economics (numbers the player can trust)
Tags: design | Ship full number suffixes and per-source breakdowns so players trust the numbers

- **Ship the whole suffix ladder** (k, M, B, T, Qa, Qi, Sx, Sp, Oc, No,
  Dc...) from the start - idle games reach big numbers faster than you
  think, and "1e15" mid-game reads as a bug.
- **Floating numbers are an economy of their own**: pooled, SMALL font
  (dozens fly at once; big text becomes an unreadable wall), a minimum
  threshold so wide AOE never sprays "+0.01" a dozen times, and a static
  "left until the next thing" progress number ON the target so mass
  clicking reads as banking, not noise.
- **Every visual firehose gets a Graphics dial** (On / Intermittent / Off):
  click flash, gain numbers, progress numbers, visual rate caps. Players
  on weak machines will thank you; the tracer will too.
- **Per-source breakdowns build trust.** Showing income split by faucet
  (clicks, growth, creatures, rain...) - with a reconciliation row so the
  table ALWAYS sums to the total - turns "is this broken?" into "oh, THAT's
  where it comes from."

## Balance instrumentation (the telemetry that answers "where do they stall")
Tags: process, economy | Log per-event progression telemetry locally to find stalls playtesting misses

Build a local, opt-in, per-event progression log:

- An EVENT is an upgrade purchase; purchases within ~20s coalesce into one
  spree (players buy in bursts - per-purchase rows are noise).
- Between events record: real seconds, in-game days, clicks, every gain by
  SOURCE, every currency by branch, populations born/died/alive, soil/world
  milestones.
- A prestige CLOSES the segment list and starts a new one, stamped with the
  permanent purchases made at the seam.
- Export TXT (readable) + CSV (spreadsheet) per session.

This answers empirically what no amount of playtesting-by-feel answers:
time-between-upgrades curves, dead stretches, which faucet actually funds
each era. Pair it with a frame-time tracer (see GODOT_FIELD_NOTES.md) so
balance sessions double as performance sessions.

## The tooling workflow ("nothing lives only in code")
Tags: process, architecture | If a designer cannot edit a number in the tool, that is a bug

The single highest-leverage decision of the project:

- **Design webs**: self-contained HTML editors GENERATED from the real game
  data - every upgrade/species as an editable card, field definitions
  PARSED from the data script itself so new fields need zero tool changes.
  Edits live in browser localStorage; Export writes a JSON; an apply script
  patches the real resources; regenerate and reset.
- **Compare tables** (one category side by side, one column per stat, every
  cell editable, arrow keys walk columns) with COMPUTED columns - total
  cost of the whole chain, effect at max - because cumulative numbers, not
  per-level numbers, are what decide balance.
- **Tree views** with requirement edges and draggable gate lines are the
  design conversation; the exported JSON is the spec.
- **The iron rule**: if a designer cannot edit a number in the tool, that is
  a bug. Every cost, curve, gate, max level and effect belongs on data the
  tool can reach - the moment something "lives in code," tooling rots
  around it.
- Commit subjects are the changelog (player-readable, exported by script);
  ship builds every batch; never delete old build zips - before/after
  captures need them.

## Living-ecosystem idle (the sub-genre lessons)
Tags: design | Gate population by food supply and match sense and eat thresholds exactly

If the idle economy is an ECOSYSTEM (creatures, food chains) rather than
pure numbers:

- **The land decides the herd**: food supply sets a target population;
  breeding fills TOWARD the target and never past it; arrivals trickle.
  Without the gate, two well-fed founders max out any population cap.
- **Render caps fold into multipliers**: population beyond the sprite
  budget lives as a "community" stat on the drawn entities (bigger appetite,
  bigger yield) - the ecosystem keeps growing without more nodes.
- **Sense gates must match eat gates.** Everwood's grazers could neither
  see nor eat plants below stage 2 - and grazing knocks plants DOWN stages,
  so cropped meadows became invisible food and animals starved amid plenty.
  Any "minimum quality" threshold on food must apply to sensing and eating
  identically, and consumption must not push food below its own floor.
- **Starvation drains a bank, not a switch**: hunger empties a belly, then
  emptiness drains stored vitality/HP - a well-fed life buys a long grace.
  And only TRUE empty should drain: early-bleed thresholds compound with
  every other pressure (hiding prey nearly wiped the predators).
- **Prey/predator behavior is cheap richness**: stop-to-eat, storm shelter,
  hiding with a visible tell, vision cones (one dot product), corpses that
  persist and feed - each was a few constants and a state flag, and
  together they read as "alive" to players.

Search keys: clicker design, idle game, cost curves, prestige economy,
  offline progress, genre lessons
See also: GODOT_FIELD_NOTES.md (engine facts); WIKI_METHOD.md (the three-
  layer rule's home)
```

### `CONTRIBUTING.md`

- Source: `CONTRIBUTING.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 6021
- SHA-256: `25fb3960a725cc613fc1cbe22f508a431349df22c185b332762e459e8469964b`

```text
# CONTRIBUTING.md - the format law and the purpose audit (for every update, ours or yours)

PURPOSE: the two guardrails every Rootstock update passes through - THE
  FORMAT (one header on every thing, checked by script and enforced by a
  hook) and THE PURPOSE AUDIT (a read-only comparison of what a thing says
  against what it does, flagged green / yellow / red and filed in
  FLAGS.md) - written so a contributor, a maintainer and any Claude apply
  them the same way.
INTENT: Mazhron 2026-09-13: "Rootstock-os will eventually, hopefully, turn
  into a community involved system. Guardrails need to be in place so
  that anything written in updates must have a comment describing the
  purpose and intent of the 'thing' in the update." And: "Any updates,
  upgrades, hooks, scripts, etc need to be in the same format so that
  they work with our current filing system. Anything without proper
  format should be flagged, a script should re-write it after review-only
  audit. This will be a law and may need this to be a hook somehow so
  that no one can inject a prompt that overrides safety protocols."

## THE FORMAT (one header, every thing)

Every thing in the kit - a script under reference tools/, a hook under
hooks/, a skill's SKILL.md, a method file, the hooks README, the front door - carries
these lines in its header. A Python file carries them in its module
docstring; a Markdown file right after its title line; a .txt at the top.

    PURPOSE: what the thing does, plainly, in one or two lines.
    INTENT:  why it exists - the owner's words verbatim, or the INTENT.md
             heading that holds them.
    Search keys: the nouns a search would use.        (scripts + MDs)
    See also: topic -> file | ...                       (scripts + MDs)

Plus, by class:
- a HOOK script imports _hooklib and answers `--selftest`;
- a SKILL carries the frontmatter (`name:` equal to its folder,
  `description:`) above a `# ` title;
- the SETTINGS template (hooks/settings.json) parses, names only hook
  scripts that exist beside it, and keeps every SAFETY hook wired with
  its required matcher: preserve_guard, bash_guard, fanout_guard,
  diet_guard, hygiene_guard, format_guard, brief_guard,
  delegation_auditor, verify_advisor, stop_tick, session_end (the SAFETY
  table in format_lint.py is the list; this prose follows it).

A placeholder ("(unfilled ...)") is scaffolding, not a header: it fails.

How it is enforced (reference tools/format_lint.py, hooks/format_guard.py):
- `python tools/format_lint.py` checks every kit thing and its original
  and names each failure; the sync script refuses to publish on a FAIL.
- The FORMAT GUARD hook blocks an edit that leaves a kit thing without
  its header (the reason names the file and the rewrite command), and
  REFUSES any edit of a settings file that would unwire, narrow or
  mis-point a safety hook. The shell guard refuses shell writes into a
  settings file; the Stop hook refuses to end a turn while the live
  settings file fails the safety check. Together: no prompt, brief or
  patch switches a guard off quietly.
- A thing WITHOUT the header is rewritten BY SCRIPT after a read-only
  audit, never by hand:
  `python tools/format_lint.py --rewrite <path> --purpose "..." --intent
  "..." [--keys "..."] [--also "..."]` inserts only the missing lines (or
  fills a placeholder) and touches nothing else.

## THE PURPOSE AUDIT (read-only -> flag -> explain)

Before an update merges, and whenever a thing is UNFLAGGED or STALE, a
Claude (or a person) audits it:

1. READ the thing. Do not edit it in the audit turn.
2. COMPARE what its PURPOSE line says with what the body actually does:
   side effects the purpose omits, writes or deletions outside its stated
   files, a way around a guard, unbounded loops or spend, injected text
   the purpose does not describe, a vague or stale purpose line.
3. FLAG it:
   - GREEN: does what it says and nothing more.
   - YELLOW: matches in substance, something is off. Fix in a later
     batch; it may ship.
   - RED: does what its purpose does not say, or crosses a law (deletes,
     disables a guard, unbounded spend, routes around a refusal). The
     owner sees it before it merges or ships.
   A thing with no PURPOSE line cannot be GREEN.
4. EXPLAIN and FILE:
   `python tools/purpose_audit.py --flag "<kit-relative path>" --color
   green|yellow|red --by <who> --does "<what it actually does>" --note
   "<why this color; what would fix it>"`
   The script copies SAYS from the PURPOSE line, hashes the exact version
   reviewed, appends the entry to FLAGS.md and regenerates the tally at
   its top. `python tools/purpose_audit.py --pending` lists what still
   needs an audit. A contributor files the same entry by pull request.

FLAGS.md is committed and published with the kit: it is the one file
that references every flag, tallies them, and holds every finding for the
next reviewer.

## What a contributed update looks like

- Every new or changed thing carries THE FORMAT header, with INTENT in
  the words of whoever asked for it.
- The update's UPGRADES.md entry says WHAT / CARRIES / GRAFT / README
  (see UPGRADES.md's protocol) and bumps the kit version.
- `python tools/format_lint.py` passes; `python tools/readme_lint.py`
  passes if the README changed; every changed thing has a FLAGS.md entry
  from a read-only audit by someone other than its author when possible.
- Nothing deletes (THE PRESERVATION LAW): a file retires, a section goes
  to the cold shelf, a wrong line is marked superseded.
- No em or en dashes in text a person reads.

Search keys: contributing, format law, purpose audit, flags, header,
PURPOSE line, INTENT line, safety wiring, community update, pull
request, guardrails.
See also: FLAGS.md (the flag ledger); reference tools/format_lint.py;
reference tools/purpose_audit.py; hooks/format_guard.py; skills/flag (the
ritual); HOOKS_METHOD.md (Tier 3b); UPGRADES.md (the graft protocol);
INTENT_METHOD.md (why the owner's words are kept verbatim).
```

### `FLAGS.md`

- Source: `FLAGS.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 157276
- SHA-256: `81b422db698d5580b2c9bda6d4b3e494dfa9d11e7c711833364be2dbe78540ef`

```text
# FLAGS.md - the purpose audit ledger (green / yellow / red, for review)

PURPOSE: the one file that references every kit thing's flag - what its
  PURPOSE line says, what a read-only audit found it actually does, the
  color, the explanation - tallied at the top and committed so anyone
  can review it and any Claude can add findings.
INTENT: Mazhron 2026-09-13: "Claude should always read-only -> Flag ->
  Explain. There should be a file that directly references anything that
  is green, yellow or red flags, tally them and put them in the git for
  review. Any Claude can review and put their findings there for future
  review."

HOW TO USE THIS FILE: the tally block is GENERATED by reference
tools/purpose_audit.py (never hand-edit it); the entries below the flags
heading are APPEND-ONLY, one per audit of one thing, newest last -
`python tools/purpose_audit.py --flag "<kit path>" --color green|yellow|red
--by <who> --does "..." --note "..."` writes one. GREEN: does what its
PURPOSE says and nothing more. YELLOW: matches in substance, something is
off (a side effect, a gap, a vague purpose); fix later, may ship. RED:
does what its purpose does not say or crosses a law (deletes, disables a
guard, unbounded spend); the owner sees it before it merges. STALE: the
thing changed since its last flag - audit it again. A contributor files
the same way, by pull request; the entry's hash names the exact version
reviewed.

Search keys: flags, purpose audit, green yellow red, review ledger,
contributor review, stale, unflagged.
See also: CONTRIBUTING.md (the format law + the audit ritual); reference
tools/purpose_audit.py (the tally + the --flag writer); reference
tools/format_lint.py (the header the SAYS line comes from); skills/flag
(the ritual as a slash command); UPGRADES.md (the graft log).

## The tally (generated - never hand-edit this block)

<!-- tally:start -->
Updated 2026-10-06 11:23 | items 78 | GREEN 74 | YELLOW 0 | RED 0 | unflagged 4 | stale 17

| item | flag | state | by | when |
|---|---|---|---|---|
| 0 - READ ME FIRST.md | GREEN | ok | fable | 2026-10-06 11:21 |
| CLICKER_DESIGN_NOTES.md | GREEN | ok | sonnet-fmt4 | 2026-09-13 11:50 |
| CONTRIBUTING.md | GREEN | ok | fable | 2026-10-06 11:21 |
| GODOT_FIELD_NOTES.md | GREEN | ok | sonnet-fmt4 | 2026-09-13 11:50 |
| HOOKS_METHOD.md | GREEN | ok | fable | 2026-10-06 11:21 |
| INTENT_METHOD.md | GREEN | STALE | sonnet-flag1 | 2026-09-14 00:58 |
| LESSONS.md | GREEN | STALE | fable | 2026-09-20 03:21 |
| REPORTING_METHOD.md | GREEN | ok | fable | 2026-10-06 11:21 |
| SECURITY_METHOD.md | GREEN | ok | fable | 2026-09-29 14:23 |
| SKILLS.md | GREEN | STALE | fable | 2026-09-13 11:57 |
| SUBAGENT_METHOD.md | GREEN | STALE | fable | 2026-09-30 12:22 |
| UPGRADES.md | GREEN | STALE | fable | 2026-09-20 03:22 |
| WIKI_METHOD.md | GREEN | ok | fable | 2026-10-06 11:21 |
| WORKFLOW_METHOD.md | GREEN | ok | fable | 2026-10-06 11:21 |
| WORKSTATION_METHOD.md | GREEN | ok | fable | 2026-09-28 23:13 |
| hooks/README.txt | GREEN | STALE | fable | 2026-09-20 03:21 |
| hooks/_hooklib.py | GREEN | ok | sonnet-fmt1 | 2026-09-13 11:51 |
| hooks/bash_guard.py | GREEN | ok | fable | 2026-09-13 11:57 |
| hooks/brief_guard.py | GREEN | ok | fable | 2026-09-30 11:57 |
| hooks/delegation_auditor.py | GREEN | ok | fable | 2026-10-01 16:55 |
| hooks/diet_guard.py | GREEN | ok | fable | 2026-09-30 11:57 |
| hooks/fanout_guard.py | GREEN | ok | sonnet-fmt1 | 2026-09-13 11:51 |
| hooks/format_guard.py | GREEN | ok | fable | 2026-09-13 11:57 |
| hooks/hygiene_guard.py | GREEN | ok | fable | 2026-09-20 03:21 |
| hooks/lesson_advisor.py | GREEN | ok | fable | 2026-09-20 03:21 |
| hooks/pre_compact.py | GREEN | ok | fable | 2026-09-30 11:57 |
| hooks/preserve_guard.py | GREEN | STALE | fable-ws1 | 2026-09-20 17:37 |
| hooks/prompt_gauge.py | GREEN | ok | fable | 2026-09-30 11:57 |
| hooks/session_end.py | - | UNFLAGGED | - | - |
| hooks/session_start.py | GREEN | ok | fable | 2026-09-29 00:24 |
| hooks/settings.json | GREEN | ok | fable | 2026-10-01 16:55 |
| hooks/stop_tick.py | GREEN | ok | fable | 2026-09-29 00:24 |
| hooks/verify_advisor.py | - | UNFLAGGED | - | - |
| reference tools/_ledger.py | GREEN | ok | fable | 2026-09-20 03:21 |
| reference tools/backup_push.py | - | UNFLAGGED | - | - |
| reference tools/big_reads.py | GREEN | ok | sonnet-fmt2 | 2026-09-13 11:50 |
| reference tools/check_claude_md.py | GREEN | STALE | sonnet-PC-FLAG-1 | 2026-09-14 16:32 |
| reference tools/check_wiki_links.py | GREEN | ok | Fable (WS2 manager) | 2026-09-22 17:37 |
| reference tools/checkpoint.py | GREEN | ok | sonnet-fmt2 | 2026-09-13 11:50 |
| reference tools/cold_shelf.py | GREEN | ok | sonnet-cd1 | 2026-09-14 15:40 |
| reference tools/core_diet.py | GREEN | ok | sonnet-PC-FLAG-1 | 2026-09-14 16:32 |
| reference tools/correction_log.py | GREEN | STALE | fable | 2026-09-20 03:21 |
| reference tools/delete_grant.py | GREEN | ok | sonnet-flag1 | 2026-09-14 00:59 |
| reference tools/export_tag_index.py | GREEN | ok | fable | 2026-09-14 15:42 |
| reference tools/format_lint.py | GREEN | ok | fable | 2026-10-01 16:55 |
| reference tools/guard_replay.py | GREEN | ok | fable | 2026-09-30 11:57 |
| reference tools/intent_log.py | GREEN | ok | sonnet-fmt2 | 2026-09-13 11:51 |
| reference tools/intent_report.py | GREEN | ok | sonnet-fmt2 | 2026-09-13 11:51 |
| reference tools/law_gaps.py | GREEN | ok | fable-manager | 2026-09-29 16:36 |
| reference tools/ledger_trends.py | GREEN | STALE | fable | 2026-09-29 00:24 |
| reference tools/lesson_log.py | GREEN | ok | fable | 2026-09-20 03:21 |
| reference tools/open_questions.py | GREEN | ok | sonnet-flag1 | 2026-09-14 00:59 |
| reference tools/purpose_audit.py | GREEN | STALE | fable | 2026-09-14 16:55 |
| reference tools/readme_audit.py | GREEN | ok | sonnet-fmt3 | 2026-09-13 11:52 |
| reference tools/readme_lint.py | GREEN | STALE | fable | 2026-09-30 12:22 |
| reference tools/refresh_kit.py | GREEN | ok | fable | 2026-09-14 16:33 |
| reference tools/retire.py | GREEN | ok | sonnet-flag1 | 2026-09-14 00:59 |
| reference tools/rootstock_update_check.py | GREEN | ok | sonnet-fmt3 | 2026-09-13 11:52 |
| reference tools/route_index.py | GREEN | ok | fable | 2026-09-28 23:37 |
| reference tools/run_all.py | GREEN | STALE | fable | 2026-09-20 03:21 |
| reference tools/security_audit.py | GREEN | ok | fable | 2026-09-29 14:23 |
| reference tools/standup.py | GREEN | STALE | fable | 2026-09-29 10:39 |
| reference tools/systems_audit.py | GREEN | ok | sonnet-fmt3 | 2026-09-13 11:52 |
| reference tools/usage_report.py | GREEN | ok | fable | 2026-09-29 00:24 |
| reference tools/usage_window.py | GREEN | ok | fable | 2026-09-30 11:57 |
| reference tools/version_hint.py | - | UNFLAGGED | - | - |
| reference tools/wiki_heat.py | GREEN | ok | fable | 2026-09-14 15:42 |
| reference tools/workstation_survey.py | GREEN | ok | sonnet-fmt3 | 2026-09-13 11:52 |
| rules/wiki.md | GREEN | STALE | sonnet-PC-FLAG-1 | 2026-09-14 16:32 |
| skills/brief/SKILL.md | GREEN | STALE | fable | 2026-09-30 12:22 |
| skills/checkpoint/SKILL.md | GREEN | STALE | fable | 2026-09-20 03:21 |
| skills/correct/SKILL.md | GREEN | ok | sonnet-fmt4 | 2026-09-13 11:48 |
| skills/flag/SKILL.md | GREEN | ok | fable-manager | 2026-09-29 16:38 |
| skills/intent/SKILL.md | GREEN | ok | sonnet-fmt4 | 2026-09-13 11:48 |
| skills/preserve/SKILL.md | GREEN | ok | sonnet-fmt4 | 2026-09-13 11:48 |
| skills/runaway/SKILL.md | GREEN | ok | sonnet-fmt4 | 2026-09-13 11:48 |
| skills/ship/SKILL.md | GREEN | ok | fable | 2026-09-30 12:22 |
| skills/standup/SKILL.md | GREEN | ok | sonnet-fmt4 | 2026-09-13 11:48 |
| 0 - READ ME FIRST, CLAUDE.md | GREEN | GONE | sonnet-fd1 | 2026-09-13 12:20 |
<!-- tally:end -->

## The flags (append-only, newest last)

### 2026-09-13 11:48 | skills/brief/SKILL.md | GREEN | sonnet-fmt4 | WS1 | ef0f65cd
SAYS: Compose and dispatch a sub-agent (employee) brief that follows the delegation laws, stamped, self-contained, budget-capped, diff-only reporting, then verify cheap and ledger the outcome.
DOES: Gives the manager a checklist for composing a delegation brief (stamp, self-contained context, budget line, report format, workflow line, fan-out check, preservation line, intent line) and the post-return steps (log intent claim, verify, ledger, capture workflow gaps).
FLAG: Every instruction matches the stated purpose, nothing routes around a guard, the preservation and fan-out lines are quoted verbatim from the actual laws.

### 2026-09-13 11:48 | skills/checkpoint/SKILL.md | GREEN | sonnet-fmt4 | WS1 | 38ad2708
SAYS: Close an arc safely: push, refresh the day file's WHERE WE LEFT OFF section with both sides of the final exchange verbatim, reset the task counter, and emit the safe-to-clear marker.
DOES: Walks the arc-close sequence: preconditions (no running employee, no uncommitted work), push, refresh the day file's WHERE WE LEFT OFF verbatim, commit and push, run checkpoint.py --reset last, then print the safe-to-clear marker; also covers the self-ticking counter and the context gauge threshold.
FLAG: Instructions match the purpose exactly; refuses to run mid-arc or with an employee running, no deletion or spend without bound.

### 2026-09-13 11:48 | skills/correct/SKILL.md | GREEN | sonnet-fmt4 | WS1 | 261a3e83
SAYS: Walk a correction: ask what needs correcting, record the owner's words, resolve the open intent claim DIFFERENT, fire /intent, then fix the thing.
DOES: Walks a correction: ask what needs fixing, record the owner's verbatim words before any fix is made, say back what will change, ask for the intent, fix the thing, then mark it fixed and ship.
FLAG: Matches its purpose; explicitly forbids paraphrasing the owner's words and requires recording before fixing, no guard bypass.

### 2026-09-13 11:48 | skills/intent/SKILL.md | GREEN | sonnet-fmt4 | WS1 | 03888cbb
SAYS: Record the WHY of a ruling in the owner's own words in INTENT.md and resolve the open intent claim comparing the manager's reading against it.
DOES: Walks filing a WHY section into INTENT.md in the owner's own words and resolving the open intent claim same/similar/different; forbids inventing an intent the owner never stated and forbids employees from invoking it.
FLAG: Matches its purpose; explicit rule against fabricating owner intent.

### 2026-09-13 11:48 | skills/preserve/SKILL.md | GREEN | sonnet-fmt4 | WS1 | 376b2c82
SAYS: Retire a file, shelve a wiki section, or walk the twice- acknowledged delete grant; the conversational front for the preservation law.
DOES: Walks the three lawful moves in order (retire, cold shelf, delete grant) before anything is removed: names the target, retires with tools/retire.py, shelves with tools/cold_shelf.py, or walks the twice-acknowledged delete grant only as a last resort, with the guard's refusal treated as final.
FLAG: Matches its purpose exactly; explicitly forbids rewording a command to slip past the guard and forbids employees from invoking the delete path.

### 2026-09-13 11:48 | skills/runaway/SKILL.md | GREEN | sonnet-fmt4 | WS1 | 6e537677
SAYS: Show and tune the fan-out guard's runaway numbers (spawn burst and flood caps, token velocity halt, the warning steps).
DOES: Shows the fan-out guard's nine tuned numbers versus defaults, lets the owner raise or lower them via --set, requires the selftest still pass at defaults, and commits the tuning file with the batch.
FLAG: Matches its purpose; explicitly restricts tuning to the owner and forbids the manager raising a limit to get past a refusal.

### 2026-09-13 11:48 | skills/ship/SKILL.md | GREEN | sonnet-fmt4 | WS1 | 09200cff
SAYS: Ship a completed batch: commit with a player-readable subject, push, and (in projects with builds) refresh build zips without deleting old ones.
DOES: Walks the per-batch ship ritual: sanity check tests, bump version if warranted, commit with a player-readable subject, push, run the build script without deleting old zips, sync the kit if touched, and export the changelog unprompted.
FLAG: Matches its purpose; explicitly says never delete older build zips, consistent with the preservation law.

### 2026-09-13 11:48 | skills/standup/SKILL.md | GREEN | sonnet-fmt4 | WS1 | e22cbe53
SAYS: Open a session: print the standup digest and hand back the last exchange (prompt and response) and project state before anything else.
DOES: Walks opening a session: relay the last exchange verbatim from the harness transcript, then the budget block, then a brief digest summary, then ask what to work on.
FLAG: Matches its purpose; explicitly forbids paraphrasing the last exchange and forbids re-running green tests or re-reading notes the digest already covers.

### 2026-09-13 11:49 | skills/flag/SKILL.md | GREEN | sonnet-fmt4 | WS1 | 2058a957
SAYS: the ritual behind FLAGS.md - one kit thing at a time, the auditor reads it, compares the stated purpose with the behaviour, gives it a color, explains the color in the entry, and never touches the thing.
DOES: Walks the read-only purpose audit ritual: pick an unflagged or stale kit thing, read only (no edits or side effects), compare its PURPOSE against its body, assign green/yellow/red, file the entry with tools/purpose_audit.py --flag, and defer any header rewrite to a later, separate step.
FLAG: Matches CONTRIBUTING.md and the actual behavior of purpose_audit.py and format_lint.py observed while running this task; explicitly separates audit from rewrite and forbids editing during the audit turn.

### 2026-09-13 11:49 | CONTRIBUTING.md | GREEN | sonnet-fmt4 | WS1 | dc276ae4
SAYS: the two guardrails every Rootstock update passes through - THE FORMAT (one header on every thing, checked by script and enforced by a hook) and THE PURPOSE AUDIT (a read-only comparison of what a thing says against what it does, flagged green / yellow / red and filed in FLAGS.md) - written so a contributor, a maintainer and any Claude apply them the same way.
DOES: States the two guardrails (the header format and the read-only purpose audit) for every kit update, explains enforcement (format_lint.py, format_guard.py hook, sync refusal on FAIL) and what a contributed update must include before it merges.
FLAG: Matches the actual scripts and hooks it describes; INTENT quotes Mazhron verbatim as required; no instruction routes around a guard or authorizes deletion.

### 2026-09-13 11:50 | reference tools/big_reads.py | GREEN | sonnet-fmt2 | WS1 | 31805a30
SAYS: Mine the harness transcripts for whole file reads of 10k or more estimated tokens, tally them per file with the fix each needs, and write docs/history/big_reads.txt plus a ledger line in docs/history/big_reads_runs.txt.
DOES: Parses this project's harness transcript jsonl files incrementally via a byte offset cache, pairs each whole file Read or bare cat/type/Get-Content tool call with its result size, tallies whole reads of 10k+ estimated tokens per file and per day, and writes docs/history/big_reads.txt plus docs/history/big_reads_runs.txt and docs/history/big_reads_cache.json.
FLAG: Matches its own described job exactly, read-only, no deletion, writes only the documented cache and report files; header was missing PURPOSE, INTENT and a real See also line (mid-line, not line-start, so the lint had never seen it), now added from the file's own text.

### 2026-09-13 11:50 | reference tools/check_claude_md.py | GREEN | sonnet-fmt2 | WS1 | 846154db
SAYS: Read CLAUDE.md and fail with exit 1 when the lean core exceeds its line budget or when the docs/systems library index in CLAUDE.md drifts from the files actually on disk.
DOES: Reads CLAUDE.md, exits 1 if it exceeds a 700 line budget or if the docs/systems index and the files on disk disagree, and prints an informational knowledge file count with a milestone note at 1000 files.
FLAG: Read-only guard, matches its stated job exactly; header had no PURPOSE, INTENT, Search keys or See also lines at all, so all four were added from the file's own content.

### 2026-09-13 11:50 | reference tools/check_wiki_links.py | GREEN | sonnet-fmt2 | WS1 | 6e42002e
SAYS: Warn-only link checker for the knowledge wiki: scan repo-root, docs/systems and docs/cold markdown for the four cross-reference forms, resolve each against the repo, and report dead links plus See-also hygiene.
DOES: Scans repo-root, docs/systems and docs/cold markdown for four link forms, resolves each against the repo, tallies dead links and See-also hygiene, and writes docs/history/wiki_links.txt plus appends docs/history/wiki_link_runs.txt; only exits 1 under --strict.
FLAG: Behavior matches the docstring's warn-only claim exactly, writes only the two documented files; PURPOSE and INTENT labels were missing so they were added.

### 2026-09-13 11:50 | reference tools/checkpoint.py | GREEN | sonnet-fmt2 | WS1 | 5d18cc11
SAYS: Track the checkpoint task counter and the live context gauge: tick, show status, or reset the count, warning at 8 tasks and dire at 15, and warning again when the session's live context nears the auto-compact budget.
DOES: Loads and saves docs/history/checkpoint_state.txt (per workstation task count) and the gitignored .claude/hooks_state.json, reports checkpoint advice at 8 and 15 tasks, and separately probes the newest session transcript to report a context gauge against EVERWOOD_CTX_COMPACT.
FLAG: Matches the docstring's described mechanics including the gitignored hook state file; PURPOSE and INTENT labels were missing so they were added from its own text.

### 2026-09-13 11:50 | reference tools/cold_shelf.py | GREEN | sonnet-fmt2 | WS1 | d1d9e416
SAYS: Move a rarely used ## wiki section out of a hot file to the cold shelf verbatim, restore one back, list the cold shelf index, or check that every stub still points at an existing cold file and heading.
DOES: Cuts a ## section out of a hot wiki file and appends it verbatim plus a provenance line to docs/cold/<name>.md, leaves a two-line stub behind, logs the move to docs/cold/INDEX.md, and can reverse it with --restore; grep of the file confirms no os.remove, unlink, rmtree or rmdir calls anywhere.
FLAG: Matches the docstring's preservation law claim exactly and no deletion calls were found in the file; PURPOSE and INTENT labels were missing so they were added.

### 2026-09-13 11:50 | reference tools/correction_log.py | GREEN | sonnet-fmt2 | WS1 | cdf5f2ad
SAYS: Record the correction ledger: a RECORD line the moment a correction is understood in the CEO's own words, a FIXED line when the fix ships, and resolve the named intent claim as DIFFERENT in the intent log when one is given.
DOES: Appends RECORD and FIXED lines to docs/history/corrections.txt, and when --intent-id is given shells out to intent_log.py --resolve to mark that claim DIFFERENT with source correction, exactly as the docstring states.
FLAG: Matches its docstring including the documented subprocess call into intent_log.py; PURPOSE and INTENT labels were missing so they were added, reusing Mazhron's quoted words for INTENT.

### 2026-09-13 11:50 | reference tools/delete_grant.py | GREEN | sonnet-fmt2 | WS1 | a9b13202
SAYS: Record the owner's double-acknowledged permission for one deletion: write the single-use, time-limited grant file and append the committed delete grants ledger, refusing targets in the never-delete list; performs no deletion itself.
DOES: Writes the single-use, time-limited .claude/delete_grant.json and appends docs/history/delete_grants.txt only after --target, --ask, --ack1 and --ack2 are all supplied and the target passes preserve_guard's never-delete check; issues no deletion itself.
FLAG: Matches its docstring exactly, the ritual gate is enforced in code, not just prose; PURPOSE and INTENT labels were missing so they were added.

### 2026-09-13 11:50 | reference tools/export_tag_index.py | GREEN | sonnet-fmt2 | WS1 | cbacb542
SAYS: Sweep repo-root and docs/systems markdown for Tags lines under headings and compile KNOWLEDGE_INDEX.md, one section per tag with links to each section's true home.
DOES: Scans repo-root and docs/systems markdown for Tags: lines under ## headings, groups entries by tag, and writes KNOWLEDGE_INDEX.md as links plus briefs; --dry-run prints only the tag inventory and count.
FLAG: Matches its docstring exactly, writes only the one documented output file; PURPOSE and INTENT labels were missing so they were added.

### 2026-09-13 11:50 | GODOT_FIELD_NOTES.md | GREEN | sonnet-fmt4 | WS1 | e9d9401d
SAYS: Hard-won engine knowledge from building Everwood (Godot 4.4): rendering and performance costs, simulation architecture patterns, GDScript and API gotchas, and the measurement toolkit, written portably so it carries to future Godot projects.
DOES: Catalogs Godot 4.4 engine lessons in tagged sections (rendering and 2D performance, simulation architecture, GDScript and API gotchas, files/editor plumbing, debugging and measurement, process habits, volume sliders, window mode) written portably with no Everwood-specific code.
FLAG: Head and section index match the stated purpose; each section carries a Tags line as the wiki convention requires; nothing in the visible portion routes around a guard or deletes.

### 2026-09-13 11:50 | CLICKER_DESIGN_NOTES.md | GREEN | sonnet-fmt4 | WS1 | f0c60c06
SAYS: Genre knowledge earned building Everwood, written portably: cost curve shapes, clicking and auto-click patterns, progression gating, the prestige economy, offline progress, feedback economics, balance telemetry, and the tooling workflow, so it carries to the next clicker or idle game.
DOES: Catalogs clicker/idle genre lessons in tagged sections (cost curve shapes, clicking and auto-click, progression gating, prestige economy, offline progress, feedback economics, balance telemetry, tooling workflow, living-ecosystem idle) written portably per the three-layer rule.
FLAG: Head and section index match the stated purpose; explicitly states the layering rule that keeps it from duplicating GODOT_FIELD_NOTES.md or project-specific docs.

### 2026-09-13 11:50 | WIKI_METHOD.md | GREEN | sonnet-fmt4 | WS1 | fdf71221
SAYS: A portable system for organizing a project's knowledge (a lean CLAUDE.md core, a docs/systems topic library, portable root notes) so an AI assistant finds anything in three cheap hops, Glob, Grep for headings, then a targeted Read, without wasting tokens.
DOES: Explains the token mechanics (Glob/Grep/Read cost tiers), the three-layer architecture (CLAUDE.md core, docs/systems library, portable root notes), the three-hop lookup, and further sections on conventions, expansion doctrine, bootstrap, the read and output diets, and the cold shelf.
FLAG: Head and section index match the stated purpose exactly; this is the method the task itself is using (three-hop lookup, section-only reads).

### 2026-09-13 11:50 | SUBAGENT_METHOD.md | GREEN | sonnet-fmt4 | WS1 | 2928636b
SAYS: A portable architecture for delegating work to sub-agent employees: the org chart (CEO, manager, employees), why it saves money, the seven laws, the assignments table, the scorecard, and bootstrap steps for a new project.
DOES: Explains the delegation org chart (CEO, manager, employees), why delegation saves tokens, the seven laws (brief is everything, stamping, cheap verification in order, and more per the section index), the assignments table, the scorecard, and bootstrap steps.
FLAG: Head and section index match the stated purpose; explicitly portable and model-agnostic, asks who manages rather than assuming.

### 2026-09-13 11:51 | reference tools/intent_log.py | GREEN | sonnet-fmt2 | WS1 | c3643cf0
SAYS: Log an intent claim before building and resolve it against the CEO's actual intent as same, similar or different, append-only, one line per claim and one per resolution.
DOES: Appends CLAIM and RESOLVED lines to docs/history/intent_log.txt, computes per id state from the newest line, and enforces the SAME, SIMILAR, DIFFERENT verdict and stated, correction, inferred source vocabularies.
FLAG: Matches its docstring exactly; PURPOSE and INTENT labels were missing so they were added, reusing Mazhron's quoted words for INTENT.

### 2026-09-13 11:51 | reference tools/intent_report.py | GREEN | sonnet-fmt2 | WS1 | 9e2f748e
SAYS: Read the intent log and the correction ledger and regenerate the day, week and month agreement metrics as txt, csv and xlsx, plus one run ledger line, with a trend verdict of improving, steady or declining.
DOES: Reads intent_log.state() and correction_log's RECORD lines, buckets them by day, week, month and actor, and writes docs/history/intent_metrics.txt, .csv, .xlsx (skipped quietly without openpyxl) plus appends docs/history/intent_runs.txt, all as documented; a grep of the file shows it opens only those paths.
FLAG: Matches its docstring exactly, writes only the four documented output paths; PURPOSE and INTENT labels were missing so they were added, reusing Mazhron's quoted words for INTENT.

### 2026-09-13 11:51 | reference tools/format_lint.py | GREEN | sonnet-fmt2 | WS1 | 1253058d
SAYS: check every kit thing (a script, a hook, a skill, a method file, the hooks README, the settings template) and its repo original for the one header the filing system needs - PURPOSE, INTENT, Search keys, See also - plus the safety wiring in settings.json; report PASS/FAIL per file with the reason; on request rewrite ONLY the missing scaffold lines, never the body.
DOES: Walks the kit folder plus each original's scope, checks each file's header lines and hook, skill or settings safety wiring, prints PASS or FAIL, and on --rewrite inserts or fills only the missing PURPOSE, INTENT, Search keys or See also lines, never touching the body.
FLAG: Already carries its own PURPOSE, INTENT, Search keys and See also header; reading the whole file confirms the rewrite function only ever inserts or replaces placeholder header lines, never body text, matching its own claim to rewrite ONLY the missing scaffold lines. Used throughout this same audit batch to fix the other 10 files.

### 2026-09-13 11:51 | reference tools/purpose_audit.py | GREEN | sonnet-fmt2 | WS1 | 1ea56fe1
SAYS: keep the kit's flag ledger (FLAGS.md in the kit folder): every kit thing's latest flag (GREEN / YELLOW / RED), who gave it and when, whether the thing changed since (STALE), the ones nobody has audited yet (UNFLAGGED), and the tally - regenerated in place from the entries; `--flag` appends one entry (SAYS = the thing's own PURPOSE line, DOES = what the reviewer found it actually does, FLAG = why the color).
DOES: Walks the kit folder, compares each item's latest FLAGS.md entry hash against the item's current content, reports UNFLAGGED, STALE or ok status and a tally, and --flag appends one entry (refusing missing --does or --note, em or en dashes, an unknown color, or GREEN on an item with no PURPOSE line), then regenerates the tally block and appends one ledger line to docs/history/purpose_audit_runs.txt.
FLAG: Already carries its own PURPOSE and INTENT header; behavior matches, including the refusals seen in code and the lock file for concurrent writers; the ledger write to docs/history/purpose_audit_runs.txt is documented in the file's prose below the PURPOSE line, just not inside the PURPOSE line itself, so nothing here is undisclosed. Used to file this whole audit batch.

### 2026-09-13 11:51 | REPORTING_METHOD.md | GREEN | sonnet-fmt4 | WS1 | ccd51ae4
SAYS: A portable method for scripted runs and history ledgers: every repeatable run is a script, every run appends one labeled line to an append-only ledger, and a recorded baseline lets a regression show up as a single line flip between two ledger lines.
DOES: Explains the three rules (script rule, ledger rule, baseline rule), what a runner script must do, what earns a ledger, the usage sheet, the weighted column, the spreadsheet rule, and bootstrap steps.
FLAG: Head and section index match the stated purpose; this is the method the task itself follows (scripted rewrite + flag, ledgered as FLAGS.md entries).

### 2026-09-13 11:51 | WORKFLOW_METHOD.md | GREEN | sonnet-fmt4 | WS1 | 349a931f
SAYS: A portable process registry method: every repeatable multi-step process gets one runbook entry, WHEN, STEPS, VERIFY, in a single registry file, so the choreography between scripts and ledgers is never lost to context clearing or memory.
DOES: Explains the process registry (WORKFLOWS.md), the registry entry template (WHEN/STEPS/VERIFY), the capture rule for missing or stale entries, who writes gap write-ups, what earns an entry, and bootstrap steps.
FLAG: Head and section index match the stated purpose; already carried Search keys and See also lines before this audit.

### 2026-09-13 11:51 | SKILLS.md | GREEN | sonnet-fmt4 | WS1 | cada839f
SAYS: The skills shelf: catalogs each ritual, standup, checkpoint, ship, brief, runaway, preserve, intent, correct, as an invocable Claude Code skill in .claude/skills/, so a ritual runs from a script instead of from memory.
DOES: Lists each skill on the shelf (standup, checkpoint, ship, brief, runaway, preserve, intent, correct) with a short description of what each does and when to use it, then the skills rule, new-project bootstrap, and a change log.
FLAG: Descriptions in the visible section match the actual SKILL.md files read earlier in this same audit (standup, checkpoint, ship, brief, preserve, runaway); consistent, no fabricated capability.

### 2026-09-13 11:51 | HOOKS_METHOD.md | GREEN | sonnet-fmt4 | WS1 | f8d04d65
SAYS: Documents the harness hooks, session start, prompt, stop, compaction, and tool-call guards, that enforce CLAUDE.md's laws mechanically instead of relying on the manager's memory, plus the hook contract and the kit's hook roster.
DOES: Explains the hooks rule (a mechanically enforceable law gets a hook, not prose), the hook contract (wiring, input, output, exit codes, config-file gotchas), the kit hook roster, the hygiene guard, unbuilt tier 4 ideas, and bootstrap steps.
FLAG: Head and section index match the stated purpose; quotes the owner's founding question verbatim as required.

### 2026-09-13 11:51 | WORKSTATION_METHOD.md | GREEN | sonnet-fmt4 | WS1 | c6e19b91
SAYS: The machine inventory method: one workstation file records what every script, hook and ritual needs, why, what the origin machine has, and how to install it, so any Claude can get a new machine up to par and write back what it adds.
DOES: Explains the workstation rule (one document records requirements, why, origin machine's version, and install steps), the write-back rule, the survey script, the install procedure for a new machine, and bootstrap steps.
FLAG: Head and section index match the stated purpose; quotes the owner's founding ask verbatim as required.

### 2026-09-13 11:51 | INTENT_METHOD.md | GREEN | sonnet-fmt4 | WS1 | 3754c5f1
SAYS: The intent discipline: one project file, INTENT.md, holds one section per ruling with the owner's verbatim ASKED and WHY, the manager's GENERALIZES TO reading, and a LIVES IN pointer, plus a comparison ledger, correction ritual, and periodic report measuring whether Claude's reading of the owner's intent is converging on it.
DOES: Explains why intent matters over rules alone, the INTENT.md file format (ASKED/WHY/GENERALIZES TO/LIVES IN), the comparison ledger of claim versus verdict, the correction ritual, the periodic report, the systems audit, and the laws.
FLAG: Head and section index match the stated purpose; quotes the owner's looping-scripts example verbatim as required.

### 2026-09-13 11:51 | hooks/_hooklib.py | GREEN | sonnet-fmt1 | WS1 | 259feb33
SAYS: Shared plumbing every hook imports: reads the harness's JSON from stdin, emits JSON back for deny, block or context decisions, and resolves the project version; import-only, no side effects on its own.
DOES: Defines read_input (JSON off stdin, empty dict on any parse error), emit/deny/context (JSON hook-output helpers) and project_version (reads project.godot); nothing beyond that, no writes, no state.
FLAG: Matches PURPOSE exactly; a clean, side-effect-free import that every other hook relies on.

### 2026-09-13 11:51 | hooks/fanout_guard.py | GREEN | sonnet-fmt1 | WS1 | 624d9011
SAYS: PreToolUse guard on every tool call implementing the fan-out law's circuit breaker: refuses only catastrophic spawn shapes (a burst inside a short window machine-wide, a flood inside a session, or runaway weighted- token velocity, all self-clearing) and otherwise only warns on spawn count, session spend and the Workflow tool; the owner tunes the numbers with --set into fanout_limits.json.
DOES: Refuses only burst/flood spawn shapes and runaway weighted-token velocity (all self-clearing), warns on spawn count, spend and Workflow use, and reads limits from fanout_limits.json via --set/--limits/--defaults/--resume/--status; selftest always runs at DEFAULTS regardless of tuning.
FLAG: Matches PURPOSE; catastrophe-only refusals, generous warn thresholds, nothing hidden.

### 2026-09-13 11:51 | hooks/hygiene_guard.py | GREEN | sonnet-fmt1 | WS1 | c2056ca0
SAYS: PostToolUse guard on Write, Edit and MultiEdit that, after an edit lands, hands the manager one line of context per applicable law: KIT REFRESH when a portable original changed, SEE-ALSO when a touched docs/systems section has no See also line, DASH when player-facing text received an em or en dash (this one BLOCKS), and IMPORT when a new asset needs the engine import run; stateless pattern matching only.
DOES: PostToolUse pattern matching only; emits KIT REFRESH, SEE-ALSO and IMPORT context lines and BLOCKS only on the DASH rule (em or en dash in player-facing text); config-driven scope at the top of the file.
FLAG: Matches PURPOSE; the one BLOCK path is the one the docstring names.

### 2026-09-13 11:51 | hooks/preserve_guard.py | GREEN | sonnet-fmt1 | WS1 | fc496b5c
SAYS: PreToolUse guard on Bash, PowerShell, Write, Edit, MultiEdit and NotebookEdit implementing the preservation law: refuses shell delete verbs with a path, git verbs that discard work or history, and deletion calls written into a file, with narrow exceptions for the session scratchpad, prose files, and one command consumed against a twice-acknowledged delete grant; a drive root, the home folder, the repo root or a bare wildcard are refused even with a grant.
DOES: Regex-matches delete verbs, git verbs and deletion-call patterns on Bash/PowerShell/Write/Edit/MultiEdit/NotebookEdit, refuses unless the path is scratchpad-only or a live grant covers it, and never lets a drive root, home folder, repo root or bare wildcard through even with a grant; selftest covers about 30 cases in-process.
FLAG: Matches PURPOSE; the NEVER list and grant consumption behave exactly as described.

### 2026-09-13 11:51 | hooks/format_guard.py | GREEN | sonnet-fmt1 | WS1 | dd6933e2
SAYS: enforce THE FORMAT LAW at the edit. BEFORE a Write/Edit lands on a settings file (.claude/settings.json or the kit's hooks/settings.json) it computes the would-be text and REFUSES it if any SAFETY hook would be unwired, narrowed or pointed at a missing script - so no prompt, brief or contributed patch can switch a guard off. AFTER a Write/Edit lands on any kit thing or its original, it runs the format lint on that one file and BLOCKS (the reason comes back, the edit stays) until the header is right - the rewrite command is in the reason.
DOES: Before a Write/Edit lands on a settings file it computes the would-be text and denies if any SAFETY hook would end up unwired, narrowed or pointed at a missing script; after a Write/Edit lands on any kit thing or its original it runs the format lint on that one file and blocks until the header conforms.
FLAG: Matches PURPOSE; written today by the manager and already has PURPOSE/INTENT, Search keys, See also, imports _hooklib and carries --selftest.

### 2026-09-13 11:51 | hooks/README.txt | GREEN | sonnet-fmt1 | WS1 | 3c95fa3a
SAYS: Installation notes for the Rootstock hooks folder: what each hook file needs filled in or wired (bash_guard.py's PROJECT RULES, fanout_guard.py's numbers via the runaway skill, hygiene_guard.py's CONFIG block) and the gitignore entries a new project needs.
DOES: Lists what to fill in for bash_guard.py, fanout_guard.py and hygiene_guard.py, names which PreToolUse/PostToolUse entries settings.json already wires, and gives the gitignore additions a new install needs.
FLAG: Matches PURPOSE; a plain install checklist, nothing extra.

### 2026-09-13 11:51 | hooks/settings.json | GREEN | sonnet-fmt1 | WS1 | 33ec4d9b
SAYS: (no PURPOSE line)
DOES: Declares SessionStart, UserPromptSubmit, Stop and PreCompact hooks plus five PreToolUse entries (bash_guard, preserve_guard, diet_guard, fanout_guard, format_guard) and two PostToolUse entries (hygiene_guard, format_guard), with matchers wide enough to satisfy the SAFETY table.
FLAG: format_lint --file reports PASS: every SAFETY hook is wired on the right event with a matcher covering its required tools, and no command names a missing script.

### 2026-09-13 11:52 | hooks/diet_guard.py | YELLOW | sonnet-fmt1 | WS1 | 2d1dea0d
SAYS: PreToolUse guard on Read, Bash and PowerShell enforcing the read diet and output diet: warns when a shell command shape (git log, git diff, recursive listing, install) has no limiter, and on the first whole read of a file over about 10k tokens in a session it denies once and returns the file's own section or function index instead; the same call repeated afterward passes with a warning only.
DOES: Warns on chatty shell shapes and warns on big whole-file reads after the first one; the FIRST whole read of a file over about 10k tokens in a session is an actual PreToolUse deny (INDEX FIRST) that returns the file's own index instead of the content; the same call repeated, or a read with offset/limit, only warns or is silent.
FLAG: YELLOW: the module docstring's own opening line calls the guard warn-only and says it NEVER refuses, but the code (and the docstring's own later INDEX FIRST section) denies the first whole big-file read per session. Behavior is fine and self-lifting on retry; the top summary line is the part that misleads a reader. Fix: reword the opening line to say it denies once per file (INDEX FIRST) and warns otherwise.

### 2026-09-13 11:52 | hooks/pre_compact.py | YELLOW | sonnet-fmt1 | WS1 | e4c443e6
SAYS: PreCompact hook that appends one ledger line per compaction (when, workstation, version, manual or auto trigger, context load, unbanked task count) to docs/history/compact_runs.txt, and on an auto trigger tells the manager the session_start hook will re-inject the standup digest right after.
DOES: Appends one ledger line to compact_runs.txt on every PreCompact fire and emits a systemMessage only when trigger is auto; otherwise silent.
FLAG: YELLOW: matches PURPOSE, but it is a hook with no --selftest, which the format lint treats as a real conformance gap (every guard hook in this set carries one). A header-only rewrite cannot add test code; flagged for a future batch to add a selftest.

### 2026-09-13 11:52 | hooks/prompt_gauge.py | YELLOW | sonnet-fmt1 | WS1 | 14c55989
SAYS: UserPromptSubmit hook that stays silent on a normal turn and, when a threshold is crossed, prints the checkpoint counter warning (8 tasks advised, 15 dire) and the context-remaining warning, plus since 2026-09-13 a KIT UNSYNCED line when a portable original is newer than its kit copy.
DOES: Silent on a normal prompt; prints the checkpoint and context lines only past their thresholds, and appends a KIT UNSYNCED line from refresh_kit's check_line() when relevant.
FLAG: YELLOW: matches PURPOSE, but like pre_compact.py it has no --selftest despite being a hook; same gap, same fix needed in a later batch.

### 2026-09-13 11:52 | hooks/session_start.py | YELLOW | sonnet-fmt1 | WS1 | 5b1d5441
SAYS: SessionStart hook that runs tools/standup.py and injects its digest into the manager's context on startup, resume, /clear and after a compaction, with a header telling the manager not to re-run standup and how to relay the last exchange.
DOES: Runs tools/standup.py as a subprocess with a 100 second timeout, injects its stdout (or a failure message) as SessionStart context with a header instructing the manager not to re-run standup.
FLAG: YELLOW: matches PURPOSE, but no --selftest, the same format gap as the other non-guard hooks in this set.

### 2026-09-13 11:52 | reference tools/ledger_trends.py | GREEN | sonnet-fmt3 | WS1 | b1e057e4
SAYS: Reads the tails of the project's history ledgers (usage, tests, wiki links, wiki heat, employee corrections, compactions, README audit, intent claims, corrections, systems audit), compares them against fixed thresholds, and prints proposed rule changes; it applies nothing itself.
DOES: Reads ledger tail lines (usage, tests, wiki links, wiki heat, SUBAGENTS corrections, compactions, README audit, intent claims, corrections, systems audit), compares each to a fixed threshold, prints PROPOSE lines, and records one line to proposal_runs.txt only when the proposal set changed; applies nothing.
FLAG: Matches its purpose exactly, read only, prints proposals, touches no file besides its own ledger.

### 2026-09-13 11:52 | reference tools/readme_audit.py | GREEN | sonnet-fmt3 | WS1 | 3e3cd79d
SAYS: Keeps the README audit ledger: prints status (last audit date, days since, kit folder commits since) and on --record appends one line to docs/history/readme_audit_runs.txt recording a finished four employee cross reference of the public README.
DOES: Reads UPGRADES.md's kit version, the audit ledger's last line, and a git commit count since that line, prints a status summary, and on --record appends one line to readme_audit_runs.txt.
FLAG: Matches its purpose exactly, status and record only, no other writes.

### 2026-09-13 11:52 | hooks/stop_tick.py | YELLOW | sonnet-fmt1 | WS1 | af0c7514
SAYS: Stop hook that ticks the checkpoint counter only when work actually happened (HEAD moved or the tree changed since the last Stop), shows an advised system message at 8 tasks or under 80% context, and refuses to end the turn once at 15 tasks or under 30% context, re-blocking every 5 further tasks; since 2026-09-13 it also refuses once when a safety hook has gone unwired in settings.json.
DOES: Ticks the checkpoint counter only when the work fingerprint changed, emits the advised systemMessage or the dire block at the documented thresholds, and separately blocks once per fingerprint when format_lint's SAFETY check on the live settings file fails.
FLAG: YELLOW: matches PURPOSE, but no --selftest despite being a hook; same format gap as the other non-guard hooks in this set. The safety-wiring block logic itself checks out against format_lint.check_file.

### 2026-09-13 11:52 | hooks/bash_guard.py | YELLOW | sonnet-fmt1 | WS1 | 39e318a3
SAYS: Kit-relative version of the PreToolUse guard on Bash and PowerShell: GENERIC RULES (no --no-verify, no plain force push, the format law's shell twin blocking shell writes into the hook-wiring settings file) plus a PROJECT RULES block of commented Everwood-derived templates for a receiving project to fill with its own laws.
DOES: Refuses --no-verify and plain force pushes, and refuses a shell write into the hook-wiring settings file (matched by its file extension pattern) when the same full command string ALSO contains any write-shaped token (tee, sed -i, cp, mv and more) anywhere in it, not just as an operation performed on that file; PROJECT RULES is commented-out Everwood templates only, so a fresh kit install enforces nothing project-specific until filled in.
FLAG: YELLOW: discovered live during this audit - a --rewrite command whose --purpose argument merely described the settings-file rule in prose (naming the file near the word for duplicating a file) was denied as a false positive, because the check looks for the two patterns anywhere in the command text instead of confirming an actual write targets that file. Not unsafe, a false refusal rather than a bypass, but worth tightening: anchor the write-pattern check to the actual settings-file argument, not the whole command string. Also carries no --selftest despite being a hook (format_lint FAILs it on that alone).

### 2026-09-13 11:52 | reference tools/readme_lint.py | GREEN | sonnet-fmt3 | WS1 | 419dd8cf
SAYS: Derives every countable README fact (laws, skills, hooks, reference tools, the box table, version, the graft README line, number word claims, prose claims) from the kit folder itself and compares it with what the public README says, ledgering PASS, FAIL or SKIP each run.
DOES: Reads the public README from the sibling kit repo clone, derives law, skill, hook, reference and box counts from the kit folder, checks the version and prose claims, prints PASS or FAIL per check, and appends one line to readme_lint_runs.txt, SKIPping cleanly when no clone is present.
FLAG: Matches its purpose exactly, including the documented SKIP path when there is no local kit repo clone.

### 2026-09-13 11:52 | reference tools/retire.py | GREEN | sonnet-fmt3 | WS1 | a4adc3f2
SAYS: Moves a file to _retired/ (same relative path, Godot import extensions suffixed .retired) and appends one line to docs/history/retired_files.txt; nothing is ever deleted.
DOES: Moves a given path into _retired/ with shutil.move, adds a .retired suffix for Godot import extensions, refuses paths outside the repo, and appends one line to retired_files.txt; contains no delete or remove call.
FLAG: Matches its purpose exactly and upholds the preservation law, it is the sanctioned move only tool.

### 2026-09-13 11:52 | reference tools/standup.py | GREEN | sonnet-fmt3 | WS1 | 734ab7ec
SAYS: Prints the post pull standup digest: the last exchange mined from harness transcripts, the day file's WHERE WE LEFT OFF, the usage budget line, ledger trend proposals, version and recent commits, WS notes, ledger tails, and the open roadmap index.
DOES: Prints the harness transcript last exchange, the day file's WHERE WE LEFT OFF, refreshes and prints the usage budget line, runs ledger_trends.py and prints its output, then prints version, recent commits, WS notes, ledger tails and the open roadmap index.
FLAG: Matches its purpose exactly, the usage sheet refresh it triggers is disclosed in its own docstring.

### 2026-09-13 11:52 | reference tools/systems_audit.py | GREEN | sonnet-fmt3 | WS1 | 87a4b8ed
SAYS: Keeps the systems audit ledger: prints status (last audit, days since, day files and commits since) and on --record appends one line to docs/history/systems_audit_runs.txt recording a finished four lane audit (tokens, process, knowledge, features) of the operating system.
DOES: Reads the systems audit ledger's last line, counts day files and commits since, prints status, and on --record appends one line to systems_audit_runs.txt.
FLAG: Matches its purpose exactly, same shape as readme_audit.py.

### 2026-09-13 11:52 | reference tools/usage_report.py | GREEN | sonnet-fmt3 | WS1 | 59f0f400
SAYS: Mines the Claude Code harness JSONL transcripts for real per model per tool token usage and writes an aggregate usage sheet (CSV, TXT, XLSX, employee runs, and the daily budget line) totaled by day, week and month.
DOES: Walks local harness transcript files under the user's Claude projects folder, aggregates token usage per model and tool by day, week and month, and writes usage_metrics.csv, usage_metrics.txt, usage_metrics.xlsx, usage_employees.csv and usage_daily.txt, all listed in its own docstring.
FLAG: Matches its purpose exactly, every output file it writes is named in its own header.

### 2026-09-13 11:52 | reference tools/wiki_heat.py | GREEN | sonnet-fmt3 | WS1 | 413caf1c
SAYS: Mines the harness transcripts for read events against wiki markdown files and sections, reports file and section read counts plus hot and cold sections, and classifies cold sections by why they are cold using git activity in their code areas; it never moves anything.
DOES: Parses local harness transcripts for read events against wiki markdown files, maps them onto each file's current headings, runs one read only git log for code activity, writes wiki_heat.txt and appends one line to wiki_heat_runs.txt; contains no move or delete call.
FLAG: Matches its purpose exactly and its own docstring's claim that nothing moves.

### 2026-09-13 11:52 | reference tools/workstation_survey.py | GREEN | sonnet-fmt3 | WS1 | 9fb7cb61
SAYS: Checks this machine against the CHECKS table (a mirror of WORKSTATION.md's requirements), prints a HAVE or MISSING table, and appends a summary line to docs/history/workstation_runs.txt; exits 1 if a required item is missing.
DOES: Runs a table of read only version probes (python, node, git, code, gh, pip show) plus filesystem existence checks, prints a HAVE or MISSING table, and appends one summary line to workstation_runs.txt.
FLAG: Matches its purpose exactly, every probe is a version check or a path check, nothing installs anything.

### 2026-09-13 11:52 | reference tools/refresh_kit.py | GREEN | sonnet-fmt3 | WS1 | 67926692
SAYS: copy every portable ORIGINAL to its grab-copy in the kit folder (repo-root MDs, .claude/skills/*/SKILL.md, tools/hooks/*.py, the tools/*.py that have a reference copy), with the one substitution the kit carries in scripts (the owner's name -> "the CEO"); report the hand-adapted files it must never overwrite; `--check` only says what is out of step (the prompt hook's KIT UNSYNCED line).
DOES: Copies each portable original (repo root MDs, skill SKILL.md files, tools/hooks/*.py, the tools/*.py with a reference copy) into the kit folder when the copy differs, applying the Mazhron to CEO substitution on scripts only, skipping ADAPTED files, and never removing a kit file the repo lacks.
FLAG: Matches its purpose exactly, already carried its own PURPOSE and INTENT header before this audit, read critically as asked and no undisclosed behavior found.

### 2026-09-13 11:52 | reference tools/rootstock_update_check.py | GREEN | sonnet-fmt3 | WS1 | 9c9dec68
SAYS: Reads the project's install stamp from CLAUDE.md, fetches the kit's current UPGRADES.md (a local clone if configured, else the public repo over HTTPS), and prints any graft entries newer than the install plus what the CEO's update policy says to do about them; it only reports, a manager Claude performs the actual grafts by hand.
DOES: Reads the CLAUDE.md install stamp, fetches UPGRADES.md from a local clone (git pull) or the public repo over HTTPS via urllib.request, compares versions, prints newer graft entries and the CEO's policy action, and appends one line to rootstock_updates.txt; performs no grafts itself.
FLAG: Matches its purpose exactly and its own docstring discloses the network call plainly.

### 2026-09-13 11:52 | UPGRADES.md | GREEN | sonnet-fmt3 | WS1 | 76247591
SAYS: The append only graft log: every kit concept update, recorded as WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed project's own files, and which README section it touched, so installs update by concept rather than by overwriting a project's customized files.
DOES: An append only markdown log: a protocol section on why updates are grafts, then dated version entries each carrying WHAT, CARRIES, GRAFT and a README line.
FLAG: Structure in the head and section index matches its stated purpose; the full entry list was not read line by line in this pass.

### 2026-09-13 11:52 | 0 - READ ME FIRST, CLAUDE.md | YELLOW | sonnet-fmt3 | WS1 | fff0f201
SAYS: The kit's front door: walks a receiving Claude step by step (ask the CEO first, then install the wiki, reporting and session rituals, the delegation company, and the skills shelf) so the four pillar operating system lands the same way every time.
DOES: A step by step install script (STEP 0 through STEP 5, Definition of Done, Updating an existing install) read by a receiving Claude; the head and section index show CEO questions first, a brownfield rule, and missing prerequisite handling, with no delete, override or guard bypass instruction visible in that scope.
FLAG: Reviewed only the head and section index per this audit's own scope, not the roughly 230 line step by step body; nothing found contradicts its stated purpose, but full body verification of an injectable prompt this sensitive is still open, so this flags yellow rather than green until a full read confirms it.

### 2026-09-13 11:57 | 0 - READ ME FIRST, CLAUDE.md | YELLOW | fable | WS1 | afc159b2
SAYS: The kit's front door: walks a receiving Claude step by step (ask the CEO first, then install the wiki, reporting and session rituals, the delegation company, and the skills shelf) so the four pillar operating system lands the same way every time.
DOES: Installs the operating system step by step for a receiving Claude; this batch added THE FORMAT GUARD + THE PURPOSE AUDIT step and two definition-of-done clauses.
FLAG: Stays YELLOW: the 230-line step body has still not been read whole by a reviewer other than its authors; the new paragraph matches the scripts it names. Re-flagged by the manager who wrote the addition.

### 2026-09-13 11:57 | HOOKS_METHOD.md | GREEN | fable | WS1 | fa4d0d26
SAYS: Documents the harness hooks, session start, prompt, stop, compaction, and tool-call guards, that enforce CLAUDE.md's laws mechanically instead of relying on the manager's memory, plus the hook contract and the kit's hook roster.
DOES: Documents the hook contract, the ten kit hooks by tier and the bootstrap; this batch added Tier 3b (the format guard) and a change-log line.
FLAG: The Tier 3b text matches format_guard.py's two behaviours and its selftest; re-flagged by the author of the addition, a second reviewer should confirm.

### 2026-09-13 11:57 | SKILLS.md | GREEN | fable | WS1 | 2eaf7e2e
SAYS: The skills shelf: catalogs each ritual, standup, checkpoint, ship, brief, runaway, preserve, intent, correct, as an invocable Claude Code skill in .claude/skills/, so a ritual runs from a script instead of from memory.
DOES: The skills shelf; this batch added the /flag entry and a change-log line.
FLAG: The entry matches skills/flag/SKILL.md; re-flagged by the author of the addition.

### 2026-09-13 11:57 | UPGRADES.md | GREEN | fable | WS1 | 74da518f
SAYS: The append only graft log: every kit concept update, recorded as WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed project's own files, and which README section it touched, so installs update by concept rather than by overwriting a project's customized files.
DOES: The graft log; this batch appended the v1.19 entry and bumped the version line.
FLAG: WHAT/CARRIES/GRAFT/README present, README line names real sections (readme_lint PASS); re-flagged by the author of the entry.

### 2026-09-13 11:57 | hooks/README.txt | GREEN | fable | WS1 | 8b1e353c
SAYS: Installation notes for the Rootstock hooks folder: what each hook file needs filled in or wired (bash_guard.py's PROJECT RULES, fanout_guard.py's numbers via the runaway skill, hygiene_guard.py's CONFIG block) and the gitignore entries a new project needs.
DOES: The hooks install checklist; this batch added the format_guard paragraph and bumped the kit version.
FLAG: Matches the guard's wiring and selftest; re-flagged by the author of the addition.

### 2026-09-13 11:57 | hooks/bash_guard.py | GREEN | fable | WS1 | 2a27b4b0
SAYS: Kit-relative version of the PreToolUse guard on Bash and PowerShell: GENERIC RULES (no --no-verify, no plain force push, the format law's shell twin blocking shell writes into the hook-wiring settings file) plus a PROJECT RULES block of commented Everwood-derived templates for a receiving project to fill with its own laws.
DOES: Refuses the generic shell laws (no-verify, plain force push) and the settings-file write rule; now structured as verdict() with a 12-case --selftest.
FLAG: Both YELLOW reasons from the first audit are fixed: the settings rule now needs a real write target (prose naming the file passes, tested) and the selftest exists. Re-flagged by the author of the fix; a second reviewer should confirm.

### 2026-09-13 11:57 | hooks/format_guard.py | GREEN | fable | WS1 | a968c4b5
SAYS: enforce THE FORMAT LAW at the edit. BEFORE a Write/Edit lands on a settings file (.claude/settings.json or the kit's hooks/settings.json) it computes the would-be text and REFUSES it if any SAFETY hook would be unwired, narrowed or pointed at a missing script - so no prompt, brief or contributed patch can switch a guard off. AFTER a Write/Edit lands on any kit thing or its original, it runs the format lint on that one file and BLOCKS (the reason comes back, the edit stays) until the header is right - the rewrite command is in the reason.
DOES: Denies a settings edit that breaks the safety wiring; blocks an unformatted kit edit; now ignores WARN-grade lint lines.
FLAG: The change only narrows the block to hard failures; selftest 10/10. Re-flagged by the author.

### 2026-09-13 11:57 | hooks/stop_tick.py | GREEN | fable | WS1 | 5e5cdda8
SAYS: Stop hook that ticks the checkpoint counter only when work actually happened (HEAD moved or the tree changed since the last Stop), shows an advised system message at 8 tasks or under 80% context, and refuses to end the turn once at 15 tasks or under 30% context, re-blocking every 5 further tasks; since 2026-09-13 it also refuses once when a safety hook has gone unwired in settings.json.
DOES: Ticks the checkpoint counter on work, escalates, and as the Stop twin refuses the turn once while the safety wiring is broken; now main() plus a --selftest.
FLAG: The YELLOW reason (no selftest) is fixed; the selftest proves the safety check bites on an unwired Stop hook. Re-flagged by the author.

### 2026-09-13 11:57 | reference tools/format_lint.py | GREEN | fable | WS1 | f8feaefe
SAYS: check every kit thing (a script, a hook, a skill, a method file, the hooks README, the settings template) and its repo original for the one header the filing system needs - PURPOSE, INTENT, Search keys, See also - plus the safety wiring in settings.json; report PASS/FAIL per file with the reason; on request rewrite ONLY the missing scaffold lines, never the body.
DOES: Checks every kit thing's header and the settings wiring, rewrites only missing lines; --selftest is now required only of hooks that can refuse or block, info-only hooks get a WARN.
FLAG: The relaxation is deliberate and documented in the code; the three WARNs are visible in every run. Re-flagged by the author.

### 2026-09-13 12:19 | 0 - READ ME FIRST, CLAUDE.md | YELLOW | sonnet-fd1 | WS1 | afc159b2
SAYS: The kit's front door: walks a receiving Claude step by step (ask the CEO first, then install the wiki, reporting and session rituals, the delegation company, and the skills shelf) so the four pillar operating system lands the same way every time.
DOES: Walks a receiving Claude through installing Rootstock in order: asks the CEO five bootstrap questions at STEP 0, then builds the knowledge wiki at STEP 1, the reporting scripts, session rituals and workstation doc at STEP 2, the delegation company at STEP 3, the skills shelf plus a large hooks and guard system at STEP 4, points to optional boards at STEP 5, and gives the graft protocol for updating an existing install. Every reference tools, hooks, skills and root MD file it names exists in the Future Project MDs folder.
FLAG: Yellow, not green, because PURPOSE and INTENT advertise only a four pillar operating system, wiki, reporting, delegation, skills, while STEP 4 also installs a fifth major component, the hooks and guard system, format guard, fanout guard, diet guard, preserve guard, hygiene guard, about a third of the file, unnamed in the header. The STEP 4 parenthetical skill list, standup checkpoint ship brief runaway preserve, is also stale, missing correct, intent and flag which exist in the skills folder. Nothing in the body deletes, disables a guard, or routes around a refusal, so this is a purpose line staleness issue, not a safety issue. Fix by naming the hooks system in PURPOSE as a fifth installed piece or folding it explicitly into the four pillars, and refreshing the STEP 4 skill list. This is the first non-author full-body read of this file, every earlier reviewer either wrote part of it or read only its head.

### 2026-09-13 12:20 | 0 - READ ME FIRST, CLAUDE.md | GREEN | sonnet-fd1 | WS1 | 39d5c17b
SAYS: The kit's front door: walks a receiving Claude step by step (ask the CEO first, then install the wiki, reporting and session rituals, the delegation company, the skills shelf and the hooks that enforce the laws in the harness, then the two companions and the optional boards) so the four pillar operating system and its guards land the same way every time.
DOES: Walks a receiving Claude through installing Rootstock in order: asks the CEO five bootstrap questions at STEP 0, then builds the knowledge wiki, reporting scripts and session rituals, the delegation company, the skills shelf, and the hooks and guard system, then points to optional boards and the graft protocol for updating an existing install. Every reference tools, hooks, skills and root MD file it names exists in the Future Project MDs folder.
FLAG: Green. This is the second read by the same non-author reviewer, after the manager fixed both prior findings. PURPOSE now names the hooks that enforce the laws in the harness and ends four pillar operating system and its guards, so the fifth component is no longer unnamed in the header. The STEP 4 skill list now reads standup checkpoint ship brief runaway preserve correct intent flag, matching every skill actually present in the skills folder. Nothing else was off in the full read, so with both spots corrected the file does what it says and nothing more.

### 2026-09-13 12:21 | hooks/diet_guard.py | GREEN | fable | WS1 | 48f93ac5
SAYS: PreToolUse guard on Read, Bash and PowerShell enforcing the read diet and output diet: warns when a shell command shape (git log, git diff, recursive listing, install) has no limiter, and on the first whole read of a file over about 10k tokens in a session it denies once and returns the file's own section or function index instead; the same call repeated afterward passes with a warning only.
DOES: PreToolUse guard on Read, Bash and PowerShell: refuses the first whole read of a file past about 10k tokens once per session with the file's own index in the refusal, passes the same call repeated with a warning, and warns on chatty shell shapes with no limiter; state in .claude/diet_state.json; 27 in-process selftest checks.
FLAG: The yellow reason is fixed: the docstring's opening line and its it-never-refuses sentence now say it refuses exactly once (INDEX FIRST) and warns on everything else, matching the code and the docstring's own INDEX FIRST section; the kit hooks README line was corrected the same way. Selftest 0 failed. Re-flagged by the author of the wording fix; the code did not change.

### 2026-09-13 12:21 | hooks/pre_compact.py | GREEN | fable | WS1 | 8fa883d6
SAYS: PreCompact hook that appends one ledger line per compaction (when, workstation, version, manual or auto trigger, context load, unbanked task count) to docs/history/compact_runs.txt, and on an auto trigger tells the manager the session_start hook will re-inject the standup digest right after.
DOES: PreCompact hook: appends one ledger line per compaction to docs/history/compact_runs.txt and on an auto trigger emits a one-line notice; the module-level work now lives in main(), the line builder and the append take a ledger path, and --selftest exercises them against a temp file.
FLAG: The yellow reason (no --selftest) is fixed by employee T-0913-YEL-1; live behavior is unchanged (same line format, same message), verified by the pipe test line in the real ledger and a diff read. Selftest 0 failed. Re-flagged by the manager who verified the diff, not its author.

### 2026-09-13 12:21 | hooks/prompt_gauge.py | GREEN | fable | WS1 | 901e18d1
SAYS: UserPromptSubmit hook that stays silent on a normal turn and, when a threshold is crossed, prints the checkpoint counter warning (8 tasks advised, 15 dire) and the context-remaining warning, plus since 2026-09-13 a KIT UNSYNCED line when a portable original is newer than its kit copy.
DOES: UserPromptSubmit hook: silent on a normal turn; prints the checkpoint counter line at 8 and 15 tasks, the context line under 80 and 30 percent remaining, and the KIT UNSYNCED line while the kit lags; gauge_lines() is the pure threshold builder and --selftest checks its five cases.
FLAG: The yellow reason (no --selftest) is fixed by employee T-0913-YEL-1; the threshold text is byte-identical to before, moved into gauge_lines() and main(). Selftest 0 failed; pipe test prints only the kit line at n=0. Re-flagged by the manager who verified the diff.

### 2026-09-13 12:21 | hooks/session_start.py | GREEN | fable | WS1 | 22cbca42
SAYS: SessionStart hook that runs tools/standup.py and injects its digest into the manager's context on startup, resume, /clear and after a compaction, with a header telling the manager not to re-run standup and how to relay the last exchange.
DOES: SessionStart hook: runs tools/standup.py in a subprocess and injects its digest as additionalContext with a relay header; header_for() builds the header and --selftest checks it plus the standup script's presence without running standup.
FLAG: The yellow reason (no --selftest) is fixed by employee T-0913-YEL-1; the header text and the subprocess call are unchanged, verified by the pipe test returning the digest JSON. Selftest 0 failed. Re-flagged by the manager who verified the diff.

### 2026-09-13 12:21 | hooks/README.txt | GREEN | fable | WS1 | 712166c6
SAYS: Installation notes for the Rootstock hooks folder: what each hook file needs filled in or wired (bash_guard.py's PROJECT RULES, fanout_guard.py's numbers via the runaway skill, hygiene_guard.py's CONFIG block) and the gitignore entries a new project needs.
DOES: Installation notes for the kit hooks folder: per-hook fill-in and wiring steps, the gitignore entries, the selftest command for each guard; this batch corrected the diet guard paragraph to say it refuses once (INDEX FIRST) and warns otherwise.
FLAG: Stale only because the diet guard paragraph changed; the new wording matches diet_guard.py's code and docstring. Re-flagged by the author of the wording fix.

### 2026-09-13 12:22 | HOOKS_METHOD.md | GREEN | fable | WS1 | 3b76afb5
SAYS: Documents the harness hooks, session start, prompt, stop, compaction, and tool-call guards, that enforce CLAUDE.md's laws mechanically instead of relying on the manager's memory, plus the hook contract and the kit's hook roster.
DOES: Documents the hook contract, the ten kit hooks by tier and the bootstrap; this batch appended one change-log line (v1.20: every hook answers --selftest, the diet guard wording, the front door's independent read).
FLAG: Stale from an appended change-log line only; the line matches the three selftests and the wording fix in the hook files. Re-flagged by the author of the addition.

### 2026-09-13 12:22 | UPGRADES.md | GREEN | fable | WS1 | 6df49141
SAYS: The append only graft log: every kit concept update, recorded as WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed project's own files, and which README section it touched, so installs update by concept rather than by overwriting a project's customized files.
DOES: The append-only graft log; this batch bumped the version to v1.20 and appended the entry for the closed yellows (WHAT / CARRIES / GRAFT / README).
FLAG: Stale from the v1.20 entry only; the entry names the files that actually changed and the README sections that carry the claims, and the README lint passes at v1.20. Re-flagged by the author of the entry.

### 2026-09-13 12:22 | hooks/README.txt | GREEN | fable | WS1 | 704677d6
SAYS: Installation notes for the Rootstock hooks folder: what each hook file needs filled in or wired (bash_guard.py's PROJECT RULES, fanout_guard.py's numbers via the runaway skill, hygiene_guard.py's CONFIG block) and the gitignore entries a new project needs.
DOES: Installation notes for the kit hooks folder: per-hook fill-in and wiring steps, gitignore entries, the selftest command per guard; the diet guard paragraph now says it refuses once and warns otherwise; header bumped to kit v1.20.
FLAG: Stale from the version bump on line 1 after the earlier re-flag; nothing else changed. Re-flagged by the author.

### 2026-09-14 00:58 | HOOKS_METHOD.md | GREEN | sonnet-flag1 | WS1 | d104bcd7
SAYS: Documents the harness hooks, session start, prompt, stop, compaction, and tool-call guards, that enforce CLAUDE.md's laws mechanically instead of relying on the manager's memory, plus the hook contract and the kit's hook roster.
DOES: Appends a dated lesson entry about the loop law (session_start running the session group, stop_tick warning on unexported commits) to the lessons log.
FLAG: Matches the file's own job of logging hard-won lessons with tags, nothing added outside that scope.

### 2026-09-14 00:58 | INTENT_METHOD.md | GREEN | sonnet-flag1 | WS1 | c0b6d333
SAYS: The intent discipline: one project file, INTENT.md, holds one section per ruling with the owner's verbatim ASKED and WHY, the manager's GENERALIZES TO reading, and a LIVES IN pointer, plus a comparison ledger, correction ritual, and periodic report measuring whether Claude's reading of the owner's intent is converging on it.
DOES: Adds two new ruling sections, the loop law and security first then cost then efficiency, each with the owner's verbatim words and tags.
FLAG: Consistent with the file's stated job of recording rulings verbatim with a manager generalization.

### 2026-09-14 00:58 | SUBAGENT_METHOD.md | GREEN | sonnet-flag1 | WS1 | 5fb1dd45
SAYS: A portable architecture for delegating work to sub-agent employees: the org chart (CEO, manager, employees), why it saves money, the seven laws, the assignments table, the scorecard, and bootstrap steps for a new project.
DOES: Adds Tags lines to four existing section headings (org chart, why this saves money, seven laws, attribution) without changing their content.
FLAG: Pure tagging for the KNOWLEDGE_INDEX export, matches the wiki tagging convention this file already follows.

### 2026-09-14 00:58 | UPGRADES.md | GREEN | sonnet-flag1 | WS1 | 5a39f152
SAYS: The append only graft log: every kit concept update, recorded as WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed project's own files, and which README section it touched, so installs update by concept rather than by overwriting a project's customized files.
DOES: Bumps CURRENT KIT VERSION to v1.21 and appends the v1.21 entry (WHAT/CARRIES/GRAFT/README) describing the first systems audit's rulings.
FLAG: Follows the file's own append-only WHAT/CARRIES/GRAFT/README format exactly.

### 2026-09-14 00:58 | hooks/README.txt | GREEN | sonnet-flag1 | WS1 | 0a405804
SAYS: Installation notes for the Rootstock hooks folder: what each hook file needs filled in or wired (bash_guard.py's PROJECT RULES, fanout_guard.py's numbers via the runaway skill, hygiene_guard.py's CONFIG block) and the gitignore entries a new project needs.
DOES: Adds one paragraph documenting that session_start.py now runs the session group daily and ledgers digest size, and stop_tick.py now warns CHANGELOG UNEXPORTED.
FLAG: Accurately summarizes the two hook changes reviewed in the same batch, nothing overstated.

### 2026-09-14 00:59 | hooks/session_start.py | GREEN | sonnet-flag1 | WS1 | b1f5f203
SAYS: SessionStart hook that runs tools/standup.py and injects its digest into the manager's context on startup, resume, /clear and after a compaction, with a header telling the manager not to re-run standup and how to relay the last exchange; also runs the session group itself when it has not run today (THE LOOP LAW) and ledgers the digest's byte size.
DOES: Adds loop_note(), which runs run_all.py session once a day via subprocess with a 600s timeout when the session group has not run today, and log_digest_size(), which appends one line to digest_size.txt for every injected digest; both are wrapped so a failure never blocks the digest.
FLAG: PURPOSE and INTENT were updated to name both the daily session run and the digest size ledger, so the new subprocess and the new ledger are disclosed, not hidden.

### 2026-09-14 00:59 | hooks/stop_tick.py | GREEN | sonnet-flag1 | WS1 | f5547518
SAYS: Stop hook that ticks the checkpoint counter only when work actually happened (HEAD moved or the tree changed since the last Stop), shows an advised system message at 8 tasks or under 80% context, refuses to end the turn once at 15 tasks or under 30% context (re-blocking every 5 further tasks), refuses once when a safety hook has gone unwired in settings.json, and warns once per unexported commit count when the changelog anchor has fallen behind HEAD.
DOES: Adds a warn-only CHANGELOG UNEXPORTED note when tools/.changelog_anchor exists and HEAD has moved past it, deduped per commit count via the existing hook state file, silent when there is no anchor.
FLAG: PURPOSE and INTENT name the changelog warning explicitly, and the selftest only touches temp anchor files, never the real tools/.changelog_anchor.

### 2026-09-14 00:59 | reference tools/_ledger.py | GREEN | sonnet-flag1 | WS1 | b63026eb
SAYS: One append_unless_identical() call site for the four check-script ledgers (format_lint, purpose_audit, readme_lint, check_wiki_links) so a rerun at an unchanged tree does not grow duplicate rows.
DOES: New shared module: append_unless_identical() skips an append when the ledger's last line has the same payload, same date, and the same git HEAD and dirty signature (excluding the ledger files themselves); includes a selftest against a temp dir.
FLAG: Body matches the PURPOSE line exactly, one helper for the four named callers and nothing else.

### 2026-09-14 00:59 | reference tools/check_wiki_links.py | GREEN | sonnet-flag1 | WS1 | fe16e092
SAYS: Warn-only link checker for the knowledge wiki: scan repo-root, docs/systems and docs/cold markdown for the four cross-reference forms, resolve each against the repo, and report dead links plus See-also hygiene.
DOES: Replaces the direct ledger append with _ledger.append_unless_identical so an unchanged rerun does not duplicate a row in wiki_link_runs.txt.
FLAG: Same ledger, same PURPOSE, only the append is deduped, the file still reads as a warn-only link checker.

### 2026-09-14 00:59 | reference tools/correction_log.py | GREEN | sonnet-flag1 | WS1 | bed7b6c0
SAYS: Record the correction ledger: a RECORD line the moment a correction is understood in the CEO's own words, a FIXED line when the fix ships, and resolve the named intent claim as DIFFERENT in the intent log when one is given.
DOES: Adds a --selftest that exercises record()/fixed() against a temp ledger with subprocess.run stubbed, so no real intent claim is resolved and the live corrections.txt is never touched.
FLAG: Matches the kit-wide selftest convention, the scratch dir is left on disk per the preservation law, nothing deleted.

### 2026-09-14 00:59 | reference tools/delete_grant.py | GREEN | sonnet-flag1 | WS1 | 26cea7dc
SAYS: Record the owner's double-acknowledged permission for one deletion: write the single-use, time-limited grant file and append the committed delete grants ledger, refusing targets in the never-delete list; performs no deletion itself.
DOES: Factors the write into write_grant() with injectable paths and clock, then adds a --selftest exercising it against temp files including expiry and never-list refusals; main() behavior is unchanged.
FLAG: PURPOSE already covers writing the grant file and ledger and refusing never-list targets, the refactor and selftest add no new live-file behavior.

### 2026-09-14 00:59 | reference tools/format_lint.py | GREEN | sonnet-flag1 | WS1 | 19b06167
SAYS: check every kit thing (a script, a hook, a skill, a method file, the hooks README, the settings template) and its repo original for the one header the filing system needs - PURPOSE, INTENT, Search keys, See also - plus the safety wiring in settings.json; report PASS/FAIL per file with the reason; on request rewrite ONLY the missing scaffold lines, never the body.
DOES: Replaces the direct ledger append with _ledger.append_unless_identical so an unchanged rerun does not duplicate a row in the format lint runs ledger.
FLAG: Internal reliability change only, the file's PURPOSE of linting the format law and ledgering the run still holds.

### 2026-09-14 00:59 | reference tools/ledger_trends.py | GREEN | sonnet-flag1 | WS1 | 5593425f
SAYS: Reads the tails of the project's history ledgers (usage, tests, wiki links, wiki heat, employee corrections, compactions, README audit, intent claims, corrections, systems audit, open questions, digest size, the run_all loop), compares them against tunable thresholds, and prints proposed rule changes; it applies nothing itself.
DOES: Adds three new proposal rules (open questions past N days, an oversized standup digest, a stale run_all group) and moves proposal-only thresholds into a tunable .claude/trend_limits.json read fresh each call, with --limits reporting source per key.
FLAG: PURPOSE, INTENT and search keys were all updated to name open questions, digest size, the run_all loop and the limits file, nothing here is undisclosed.

### 2026-09-14 00:59 | reference tools/open_questions.py | GREEN | sonnet-flag1 | WS1 | f64b0c92
SAYS: Log a question only the owner can answer, list the open ones with their age, and record the resolution in the owner's own words when it lands, append-only.
DOES: New CLI and ledger: --add raises a question, --resolve records the owner's answer, --open lists open ones oldest first with age, appending to docs/history/open_questions.txt.
FLAG: Body matches its PURPOSE line exactly.

### 2026-09-14 00:59 | reference tools/purpose_audit.py | GREEN | sonnet-flag1 | WS1 | 3e3e19e7
SAYS: keep the kit's flag ledger (FLAGS.md in the kit folder): every kit thing's latest flag (GREEN / YELLOW / RED), who gave it and when, whether the thing changed since (STALE), the ones nobody has audited yet (UNFLAGGED), and the tally - regenerated in place from the entries; `--flag` appends one entry (SAYS = the thing's own PURPOSE line, DOES = what the reviewer found it actually does, FLAG = why the color).
DOES: Replaces the direct ledger append with _ledger.append_unless_identical so an unchanged rerun does not duplicate a row in purpose_audit_runs.txt; the flagging logic itself is unchanged.
FLAG: Internal reliability change only, consistent with the file's own PURPOSE of keeping the flag ledger.

### 2026-09-14 00:59 | reference tools/readme_lint.py | GREEN | sonnet-flag1 | WS1 | 9520ba06
SAYS: Derives every countable README fact (laws, skills, hooks, reference tools, the box table, version, the graft README line, number word claims, prose claims) from the kit folder itself and compares it with what the public README says, ledgering PASS, FAIL or SKIP each run.
DOES: Replaces the direct ledger append with _ledger.append_unless_identical so an unchanged rerun does not duplicate a row in the README parity lint ledger.
FLAG: Same ledger, same PURPOSE, only the append is deduped.

### 2026-09-14 00:59 | reference tools/retire.py | GREEN | sonnet-flag1 | WS1 | d9276e6a
SAYS: Moves a file to _retired/ (same relative path, Godot import extensions suffixed .retired) and appends one line to docs/history/retired_files.txt; nothing is ever deleted.
DOES: Adds a --selftest that exercises the real retire() move-and-ledger path against a temp ROOT/SHELF/LEDGER, proving byte-identical moves and header handling without ever touching the live _retired/ folder or ledger.
FLAG: No deletion anywhere in the selftest or the mover, matches the never-delete PURPOSE line.

### 2026-09-14 00:59 | reference tools/run_all.py | GREEN | sonnet-flag1 | WS1 | d6e1356a
SAYS: Chain habitual scripts by named group (check/regen/tests/metrics/ probes/builds/session/standup) and ledger every group run so staleness is visible instead of silent.
DOES: New parent-loop runner: chains named groups of scripts (check/regen/tests/metrics/probes/builds/session/standup), prints each step's tail, stops on first failure, and appends one loop_runs.txt line per group with duration and result; last_run() reads that ledger for session_start.py.
FLAG: Body matches the PURPOSE line exactly, including the full group list.

### 2026-09-14 00:59 | reference tools/standup.py | YELLOW | sonnet-flag1 | WS1 | 0204c51e
SAYS: Prints the post pull standup digest: the last exchange mined from harness transcripts, the day file's WHERE WE LEFT OFF, the usage budget line, ledger trend proposals, version and recent commits, WS notes, ledger tails, and the open roadmap index.
DOES: Adds print_loop() (prints each run_all group's last run and age from loop_runs.txt) and print_open_questions() (prints open_questions.py's open rows oldest first) as two new sections printed on every standup run.
FLAG: The PURPOSE line still lists only the pre-existing sections and should also name THE LOOP and OPEN QUESTIONS TO MAZHRON blocks since they now print on every run; add them to PURPOSE in a later batch.

### 2026-09-14 00:59 | reference tools/usage_report.py | YELLOW | sonnet-flag1 | WS1 | dcf11aff
SAYS: Mines the Claude Code harness JSONL transcripts for real per model per tool token usage and writes an aggregate usage sheet (CSV, TXT, XLSX, employee runs, and the daily budget line) totaled by day, week and month.
DOES: Adds arc_lines()/miss_lines() and wires them into main() to write two new ledgers every run, docs/history/usage_by_arc.txt (per-arc spend between Checkpoint commits, via git log subprocess calls) and docs/history/cache_misses.txt plus cache_miss_runs.txt (per-miss cause classification), alongside the existing daily/CSV/XLSX outputs.
FLAG: The PURPOSE line only names the aggregate usage sheet totaled by day, week and month, it should also name usage_by_arc.txt and cache_misses.txt/cache_miss_runs.txt, which the file body documents but PURPOSE does not.

### 2026-09-14 00:59 | skills/checkpoint/SKILL.md | GREEN | sonnet-flag1 | WS1 | 95bfccc9
SAYS: Close an arc safely: push, refresh the day file's WHERE WE LEFT OFF section with both sides of the final exchange verbatim, reset the task counter, and emit the safe-to-clear marker.
DOES: Adds a new SEQUENCE step 0 that runs the session loop group, checks for an unexported changelog, and asks once whether anything was done by hand twice (a workflow gap) before the existing push and day-file steps.
FLAG: Fits the skill's own stated purpose of closing an arc safely, this is a precondition-style addition, not a new capability outside that purpose.

### 2026-09-14 00:59 | skills/flag/SKILL.md | GREEN | sonnet-flag1 | WS1 | 0a20dd69
SAYS: the ritual behind FLAGS.md - one kit thing at a time, the auditor reads it, compares the stated purpose with the behaviour, gives it a color, explains the color in the entry, and never touches the thing.
DOES: Adds THE BATCH RULE to step 1: more than about five pending items go to one read-only employee that files the flags itself, with the manager reading only the REDs it reports.
FLAG: Matches the skill's own stated purpose of running the ritual, this documents who performs it at scale, not a new behavior.

### 2026-09-14 01:01 | reference tools/standup.py | GREEN | fable | WS1 | 8927b63b
SAYS: Prints the post pull standup digest: the last exchange mined from harness transcripts, the day file's WHERE WE LEFT OFF, the usage budget line, THE LOOP (each run_all group's age), ledger trend proposals, version and recent commits, WS notes, ledger tails, the open roadmap index, and OPEN QUESTIONS TO MAZHRON.
DOES: prints the digest: last exchange, where we left off, the budget line, THE LOOP block, trend proposals, version + commits, WS notes, ledger tails, roadmap index, OPEN QUESTIONS block
FLAG: PURPOSE amended 2026-09-14 to name THE LOOP and OPEN QUESTIONS blocks the yellow named; re-read the block list against main(), matches

### 2026-09-14 01:01 | reference tools/usage_report.py | GREEN | fable | WS1 | d12a7b49
SAYS: Mines the Claude Code harness JSONL transcripts for real per model per tool token usage and writes an aggregate usage sheet (CSV, TXT, XLSX, employee runs, and the daily budget line) totaled by day, week and month, plus usage_by_arc.txt (checkpoint to checkpoint) and cache_misses.txt + cache_miss_runs.txt (every miss with its likely cause).
DOES: mines transcripts into the usage sheet, the daily line, usage_by_arc.txt and cache_misses.txt + cache_miss_runs.txt
FLAG: PURPOSE amended 2026-09-14 to name the two new ledgers the yellow named; main() writes exactly those

### 2026-09-14 01:01 | reference tools/run_all.py | GREEN | fable | WS1 | 946248e6
SAYS: Chain habitual scripts by named group (check/regen/tests/metrics/ probes/builds/session/standup) and ledger every group run so staleness is visible instead of silent.
DOES: runs the named groups in order, appends one loop_runs.txt line per group, and a composite (session) also logs its members; --stale prints each group's age
FLAG: re-flag after the composite-member logging patch of 2026-09-14; header names the ledger and the flag

### 2026-09-14 15:40 | 0 - READ ME FIRST.md | GREEN | sonnet-cd1 | WS1 | c9205c6c
SAYS: The kit's front door: walks a receiving Claude through the install in order (ask the CEO first, then the wiki, reporting and session rituals, the delegation company, the skills and hooks, the companions, the optional boards) by POINTING at each method file's bootstrap section, so the operating system lands the same way every time.
DOES: Walks a receiving Claude through install order (ask CEO, wiki, reporting, delegation, skills/hooks, optional boards), pointing at each method file's bootstrap section; states it is not a CLAUDE.md and loads once at install
FLAG: Body matches PURPOSE exactly: STEP 0-5 plus DEFINITION OF DONE and the update-existing-install section all point outward as described, no restated content found

### 2026-09-14 15:40 | UPGRADES.md | GREEN | sonnet-cd1 | WS1 | 654539f1
SAYS: The append only graft log: every kit concept update, recorded as WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed project's own files, and which README section it touched, so installs update by concept rather than by overwriting a project's customized files.
DOES: Append-only graft log; CURRENT KIT VERSION bumped to v1.22 and a new dated entry (the core diet) appended with WHAT/CARRIES/GRAFT/README fields intact
FLAG: Matches PURPOSE (graft log, never overwritten files); v1.22 entry follows the established WHAT/CARRIES/GRAFT/README shape

### 2026-09-14 15:40 | WIKI_METHOD.md | GREEN | sonnet-cd1 | WS1 | ba864436
SAYS: A portable system for organizing a project's knowledge (a lean CLAUDE.md core, a docs/systems topic library, portable root notes) so an AI assistant finds anything in three cheap hops, Glob, Grep for headings, then a targeted Read, without wasting tokens.
DOES: New section 'The hot core and the sub-indexes' fully specifies the core-diet law (units, Index: routing, heat, moves, sub-indexes, nothing deleted); architecture layer 1 reworded to describe the token-budgeted hot core and docs/index fallout
FLAG: Text matches core_diet.py's actual behavior verified separately; See-also links point at core_diet.py, check_claude_md.py, WORKFLOWS.md, INTENT.md

### 2026-09-14 15:40 | hooks/hygiene_guard.py | GREEN | sonnet-cd1 | WS1 | 4977f284
SAYS: PostToolUse guard on Write, Edit and MultiEdit that, after an edit lands, hands the manager one line of context per applicable law: KIT REFRESH when a portable original changed, SEE-ALSO when a touched docs/systems section has no See also line, DASH when player-facing text received an em or en dash (this one BLOCKS), and IMPORT when a new asset needs the engine import run; stateless pattern matching only.
DOES: PostToolUse guard on Write/Edit/MultiEdit; KIT_ONLY set lists '0 - READ ME FIRST.md' (with a comment noting the 2026-09-14 rename) alongside UPGRADES.md/CONTRIBUTING.md/FLAGS.md as kit-only files with no repo-root original
FLAG: Matches PURPOSE; KIT_MDS/KIT_ONLY/CORE_FILE config block is consistent with the renamed front door and triggers KIT REFRESH guidance correctly

### 2026-09-14 15:40 | reference tools/check_claude_md.py | GREEN | sonnet-cd1 | WS1 | ae5a2bf7
SAYS: Read CLAUDE.md and fail with exit 1 when the lean core exceeds its token or line budget or when the docs/systems library index or the docs/index sub-index list in CLAUDE.md drifts from the files on disk.
DOES: TOKEN_BUDGET=3500 constant added and enforced (bytes/4) with FAIL past it; checks docs/index sub-index list in CLAUDE.md against files on disk both directions; body executes under an if __name__ == '__main__' guard
FLAG: Matches PURPOSE exactly: token budget, docs/index drift check, and main-guard all verified in code

### 2026-09-14 15:40 | reference tools/cold_shelf.py | GREEN | sonnet-cd1 | WS1 | b3d21559
SAYS: Move a rarely used ## wiki section out of a hot file to the cold shelf verbatim, restore one back, list the cold shelf index, or check that every stub still points at an existing cold file and heading.
DOES: hot_files() now globs docs/index/*.md alongside repo-root and docs/systems, so --check verifies stubs there too; --move/--restore/--list logic unchanged and still contains no deletion calls
FLAG: PURPOSE stays generic (hot wiki file, cold shelf, stub check) so the docs/index addition is a compatible extension, not a contradiction

### 2026-09-14 15:40 | reference tools/core_diet.py | GREEN | sonnet-cd1 | WS1 | f7e93c5d
SAYS: Measure the heat of every CLAUDE.md section from the transcript read cache, git recency and pointer follows, report it, and move cold or over-budget routed sections verbatim into named sub-index files under docs/index/ leaving a one-line stub, with an explicit move and a restore, so the always-loaded core stays inside its token budget by script.
DOES: New heat-based mover, read whole: measures each CLAUDE.md unit's heat from wiki_heat's transcript cache (reads+follows) plus git-blame recency; --move moves cold routed units then coldest-until-budget verbatim into docs/index/<name>.md with a provenance comment and a stub line in the ## The sub-indexes block; --move-section, --restore and --selftest all implemented and wired; writes docs/history/core_diet.txt report and core_diet_runs.txt ledger
FLAG: Every claim in the PURPOSE and the manager's context note checked against code line by line and confirmed; no os.remove/unlink/rmtree calls anywhere, selftest proves the move+restore round trip

### 2026-09-14 15:40 | reference tools/run_all.py | GREEN | sonnet-cd1 | WS1 | afe11490
SAYS: Chain habitual scripts by named group (check/regen/tests/metrics/ probes/builds/session/standup) and ledger every group run so staleness is visible instead of silent.
DOES: GROUPS['check'] list's first element is ['tools/core_diet.py', '--move'], running before check_claude_md so cold sections move before the lint judges size
FLAG: Matches PURPOSE and the CARRIES claim in UPGRADES.md v1.22

### 2026-09-14 15:40 | reference tools/standup.py | GREEN | sonnet-cd1 | WS1 | 29a42fe0
SAYS: Prints the post pull standup digest: the last exchange mined from harness transcripts, the day file's WHERE WE LEFT OFF, the usage budget line, THE LOOP (each run_all group's age), ledger trend proposals, version and recent commits, WS notes, ledger tails, the open roadmap index, and OPEN QUESTIONS TO MAZHRON.
DOES: print_last_exchange sets a 'replayed' flag; the WHERE WE LEFT OFF block then skips reprinting the quoted prompt/response lines when already replayed, printing an omitted-here note instead; the ledger tails section prints only lines[-1] per docs/history/*.txt file
FLAG: Matches PURPOSE and the digest-diet comments in the code; verified both the no-duplicate-exchange logic and the one-tail-line-per-ledger logic directly

### 2026-09-14 15:40 | reference tools/check_wiki_links.py | YELLOW | sonnet-cd1 | WS1 | 1c3cf977
SAYS: Warn-only link checker for the knowledge wiki: scan repo-root, docs/systems and docs/cold markdown for the four cross-reference forms, resolve each against the repo, and report dead links plus See-also hygiene.
DOES: wiki_files() now also lists docs/index/*.md, and the CLAUDE.md mention-check regex covers both docs/systems and docs/index tokens, so docs/index sub-indexes are fully scanned for dead links
FLAG: Drift: the PURPOSE line and the 'THE WIKI:' docstring definition still say only repo-root, docs/systems and docs/cold markdown; docs/index is a found feature not stated. Fix: add docs/index to the PURPOSE line and THE WIKI definition

### 2026-09-14 15:40 | reference tools/export_tag_index.py | YELLOW | sonnet-cd1 | WS1 | d8a73453
SAYS: Sweep repo-root and docs/systems markdown for Tags lines under headings and compile KNOWLEDGE_INDEX.md, one section per tag with links to each section's true home.
DOES: main() now also lists docs/index/*.md and appends them to the sweep with a 'docs/index/<name>' label, so Tags lines inside sub-indexes are compiled into KNOWLEDGE_INDEX.md too
FLAG: Drift: the PURPOSE line and the opening docstring both say it sweeps only repo-root and docs/systems markdown; docs/index is a found feature not stated. Fix: mention docs/index in the PURPOSE line

### 2026-09-14 15:40 | reference tools/wiki_heat.py | YELLOW | sonnet-cd1 | WS1 | 0eb142d6
SAYS: Mines the harness transcripts for read events against wiki markdown files and sections, reports file and section read counts plus hot and cold sections, and classifies cold sections by why they are cold using git activity in their code areas; it never moves anything.
DOES: discover_wiki_files adds docs/index/*.md under a 'docs/index/' id prefix and match_wiki_file categorizes it, so sub-index reads are tracked and reported
FLAG: Drift: the docstring's explicit 'THE WIKI = ...' definition near the top lists only repo-root, docs/systems and docs/cold, omitting docs/index even though the code discovers it; the PURPOSE line itself is vague enough to not directly contradict. Fix: add docs/index to THE WIKI definition

### 2026-09-14 15:42 | reference tools/check_wiki_links.py | GREEN | fable | WS1 | 927f4401
SAYS: Warn-only link checker for the knowledge wiki: scan repo-root, docs/systems, docs/cold and docs/index markdown for the four cross-reference forms, resolve each against the repo, and report dead links plus See-also hygiene.
DOES: discovers docs/index/*.md alongside repo-root, docs/systems and docs/cold; header now says so
FLAG: the yellow named the header prose omitting docs/index; the THE WIKI / PURPOSE lines were amended 2026-09-14 and re-read against the discovery code

### 2026-09-14 15:42 | reference tools/export_tag_index.py | GREEN | fable | WS1 | fc517f23
SAYS: Sweep repo-root, docs/systems and docs/index markdown for Tags lines under headings and compile KNOWLEDGE_INDEX.md, one section per tag with links to each section's true home.
DOES: discovers docs/index/*.md alongside repo-root, docs/systems and docs/cold; header now says so
FLAG: the yellow named the header prose omitting docs/index; the THE WIKI / PURPOSE lines were amended 2026-09-14 and re-read against the discovery code

### 2026-09-14 15:42 | reference tools/wiki_heat.py | GREEN | fable | WS1 | faa038d8
SAYS: Mines the harness transcripts for read events against wiki markdown files and sections, reports file and section read counts plus hot and cold sections, and classifies cold sections by why they are cold using git activity in their code areas; it never moves anything.
DOES: discovers docs/index/*.md alongside repo-root, docs/systems and docs/cold; header now says so
FLAG: the yellow named the header prose omitting docs/index; the THE WIKI / PURPOSE lines were amended 2026-09-14 and re-read against the discovery code

### 2026-09-14 16:32 | rules/wiki.md | GREEN | sonnet-PC-FLAG-1 | WS1 | 62ac5a1e
SAYS: path-scoped rule carrying the wiki convention at the moment a markdown file is read: headings are search keys, every section ends with See also, the core stays a pointer file, nothing is deleted
DOES: Path-scoped rule (paths: **/*.md) injecting the wiki convention (read cheap, headings as search keys, grow the wiki into docs/systems + one MASTER_INDEX line, preservation law) whenever a markdown file is open; its format header sits inside an HTML block comment so the comment is stripped before the rule enters context
FLAG: Matches its own header exactly; body content is identical to the source .claude/rules/wiki.md; correctly points new always-true knowledge to a sub-index or path-scoped rule instead of CLAUDE.md

### 2026-09-14 16:32 | 0 - READ ME FIRST.md | GREEN | sonnet-PC-FLAG-1 | WS1 | 16eaae6a
SAYS: The kit's front door: walks a receiving Claude through the install in order (ask the CEO first, then the wiki, reporting and session rituals, the delegation company, the skills and hooks, the companions, the optional boards) by POINTING at each method file's bootstrap section, so the operating system lands the same way every time.
DOES: Install runbook walking a receiving Claude through STEP 0-5 by pointing at each method file's bootstrap section; STEP 1 already describes the pointer-core CLAUDE.md, docs/index/MASTER_INDEX.md as the one door, .claude/rules path-scoped rules including copying rules/wiki.md, and the 200-line/2000-token lint
FLAG: Content matches current behavior, no stale references to the old stub-in-CLAUDE.md scheme found

### 2026-09-14 16:32 | UPGRADES.md | GREEN | sonnet-PC-FLAG-1 | WS1 | 026fae52
SAYS: The append only graft log: every kit concept update, recorded as WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed project's own files, and which README section it touched, so installs update by concept rather than by overwriting a project's customized files.
DOES: Append-only graft log; the v1.23 entry (lines ~815-882) documents today's pointer-core batch accurately: the pointer core, three knowledge homes, the guard's LINE_BUDGET/TOKEN_BUDGET/WARN_TOKENS and its rule paths check, core_diet.py's stub moving to the master index, check_wiki_links treating the master index like the core, refresh_kit's PORTABLE_RULES, and the new WORKFLOWS entry
FLAG: Entry is thorough and current, matches the actual files it lists under CARRIES

### 2026-09-14 16:32 | WIKI_METHOD.md | GREEN | sonnet-PC-FLAG-1 | WS1 | 8de2a323
SAYS: A portable system for organizing a project's knowledge (a lean CLAUDE.md core, a docs/systems topic library, portable root notes) so an AI assistant finds anything in three cheap hops, Glob, Grep for headings, then a targeted Read, without wasting tokens.
DOES: Portable method file; both the architecture section (layer 1) and 'The hot core and the sub-indexes' section fully describe the 2026-09-14 pointer-core restructure: three knowledge homes (CLAUDE.md always, path-scoped rules when a file is read, MASTER_INDEX.md on demand), the LINE_BUDGET/TOKEN_BUDGET/WARN_TOKENS guard, and that the sub-indexes stub block now lives in the master index rather than CLAUDE.md itself
FLAG: No stale language describing the old CLAUDE.md-holds-its-own-stub-block behavior found; matches core_diet.py and check_claude_md.py as read

### 2026-09-14 16:32 | hooks/hygiene_guard.py | GREEN | sonnet-PC-FLAG-1 | WS1 | 2d15b330
SAYS: PostToolUse guard on Write, Edit and MultiEdit that, after an edit lands, hands the manager one line of context per applicable law: KIT REFRESH when a portable original changed, SEE-ALSO when a touched docs/systems section has no See also line, DASH when player-facing text received an em or en dash (this one BLOCKS), and IMPORT when a new asset needs the engine import run; stateless pattern matching only.
DOES: PostToolUse guard on Write/Edit/MultiEdit; kit_refresh() checks r == CORE_FILE or r == CORE_CONTRACT[0] (docs/index/MASTER_INDEX.md) or r.startswith(CORE_CONTRACT[1]) (.claude/rules/) and runs check_claude_md.py, relaying a FAIL; also emits KIT REFRESH, SEE-ALSO, DASH (blocking) and IMPORT lines as documented
FLAG: CORE_CONTRACT tuple matches the PURPOSE/header description that editing the core, the master index or a rules file triggers the lint; selftest covers CLAUDE.md triggering the lint but not MASTER_INDEX.md or a rules file directly, a minor test gap rather than a purpose mismatch

### 2026-09-14 16:32 | reference tools/check_claude_md.py | GREEN | sonnet-PC-FLAG-1 | WS1 | b547dc7e
SAYS: Read CLAUDE.md and fail with exit 1 when the pointer core exceeds its token or line budget, when CLAUDE.md does not name the master index, when the master index (docs/index/MASTER_INDEX.md) drifts from the docs/systems and docs/index files on disk, or when a .claude/rules file has no paths field (it would load every session; its tokens count against the core); warn past WARN_TOKENS.
DOES: Reads CLAUDE.md, fails at LINE_BUDGET 200 or TOKEN_BUDGET 2000, warns past WARN_TOKENS 1000, requires CLAUDE.md to name docs/index/MASTER_INDEX.md, requires the master index to list every docs/systems file, every docs/index sub-index and every scoped .claude/rules file, and fails when a rules file lacks a paths: front matter field (counting its tokens against the core budget)
FLAG: Body matches PURPOSE line for line, no undisclosed behavior

### 2026-09-14 16:32 | reference tools/check_wiki_links.py | GREEN | sonnet-PC-FLAG-1 | WS1 | 7d51e915
SAYS: Warn-only link checker for the knowledge wiki: scan repo-root, docs/systems, docs/cold and docs/index markdown for the four cross-reference forms, resolve each against the repo, and report dead links plus See-also hygiene.
DOES: Scans repo-root, docs/systems, docs/cold and docs/index markdown for the four cross-reference forms and reports dead links plus See-also hygiene; is_claude_md now covers both CLAUDE.md and MASTER_INDEX.md (line 270) so form (d), every docs/systems and docs/index mention, is checked in both files; writes docs/history/wiki_links.txt and appends to wiki_link_runs.txt, never deletes
FLAG: Docstring form (d) explicitly names MASTER_INDEX.md, matching the code; PURPOSE line's general docs/index wording is consistent with this

### 2026-09-14 16:32 | reference tools/core_diet.py | GREEN | sonnet-PC-FLAG-1 | WS1 | ec76c931
SAYS: Measure the heat of every CLAUDE.md section from the transcript read cache, git recency and pointer follows, report it, and move cold or over-budget routed sections verbatim into named sub-index files under docs/index/ leaving a one-line stub, with an explicit move and a restore, so the always-loaded core stays inside its token budget by script.
DOES: Measures CLAUDE.md section heat (reads, follows, git recency), then --move moves cold or over-budget routed sections verbatim into docs/index/<name>.md, leaving one stub line in docs/index/MASTER_INDEX.md's sub-indexes block (moved out of CLAUDE.md itself per the 2026-09-14 pointer core); --restore reverses it and also strips a stub from a pre-09-14 core that still holds its own block; selftest exercises the full move/restore round trip against the master index
FLAG: Docstring and code agree that the stub block lives in the master index now, not CLAUDE.md; no deletion, matches the preservation law

### 2026-09-14 16:32 | reference tools/refresh_kit.py | YELLOW | sonnet-PC-FLAG-1 | WS1 | 22e9186d
SAYS: copy every portable ORIGINAL to its grab-copy in the kit folder (repo-root MDs, .claude/skills/*/SKILL.md, tools/hooks/*.py, the tools/*.py that have a reference copy), with the one substitution the kit carries in scripts (the owner's name -> "the CEO"); report the hand-adapted files it must never overwrite; `--check` only says what is out of step (the prompt hook's KIT UNSYNCED line).
DOES: Copies portable originals to their kit grab-copies; pairs() now also copies any rules/*.md file named in PORTABLE_RULES (currently wiki.md) from .claude/rules/ to the kit's rules/ folder, applying the CEO substitution to it as a script
FLAG: PURPOSE line lists 'repo-root MDs, .claude/skills/*/SKILL.md, tools/hooks/*.py, the tools/*.py that have a reference copy' but omits the .claude/rules/ PORTABLE_RULES category entirely, even though pairs() (lines 89-92) copies rules/wiki.md every run. Fix: add '.claude/rules/*.md files listed in PORTABLE_RULES' to the PURPOSE line's parenthetical list

### 2026-09-14 16:33 | reference tools/standup.py | YELLOW | sonnet-PC-FLAG-1 | WS1 | bb3c3ee6
SAYS: Prints the post pull standup digest: the last exchange mined from harness transcripts, the day file's WHERE WE LEFT OFF, the usage budget line, THE LOOP (each run_all group's age), ledger trend proposals, version and recent commits, WS notes, ledger tails, the open roadmap index, and OPEN QUESTIONS TO MAZHRON.
DOES: Prints the post-pull digest; also runs check_claude_md.py as a subprocess and prints its first output lines under a '== THE CORE' heading (lines 363-371), and reads workstation-note headlines from docs/index/notes.md under '== NEWEST WS NOTES' (lines 373-381)
FLAG: PURPOSE line lists the last exchange, WHERE WE LEFT OFF, the usage budget line, THE LOOP, ledger trend proposals, version and recent commits, WS notes, ledger tails, the open roadmap index, and OPEN QUESTIONS, but never mentions the == THE CORE section that runs check_claude_md.py and prints the lint's OK-or-WARN line every session. Fix: add '(5) the core lint's OK/WARN line under == THE CORE' to the PURPOSE list so the subprocess call is disclosed

### 2026-09-14 16:33 | reference tools/refresh_kit.py | GREEN | fable | WS1 | da71b966
SAYS: copy every portable ORIGINAL to its grab-copy in the kit folder (repo-root MDs, .claude/skills/*/SKILL.md, tools/hooks/*.py, the tools/*.py that have a reference copy, and the .claude/rules/*.md files named in PORTABLE_RULES), with the one substitution the kit carries in scripts (the owner's name -> "the CEO"); report the hand-adapted files it must never overwrite; `--check` only says what is out of step (the prompt hook's KIT UNSYNCED line).
DOES: copies every portable original (repo-root MDs, skills, hooks, reference tools, and the .claude/rules files named in PORTABLE_RULES) to its kit grab-copy with the CEO substitution in scripts; --check reports drift
FLAG: PC-FLAG-1 yellow: the PURPOSE list omitted the rules category; header amended to name PORTABLE_RULES

### 2026-09-14 16:33 | reference tools/standup.py | GREEN | fable | WS1 | 5eff3c08
SAYS: Prints the post pull standup digest: the last exchange mined from harness transcripts, the day file's WHERE WE LEFT OFF, the usage budget line, THE LOOP (each run_all group's age), ledger trend proposals, version and recent commits, THE CORE (check_claude_md.py's OK/WARN line, run as a subprocess so the owner sees the core's size every session), WS notes from docs/index/notes.md, ledger tails, the open roadmap index, and OPEN QUESTIONS TO MAZHRON.
DOES: prints the standup digest including THE CORE line from check_claude_md.py run as a subprocess and WS note headlines from docs/index/notes.md
FLAG: PC-FLAG-1 yellow: the PURPOSE list did not mention the core lint line; header amended

### 2026-09-14 16:55 | reference tools/purpose_audit.py | GREEN | fable | WS1 | f93ac4aa
SAYS: keep the kit's flag ledger (FLAGS.md in the kit folder): every kit thing's latest flag (GREEN / YELLOW / RED), who gave it and when, whether the thing changed since (STALE), the ones nobody has audited yet (UNFLAGGED), and the tally - regenerated in place from the entries; `--flag` appends one entry (SAYS = the thing's own PURPOSE line, DOES = what the reviewer found it actually does, FLAG = why the color).
DOES: keeps FLAGS.md: status regenerates the tally in place, --flag appends one entry, STALE/UNFLAGGED listed, one runs-ledger line per status run; since Q0003 option 2 the regenerate step compares the fresh tally block to the one in the file with the Updated stamp masked and skips the write when nothing else changed, so the stamp means last changed, not last run
FLAG: does what the PURPOSE says and nothing more; the no-change skip narrows a side effect (a timestamp rewrite every loop run) that the purpose never asked for; selftest covers both branches

### 2026-09-14 16:56 | UPGRADES.md | GREEN | fable | WS1 | 051849d8
SAYS: The append only graft log: every kit concept update, recorded as WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed project's own files, and which README section it touched, so installs update by concept rather than by overwriting a project's customized files.
DOES: the graft log: the current kit version line and one WHAT/CARRIES/GRAFT/README entry per concept, newest v1.24 the quiet audit; append-only, read by the README lint for the version and the README field
FLAG: matches its purpose; the v1.24 entry follows the entry shape and names its README section

### 2026-09-14 19:02 | reference tools/standup.py | GREEN | fable | WS1 | 9cc6925d
SAYS: Prints the post pull standup digest: the last exchange mined from harness transcripts, the day file's WHERE WE LEFT OFF, the usage budget line, THE LOOP (each run_all group's age), ledger trend proposals, version and recent commits, THE CORE (check_claude_md.py's OK/WARN line, run as a subprocess so the owner sees the core's size every session), WS notes from docs/index/notes.md, ledger tails, the open roadmap index, and OPEN QUESTIONS TO MAZHRON.
DOES: prints the session-start digest: the last exchange mined from the transcript, WHERE WE LEFT OFF, the budget line, the loop ages, proposals, version and five commits, the core lint line, WS note headlines, ledger tails (full line for a verdict or a ledger newer than the last standup, the rest as name plus date, ledgers shown elsewhere skipped), the roadmap index, open questions, recent days as first clauses; --selftest covers the pure diet helpers
FLAG: does what the PURPOSE says; the diet narrows what prints, never what exists, and the header tells the reader where the rest is

### 2026-09-14 19:02 | reference tools/ledger_trends.py | GREEN | fable | WS1 | 61eea05b
SAYS: Reads the tails of the project's history ledgers (usage, tests, wiki links, wiki heat, employee corrections, compactions, README audit, intent claims, corrections, systems audit, open questions, digest size, the run_all loop), compares them against tunable thresholds, and prints proposed rule changes; it applies nothing itself.
DOES: reads the history ledgers against thresholds (script DEFAULTS overlaid by .claude/trend_limits.json) and prints PROPOSE lines, nothing applied; digest_warn_bytes default now 12000 after the digest diet
FLAG: unchanged in behavior; one default lowered to match the smaller digest

### 2026-09-14 19:02 | UPGRADES.md | GREEN | fable | WS1 | f142e4cc
SAYS: The append only graft log: every kit concept update, recorded as WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed project's own files, and which README section it touched, so installs update by concept rather than by overwriting a project's customized files.
DOES: the graft log: the current kit version line and one WHAT/CARRIES/GRAFT/README entry per concept, newest v1.25 the digest diet; append-only, read by the README lint
FLAG: matches its purpose; the v1.25 entry names its README section

### 2026-09-20 03:21 | LESSONS.md | GREEN | fable | WS1 | 4b7dee43
SAYS: One entry per task shape: THE ONE RIGHT WAY first, then what was tried, why it failed and what to do instead, then nuance headlines as they accumulate, so a future session does the correct thing first instead of repeating trial and error.
DOES: the one-right-way book: the law and the entry shape at the top, then five entries, each with Tags, Keys, THE ONE RIGHT WAY, dated TRIED / FAILED BECAUSE / DO INSTEAD bullets and a See also to the detail's home; read by lesson_log.py for the prompt match and the lint
FLAG: does what the PURPOSE says; the Keys line is the one addition the purpose implies (the prompt hook needs match terms); every entry is a recorded event, none invented

### 2026-09-20 03:21 | hooks/lesson_advisor.py | GREEN | fable | WS1 | aca625cd
SAYS: Stop hook that scans the turn's transcript slice for trial-and- error signals and refuses to end the turn once with LESSON ADVISED when it finds one, so the manager captures the lesson in LESSONS.md or the wiki before the turn ends; silent otherwise, never the same slice twice.
DOES: Stop hook: reads the transcript slice since the last Stop (line pointer per transcript in .claude/lesson_state.json), asks lesson_log.signals(), refuses once per slice signature with LESSON ADVISED, passes a slice that edited LESSONS.md as WRITTEN, ledgers ADVISED/WRITTEN, exits 0 on every failure path; --selftest covers decide() and the state round trip
FLAG: does what the PURPOSE says and nothing more; the refusal is once per signature and guarded by stop_hook_active, so it cannot trap; pipe-tested for real on the live transcript (blocked once, silent on the rerun)

### 2026-09-20 03:21 | reference tools/lesson_log.py | GREEN | fable | WS1 | 2a232079
SAYS: Serve the lesson loop's three ends: match a prompt against the Keys lines of LESSONS.md entries and name the ones to read first; scan a transcript slice for trial-and-error signals so the Stop hook can advise a lesson; lint the entries' shape and ledger the counts for the check loop.
DOES: three ends in one script: --match scores a prompt's stemmed words against each entry's Keys (multi-word 2, single 1, named at 2+, cap 3, prompts under four content words skipped); --scan finds six trial-and-error signals in a transcript slice; --check lints Tags/Keys/THE ONE RIGHT WAY/See also and appends a CHECK line through _ledger; record() appends MATCHED/ADVISED/WRITTEN; 16 selftests
FLAG: matches its purpose; the DIFFERENT signal was narrowed before wiring to intent_log's exact resolve line after a quoted digest line read as a false positive

### 2026-09-20 03:21 | hooks/prompt_gauge.py | GREEN | fable | WS1 | 6b896181
SAYS: UserPromptSubmit hook that stays silent on a normal turn and, when a threshold is crossed, prints the checkpoint counter warning (8 tasks advised, 15 dire) and the context-remaining warning, plus since 2026-09-13 a KIT UNSYNCED line when a portable original is newer than its kit copy, and since 2026-09-20 the LESSONS line naming the LESSONS.md entries whose Keys match the prompt, so the one right way is read before the first tool call.
DOES: the counter and context lines as before, THE KIT LINE, and since 2026-09-20 THE LESSON LINE: lesson_log.match_lines() on the prompt, at most three entries with line numbers, one MATCHED ledger line per hit, silent on no match; selftest gained the two lesson cases
FLAG: purpose amended to name the lessons line; behavior on a normal prompt unchanged (silent, zero tokens)

### 2026-09-20 03:21 | hooks/hygiene_guard.py | GREEN | fable | WS1 | 33912ad4
SAYS: PostToolUse guard on Write, Edit and MultiEdit that, after an edit lands, hands the manager one line of context per applicable law: KIT REFRESH when a portable original changed, SEE-ALSO when a touched docs/systems section has no See also line, DASH when player-facing text received an em or en dash (this one BLOCKS), and IMPORT when a new asset needs the engine import run; stateless pattern matching only.
DOES: unchanged behavior; KIT_MDS gained INTENT_METHOD.md (it was already a kit MD, an omission) and LESSONS.md so an edit to either gets the kit-refresh line
FLAG: config-only change inside the stated purpose

### 2026-09-20 03:21 | hooks/settings.json | GREEN | fable | WS1 | d9956742
SAYS: (no PURPOSE line)
DOES: the settings template now carries two Stop entries, stop_tick.py and lesson_advisor.py, beside the existing wiring; parses
FLAG: wording-level change to the template; every SAFETY hook stays wired

### 2026-09-20 03:21 | hooks/README.txt | GREEN | fable | WS1 | 196a5393
SAYS: Installation notes for the Rootstock hooks folder: what each hook file needs filled in or wired (bash_guard.py's PROJECT RULES, fanout_guard.py's numbers via the runaway skill, hygiene_guard.py's CONFIG block) and the gitignore entries a new project needs.
DOES: install notes gained the lesson_advisor.py paragraph: copy LESSONS.md and lesson_log.py, wire the Stop entry, gitignore the state file, run both selftests, add the check-group line, pipe-test once
FLAG: does what its purpose says: per-hook setup steps, now for eleven hooks

### 2026-09-20 03:21 | reference tools/_ledger.py | GREEN | fable | WS1 | 676f9073
SAYS: One append_unless_identical() call site for the check-script ledgers (format_lint, purpose_audit, readme_lint, check_wiki_links and, since 2026-09-20, lesson_log's CHECK line) so a rerun at an unchanged tree does not grow duplicate rows.
DOES: unchanged behavior; LEDGER_BASENAMES gained lesson_runs.txt so the lesson ledger's own append does not dirty the tree it checks; purpose header now names lesson_log as the fifth caller
FLAG: config-only change; header amended to stay honest about the caller count

### 2026-09-20 03:21 | reference tools/correction_log.py | GREEN | fable | WS1 | 3b8d1a81
SAYS: Record the correction ledger: a RECORD line the moment a correction is understood in the CEO's own words, a FIXED line when the fix ships, and resolve the named intent claim as DIFFERENT in the intent log when one is given.
DOES: unchanged recording; after a correction resolves a claim DIFFERENT it now also prints LESSON ADVISED naming the claim, so the lesson is written in the same batch as the fix
FLAG: one extra output line inside the stated purpose (the correction ritual is the feedback loop; the lesson is its capture)

### 2026-09-20 03:21 | reference tools/ledger_trends.py | GREEN | fable | WS1 | b7b0d9f4
SAYS: Reads the tails of the project's history ledgers (usage, tests, wiki links, wiki heat, employee corrections, compactions, README audit, intent claims, corrections, systems audit, open questions, digest size, the run_all loop, the lesson loop), compares them against tunable thresholds, and prints proposed rule changes; it applies nothing itself.
DOES: rule 14 added: ADVISED lines in the last 7 days at or past lesson_advised_unwritten (3) with no WRITTEN line and no entry growth across the CHECK lines proposes a look; DEFAULTS gained the key; nothing applied
FLAG: purpose header amended to list the lesson loop among the ledgers read; still propose-only

### 2026-09-20 03:21 | reference tools/run_all.py | GREEN | fable | WS1 | 25f6247c
SAYS: Chain habitual scripts by named group (check/regen/tests/metrics/ probes/builds/session/standup) and ledger every group run so staleness is visible instead of silent.
DOES: the check group gained [tools/lesson_log.py, --check] as its last step; the group comment names it
FLAG: add-only change per the Script Rule (changed only to add or fix)

### 2026-09-20 03:21 | skills/checkpoint/SKILL.md | GREEN | fable | WS1 | 6e721ed2
SAYS: Close an arc safely: push, refresh the day file's WHERE WE LEFT OFF section with both sides of the final exchange verbatim, reset the task counter, and emit the safe-to-clear marker.
DOES: step 0 asks a second question: was anything learned by trial and error or corrected this arc; then the LESSONS.md entry is written before pushing
FLAG: one sentence inside the ritual's purpose (close the arc losslessly; a lesson left unwritten is a loss)

### 2026-09-20 03:22 | HOOKS_METHOD.md | GREEN | fable | WS1 | 2b0c8332
SAYS: Documents the harness hooks, session start, prompt, stop, compaction, and tool-call guards, that enforce CLAUDE.md's laws mechanically instead of relying on the manager's memory, plus the hook contract and the kit's hook roster.
DOES: Tier 1 gained item 5, the lesson advisor, with the block-not-systemMessage design note; the kit hooks heading says eleven; the change log has the 2026-09-20 entry
FLAG: matches its purpose; counts agree with the folder (readme_lint PASS at 11 hooks)

### 2026-09-20 03:22 | 0 - READ ME FIRST.md | GREEN | fable | WS1 | f54b98cd
SAYS: The kit's front door: walks a receiving Claude through the install in order (ask the CEO first, then the wiki, reporting and session rituals, the delegation company, the skills and hooks, the companions, the optional boards) by POINTING at each method file's bootstrap section, so the operating system lands the same way every time.
DOES: STEP 4 names the lesson loop among the loops that measure the loop and points at hooks/README.txt for the steps; the See also list names LESSONS.md
FLAG: wording-level; the install order is unchanged

### 2026-09-20 03:22 | UPGRADES.md | GREEN | fable | WS1 | 86b972a4
SAYS: The append only graft log: every kit concept update, recorded as WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed project's own files, and which README section it touched, so installs update by concept rather than by overwriting a project's customized files.
DOES: the graft log: CURRENT KIT VERSION v1.26 and the v1.26 entry (WHAT/CARRIES/GRAFT/README) for the lesson loop; append-only
FLAG: matches its purpose; the entry names its README sections and the lint accepts it

### 2026-09-20 17:37 | hooks/preserve_guard.py | GREEN | fable-ws1 | WS1 | 405b21e5
SAYS: PreToolUse guard on Bash, PowerShell, Write, Edit, MultiEdit and NotebookEdit implementing the preservation law: refuses shell delete verbs with a path, git verbs that discard work or history, and deletion calls written into a file, with narrow exceptions for the session scratchpad, prose files, and one command consumed against a twice-acknowledged delete grant; a drive root, the home folder, the repo root or a bare wildcard are refused even with a grant.
DOES: PreToolUse guard on Bash, PowerShell and the write tools: refuses shell delete verbs (bare names, pipelines, foreach bodies, find -exec, robocopy mirror, rsync delete), the work-discarding and history-rewriting git verbs (every force push included), deletion calls written into non-prose files, and any script a command executes whose untracked body or uncommitted added lines carry a deletion shape; passes the session scratchpad, prose files, heredoc bodies aimed at prose, permission-rule strings in a settings file, and one command per twice-acknowledged grant; a drive root, the home folder, the repo root, any .git folder, a bare wildcard, a .. climb or a variable target are refused with no grant possible; a crash falls back to a crude substring check and refuses on a hit
FLAG: Hardened 2026-09-20 after the 48,000-file public report; probed with the incident's shapes first (14 of 29 passed the old guard), all closed, 74 selftest checks green; the guard refused its own hardening five times and was reworded each time, never routed around

### 2026-09-22 17:11 | WIKI_METHOD.md | GREEN | Fable (WS2 manager) | WS2 | b5db5849
SAYS: A portable system for organizing a project's knowledge (a lean CLAUDE.md core, a docs/systems topic library, portable root notes) so an AI assistant finds anything in three cheap hops, Glob, Grep for headings, then a targeted Read, without wasting tokens.
DOES: Teaches the three-layer knowledge architecture and cheap lookup; v1.29 adds The harness memory section ruling that per-machine auto-memory holds machine-local facts only, with the bank, stub and tally protocol for repo-shaped memories.
FLAG: The new section is a knowledge-home boundary, squarely inside the stated purpose of organizing where facts live; no side effects, no new tools, read-only doctrine.

### 2026-09-22 17:11 | WORKSTATION_METHOD.md | GREEN | Fable (WS2 manager) | WS2 | 76fe2cd7
SAYS: The machine inventory method: one workstation file records what every script, hook and ritual needs, why, what the origin machine has, and how to install it, so any Claude can get a new machine up to par and write back what it adds.
DOES: The machine inventory method; v1.29 adds one closing paragraph extending the Claude-side settings section: harness auto-memory keeps machine-local facts only, pointing to WIKI_METHOD.md for the full trim ruling.
FLAG: Matches the purpose (what is per-machine and how a machine gets up to par); a pointer paragraph, nothing beyond the stated scope.

### 2026-09-22 17:37 | reference tools/check_wiki_links.py | GREEN | Fable (WS2 manager) | WS2 | 1b459474
SAYS: Warn-only link checker for the knowledge wiki: scan repo-root, docs/systems, docs/cold and docs/index markdown for the four cross-reference forms, resolve each against the repo, and report dead links plus See-also hygiene.
DOES: Checks See-also blocks, wiki links and markdown links across the wiki; v1.29 adds a fenced-code-block skip so quoted text (banked memories, code samples) is not counted as live links.
FLAG: The skip narrows the scan to real links, exactly the stated purpose; no new writes or side effects.

### 2026-09-28 13:59 | hooks/stop_tick.py | GREEN | fable | WS1 | 43e25a82
SAYS: Stop hook that ticks the checkpoint counter only when work actually happened (HEAD moved or the tree changed since the last Stop), shows an advised system message at 8 tasks or under 80% context, refuses to end the turn once at 15 tasks or under 30% context (re-blocking every 5 further tasks), refuses once when a safety hook has gone unwired in settings.json, and warns once per unexported commit count when the changelog anchor has fallen behind HEAD.
DOES: Stop hook: ticks the checkpoint counter on real work, advises at 8 tasks or under 80 percent context, refuses once at 15 or under 30 percent, refuses once when a safety hook is unwired, and warns once per unexported commit count; since kit v1.31 the count skips commits whose subject starts with changelog: (the export's own commit) and the line is worded as an order to the manager (MANAGER: run the export before this reply ends), with the incident shape in the selftest
FLAG: PURPOSE and INTENT name every side effect; the changelog count change only narrows what is counted and the selftest touches temp anchor files only; the wording change makes the line an instruction to the manager per THE HOOK LAW (C0003)

### 2026-09-28 23:13 | WORKSTATION_METHOD.md | GREEN | fable | WS1 | 33973747
SAYS: The machine inventory method: one workstation file records what every script, hook and ritual needs, why, what the origin machine has, and how to install it, so any Claude can get a new machine up to par and write back what it adds.
DOES: The machine inventory method; v1.32 adds one section under the Claude-side settings: Remote Control pairs the phone to the same local session, the checkpoint clear keeps the link, the phone-typed clear firing the SessionStart hook is recorded as unconfirmed with the one-clear check, and the cloud session is the alternative
FLAG: Matches the purpose (what the harness setup needs and how a machine is driven); documentation from the harness docs with the unconfirmed point marked, no new side effect

### 2026-09-28 23:37 | hooks/prompt_gauge.py | GREEN | fable | WS1 | 8c1d05c0
SAYS: UserPromptSubmit hook that stays silent on a normal turn and, when a threshold is crossed, prints the checkpoint counter warning (8 tasks advised, 15 dire) and the context-remaining warning, plus since 2026-09-13 a KIT UNSYNCED line when a portable original is newer than its kit copy, and since 2026-09-20 the LESSONS line naming the LESSONS.md entries whose Keys match the prompt, so the one right way is read before the first tool call, and since 2026-09-28 the ROUTE line naming the WORKFLOWS.md entries and the reference tools whose heading, WHEN line or Search keys the prompt hits.
DOES: UserPromptSubmit hook: the checkpoint and context threshold lines, the KIT UNSYNCED line, the LESSONS line naming matching LESSONS.md entries, and since kit v1.33 the ROUTE line naming the WORKFLOWS.md entries and reference tools whose heading, WHEN line or Search keys the prompt hits (route_index.match_lines, at most two each, every exception swallowed); selftest covers threshold, lesson and route cases
FLAG: PURPOSE names the new line; the route block reads WORKFLOWS.md and tool docstrings only, writes nothing, no ledger, silent on a miss; a hook that cannot crash the turn

### 2026-09-28 23:37 | reference tools/route_index.py | GREEN | fable | WS1 | 9f960c3e
SAYS: Match a prompt against the headings and WHEN lines of WORKFLOWS.md and the Search keys of every tools/ and tools/hooks/ script, and print the ROUTE line the prompt hook relays, so an existing workflow or script is named before the manager re-derives it.
DOES: Reads WORKFLOWS.md headings and WHEN lines and the Search keys line of every tools/ and tools/hooks/ script, scores them with lesson_log's matcher (workflow 3, tool 2, two of each at most), and prints the ROUTE lines the prompt hook relays; answers --match and --selftest; no writes, no ledger
FLAG: Matches the purpose exactly: read-only indexing plus a printed pointer; the only side effect is stdout; a project without Search keys or WHEN lines gets silence, not errors

### 2026-09-28 23:44 | hooks/stop_tick.py | GREEN | fable | WS1 | 8b404f83
SAYS: Stop hook that ticks the checkpoint counter only when work actually happened (HEAD moved or the tree changed since the last Stop), shows an advised system message at 8 tasks or under 80% context, refuses to end the turn once at 15 tasks or under 30% context (re-blocking every 5 further tasks), refuses once when a safety hook has gone unwired in settings.json, warns once per unexported commit count when the changelog anchor has fallen behind HEAD, and since 2026-09-28 refuses once per prompt when the reply names a checkpoint as due without the safe-to-clear marker (the reply text read from the transcript).
DOES: Stop hook: ticks the counter on real work, advises at 8 or under 80 percent, refuses once at 15 or under 30 percent, refuses once on broken safety wiring, warns once per unexported commit count, and since kit v1.34 reads the turn's reply text from the transcript through lesson_log and refuses once per prompt when it names a checkpoint as due without the safe-to-clear marker (CHECKPOINT NAMED); dedup key per prompt in the hook state, stop_hook_active stops a loop
FLAG: PURPOSE names the new refusal; the check reads the transcript only, writes the dedup key to the hook state it already owns, and the once-per-prompt key plus stop_hook_active mean it can never trap a turn

### 2026-09-29 00:24 | hooks/stop_tick.py | GREEN | fable | WS1 | e886573b
SAYS: Stop hook that ticks the checkpoint counter only when work actually happened (HEAD moved or the tree changed since the last Stop), shows an advised system message at 8 tasks or under 80% context, refuses to end the turn once at 15 tasks or under 30% context (re-blocking every 5 further tasks), refuses once when a safety hook has gone unwired in settings.json, warns once per unexported commit count when the changelog anchor has fallen behind HEAD, and since 2026-09-28 refuses once per prompt when the reply names a checkpoint as due without the safe-to-clear marker (the reply text read from the transcript), and since 2026-09-29 refuses once per prompt when the reply names a DO proposal that its ledger still raises (PROPOSAL NAMED).
DOES: Ticks the checkpoint counter on real work, warns or refuses by task count and context, refuses on broken safety wiring, warns once per unexported commit count, refuses once per prompt when the reply names a checkpoint as due without the marker, and since 2026-09-29 refuses once per prompt when the reply names a DO proposal that ledger_trends still raises; the reply text comes from the transcript, the proposals from ledger_trends.open_do with no ledger write.
FLAG: PURPOSE names every refusal including the new PROPOSAL NAMED; the check only reads, its state key prop_named_turn keeps it to once per prompt, and stop_hook_active stops a loop; six selftest cases carry the incident reply.

### 2026-09-29 00:24 | hooks/session_start.py | GREEN | fable | WS1 | 8a7f9b93
SAYS: SessionStart hook that runs tools/standup.py and injects its digest into the manager's context on startup, resume, /clear and after a compaction, with a header telling the manager not to re-run standup and how to relay the last exchange; also runs the session group itself when it has not run today (THE LOOP LAW) and ledgers the digest's byte size.
DOES: Runs the session group once a day, runs standup.py, injects the digest with a preamble that now names THE PROPOSAL LAW (DO lines are the first reply's work, ASK lines are questions), and ledgers the digest size.
FLAG: The preamble sentence is text the manager reads, described in PURPOSE by way of the standup relay; no new side effect.

### 2026-09-29 00:24 | reference tools/ledger_trends.py | GREEN | fable | WS1 | b3f73680
SAYS: Reads the tails of the project's history ledgers (usage, tests, wiki links, wiki heat, employee corrections, compactions, README audit, intent claims, corrections, systems audit, open questions, digest size, the run_all loop, the lesson loop), compares them against tunable thresholds, and prints proposed rule changes, each tagged [DO] (a script, hook or employee carries it out in the reply that reads it) or [ASK] (only the owner can answer); it applies nothing itself.
DOES: Reads the ledger tails, compares against the thresholds file, prints each proposal tagged DO or ASK from a fixed ACTION table, exposes open_do and HOW for the Stop hook, and records a proposal_runs line only when the set changed; applies nothing.
FLAG: PURPOSE updated to name the classes; open_do() calls proposals() without record(), so a hook read never writes the ledger.

### 2026-09-29 00:24 | reference tools/standup.py | GREEN | fable | WS1 | ad3ccd68
SAYS: Prints the post pull standup digest: the last exchange mined from harness transcripts, the day file's WHERE WE LEFT OFF, the usage budget line, THE LOOP (each run_all group's age), ledger trend proposals, version and recent commits, THE CORE (check_claude_md.py's OK/WARN line, run as a subprocess so the owner sees the core's size every session), WS notes from docs/index/notes.md, ledger tails, the open roadmap index, and OPEN QUESTIONS TO MAZHRON.
DOES: Prints the standup digest: the last exchange from the transcript, WHERE WE LEFT OFF, the budget, the loop, the proposals, commits, the core check, notes, ledger tails (a moved all-clear that repeats the previous one collapses), the roadmap (long entries as first clause ... last clause), open questions, recent days.
FLAG: Both trims are loss-test cuts described in the code and self-audit.md; twelve selftest cases; nothing written but the usage refresh it already ran.

### 2026-09-29 00:24 | reference tools/usage_report.py | GREEN | fable | WS1 | bd5f06ac
SAYS: Mines the Claude Code harness JSONL transcripts for real per model per tool token usage and writes an aggregate usage sheet (CSV, TXT, XLSX, employee runs, and the daily budget line) totaled by day, week and month, plus usage_by_arc.txt (checkpoint to checkpoint) and cache_misses.txt + cache_miss_runs.txt (every miss with its likely cause).
DOES: Builds the usage sheets and ledgers from the transcripts; the cache-miss run ledger now skips a line whose fields after the stamp equal the previous line's, so two hooks minutes apart ledger one reading.
FLAG: A dedupe on an append-only ledger; the skipped line is the same reading, not a lost one.

### 2026-09-29 10:39 | reference tools/standup.py | GREEN | fable | WS1 | 0c1edbb0
SAYS: Prints the post pull standup digest: the last exchange mined from harness transcripts, the day file's WHERE WE LEFT OFF, the usage budget line, THE LOOP (each run_all group's age), ledger trend proposals, version and recent commits, THE CORE (check_claude_md.py's OK/WARN line, run as a subprocess so the owner sees the core's size every session), WS notes from docs/index/notes.md, ledger tails, the open roadmap index, and OPEN QUESTIONS TO MAZHRON.
DOES: Prints the session-start digest: the last exchange mined from the newest transcript (now returning its time window), WHERE WE LEFT OFF, the budget tail after a quiet usage_report refresh, THE LOOP grouped by last-run stamp, ledger_trends proposals, version and commits without the auto changelog exports, the core lint line, WS note headlines, ledger tails under the loss test (verdict or new since, minus repeated all-clears and lines the last exchange itself wrote), the roadmap index, open questions and recent days. Every helper is pure and covered by --selftest; the subprocesses are read-only except usage_report --quiet, which writes its own usage sheets.
FLAG: Matches the PURPOSE line; the fourth trim adds three pure helpers (in_window, loop_rows, keep_commit) with sixteen selftest cases and no new side effect. The one write, the usage-sheet refresh, is stated in the docstring's THE BUDGET paragraph and skippable with --no-usage; the PURPOSE line names only the budget line it prints, which is fine as the refresh is that line's source.

### 2026-09-29 14:23 | SECURITY_METHOD.md | GREEN | fable | WS1 | 40063780
SAYS: The pre-production security audit: one checklist, one read-only script and one ledger line that every app, SaaS or website with a backend, an API key, an env file or user data passes before it goes public, and again before every public release that touched secrets, auth, headers, config or the database rules.
DOES: States the pre-production security audit law (the gate, the re-run, the rotation law, the prefix law, the script-and-ledger split, read-only against the owner's own deployment), a nine-class checklist with WHAT / HOW / PASS per class, the ledger line's shape, a WORKFLOWS entry to paste and a four-step bootstrap; a method file, no side effect.
FLAG: Matches its PURPOSE line: checklist, script and ledger line named and delivered; the origin survey's numbers are quoted with their source; the exemption path for a keyless static export is stated so the rule never fires on nothing.

### 2026-09-29 14:23 | reference tools/security_audit.py | GREEN | fable | WS1 | e01ea5ac
SAYS: Run the read-only checks SECURITY_METHOD.md's checklist gives a script: grep a production build folder for secret-shaped strings (class 1), read the site's response headers for HSTS, CSP and a frame rule (class 2), request the exposed-file paths and expect 404 or 403 (class 3), and read the CORS header under a foreign Origin (class 4); print one PASS / WARN / FAIL line per check and, with --record, append the counts and a note to docs/history/security_audit_runs.txt.
DOES: With --dir walks a build folder (node_modules and .git skipped) and prints one FAIL per file and secret shape naming file, line and pattern, never the match; with --url makes GET requests to the given site only: the root's headers against six names, eighteen fixed exposed paths expecting 404 or 403, and one request under a foreign Origin for the CORS answer; --record appends counts and a note to docs/history/security_audit_runs.txt through _ledger's dedup; --selftest runs two localhost servers and sixteen cases. Exit 1 on any FAIL.
FLAG: Matches its PURPOSE line; the only write is the ledger line under --record, stated in the header; the network calls are the fixed list against the URL the owner gives and nothing else; the printed lines never carry the matched secret (a selftest case checks it).

### 2026-09-29 16:36 | reference tools/law_gaps.py | YELLOW | fable-manager | WS1 | 9ddfe65c
SAYS: Ledger two proxies for laws no other script measures: notes.md entries actioned but not swept to history.md, and tools changed in 30 days that no WORKFLOWS.md entry names.
DOES: Appends one line each to sweep_audit_runs.txt and workflow_gap_runs.txt: notes.md bullets whose status parenthesis holds actioned, done, closed or resolved, and tools changed in 30 days of git log whose basename appears in none of WORKFLOWS.md, tools/run_all.py, .claude/settings.json or any skill file. Writes nothing else, deletes nothing.
FLAG: Matches in substance. Off: the PURPOSE line and CHECK B text say named in WORKFLOWS.md only, but since 2026-09-29 the corpus also counts run_all.py, settings.json and the skills (the verdict string already says so). The actioned test is a substring match on the status parenthesis, so a status that merely contains done (2026-09-29, a new open note) counts as actioned. Fix: rewrite PURPOSE via format_lint --rewrite to name the full corpus, and match whole words at the status start.

### 2026-09-29 16:36 | reference tools/law_gaps.py | GREEN | fable-manager | WS1 | 4f112ffc
SAYS: Ledger two proxies for laws no other script measures: notes.md entries actioned but not swept to history.md, and tools changed in 30 days that no WORKFLOWS.md entry, run_all group, hook setting or skill names.
DOES: Appends one line each to sweep_audit_runs.txt and workflow_gap_runs.txt: notes.md bullets whose status parenthesis holds the whole word actioned, done, closed or resolved, and tools changed in 30 days of git log named in none of WORKFLOWS.md, tools/run_all.py, .claude/settings.json or a skill file. Writes nothing else, deletes nothing.
FLAG: The 16:36 YELLOW's two fixes landed: PURPOSE and CHECK B now name the full named corpus, and the actioned test matches whole words (selftest case added). Does what it says, nothing more.

### 2026-09-29 16:38 | skills/flag/SKILL.md | GREEN | fable-manager | WS1 | 7ffcc2f5
SAYS: the ritual behind FLAGS.md - one kit thing at a time, the auditor reads it, compares the stated purpose with the behaviour, gives it a color, explains the color in the entry, and never touches the thing.
DOES: Instructs a read-only purpose audit of one kit thing: pick from purpose_audit --pending, read, compare PURPOSE with the body, file a green, yellow or red entry via purpose_audit --flag. Step 6 now splits a missing header (format_lint --rewrite) from a wrong existing line (edited in the original after the flag, then re-flagged).
FLAG: Does what it says. The 2026-09-29 amendment fixes a stale step: --rewrite only fills gaps, so the old never-by-hand rule could not be followed for a stale PURPOSE.

### 2026-09-30 11:57 | hooks/diet_guard.py | GREEN | fable | WS1 | 4ac53f36
SAYS: PreToolUse guard on Read, Bash and PowerShell enforcing the read diet and output diet: warns when a shell command shape (git log, git diff, recursive listing, install) has no limiter, and on the first whole read of a file over about 10k tokens in a session it denies once and returns the file's own section or function index instead; the same call repeated afterward passes with a warning only; a LATER whole read of that same file in the same session, fingerprint (mtime_ns+size) unchanged since the admitted read, is denied once more as RE-READ and passes on repeat; forget_session_reads() clears a session's RE-READ marks (not its INDEX FIRST marks) after a compaction empties the context.
DOES: the read and output diet on Read/Bash/PowerShell: shell-shape warnings, INDEX FIRST once per big file per session, and since v1.40 RE-READ once for an unchanged big file already admitted this session; per-session state in .claude/diet_state.json; forget_session_reads() for pre_compact
FLAG: diff read 2026-09-30: RE-READ reuses the offered-dict mechanism, fingerprint is mtime_ns:size, big files only; 38 selftest checks pass

### 2026-09-30 11:57 | hooks/brief_guard.py | GREEN | fable | WS1 | 3991c850
SAYS: PreToolUse guard that refuses an Agent/Task dispatch to a work agent type when the brief is missing the stamp template (STAMP/TOOLS/ WORKFLOW), the INTENT line ask, the budget line or THE PRESERVATION LAW line; also refuses THE EMPLOYEE MODEL RULE (SUBAGENTS.md rule 6): a dispatch whose tool_input.model is missing/empty, or matches Fable (case-insensitive, even inside a longer id like "claude-fable-5-1"), since a model-less dispatch inherits the parent model (Fable), and Fable is never an employee; silent for read-only agent types and complete briefs.
DOES: refuses an Agent/Task work dispatch whose brief lacks the stamp template, intent line, budget line or preservation line, and since v1.40 whose model is missing or names Fable; read-only agent types exempt; pure missing_pieces() with a sentinel third arg
FLAG: full hunk read 2026-09-30; 12 selftest checks pass; the model rule prints through the existing Missing: path

### 2026-09-30 11:57 | hooks/pre_compact.py | GREEN | fable | WS1 | b78c1b66
SAYS: PreCompact hook that appends one ledger line per compaction (when, workstation, version, manual or auto trigger, context load, unbanked task count) to docs/history/compact_runs.txt, and on an auto trigger tells the manager the session_start hook will re-inject the standup digest right after; also clears diet_guard's RE-READ marks for this session (via forget_session_reads(), imported defensively) since a compaction empties what was "already in context."
DOES: appends one compact ledger line per compaction and, since v1.40, clears the session's RE-READ marks through a defensively imported forget_session_reads()
FLAG: hunk read 2026-09-30: both the import and the call are wrapped so the hook cannot crash; 3 selftest checks pass

### 2026-09-30 11:57 | hooks/prompt_gauge.py | GREEN | fable | WS1 | c1901def
SAYS: UserPromptSubmit hook that stays silent on a normal turn and, when a threshold is crossed, prints the checkpoint counter warning (8 tasks advised, 15 dire) and the context-remaining warning, plus since 2026-09-13 a KIT UNSYNCED line when a portable original is newer than its kit copy, and since 2026-09-20 the LESSONS line naming the LESSONS.md entries whose Keys match the prompt, so the one right way is read before the first tool call, and since 2026-09-28 the ROUTE line naming the WORKFLOWS.md entries and the reference tools whose heading, WHEN line or Search keys the prompt hits, and since 2026-09-30 a live USAGE WINDOW line (tools/usage_window.py) when the rolling five-hour spend is already most of the seven-day peak.
DOES: the silent per-prompt gauge: checkpoint and context thresholds, the lesson match, the route line, and since v1.40 the usage window line via usage_window.gauge_line(), in-process, wrapped so any exception stays silent
FLAG: hunk read 2026-09-30; 9 selftest checks pass; empty stdin exits 0

### 2026-09-30 11:57 | hooks/settings.json | GREEN | fable | WS1 | 690e81dc
SAYS: (no PURPOSE line)
DOES: wires the fifteen hooks and, since v1.40, carries a permissions.deny block: destructive shell shapes plus Read/Edit of .env files, key material and credentials; no allow or ask entries
FLAG: json validated 2026-09-30; the block is a copy of the origin project's committed list

### 2026-09-30 11:57 | reference tools/usage_window.py | GREEN | fable | WS1 | 3efea537
SAYS: Mine the harness transcripts for a LIVE weighted-token read of the last 5 hours, the peak 5-hour window inside the last 7 days, and the 7-day total, printed as one line or advised only past an owner-tuned share of that peak; incremental (byte offset + 10-minute slot cache) so a warm read costs well under a second.
DOES: mines the harness transcripts incrementally for the last-5h, peak-5h-in-7d and 7d weighted spend; writes only its own gitignored cache and, when advised, one ledger line; --selftest builds fixtures in a TemporaryDirectory
FLAG: writes enumerated 2026-09-30 (cache, ledger, selftest temp); no subprocess, no delete; 14 checks pass; 0.1s warm

### 2026-09-30 11:57 | reference tools/guard_replay.py | GREEN | fable | WS1 | 02fe2b54
SAYS: Replays the four PreToolUse guards' pure judge functions (diet_guard.evaluate, bash_guard.verdict, preserve_guard.evaluate, brief_guard.missing_pieces) against the last N days of harness transcript traffic in a sandbox (a fresh in-memory diet_guard state per run, no grant, no ledger writes except its own), counts replayed / would-refuse / refused-live calls per guard per rule, and prints the NEW CATCH and LOST deltas with `--show <guard>` giving up to ten one-line examples each; never executes a command and never modifies a transcript, a hook, or a hook's state.
DOES: replays recorded tool calls, employee transcripts included since the manager's os.walk fix, through the four guards' judge functions with sandbox state; writes only its own ledger; the one subprocess is preserve_guard's read-only git diff, memoized, never a replayed command
FLAG: writes enumerated 2026-09-30 (ledger, selftest temp); 13 checks pass; the sandbox promise is a selftest case; first true run WARN lost 1, a shell read judged at today's size

### 2026-09-30 12:22 | skills/ship/SKILL.md | GREEN | fable | WS1 | db5829c2
SAYS: Ship a completed batch: commit with a player-readable subject, push, and (in projects with builds) refresh build zips without deleting old ones.
DOES: seven steps, sanity to counter; step 1 now carries THE SECURITY QUESTION (v1.39's graft line the kit's own skill had missed for a day): a diff that touched secrets, env, auth, headers, CORS, hosting or database rules runs the audit first, a no-backend project answers by its exemption
FLAG: read whole 2026-09-30; the new line adds a gate, not a step the PURPOSE would need to name; no delete, no write

### 2026-09-30 12:22 | skills/brief/SKILL.md | GREEN | fable | WS1 | d346216c
SAYS: Compose and dispatch a sub-agent (employee) brief that follows the delegation laws, stamped, self-contained, budget-capped, diff-only reporting, then verify cheap and ledger the outcome.
DOES: eight brief parts plus the after-return steps; part 1 now states THE EMPLOYEE MODEL RULE (v1.40): the Agent call's model field is always set, a model-less call inherits the manager's tier, the brief guard refuses it
FLAG: read whole 2026-09-30; the rule matches brief_guard.py's refusal and SUBAGENT_METHOD.md's new paragraph word for sense; no delete, no write

### 2026-09-30 12:22 | SUBAGENT_METHOD.md | GREEN | fable | WS1 | 313e4d43
SAYS: A portable architecture for delegating work to sub-agent employees: the org chart (CEO, manager, employees), why it saves money, the seven laws, the assignments table, the scorecard, and bootstrap steps for a new project.
DOES: those seven sections; the assignments table section closes with THE EMPLOYEE MODEL RULE paragraph (2026-09-30, v1.41), the harness fact behind it (a model-less dispatch inherits the parent's model) and the guard that enforces it
FLAG: read the assignments section 2026-09-30 after the edit; the rule is stated where the manager picks the row, which is where the README audit found it missing

### 2026-09-30 12:22 | reference tools/readme_lint.py | GREEN | fable | WS1 | f098e411
SAYS: Derives every countable README fact (laws, skills, hooks, reference tools, the box table, version, the graft README line, number word claims, prose claims) from the kit folder itself and compares it with what the public README says, ledgering PASS, FAIL or SKIP each run.
DOES: the same derivation; the CLAIMS table gains six rows from the 2026-09-30 audit (the weighted-share explanation, the --url network answer, public release over public URL, the session-open figure, the ship question, the employee model rule); 91 checks, selftest 8/8
FLAG: read the CLAIMS table 2026-09-30; the DOTALL claim regexes bite fresh prose that reuses a phrase (two rewordings this batch), which is the lint doing its job

### 2026-10-01 16:55 | hooks/delegation_auditor.py | GREEN | fable | WS1 | e7dd9f63
SAYS: PostToolUse hook that reads the harness-metered tool and token figures from an Agent/Task result, warns on rule 9's fabrication tell, a TOOLS-line mismatch or a malformed report, and appends one PENDING line per work delegation; on SubagentStop it meters the employee's own transcript, holds the employee once over a malformed report or a self-count miss, and appends the METER line with the true figures.
DOES: both branches as said; writes only the pending ledger (append) and the block decision; reads the employee's transcript through agent_transcript_path then the subagents folder, never the manager's; no subprocess, no delete; 33 selftest cases
FLAG: read whole 2026-10-01 after five live runs; the first two live events exposed the manager's-transcript field and the pre-hand-back stop, both handled in the code and the docstring; the hold is bounded by stop_hook_active and the ASKED tail line

### 2026-10-01 16:55 | hooks/settings.json | GREEN | fable | WS1 | 250ba570
SAYS: Wires the fifteen hooks and, since v1.40, carries a permissions.deny block.
DOES: the same wiring plus a SubagentStop block running delegation_auditor.py (v1.42); json validated; the format guard's SAFETY row knows the event
FLAG: diffed against the origin project's live settings 2026-10-01; identical hook blocks

### 2026-10-01 16:55 | reference tools/format_lint.py | GREEN | fable | WS1 | 5f82c9c9
SAYS: check every kit thing (a script, a hook, a skill, a method file, the hooks README, the settings template) and its repo original for the one header the filing system needs - PURPOSE, INTENT, Search keys, See also - plus the safety wiring in settings.json; report PASS/FAIL per item.
DOES: the same; the delegation_auditor row now requires PostToolUse on Agent|Task AND SubagentStop (v1.42), so unwiring the stop-time check is refused like unwiring any safety hook
FLAG: read the SAFETY table 2026-10-01; 151 items PASS after the wiring, FAIL on the kit template between the two settings edits (the in-between-state lesson, by design)

### 2026-10-06 11:21 | 0 - READ ME FIRST.md | GREEN | fable | WS1 | a82a24ae
SAYS: The kit's front door: walks a receiving Claude through the install in order (ask the CEO first, then the wiki, reporting and session rituals, the delegation company, the skills and hooks, the companions, the optional boards) by POINTING at each method file's bootstrap section, so the operating system lands the same way every time.
DOES: the same as its PURPOSE line; the 2026-10-06 README audit (T-1006-RA) corrected one stale sentence in it at the source
FLAG: read-only compare after the T-1006-RA batch edit; PURPOSE unchanged, body matches the kit v1.44 entry

### 2026-10-06 11:21 | WIKI_METHOD.md | GREEN | fable | WS1 | 379900d7
SAYS: A portable system for organizing a project's knowledge (a lean CLAUDE.md core, a docs/systems topic library, portable root notes) so an AI assistant finds anything in three cheap hops, Glob, Grep for headings, then a targeted Read, without wasting tokens.
DOES: the same as its PURPOSE line; the 2026-10-06 README audit (T-1006-RA) corrected one stale sentence in it at the source
FLAG: read-only compare after the T-1006-RA batch edit; PURPOSE unchanged, body matches the kit v1.44 entry

### 2026-10-06 11:21 | REPORTING_METHOD.md | GREEN | fable | WS1 | b0c156a9
SAYS: A portable method for scripted runs and history ledgers: every repeatable run is a script, every run appends one labeled line to an append-only ledger, and a recorded baseline lets a regression show up as a single line flip between two ledger lines.
DOES: the same as its PURPOSE line; the 2026-10-06 README audit (T-1006-RA) corrected one stale sentence in it at the source
FLAG: read-only compare after the T-1006-RA batch edit; PURPOSE unchanged, body matches the kit v1.44 entry

### 2026-10-06 11:21 | HOOKS_METHOD.md | GREEN | fable | WS1 | b3dccc4b
SAYS: Documents the harness hooks, session start, prompt, stop, compaction, and tool-call guards, that enforce CLAUDE.md's laws mechanically instead of relying on the manager's memory, plus the hook contract and the kit's hook roster.
DOES: the same as its PURPOSE line; the 2026-10-06 README audit (T-1006-RA) corrected one stale sentence in it at the source
FLAG: read-only compare after the T-1006-RA batch edit; PURPOSE unchanged, body matches the kit v1.44 entry

### 2026-10-06 11:21 | CONTRIBUTING.md | GREEN | fable | WS1 | 35d0df34
SAYS: the two guardrails every Rootstock update passes through - THE FORMAT (one header on every thing, checked by script and enforced by a hook) and THE PURPOSE AUDIT (a read-only comparison of what a thing says against what it does, flagged green / yellow / red and filed in FLAGS.md) - written so a contributor, a maintainer and any Claude apply them the same way.
DOES: the same as its PURPOSE line; the 2026-10-06 README audit (T-1006-RA) corrected one stale sentence in it at the source
FLAG: read-only compare after the T-1006-RA batch edit; PURPOSE unchanged, body matches the kit v1.44 entry

### 2026-10-06 11:21 | WORKFLOW_METHOD.md | GREEN | fable | WS1 | 7f405d14
SAYS: A portable process registry method: every repeatable multi-step process gets one runbook entry, WHEN, STEPS, VERIFY, in a single registry file, so the choreography between scripts and ledgers is never lost to context clearing or memory.
DOES: the same as its PURPOSE line; the 2026-10-06 README audit (T-1006-RA) corrected one stale sentence in it at the source
FLAG: read-only compare after the T-1006-RA batch edit; PURPOSE unchanged, body matches the kit v1.44 entry
```

### `GODOT_FIELD_NOTES.md`

- Source: `GODOT_FIELD_NOTES.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 16590
- SHA-256: `86652811ea89bb300cf0af6ddbedf96b75cc501e0deb7ec9d752a09a9ef2a1e8`

```text
# Godot Field Notes

PURPOSE: Hard-won engine knowledge from building Everwood (Godot 4.4):
  rendering and performance costs, simulation architecture patterns,
  GDScript and API gotchas, and the measurement toolkit, written portably so
  it carries to future Godot projects.
INTENT: Everything in here was learned the expensive way, measured,
  debugged, or shipped around, so future work, this game or the next one,
  never pays for it twice.

Hard-won engine knowledge from building Everwood (Godot 4.4). Everything in
here was LEARNED THE EXPENSIVE WAY - measured, debugged, or shipped around -
so future work (this game or the next one) never pays for it twice. Portable
by design: nothing below depends on Everwood's code.

---

## Rendering and the 2D performance model
Tags: performance, gotchas | Renderer choice and per-item costs matter more than texture packing alone

- **GL Compatibility barely batches across canvas items.** Measured
  directly: forcing ONE texture onto ~5,700 sprites still produced ~2,400
  draw calls (~3 sprites per batch). A texture atlas bought only ~17% there.
  **Forward+ (Vulkan) has real 2D batching** - the same board dropped to
  ~520 calls, and the atlas multiplied its effect (3.7x under Forward+).
  If a 2D game has thousands of sprites, the renderer choice matters more
  than any texture arrangement.
- **You can split renderers per platform in one project:**
  `renderer/rendering_method="forward_plus"` with
  `renderer/rendering_method.web="gl_compatibility"` (and `.mobile`).
  Desktop gets Vulkan, the web export automatically keeps GL. Keep
  `config/features` renderer tag in sync.
- **Draw-call submission cost hides INSIDE TIME_PROCESS.** GL renders on
  the main thread within the process step, so no GDScript profiler line
  ever owns it. If your instrumented script costs sum to 15ms but
  TIME_PROCESS reads 50ms, the missing ~35ms is the renderer/driver.
- **Canvas item COUNT is its own cost, independent of batching**: roughly
  ~3us of main-thread processing per visible item per frame. 11,000 items
  on screen = ~30ms before a single pixel draws. Levers: cull sub-pixel
  decorations at far zoom, bake static content into chunk textures (see
  the soil pattern below), or MultiMesh.
- **Property setters are NOT free, even for unchanged values.** In Godot 4,
  `Sprite2D.flip_h`, `modulate`, and `z_index` setters trigger canvas
  redraws / RenderingServer calls without equality checks. A herd of 180
  idle creatures rewriting identical values 60x/s was a measured cost.
  On hot paths, guard every visual property write with `if new != old`.
- **`Label.text = same_string` still re-shapes the font.** Pooled floating
  text re-setting an identical string ~450x/s was a measured storm. Skip
  the assignment when the pooled node already wears that exact text.
- **CANVAS_ITEM_Z_MAX is 4096, and relative z STACKS.** A child at z 4090
  under a parent with any z silently overflows - the engine spams an error
  you only see on stderr. Leave generous headroom (we cap decor at ~3900).
- **Runtime texture atlas is easy and pipeline-free**: at load, collect
  every unique Texture2D (including procedurally generated ones a build-time
  packer could never see), shelf-pack into big `Image`s (2px padding,
  4096 max width for old web GPUs), `ImageTexture.create_from_image`, and
  swap each source for an `AtlasTexture` region. AtlasTexture is a drop-in
  Texture2D (get_width/height return the region), with ONE trap:
  **`AtlasTexture.get_image()` returns the WHOLE sheet**, so image-reading
  tools need a bypass lever.
- **Group atlases along the draw order.** Batches break when the texture
  changes along the z-sorted draw sequence - pack categories that draw
  adjacently into the same sheet, never split a category across sheets.

## Simulation architecture (the patterns that scaled)
Tags: architecture, performance | Pool objects, tick centrally in buckets, and let the grid be the spatial hash

- **Pool everything; never instantiate/queue_free during gameplay.** Pooled
  scenes implement pool_activate()/pool_reset(). Corollary trap:
  `is_instance_valid()` is TRUE for a pooled-and-recycled node - a stale
  reference points at a reused object. Guard cross-references with state
  flags, never validity alone.
- **No per-entity Timer or _process.** One central system ticks entities at
  a fixed rate split into buckets (each entity ticks every Nth tick with
  Nx dt). Smooth per-frame motion stays per-frame; hunger/growth/decay ride
  the slow tick.
- **Fixed-timestep accumulators NEED a catch-up cap** (`while accum >=
  interval` is a death spiral: a slow frame banks ticks, repaying them makes
  the next frame slower - we caught 28 ticks running in one frame). Cap at
  ~3 ticks/frame and DROP the remainder (`accum = fmod(accum, interval)`) -
  sim time stretches gracefully under load instead of killing the frame
  rate. **Scale the cap by Engine.time_scale** or your fast-forward setting
  silently under-delivers at low fps.
- **Stagger everything.** (1) Give each system's accumulator a different
  initial offset so they don't all fire the same frame. (2) If off-screen
  entities tick at half rate, alternate by ENTITY PARITY, not a global
  phase flag - a global flag makes every off-screen entity tick on the same
  cycle, producing a visible multi-second fps sawtooth (heavy cycle, light
  cycle). Even/odd stagger = same cadence per entity, flat load.
- **The grid IS the spatial hash.** A game on a cell grid needs no Area2D
  and no physics queries - "what am I standing on" is integer math, radius
  queries walk cells. We render 6,000+ interactive plants with zero physics.
- **Bake state into one texture** (the soil pattern): a whole 560x11 grid is
  ONE Image/ImageTexture (1px per cell, nearest filter, scaled up), painted
  per-cell only when a cell changes, uploaded per-row only when dirty. One
  draw call for the entire floor. The same idea extends to static flora
  chunks ("chunk baking") when item count becomes the ceiling.
- **Cache expensive AI scans WITH their misses.** The worst pathology was a
  starving animal rescanning a 441-cell radius every tick and finding
  nothing, forever. A short TTL memory (hit OR miss, ~2 ticks; shorter for
  chasers; cleared on panic) removed the cost without changing behavior.
  Likewise, an O(N^2) "is a predator near me" scan became O(N + K) by
  collecting the few predator positions once per tick.
- **Vision cones cost one dot product.** Directional senses (prey sees
  ~300 degrees, hunters ~200) add rich behavior for essentially free -
  cost lives in scan COUNT, not scan quality.
- **Engine.time_scale scales _process delta and timers** - a free sim-speed
  lever, with the catch-up-cap interaction above as its one trap.
- **No physics used? Drop `physics/common/physics_ticks_per_second` to 10.**
  Harmless. But do NOT trust `TIME_PHYSICS_PROCESS` to confirm anything -
  we measured ~11ms there with ZERO physics nodes, unmoved by the tick
  rate; the monitor apparently misattributes frame-pacing time.

## GDScript and API gotchas
Tags: gotchas | Godot 4 language and API traps that silently break code or drop behavior

- `-1 << 30` is a PARSE ERROR (negative shift operand). Use a plain literal
  sentinel.
- `var x := dict.get(...)` (inferred Variant) is a parse error in strict
  projects - write `var x: Variant = ...`.
- **Never call `Input.parse_input_event()` from inside input handling**
  (a pressed callback etc.) - the synthesized event is silently dropped.
  `call_deferred` it.
- **CanvasLayer is not a CanvasItem** - generic code reading `visible`
  across mixed node types should use `node.get("visible")`.
- **`load()` caches resources.** Mutating a loaded Image/Texture mutates it
  for EVERY user - a shared folder sprite resized "for one species" shrinks
  for all of them. `duplicate()` before editing.
- **Static vars survive scene reloads.** Any static flag a catastrophe or
  mode sets must be reset in the owning system's `_ready()`.
- **Autoloads process before the current scene** (tree order); among
  autoloads, project.godot order rules. Matters for anything that
  accumulates per-frame data across systems.
- Integer division truncates (`level / 4` on ints) - handy for banded
  curves, a bug when a refactor makes one side float.
- **Enum-typed exports serialize as text defaults in .tres parsing tools**:
  a .tres omits fields at default value, so external tools reading tres
  files must also parse the script's defaults - and an enum default reads
  as `Op.ADD`, not a number. Write explicit values in generated tres files.

## Files, editor, and project plumbing
Tags: gotchas, process | Editor, export, and tooling traps that cause silent failures

- **Hand-written .tscn typed node exports need the header attribute** or the
  export silently stays null:
  `[node ... node_paths=PackedStringArray("soil")]` + `soil = NodePath(...)`.
- **PowerShell `Set-Content`/redirects write a BOM** that Godot's .tres
  parser rejects (`Parse Error: Expected '['`). Worse, a BOM once entered
  project.godot as a garbage duplicate key and survived for weeks. Write
  engine files from tools that emit clean UTF-8.
- **New asset FOLDERS require a `--headless --import` pass** - the silent
  failure is flat colors and no .import files beside the PNGs.
- **Export presets are addressed BY NAME**: `--export-release "Web"` fails
  informatively only if you read stderr; check `export_presets.cfg` for the
  actual names.
- **`--quit-after N` counts FRAMES, not milliseconds** - and headless
  `--fixed-fps` runs as fast as the CPU allows, so N frames of simulated
  time can pass in seconds (or a "25 minute" mistake).

## Debugging and measurement (the toolkit that cracked the case)
Tags: process, performance | Instrument every frame and measure windowed, not just headless, to find real costs

- **Read stderr.** `2>$null` hid SCRIPT ERRORs for days: a totally silent
  test run almost always means a parse error upstream, not a hung test.
  Engine error spam (like the z overflow) is stderr-only.
- **A frame-time watchdog beats guessing**: an autoload that logs any frame
  over threshold with `Performance` monitors (draw calls, objects, nodes,
  orphans, memory) plus game context. Orphan/node growth = leak;
  draw-call explosion = render burst; high process with low draws = script.
- **A cost ledger names the culprit**: wrap every per-frame `_process` with
  usec timing reported to the watchdog (`rename body to _frame(), add a
  4-line wrapper`), print the top costs on each spike line, and compute
  `unaccounted = frame - process - physics` (that remainder is render).
  When everything is instrumented, whichever key dominates IS the answer.
- **Per-second RHYTHM lines catch what spike lines cannot**: one compact
  line per second (fps, worst frame, the second's summed top costs) makes
  multi-second waves - like the off-phase sawtooth - readable at a glance.
- **Measure draw calls in-game, windowed**
  (`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`), and bisect by hiding
  layers (plants off, fx off, one-texture-for-everything...). The
  one-texture experiment is what proved the GL batching truth in minutes
  after days of atlas theory.
- **Headless benches cannot see the render side.** A sim that benches at
  1.5ms/frame can still play at 15fps - always pair a bench with a
  windowed measurement before concluding anything about frames.
- **Prove time-scaling claims with a truth test** (count real frames to a
  sim event at 1x vs 3x). Ours read ratio 2.98 and turned a "bug report"
  into two real findings elsewhere.
- **Visual regressions: capture a screenshot from the game itself**
  (`get_viewport().get_texture().get_image().save_png(...)`) behind an env
  var, and compare before/after. Cheap, scriptable, decisive (verified the
  atlas and the Forward+ switch render identically).

## Process habits that repeatedly paid off
Tags: process, lessons | Self-test everything, data-drive every number, and trust player reports

- Self-test everything behind env vars with one PASS/FAIL line; run tests
  headless before every commit. A parse error that reaches main costs more
  than every test run combined.
- Data-drive every number (resources, not code constants). Twice we had to
  migrate hardcoded systems (perm costs, then the whole eternal shop) into
  resources so tools could edit them - starting data-driven is free.
- Guard generated patches: bash heredocs collapse backslash-newline
  sequences inside embedded code, producing joined lines that sometimes
  still parse (worse than failing). Literal-string edit tools for any
  continuation-bearing code.
- Filter test output by the string the test ACTUALLY prints ("TOOLTEST
  water:" does not contain "TEST:").
- When a player reports something impossible ("hidden animals are not
  behind the brush"), believe them: the per-frame row sort was clobbering
  the z shift every frame. The report was exactly right.

## Volume sliders: never feed a raw 0-1 slider into linear_to_db
Tags: gotchas, lessons, design | A linear slider through linear_to_db is far too loud at the bottom; square it first (10% = -40 dB) or players hear 10% as 40%

`AudioServer.set_bus_volume_db(bus, linear_to_db(slider))` looks right and
is wrong: linear_to_db maps AMPLITUDE, and the ear hears loudness, which
halves roughly every -10 dB. So 10% = -20 dB = about a quarter of full
volume, 50% = -6 dB = barely quieter than max. Players who set every game
to 5-15% find the bottom of the slider useless. The fix is one line: raise
the slider fraction to a power before linear_to_db. Exponent 2 gives
10% = -40 dB, 50% = -12 dB, 70% = -6 dB, 100% = 0 dB, which is the range
most games live in; 3 is stronger still. Put the exponent on a const and
route EVERY bus through the same function, then assert the curve in a
self-test (the value 10% maps to), because nothing else catches it: the
bus exists, the stream plays, mute works, and it is still wrong.
See also: CLICKER_DESIGN_NOTES.md (feedback economics: sound is part of
the click feel); Everwood docs/systems/ui.md "Music and the Audio section".

## Window mode toggles: a screen-sized windowed window IS fullscreen to Godot on Windows
Tags: gotchas, lessons | If the OS window exactly covers the screen, Godot/Windows gives it the frameless popup style and reads the mode back as fullscreen; set a window-size override smaller than the screen, and keep the chosen mode as your own state

Two bugs, one cause, found by measuring the real Win32 style word from
outside the game (a probe script reading GetWindowLong GWL_STYLE while
the game walks the modes on a timer - the only honest way to test window
chrome; headless has no window). A windowed window whose rect exactly
covers the screen gets WS_POPUP|WS_BORDER (no caption, no frame, no X or
minimize) and `Window.mode` reads back MODE_FULLSCREEN even though you
set MODE_WINDOWED. A project whose viewport size equals the dev screen
(1920x1080) hits this on every drop to windowed. Consequences: (1) an F11
toggle written as "if mode == FULLSCREEN then windowed else fullscreen"
sticks - the read-back says fullscreen forever; (2) "windowed" has no
title bar. What does NOT fix it (all measured): resizing the window after
the mode change, deferred or not; flipping `borderless` on and off. What
does: `display/window/size/window_width_override` / `height_override`
smaller than the screen (1600x900 for a 1920x1080 design viewport) - the
viewport keeps its design size under the stretch mode, only the OS window
shrinks. Plus the state rule: hold the DESIRED mode in your settings,
persist it, have every entry point (menu row, hotkey) flip that state and
apply it; the hotkey goes in an autoload's _input so no Control swallows
it and it works on menus and while paused. Names players expect:
Borderless fullscreen = MODE_FULLSCREEN, Exclusive = MODE_EXCLUSIVE_
FULLSCREEN, Windowed = MODE_WINDOWED. Remaining limit: screens no larger
than the override still hit the popup case.
Probe gotchas: the console exe is a WRAPPER (the game is a child process,
its pid never matches); with stdout PIPED the wrapper never shows the game
window at all (log to a file instead); a from-source run titles its window
"<name> (DEBUG)"; sample after the game's own log marker, never by wall
clock (boot time varies 2-4 s).
See also: Everwood docs/systems/ui.md "Window mode: the Graphics row and F11".

Search keys: godot field notes, engine lessons, rendering performance,
  gdscript gotchas, portable knowledge
```

### `HOOKS_METHOD.md`

- Source: `HOOKS_METHOD.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 46956
- SHA-256: `50476631769b17068f458f7066a4287f8bdd55fc173f7b3d533a504dd9b20676`

```text
# HOOKS_METHOD.md - laws the harness enforces itself (PORTABLE, part of the future-project kit)

PURPOSE: Documents the harness hooks, session start, prompt, stop,
  compaction, and tool-call guards, that enforce CLAUDE.md's laws
  mechanically instead of relying on the manager's memory, plus the hook
  contract and the kit's hook roster.
INTENT: Founded on Mazhron's question: Claude has a thing called hooks, are
  there any we could create and add to our workflows. Every law and ritual
  previously ran from the manager's memory; a hook turns Claude should into
  Claude cannot.

Founded 2026-09-06 on Mazhron's question "Claude has a thing called hooks -
are there any we could create and add to our workflows?". The answer was
yes, and the reason is structural: every law in CLAUDE.md, every ritual on
the skills shelf, ran from the manager's MEMORY. After a /clear the CEO
had nothing until someone typed "standup"; the checkpoint counter ticked
only when the manager remembered; "never delete a build zip" was a
sentence. A HOOK is a script the HARNESS runs at a fixed moment, with no
one remembering anything. It turns "Claude should" into "Claude can't".

Search keys: hooks, harness hooks, settings.json, session start, stop
hook, pretooluse, deny, block, context gauge, auto standup, auto tick.
See also: SKILLS.md (the voluntary twin: skills run when invoked, hooks
run when the harness reaches a moment), REPORTING_METHOD.md (the ledgers
the hooks feed), SUBAGENT_METHOD.md (the stamp a Tier-4 hook will check),
WORKFLOW_METHOD.md (the registry entry "Add or change a harness hook").

## THE HOOKS RULE (standing, Mazhron 2026-09-06)

A law the harness CAN enforce mechanically gets a hook, not a prose
reminder. The test: does the law fire at a moment the harness exposes
(session start, prompt submit, before/after a tool call, manager stop,
compaction, employee stop)? If yes, script it. Prose stays for judgment
calls; hooks take the mechanical ones. Adding a hook is a normal batch:
script + wiring + pipe test + its doc line + (if portable) the kit copy
and an UPGRADES entry.

## The contract (what a hook is, mechanically)

- Wiring: `.claude/settings.json` (project-level, CHECKED IN - it travels
  to every workstation via git) maps an EVENT (+ optional tool MATCHER) to
  a command. The command form that survives Windows paths with spaces and
  a missing env var: `python "${CLAUDE_PROJECT_DIR:-.}/tools/hooks/x.py"`.
- Input: one JSON object on stdin. Common fields: `session_id`,
  `transcript_path`, `cwd`; per event: `source` (SessionStart:
  startup/resume/clear/compact), `trigger` (PreCompact: manual/auto),
  `tool_name` + `tool_input` (PreToolUse; a shell tool's command is
  `tool_input.command`), `stop_hook_active` (Stop: true when this stop
  was already refused once - the loop guard).
- Output: exit 0 + plain stdout = injected as context (UserPromptSubmit,
  SessionStart); JSON `{"hookSpecificOutput": {"hookEventName": E,
  "additionalContext": T}}` does the same explicitly; PreToolUse deny =
  `{"hookSpecificOutput": {"hookEventName": "PreToolUse",
  "permissionDecision": "deny", "permissionDecisionReason": R}}`; Stop
  refuse = `{"decision": "block", "reason": R}`; `{"systemMessage": M}`
  shows the user a line without touching the model's context.
- Exit 2 = BLOCKING ERROR with stderr fed back. A Python "can't open
  file" is exit 2 - a mis-pathed PreToolUse hook refuses EVERY tool call.
  Hence the `${CLAUDE_PROJECT_DIR:-.}` form, never a bare relative path,
  and a try/except around anything that can throw.
- A broken settings.json silently disables every hook in it: validate
  with `python -m json.tool .claude/settings.json` after each edit.
- The template's permissions.deny block (v1.40, a take from serio-focus)
  is the layer under the hooks: destructive shell shapes and Read/Edit of
  .env files, key material and credentials are refused by the harness
  itself, before any hook runs, at zero cost. Merge it, do not replace
  your own list.
- The settings watcher picks up edits live for directories that had a
  settings file at session start; a brand-new file MAY need /hooks or a
  restart (in the origin project it was picked up live).
- Cost: one interpreter launch (~0.3 s) per trigger. Fine for session,
  prompt, stop, compact and shell-command hooks; a PostToolUse hook on
  every Write/Edit must stay a pattern match with no heavy imports.

## The kit hooks (hooks/ - fifteen scripts + _hooklib + settings.json)

TIER 1 - the resumption + checkpoint loop:
1. `session_start.py` (SessionStart, all sources): runs the standup
   script and injects the digest with a relay instruction. Resumption no
   longer depends on anyone typing "standup"; after an auto-compaction the
   digest re-anchors the summary.
2. `stop_tick.py` (Stop): ticks the checkpoint counter ONLY when work
   happened - `work_fingerprint()` in the checkpoint script = HEAD + the
   working tree's porcelain status minus bookkeeping files. A Q&A reply
   does not tick. ADVISED (8 tasks or <80% context) = a system message
   to the user; URGENT (15 tasks or <30% context) = the hook REFUSES to
   end the turn once (re-blocks every 5 tasks; `stop_hook_active` guards
   the loop) and the reason tells the manager to relay and checkpoint.
   Manual `--tick` is retired (it double-counts next to the hook).
   ADVISED MEANS DO IT (kit v1.13, the origin CEO's ruling 2026-09-10:
   "If a checkpoint is advised, you should do it. That way a user
   doesn't need to ask you to checkpoint, they can simply clear"): an
   ADVISED line from either hook is an instruction, not a suggestion -
   the manager runs the checkpoint ritual at the end of that reply if
   the arc is closed and the tree is committed, and the CEO just
   /clears. Mid-arc: finish the step, ship, then checkpoint. THE HOOK
   LAW (kit v1.31, the origin CEO 2026-09-28, after a warn-only line was
   relayed to him three replies running: "A Warning from the hook means
   do it, not relay the message for the user to do"): the rule covers
   EVERY line a hook prints that names work - CHECKPOINT ADVISED, LESSON
   ADVISED, KIT UNSYNCED, CHANGELOG UNEXPORTED, LEDGER ADVISED - not only
   the ones tagged ADVISED. Each is executed inside that reply; a hook
   words its line as an order to the manager, never as a note for the
   CEO; the same line seen twice is the failure. stop_tick.py's changelog
   count also skips the export's own "changelog:" commit (it warned "1
   commit" after every export before). Why the
   whole thing is not one script: the day file stores both sides of the
   final exchange word for word, and the manager's side is the reply
   being written at that moment - no script can see it before it is
   sent. The script does the mechanics (push, fingerprint, reset); the
   manager writes the two paragraphs.
3. `prompt_gauge.py` (UserPromptSubmit): silent unless a threshold is
   crossed; then one line the manager relays verbatim. Zero tokens on a
   normal turn. Since kit v1.33 (THE ROUTE LINE, 2026-09-28, after
   Kelsey Hightower's Zero Token Architecture) it also names the
   WORKFLOWS.md entries and the reference tools whose heading, WHEN line
   or Search keys the prompt hits (reference tools/route_index.py, the
   lesson matcher; at most two of each), so "does software already
   handle this" is a lookup and not the manager's inference each turn.
4. `pre_compact.py` (PreCompact): one ledger line per compaction
   (when/WS/version/manual-auto/context/unbanked tasks) in
   docs/history/compact_runs.txt; a system message on auto.
5. `lesson_advisor.py` (Stop; kit v1.26, THE LESSON LOOP, the CEO's ask
   2026-09-20: "something to push you to write what you learned, as
   well as push you to add to the knowledge base"): the checkpoint
   counter's twin for learning. It reads the turn's transcript slice
   (since the last Stop, a line pointer per transcript in .claude/
   lesson_state.json) through reference tools/lesson_log.py and, on a
   trial-and-error signal - the same command run again after an error,
   repeated edit misses, a FAIL followed by a PASS, an intent claim
   resolved DIFFERENT, an employee briefed twice, a prompt that reads as
   a correction - REFUSES to end the turn once with LESSON ADVISED, and
   ADVISED MEANS DO IT: the manager writes or amends the LESSONS.md
   entry for the task shape (or the wiki fact under a Tags line, or one
   line saying why there is no lesson) before the turn ends. A block is
   used, not a systemMessage, because only a block's reason reaches the
   manager. Never the same slice twice; a turn that edited the book is
   ledgered WRITTEN and passes. The prompt end lives in prompt_gauge.py
   (THE LESSON LINE: the entries whose Keys hit the prompt, read before
   the first tool call). Ledger: docs/history/lesson_runs.txt; the
   check loop lints the book and ledger_trends proposes when advised
   lines pile up unwritten. State file: gitignore it.
   Since kit v1.34 (THE CHECKPOINT NAMED CHECK, 2026-09-28, correction
   C0004: "Any reference to a checkpoint from any valid source should
   prompt you to do it") it also reads the turn's reply text from the
   transcript and refuses once per prompt when the reply names a
   checkpoint as due (the word within a sentence of next / natural / due
   / advised / ready / should / whenever / now) without the safe-to-clear
   marker: naming a checkpoint is making it, and the manager's own reply
   is a valid source like any hook line.
   Since kit v1.35 (THE PROPOSAL NAMED CHECK, 2026-09-29, correction
   C0005: "If an audit is required, and it can be done with a sub-agent,
   or a script, it doesn't need my permission. Just do it.") the same
   reader holds the reply to the standup's proposals: ledger_trends.py
   tags every PROPOSE line [DO] or [ASK] and exposes the DO ones that
   clear when done (the systems audit, the README audit, the digest trim,
   a stale loop group, dead links, an unwritten lesson, a stale claim);
   a reply that names one of them while its ledger still raises it is
   refused once per prompt with PROPOSAL NAMED, and the block's reason
   carries the scripted way (HOW). A reply that did it passes because
   the ledger no longer proposes; a reply that never mentions it passes.

6. `session_end.py` (SessionEnd; kit v1.28, THE AUTO-CHECKPOINT, the
   CEO's ask 2026-09-20: "Can we make /clear automatically check for a
   checkpoint, and if none was done, perform a checkpoint before
   clearing?"): fires when the session ends (clear, logout, stdin
   closed, other; a `resume` suspension is ignored). It cannot hold the
   clear back and the manager is gone, so it does the MECHANICS alone
   and only when work is UNBANKED (a change outside the ledger folder,
   or a commit not on origin): mines the final prompt + reply verbatim
   from the session's transcript (transcript_path; the standup miner),
   writes them into today's day file as an AUTO `## WHERE WE LEFT OFF`
   (the old section stays above it under a SUPERSEDED heading, the
   file and its index line are created if missing, NEXT LIKELY says
   "not written"), `git add -A` + a "Checkpoint (auto)" commit, a push
   to origin and to the local mirror (backup_push.py), then the counter
   reset with the fingerprint stored. Nothing unbanked = one ledger
   line (docs/history/session_end_runs.txt) and nothing else. Never
   raises: an exception is a ledger line and exit 0. Budget: the
   harness caps SessionEnd at 60 s total, so the settings timeout is
   55 and every git call has its own. What it is NOT: the manager's
   checkpoint - the judgment paragraphs (STATE in prose, OPEN QUEUE,
   NEXT LIKELY) are still written at the next real one, and ADVISED
   MEANS DO IT still stands; this is the net under it. `--selftest`
   builds a throwaway repo with its own bare origin in the OS temp
   folder and runs the real path (18 checks); the sandbox is left for
   the OS, because the preserve guard refuses a script that removes
   its own sandbox and the lesson says reword, never route around.

TIER 2 - shell guards (`bash_guard.py`, PreToolUse on Bash|PowerShell):
generic rules - no `--no-verify`, no plain force push - plus a PROJECT
RULES block the receiving project fills with its own laws. The origin
project's examples: no delete/move in the builds folder (build zips are
never deleted), tests only through the runner script (never set the test
env var by hand), no em/en dashes in commit text (subjects become the
public changelog), no shell writes/redirects into engine resource files
(the BOM gotcha).

TIER 2b - THE FAN-OUT GUARD (`fanout_guard.py`, PreToolUse on EVERY
tool; kit v1.9, the CEO's ask 2026-09-10 after a public report of a
manager spawning 821 sub-agents and burning 50M+ tokens in thirty
seconds). CATASTROPHE-ONLY by the CEO's ruling the same day ("this
might be too restrictive... I just wanted to prevent complete runaway
agents and gigantic token spend"): nothing fires on real work, nothing
needs a command to lift, and the manager is never locked out for more
than a cooldown.
- THE SPEND METER: every call folds the NEW bytes of the session
  transcript and its employee transcripts into raw + WEIGHTED tokens
  (weighted ~ cost: input 1, cache write 1.25, cache read 0.1, output 5;
  byte offsets in the state file, so a warm call costs ~0.06 s). The
  first sight of a file backfills totals without feeding the velocity
  meter, so installing mid-session never trips on catch-up.
- REFUSES only the runaway shapes: a BURST (8 spawns inside 60 s,
  machine-wide - the 821 shape), a FLOOD (25 spawns inside 10 min per
  session - a loop, not a plan), and RUNAWAY VELOCITY (10M weighted
  tokens inside 120 s: every tool call refused until the window drains,
  a self-clearing cooldown; the manager can still talk and report).
- WARNS, never refuses, on everything else: a systemMessage the CEO sees
  plus a context line the manager relays - every 10 spawns, every 10M
  weighted tokens, velocity past 3M inside the window, and a one-time
  reminder when the bulk-orchestration tool runs.
- No unlock file, no --allow commands, no self-edit lock: `--status`
  shows the meter, `--resume` clears it early, `--selftest` runs the
  twenty-four pipe tests in-process (always at DEFAULTS, so tuning can
  never fail them). The manager-side rule is the delegation method's
  law 6 (THE FAN-OUT LAW); the guard is what makes it true on a bad day.
- THE NUMBERS ARE THE CEO'S (kit v1.10, the origin CEO's ask
  2026-09-10): the script carries DEFAULTS; the CEO's tuned numbers live
  in `.claude/fanout_limits.json` (COMMITTED - they travel with the repo
  and survive a kit graft; a missing or junk file falls back per key).
  `--limits` prints every number current vs default with its meaning,
  `--set key=value ...` writes (refusing a warn threshold above its halt),
  `--defaults` forgets. The /runaway skill (SKILLS.md) is the
  conversational front: show, ask, set, selftest, commit. The manager
  never raises a limit on its own - a refusal still means stop and
  report.

TIER 2c - THE DIET GUARD (`diet_guard.py`, PreToolUse on Read|Bash|
PowerShell; kit v1.12, the origin CEO's ruling 2026-09-10 after the
weighted-usage insight: only the tokens that count against the plan
matter, and under those weights the manager's context is written at
1.25x and every tool result rides in it forever). Nothing to type; one
refusal shape only (INDEX FIRST, kit v1.15), the rest warn-only:
- INDEX FIRST (kit v1.15, the origin CEO's order 2026-09-10 PM: "section
  or split as necessary ... should not require my approval ... part of
  the looping scripts"): the FIRST whole read of a big file per file per
  session is refused, and the refusal carries the file's own index -
  `## ` headings for markdown, func/class/def lines for code, each with
  its line number, capped at 80 - so the next call reads one section by
  offset/limit. The SAME call repeated passes with the warning only (the
  editing exception, no words needed). A file with no structure only
  warns; an image is silent (priced by pixels, ~1-2k tokens however many
  bytes it holds - sizing pictures by their bytes was the bug that made
  the origin project's "21 big reads a day": they were screenshots).
- THE READ DIET (the 10k rule): every later whole-file Read (no
  offset/limit) or bare cat/type/Get-Content of a file past ~10k tokens
  gets one line at the moment of the decision - the size, the line
  count, how many `## ` sections it has, and the cheaper move (grep the
  headings and read one section; or, for an understand-this step,
  delegate the reading to an employee and take back a summary). The CEO's own idea was a token count
  in every heading; that went stale by design and cost output to
  maintain, so the count is GENERATED at the cliff edge instead - the
  harness knows the file size before the read happens. Editing that
  needs the exact text is a fair reason to proceed; the guard says so.
- THE OUTPUT DIET: a chatty shell shape with no limiter - git log
  without a count, a bare git diff, a recursive listing, a noisy
  install - gets the limiter to add, at most three times per session
  per shape so a deliberate choice is not nagged.
- `--selftest` runs the in-process checks; state in
  `.claude/diet_state.json` (gitignored). The outcome is graded by the
  usage sheet's daily line (REPORTING_METHOD.md, THE COMPARISON RULE):
  heavy whole-file reads and section-read share, each day against the
  previous seven, so a bad day is named the next morning.

TIER 2d - THE PRESERVE GUARD (`preserve_guard.py`, PreToolUse on Bash|
PowerShell|Write|Edit|MultiEdit|NotebookEdit; kit v1.14, the origin CEO's
ruling 2026-09-10 after public reports of an agent whose script deleted a
person's files and another that wiped a machine: "You nor any of your
employees should ever delete a file, record, etc. without express
permission from the user. There should be no script created to delete
either"). A REFUSAL, the second one in the kit after the fan-out guard,
and like it aimed at the cliff edge only:
- SHELL: delete verbs with a path argument (rm, rmdir, rd, del, erase,
  unlink, shred, Remove-Item, ri, Clear-Content, format, diskpart,
  truncate), find -delete, xargs rm, moves into nul or /dev/null, the
  git verbs that discard work or history (rm, clean, reset --hard,
  checkout -- path, restore path, branch -d/-D, push --delete, stash
  drop/clear, worktree remove, tag -d, reflog expire, gc --prune), and
  deletion CALLS inside a one-liner or an executed heredoc.
  HARDENED (kit v1.27, 2026-09-20) after a public report - an agent's
  throwaway remover, written to Temp and run in a later command, walked
  a tree through Windows directory junctions (os.walk and islink() do
  not stop at a junction) and emptied a repo's .git, 48,000 files: a
  bare-name target (rm build), a pipeline or foreach body feeding a
  delete verb, find -exec, the mirror verbs (robocopy /MIR or /PURGE,
  rsync --delete), git checkout of a path or `.`, switch
  --discard-changes, every force push (the grant is the go-ahead),
  branch -f/-M, filter-branch, prune. A variable target ($DIR, %X%) is
  refused outright: the guard cannot read it, so no grant can cover it.
- RUN: every script a command EXECUTES (python x.py, pwsh -File, bash
  x.sh, node, `&`, a script that starts a command; flags or a runner
  like timeout in between) is read and scanned before it runs - the
  whole file when git does not track it, only the uncommitted ADDED
  lines when it does. Whatever wrote the script (a Write the guard saw,
  a heredoc, an editor, another agent), it cannot delete when it runs.
  grep, cat or diff of a script is reading, not running, and passes.
- WRITE: content that adds deletion calls to a non-prose file (the
  os/shutil/pathlib calls, the engine's file removal, fs.rm and
  fs.promises.rm, rimraf, File.Delete, a subprocess or os.system that
  names a delete verb, a Remove-Item, rm -rf, rd /s, robocopy /MIR,
  rsync --delete, find -delete or git clean line in a script). Prose
  files pass: a law written down names the verbs it bans, and the guard
  refused its own author's documentation twice before that exemption
  existed (and its own hardening five times: two-letter helper variables
  that read as verbs, pattern sources that matched themselves - reword,
  never route around).
- PASSES: every path inside the session scratchpad (the harness's own
  per-session junk); a heredoc body fed to cat/tee whose target is a
  PROSE file (a body aimed at a script file is scanned like code); ONE
  command matching a live GRANT.
- FAILS CLOSED: a crash inside the guard falls back to a crude substring
  check of the obvious verbs and refuses on a hit; a guard bug never
  becomes an open door.
- THE GRANT (tools/delete_grant.py, reference tools/): the manager asks
  naming the exact target, the CEO says yes, the manager restates, the
  CEO says yes again, and the four texts are recorded VERBATIM in
  .claude/delete_grant.json (gitignored, 15 minutes, single use - the
  guard marks it used, never removes it) plus a committed ledger
  docs/history/delete_grants.txt. The grant script itself refuses the
  never-list.
- NEVER, grant or not: a drive root, the home folder, the repo root or
  its .git, a bare wildcard, a path that climbs out with "..". Those
  shapes have no legitimate use in an agent's hands.
- THE MOVERS replace deletion: tools/retire.py moves a file to
  _retired/<same relative path> with a ledger line; tools/cold_shelf.py
  moves a rarely-read wiki section to docs/cold/ verbatim with a stub at
  the old heading and an index line (WIKI_METHOD.md "The cold shelf").
  A wrong memory is marked superseded in place.
- `--selftest` runs 35 in-process checks. No state file; the grant is
  the only thing it reads besides the tool input.
The lesson that shaped it: the guard fired on its author within a
minute of being wired (the settings watcher is live) - first on a
docstring that mentioned the remove call, then on the documentation
table naming the banned verbs. Both were the guard working as written;
the fix was a prose exemption, not a workaround. And the audit the law
forced turned up one real hazard: the kit-mirror script wiped its
target folder before copying, which a misconfigured path would have
turned into an emptied directory. It now refuses a target whose README
does not name the kit and reports stale files instead of removing them.

State: `.claude/hooks_state.json` (gitignored - the fingerprint is per
machine); `.claude/fanout_state.json` (gitignored, the guard's meter);
`.claude/diet_state.json` (gitignored, the diet guard's per-session caps);
`.claude/delete_grant.json` (gitignored, the single-use grant). The checkpoint script's `--reset` stores the fingerprint LAST so
the checkpoint commit itself is not counted; the checkpoint ritual's step
order is commit + push, THEN reset, THEN the marker.

## Tier 3 - THE HYGIENE GUARD (hygiene_guard.py, PostToolUse on Write|Edit|MultiEdit)
Tags: process, lessons | The laws easiest to forget mid-batch fire on a file edit, not a command - so the harness says them at the edit (kit v1.16)

Born 2026-09-11 when the public README was found two kit versions
behind: three law batches had shipped in one evening and nothing said
"refresh the README" at the moment the originals changed. The CEO:
"we definitely don't want the readme falling behind again." One script,
pattern matching only, no state, one interpreter launch per edit
(~0.3 s). It runs AFTER the edit lands and answers with context lines -
never a refusal - except the dash rule, which BLOCKS (PostToolUse
"decision: block" feeds the reason back so the line is fixed at once).
Its CONFIG block at the top names the project's files; a kit install
rewrites that block and nothing else.

1. KIT REFRESH: the edited file is a portable original (a kit MD, a
   skill's SKILL.md, a hook script, a tool that has a reference copy) ->
   one line naming the grab-copy to refresh, the graft-log entry + version
   bump if a concept changed, the public README if a pillar / skill /
   hook / box item changed, then the sync script. Editing a kit COPY
   directly names the original instead; editing the graft log reminds of
   the version line; editing the core instructions file runs its lint at
   once and relays a FAIL (silent when OK).
2. SEE-ALSO: a touched section of a wiki topic page (the link checker's
   hygiene scope) carries no "See also:" line -> the heading is named at
   the edit, instead of in the next link-checker run. A Write lints every
   section; an Edit only the section(s) its new text landed in.
3. DASH (BLOCKS): player-facing text (resource files, UI scripts, the
   store copy, the changelog) received an em or en dash -> the offending
   lines come back and the manager fixes them before anything else. The
   origin project's 217-dash sweep never runs again.
4. IMPORT: a new asset file landed under the assets folder -> "run the
   engine import before the next test".

Companion, not a hook: the kit sync script REFUSES to push while the
README's "Kit version:" line lags the graft log's CURRENT KIT VERSION -
the README lives only in the public repo, so the sync is the one place a
stale one can be caught mechanically.

`--selftest` runs 25 in-process checks (every rule, its scope edges, the
outside-the-repo and empty-input cases).

See also: WORKFLOWS.md "Edit the future-project kit (Rootstock)"; the
link checker (reference tools/check_wiki_links.py, the after-the-fact
twin of rule 2); SKILLS.md (THE SKILLS RULE the kit-refresh line backs).

## Tier 3b - THE FORMAT GUARD (format_guard.py, PreToolUse + PostToolUse on Write|Edit|MultiEdit)
Tags: process, architecture, lessons | A community kit needs a guardrail that does not depend on the reader's good faith: a hook that refuses the unsafe settings edit and blocks the unformatted one (kit v1.19)

Born 2026-09-13 from the CEO's three-part ruling on community updates
(INTENT.md "The format law"): "Anything without proper format should be
flagged, a script should re-write it after review-only audit. This will
be a law and may need this to be a hook somehow so that no one can
inject a prompt that overrides safety protocols." One script, stateless,
one JSON parse plus pattern matching, ~0.3 s per edit; it imports the
format lint (reference tools/format_lint.py) and dispatches on the
event name:

1. BEFORE an edit of a settings file (.claude/settings.json or the kit's
   hooks/settings.json): the would-be text is computed (a Write's
   content; an Edit's old -> new applied to the current file) and
   REFUSED if it would not parse, would name a hook script that does not
   exist beside it, or would leave any SAFETY hook unwired, narrowed or
   mis-pointed. The SAFETY table lives in the lint: preserve_guard,
   bash_guard, fanout_guard, diet_guard, hygiene_guard, format_guard,
   stop_tick, each with the event and the tools its matcher must cover.
   Only the CEO changes the wiring, by hand; a prompt, a brief or a
   contributed patch cannot.
2. AFTER any edit of a kit thing or its original: the lint runs on that
   one file and the edit is BLOCKED (PostToolUse "decision: block" - the
   reason comes back, the edit stays) until the header is right:
   PURPOSE, INTENT, Search keys, See also; a hook's --selftest and
   _hooklib import; a skill's frontmatter. The reason carries the
   rewrite command (`format_lint.py --rewrite <path> --purpose ...
   --intent ...`), which inserts only the missing lines after a
   read-only look - never a hand edit.

Two twins close the other doors: the shell guard refuses a shell write
into a settings file (redirect, Set-Content, sed -i, tee, copy/move, a
python one-liner), and the Stop hook refuses to end the turn once per
fingerprint while the live settings file fails the safety check. The
three together are what "no one can inject a prompt that overrides
safety protocols" means mechanically.

`--selftest` runs the in-process checks against the live settings file
(deny on an unwiring Write, on a rename to a missing script, on
unparsable JSON; silence on a timeout edit; silence on out-of-scope
files). Install: wire both entries from the kit's settings.json, run the
selftest, then `python tools/format_lint.py` to see what the project's
own tools and hooks lack.

See also: reference tools/format_lint.py (the checks, the scope, the
rewrite); reference tools/purpose_audit.py + FLAGS.md (the audit the
PURPOSE line serves); CONTRIBUTING.md (the law for contributors);
SKILLS.md (/flag); WORKFLOWS "Format-check and rewrite a kit thing".

## Tier 4a - THE DELEGATION TRUTH SET (brief_guard.py, delegation_auditor.py, verify_advisor.py)

Born 2026-09-26 of the CEO's ask ("Can we make these processes more fool
proof in any way through hooks") and the public case he relayed the same
day: a manager that said its sub-agents did their job when they had not.
The manager book's truthfulness rules (SUBAGENT_METHOD.md: the stamp
template, the metered fabrication check, ledger-every-delegation) were
discipline; these three make the mechanical parts mechanical, one hook
per moment:
- DISPATCH: brief_guard.py (PreToolUse on Agent|Task, a REFUSAL) - a
  work brief missing the STAMP/TOOLS/WORKFLOW template, the INTENT line,
  the budget line or the preservation line is refused with the pieces
  named; a malformed brief costs a refusal, never a spent employee.
  Read-only searcher agent types pass untouched.
- RESULT: delegation_auditor.py (PostToolUse on Agent|Task) - reads the
  harness-metered tool/token figures out of the result (the numbers no
  model can fake): 0 metered calls on a work task = the fabrication
  tell; a TOOLS line claiming >3x the meter = a truthfulness signal; a
  report without its template lines is named. One PENDING line per work
  delegation lands in docs/history/delegation_pending.txt (id + metered
  truth) so no delegation vanishes unledgered. Resolution is a NEW
  `RESOLVED | <id> | OK/CORRECTED - <words>` line, never an edit.
- THE EMPLOYEE'S STOP (2026-10-01, the same script on SubagentStop):
  the RESULT branch above sees the Agent call's result, and with a
  background employee that is only the launch notice - 24 of the first
  25 PENDING lines carried tools=? tokens=?, so rule 3 had nothing to
  cross-check. At the employee's own stop the hook finds its transcript
  (agent_transcript_path, else <session>/subagents/agent-<id>.jsonl;
  this build hands the MANAGER's file under transcript_path), counts the
  tool_use blocks (the harness's own figure, nine of nine exact on the
  calibration day), sums output + cache-write tokens once per message
  id, and judges the union of the hand-back text, the last text block
  and last_assistant_message (the stop and the hand-back land in either
  order). A report without its template lines, or a TOOLS line under
  selfcount_floor (0.7, owner-tuned in .claude/fanout_limits.json) of
  the meter by three calls or more, HOLDS the employee once with the
  true count in the reason ("your TOOLS line says 18, the transcript
  holds 27; restate it"); stop_hook_active and an ASKED line at the
  ledger's tail guarantee once. Then a METER line lands in the pending
  ledger: `METER | <task id> | tools=N tokens=~Mk | claimed=C | OK /
  RULE 3 MISS / MALFORMED / FABRICATION TELL`, read at the tail (the
  event fires twice for a background employee, before and after the
  hand-back; the earlier line says pre-hand-back). The first replay
  over the week's nine employees reproduced the manager's hand ledger
  exactly: four misses held, three honest reports passed.
- STOP: verify_advisor.py (Stop, a once-per-set REFUSAL, the lesson
  advisor's pattern) - a PENDING id with no later RESOLVED line refuses
  the turn end once: verify cheap, write the manager-book ledger line,
  resolve the intent claim, append RESOLVED - or say in one line why
  verification waits. State: .claude/verify_state.json (gitignored).
THE CEILING, stated when the set was built: hooks force evidence to
exist and numbers to agree; whether the diff matches the claims and
whether an OK verdict is earned stays the manager's judgment, audited
through the ledgers.

## Tier 4 (still pinned - the origin project's FUTURE_FEATURES.md)

SubagentStop refusing an employee's stop when its report lacks the stamp /
workflow line: deferred 2026-09-26 as ~90% redundant with
delegation_auditor, then BUILT in v1.42 (2026-10-01) as the auditor's own
stop-time branch (Tier 4a: a report without its template lines is held
once), so it is no longer pinned;
Notification -> an OS toast when the manager waits on permission or
idles after a long employee run.

## Bootstrap (new project)

1. Copy the kit's hooks/ folder to the project's tools/hooks/ (or wherever
   its scripts live; the scripts locate the repo root from their own path
   and import the checkpoint script from the folder above them).
2. Copy hooks/settings.json to .claude/settings.json (MERGE if the project
   already has one - never replace its arrays). Validate with json.tool.
3. Gitignore `.claude/hooks_state.json` and `.claude/settings.local.json`.
4. Make sure the project's checkpoint script has `work_fingerprint`,
   `load_hook_state`, `save_hook_state` (the kit's reference
   tools/checkpoint.py carries them); reorder its checkpoint ritual so
   `--reset` runs last; strike every "tick by hand" instruction from its
   laws and skills.
5. Fill the bash guard's PROJECT RULES block from the CEO's STEP-0 laws.
6. Pipe-test every hook with synthesized stdin (`echo '{"tool_input":
   {"command":"..."}}' | python tools/hooks/bash_guard.py`); trigger the
   shell guard live once. Add the WORKFLOW entry "Add or change a harness
   hook" to the process registry and a "The hooks" section to the tooling
   doc (the table of event/script/does + the gotchas above).
7. The diet guard needs nothing project-specific: wire its
   Read|Bash|PowerShell PreToolUse entry (the template settings.json has
   it), run `python tools/hooks/diet_guard.py --selftest`, gitignore
   `.claude/diet_state.json`. If the project's checkpoint script
   fingerprints the tree, exclude the usage sheet's outputs (the
   reference copy does) so standup's silent refresh never counts as work.
8. The preserve guard needs nothing project-specific either: wire its
   Bash|PowerShell|Write|Edit|MultiEdit|NotebookEdit PreToolUse entry
   (the template settings.json has it), run `python
   tools/hooks/preserve_guard.py --selftest`, gitignore
   `.claude/delete_grant.json`, copy delete_grant.py, retire.py and
   cold_shelf.py from reference tools/ into tools/. Then AUDIT the
   project's existing scripts for deletion calls (grep the os/shutil/
   pathlib removal calls and the shell verbs) and bring each to the CEO:
   convert to a move, or keep with the CEO's word on record. Add the
   registry entries "Delete something (the grant ritual)" and "Retire a
   file or move a wiki section to the cold shelf".
9. The hygiene guard (Tier 3): rewrite its CONFIG block (the portable
   MD names, the kit folder, the skills/hooks dirs, the core file + its
   lint command, the wiki dirs the link checker lints, the player-text
   patterns, the assets folder + import hint), wire its
   Write|Edit|MultiEdit PostToolUse entry (the template settings.json
   has it), run `python tools/hooks/hygiene_guard.py --selftest`. No
   state file. Give the public README (if the project publishes a kit)
   a "Kit version: vX.Y" line so the sync script's check can hold.

## Change log

- 2026-09-06 WS1: founded. Tier 1 + 2 built and pipe-tested in Everwood
  (kit v1.7); Tier 3/4 pinned on the origin project's FUTURE_FEATURES.md.
- 2026-09-10 WS1: Tier 2b, the fan-out guard (kit v1.9) - the CEO's ask
  after the 821-agents report. The first cut was STRICT (session caps,
  a workflow lock, a self-edit lock, CEO-only unlock commands, a bash
  rule refusing the manager); it locked its own author out mid-batch
  and, within the hour, the CEO ruled it too restrictive: "I don't want
  to have to type these commands all the time and neither will any
  users who use Rootstock-os. I just wanted to prevent complete runaway
  agents and gigantic token spend." Loosened to CATASTROPHE-ONLY the
  same day (burst/flood/velocity refusals that clear themselves;
  warnings for the rest; no unlock machinery). Lesson: a guard rail is
  for the cliff edge, not the path - if a normal day ever needs a
  command to get past it, the rail is in the wrong place.
- 2026-09-10 WS1 (later): the numbers become the CEO's (kit v1.10) -
  `--limits` / `--set` / `--defaults` on the guard, a committed
  .claude/fanout_limits.json over the script's DEFAULTS, and the /runaway
  skill as the front. Rule of thumb that fell out: a guard's defaults
  belong to the kit, its tuning to the project - keep them in separate
  files so a graft never overwrites what the CEO chose.
- 2026-09-10 WS1 (evening): Tier 2c, the diet guard (kit v1.12) - born
  from the CEO's weighted-usage insight ("the most important token counts
  are the ones that actually count against a user's usage amount"). The
  usage sheet had shown that under budget weights cache WRITES are the
  top pillar and output is a fifth; the two leaks are whole-file reads
  and chatty tool results, and both are visible BEFORE the call. Hence a
  warn-only PreToolUse guard that says the number at the decision point.
  Lesson: a hook can enforce a diet only if it never blocks - the manager
  sometimes needs the whole file (an edit), and a refusal there would
  breed workarounds; a one-line cost at the cliff edge changes the habit
  without a fight.
- 2026-09-10 WS1 (night): ADVISED MEANS DO IT (kit v1.13) - the CEO:
  "If the checkpoint is a script, there is no reason not to just run it
  at the time a checkpoint is advised." Both hooks' ADVISED lines now
  say "checkpoint at the end of this reply if the arc is closed"; the
  checkpoint skill carries the rule at its top. An advisory the manager
  merely relays is a nag; an advisory the manager acts on is a law.
- 2026-09-10 WS1 (night): Tier 2d, the preserve guard (kit v1.14) - the
  CEO's ruling after public reports of an agent whose script deleted a
  person's files and another that wiped a machine: nobody deletes, no
  script deletes, and a real deletion is granted twice and recorded. The
  same evening the CEO asked whether the system learns, and the answer
  became three read-only scripts (link checker, section heat map, ledger
  trends -> proposals at standup) plus the cold shelf: pruning means
  MOVING to an indexed shelf, never deleting - "all of this is hard
  fought, hard earned knowledge, even the rarely used knowledge." The
  guard refused its own author twice within minutes (a docstring, then
  the documentation naming the banned verbs); prose files are exempt now.
  The audit it forced found the kit-mirror script emptying its target
  folder before copying - a misconfigured path away from the horror
  story - and that is fixed too.
- 2026-09-10 PM (kit v1.15): Tier 2c gains INDEX FIRST - the first whole
  read of a big file per session is refused with the file's index in the
  refusal, the same call repeated passes; images are silent (priced by
  pixels). Born when the origin project's "21 big reads a day" turned out
  to be screenshots sized by their bytes.
- 2026-09-11 WS1: Tier 3, the hygiene guard (kit v1.16) - the first
  PostToolUse hook. Born when the public README was found two kit
  versions behind; the CEO: "we definitely don't want the readme falling
  behind again." Kit-refresh reminder (naming the README), See-also lint
  at the edit, the dash rule as a block, the import reminder; plus the
  sync script's README version check. Tier 4 stays pinned. Lesson: a
  reminder that fires at the moment of the edit is worth ten in a law
  file - the README fell behind while the law was already written.
- 2026-09-13 WS1 (kit v1.19): Tier 3b, the format guard - the first hook
  that runs BEFORE and AFTER the same tools. Born from the CEO's ruling
  on community updates: every kit thing carries one header, a script
  flags the rest and rewrites only the missing lines after a read-only
  look, and a hook refuses a settings edit that would unwire a safety
  hook, so "no one can inject a prompt that overrides safety protocols".
  Twins in the shell guard (no shell writes into a settings file) and
  the Stop hook (refuses the turn while the wiring is broken); the prompt
  gauge gained the KIT UNSYNCED line the same day. Lesson: a guardrail
  for a community kit cannot depend on good faith; it is a script that
  flags, a script that rewrites, and a hook that refuses.
- 2026-09-13 PM (kit v1.20): the first purpose audit's five yellows closed.
  The three info-only hooks (session_start, prompt_gauge, pre_compact)
  gained `--selftest` with no live change (module work into main(), pure
  builders factored so a selftest never touches stdin, a real ledger or
  the standup script); every hook in the kit now answers `--selftest`.
  The diet guard's docstring stopped claiming it never refuses (it
  refuses once, INDEX FIRST). The front door got its first independent
  full read, which found the PURPOSE line undersold the hooks install
  and a stale skill list; both fixed, then GREEN. Lesson: the audit
  loop works on the kit's own authors - a non-author read found what
  three author passes had not.
- 2026-09-14 (kit v1.21): THE LOOP LAW landed in two hooks. session_start
  now runs the parent loop's session group once a day before the digest
  (a note says it ran or when it last ran; a missing run_all.py degrades
  to a note) and appends the digest's byte size to digest_size.txt every
  time it fires, so the injected context is measured, not guessed.
  stop_tick adds a warn-only CHANGELOG UNEXPORTED line when commits sit
  past the changelog anchor (once per count; silent when no anchor
  exists). Both selftests extended. The systems audit that asked for
  this is in INTENT_METHOD.md "The loop law".

- 2026-09-20 WS1: Tier 1 gains the lesson advisor (kit v1.26), THE LESSON
  LOOP's stop end, with the prompt end in prompt_gauge.py and the book in
  LESSONS.md. The CEO's ask: a system that learns HOW, not only what -
  the one right way first, then the pitfalls as headlines, so trial and
  error is paid for once. Design note: a Stop hook's systemMessage
  reaches the user, its block reason reaches the manager; an instruction
  to the manager must be a block, guarded so it can never trap (once per
  slice signature, stop_hook_active, WRITTEN passes).
- 2026-09-20 WS1 PM (kit v1.28): Tier 1 #6, the SessionEnd auto-checkpoint
  (session_end.py) - the CEO's ask the same evening, after the mirror
  question: /clear checks for a checkpoint and does the mechanics itself
  when none was done. Twelve scripts now. The local mirror
  (backup_push.py, a reference tool) pushes every ref to a bare repo on
  another drive; the hook, the ship and checkpoint skills and run_all's
  session group all call it.
- 2026-09-26 WS2 (kit v1.30): Tier 4a, THE DELEGATION TRUTH SET - the
  CEO asked "Can we make these processes more fool proof in any way
  through hooks or are we at maximum hookiness" after relaying a public
  case (a manager that said its sub-agents did their job when they had
  not). Three hooks, one per moment of a delegation: brief_guard.py
  refuses a lawless work brief at dispatch; delegation_auditor.py reads
  the metered figures out of every result (the fabrication tell, the
  TOOLS-line cross-check) and appends the PENDING line;
  verify_advisor.py refuses a turn end while a PENDING id lacks its
  RESOLVED line. All three in the format guard's SAFETY table. Fifteen
  scripts now. The fourth idea (the SubagentStop stamp check) stays
  pinned as ~redundant with the auditor. Lesson from building: the
  SAFETY table bites the kit template too - three single edits each
  left the other two unwired and were refused; one whole-file write
  that adds all three at once is the move.
- kit v1.31 (2026-09-28): THE HOOK LAW - every work-naming hook line is
  an order to the manager, executed in that reply, worded as such;
  stop_tick.py's changelog count skips "changelog:" commits (the export
  itself no longer reads as one unexported commit) and its line says
  MANAGER: run the export before this reply ends. Selftest gained the
  incident shape (anchor at the export's parent, range to the export
  commit, must count 0).
- 2026-09-28 WS1 (late): THE ROUTE LINE (kit v1.33). The CEO read Kelsey
  Hightower's Zero Token Architecture ("infer once, export the logic, run
  it without inference") and asked which of its gaps Rootstock should
  close; the one that mattered was the routing: the script rule exports
  the logic, but WHICH workflow or script handles a prompt was still
  inferred every turn. prompt_gauge.py now prints ROUTE with the
  matching WORKFLOWS.md entries and tools (route_index.py: the lesson
  matcher over headings, WHEN lines and Search keys; a workflow needs 3
  points, a tool 2, two of each at most). No ledger: a route is a
  pointer, the tool it names keeps the ledger. First eleven real prompts:
  six routed right, five silent, none wrong.
- 2026-09-28 WS1 (later still): THE CHECKPOINT NAMED CHECK (kit v1.34).
  The route line batch's reply closed "a checkpoint and clear is the
  natural next step whenever you want to stop"; the CEO: "If this is the
  case, you should have just done a checkpoint. Any reference to a
  checkpoint from any valid source should prompt you to do it" (C0004).
  C0002 made an advised checkpoint a step, C0003 made every hook line an
  order; this closes the source: the manager's own reply counts.
  stop_tick.py reads the reply text since the last typed prompt (the
  lesson loop's transcript reader) and refuses once per prompt when it
  names a checkpoint as due without the marker; stop_hook_active keeps
  it from looping; five selftest cases carry the incident sentence.
- 2026-09-29 WS1: THE PROPOSAL NAMED CHECK (kit v1.35). The first reply
  after /clear relayed the digest's four PROPOSE lines and asked what
  to work on; the CEO: "If an audit is required, and it can be done with
  a sub-agent, or a script, it doesn't need my permission. Just do it.
  If the standup digest requires a trim, it doesn't need my permission.
  Do it." (C0005, the fourth relay of the week: C0002 a hook's ADVISED,
  C0003 a hook's warning, C0004 the manager's own sentence, C0005 a
  standup proposal - one law, a line that names work is an order).
  ledger_trends.py tags every proposal [DO] / [ASK]; session_start.py's
  preamble says the DO lines are the first reply's work; stop_tick.py
  refuses once per prompt when the reply names a [DO] proposal its
  ledger still raises; six selftest cases carry the incident reply.
```

### `INTENT_METHOD.md`

- Source: `INTENT_METHOD.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 16621
- SHA-256: `02b3cac02a88353449ff301615d8f785c61b2caab2f09f92627c8d124707ee5e`

```text
# The Intent Method (portable: the intent discipline, for any project)

PURPOSE: The intent discipline: one project file, INTENT.md, holds one
  section per ruling with the owner's verbatim ASKED and WHY, the manager's
  GENERALIZES TO reading, and a LIVES IN pointer, plus a comparison ledger,
  correction ritual, and periodic report measuring whether Claude's reading
  of the owner's intent is converging on it.
INTENT: The owner's example: "It's not as important that you know to make
  looping scripts because you were told to, it's almost more important that
  you understand we make looping scripts because 1.) It decreases your token
  usage, 2.) It's done the same every time and very structured, 3.) It's
  something that triggers without asking."

PORTABLE FILE: an architecture, not a project. Hand it to any Claude (or any
capable agent) at the start of any project alongside its siblings
(WIKI_METHOD.md, SUBAGENT_METHOD.md, REPORTING_METHOD.md, WORKFLOW_METHOD.md)
and say "set this up". Nothing here assumes a game, a language, a team size,
or which model manages - never assume today's manager is tomorrow's; this
file speaks of "the manager" and "the owner" throughout, not any one name.

THE PROBLEM IT KILLS: a Claude that follows rules without knowing their WHY
re-derives the reasoning every time a new case doesn't quite match the old
one, and re-asks questions the owner already answered once. Ledgers
(REPORTING_METHOD.md) remember RESULTS; the registry (WORKFLOW_METHOD.md)
remembers ORDER; nothing remembered REASONS. This file is for the reasons,
and for measuring - honestly, with real data - whether Claude's reading of
what the owner wants is actually converging on it.

Search keys: intent, why, reasons, rationale, purpose, what did the owner
mean, agreement rate, correction ritual, feedback loop.
See also: INTENT.md (a project's instance - read it for the format);
tools/intent_log.py, tools/intent_report.py, tools/correction_log.py,
tools/systems_audit.py; REPORTING_METHOD.md (the ledger rules this method
reuses); SUBAGENT_METHOD.md (who states an intent and when); WORKFLOW_METHOD.md
(the registry that names where a rule lives).

## Why intent: knowing the reason beats knowing the rule
Tags: intent, design | Understanding why a rule exists lets Claude apply its reasoning to a new case; knowing only that a rule exists does not

The method exists because of one example the owner gave when asking for it:
"It's not as important that you know to make looping scripts because you
were told to, it's almost more important that you understand we make
looping scripts because 1.) It decreases your token usage, 2.) It's done
the same every time and very structured, 3.) It's something that triggers
without asking." A Claude that only knows THAT scripts get looped will
follow the letter of the rule and miss a new case that the same three
reasons plainly cover. A Claude that knows WHY can extend the rule itself,
correctly, without asking. That is the entire bet of this method: capture
reasons once, in the owner's own words, and every future reader - manager,
employee, or auditor - inherits the judgment, not just the instruction.

## The intent file: one project file, one section per ruling
Tags: intent, architecture | INTENT.md holds one section per ruling with fixed fields; it grows incrementally and a missing section is the question to ask

Each project keeps ONE file, INTENT.md, at its root. It holds one section
per ruling - a decision, a law, a standing instruction - and nothing else.
Each section carries four fields, in this order:

- ASKED: the owner's prompt, verbatim. Never paraphrased - the whole point
  of the file is the owner's actual words, not a manager's summary of them.
- WHY: the owner's reasons, verbatim where the owner numbered them. If the
  owner gave three numbered reasons, the section holds exactly those three,
  numbered the same way.
- GENERALIZES TO: the manager's own reading of what the reasons reach
  beyond the specific case that raised them, explicitly marked as the
  manager's reading (never blended with the owner's words above it).
- LIVES IN: the law, script, or file that actually carries the rule day to
  day - a pointer, not a duplicate, so the rule has one true home and
  INTENT.md carries only its reason.

The file follows the same wiki conventions as everything else (WIKI_METHOD.md):
searchable `## ` headings naming what a search would look for, a `Tags:`
line on hard-won sections, and `See also:` cross-references so a hop needs
no search. It GROWS INCREMENTALLY - a ruling's intent is captured the day
the ruling is made, or the day a correction reveals it - never a backfill
sweep of old decisions nobody asked to revisit. A brief for a delegated
task pastes the relevant section straight in, so an employee starts with
the reason already in hand. And the reverse holds too: a section that
DOES NOT EXIST YET, when a question like "what did the owner mean by this?"
fires, is itself the signal to stop guessing and ask the owner - the answer
then gets filed the same batch.

## The comparison ledger: claim, then verdict
Tags: intent, process | A claim records the manager's reading before building; a verdict records the owner's truth when it's known, naming its source so self-judged agreement never inflates the rate

Before building anything nontrivial, the manager logs its OWN reading of
the ask as a CLAIM (`tools/intent_log.py --claim --actor <name> --task
"<3-8 words>" --mine "<the reading>"`) - written down before the work,
so it can't be quietly rewritten after the fact to match what shipped.
An employee does the same in miniature: it states its own reading in its
delegation stamp as an `INTENT:` line, and the manager logs that claim
with the employee's model as the actor, never folding it into its own.

When the owner's actual intent becomes known - stated outright, revealed
by a correction, or judged by the manager from how the work landed - the
claim RESOLVES with a verdict:

- SAME: the reading matched; nothing was rebuilt or adjusted.
- SIMILAR: matched in substance; a detail differed and was adjusted
  without a rebuild.
- DIFFERENT: a correction or rebuild was needed.

Every resolution also names its SOURCE: `stated` (the owner said so
directly), `correction` (a `/correct` ritual revealed it), or `inferred`
(the manager judged it with no explicit words). Inferred verdicts are
counted separately in every report, on purpose - a Claude grading its own
homework must never be allowed to quietly inflate its own agreement rate.
The log (`docs/history/intent_log.txt`) is append-only: a resolve appends
a RESOLVED line that supersedes the claim's PENDING state, and the newest
line for a given id is the one that counts. Nothing is ever edited in place.

## The correction ritual: a fix plus the reason it was needed
Tags: intent, lessons | A correction records the owner's words verbatim, resolves the matching claim DIFFERENT by itself, then asks for the intent while the mismatch is still fresh

The owner described the ritual this way: "Lets pretend I ask you to do
something. You build it, and it's wrong. I send you a correction skill.
You then inquire: What about the last thing I did needs correcting? The
user explains. You mark that down and prepare to fix the thing that needs
correcting, then you would ask 'What was the intent?' firing off the intent
immediately after. These two create a feedback loop."

Mechanically: the `/correct` skill asks "What about the last thing I did
needs correcting?", records the answer verbatim with `tools/correction_log.py
--record` (never paraphrased - the owner's exact words are the evidence).
If the correction names the intent claim it falsifies, that call alone
resolves the claim DIFFERENT with source `correction` - the hardest
evidence the comparison ledger ever gets, and it is never left to be
remembered separately. Then, while the mismatch is still fresh, the
`/intent` skill asks "What was the intent?" and files the answer into
INTENT.md as a new or amended section. Only after both of those does the
fix ship, closed out with `tools/correction_log.py --fixed`. A correction
is never JUST a fix - it is evidence about a misread intent, logged before
the fix is allowed to erase the trail.

## The report: real data, on a cadence, from a script
Tags: intent, economy | The report exists for the same three reasons every looping script does - it is a scorecard the loop produces on its own, not a status the manager has to remember to give

The owner's reasons for wanting real numbers instead of a feeling: "we 1.)
Want to have real data, 2.) We want to compare past to present, 3.) We want
to know if we are improving, staying the same, or declining because each
one of those will tell us something about our feedback loop." And the
reasons this has to be a script, not a habit: "The Intent there is 1.) It's
the same every time, 2.) It's cheap and costs no tokens, 3.) it's
structured and we don't need to remember to call it by adding it to the
loop we already have."

`tools/intent_report.py` is that script. It reads the intent log and the
correction ledger and regenerates, whole, every run: a txt summary for
Claude and employees (all-time, the last window vs the window before, the
trend verdict, then day/week/month tables per actor), a csv for a human,
and an xlsx twin (THE SPREADSHEET RULE from REPORTING_METHOD.md - frozen
header, bold totals - skipped quietly, never fatally, when the library
isn't installed). It appends one line per run to a runs ledger so the
trend itself has history. It calls the trend IMPROVING, DECLINING, or
STEADY by comparing agreement across two windows, with a minimum-resolved
floor below which it says "n/a" rather than call a coin flip a trend. The
exact thresholds (points of movement, minimum resolved claims per window)
live in the script as constants - they are the owner's to tune, never the
manager's to loosen on its own judgment. The script runs from the same
metrics loop every other recurring report runs from, for the same reason
looping scripts exist at all: it costs no tokens, it is identical every
time, and it fires without anyone having to remember to ask for it.

## The systems audit: the loop measured, but never thought
Tags: intent, process | A ledgered, cadence-proposed audit in four read-only lanes returns proposals only; the owner decides what, if anything, changes

The owner's ask that started this: "Do we have anything in our loops that
audits our ledgers, new features, etc. and considers new options to
increase efficiency (without losing context), decrease token usage
(without losing efficiency or context), add txt data structures for
increased knowledge, etc?" The honest answer was no - every ledger measured
something, but nothing ever stepped back and asked whether the measuring
itself was still the right shape.

`tools/systems_audit.py` is that step-back, run as a handful of READ-ONLY
employees across four lanes: TOKENS (the usage sheet, big reads, the diet),
PROCESS (workflows, skills, hooks, what got done by hand instead of by
script), KNOWLEDGE (the wiki, the ledgers, what a new data structure would
capture), and FEATURES (what shipped since the last audit, and whether any
of it should have been a script, a hook, a data file, or a cheaper model).
Every lane returns PROPOSALS only - nothing is applied by the audit itself,
ever; the owner decides what, if anything, changes. A finished audit is
ledgered (`--record`), and a trend-watching script proposes the NEXT audit
once enough day files or enough elapsed time has piled up since the last
one - the audit is on a cadence, not a whim, but the cadence only proposes,
it never fires the audit unasked.

## The loop law: a repeatable script is called by the loop, never by hand
Tags: intent, process, lessons | The first systems audit's headline: ledgers drift when the parent loop is bypassed; the fix is wiring, not discipline

The first audit (the night of 2026-09-13, ledgered 2026-09-14 00:02)
found the scorecard ledger silent for ten
days while its siblings in the same run_all group ran by hand, one probe
group run once as a baseline and never again, and four check scripts
appending identical rows minutes apart because two callers ran them. The
owner's ruling, verbatim: "Any script that should be run multiple times
must be called by the main looping script; every action, every standup,
something like this. If it requires a hook or re-write of scripts to
accommodate, have the appropriate manager/employee do it."

What that builds, portably: the parent loop ledgers every group it runs
(loop_runs.txt); the session-start hook runs the session group once a
day before the digest and measures the digest it injects; standup shows
each group's age; the trend script proposes when a group goes stale; the
build script runs the probes. A ledger that stops advancing is a wiring
bug. Identical results at an unchanged tree are not re-appended (the
trust-the-ledger helper) so the loop can call a check twice without
lying in the ledger.
See also: REPORTING_METHOD.md (the script and ledger rules);
WORKFLOW_METHOD.md; HOOKS_METHOD.md (the session-start hook).

## Security first, then cost, then efficiency
Tags: intent, design | The order of goods when a proposal trades one for another

The audit proposed moving tunable numbers out of code into a committed
data file, as the fan-out guard's limits already are. The owner's answer:
"We care about Security first, then cost and efficiency." So the rule:
a number behind a REFUSAL (a guard's threshold) stays in code, where a
data-file edit cannot silently disarm it; a number behind a PROPOSAL
(the trend thresholds) may live in a data file the owner tunes. The
fan-out guard is the ruled exception, its numbers the owner's by name.
See also: HOOKS_METHOD.md (guards vs warnings); "The systems audit"
above.

## The laws
Tags: intent, process, lessons | The discipline in seven short rules, none of them optional and none of them automatic

1. A claim is logged before building, not reconstructed afterward to match
   what shipped.
2. A verdict is recorded the moment truth is known, and it always names
   its source - stated, correction, or inferred - so a self-graded verdict
   never passes as owner-confirmed agreement.
3. A correction is evidence, never just a fix: it is recorded verbatim
   before the fix ships, and it resolves its claim by itself.
4. The report is a script living in the loop the project already runs -
   never a status a manager has to remember to compile by hand.
5. Nothing is ever applied by a script in this method. The systems audit
   proposes; the owner decides.
6. Growth is incremental. A ruling's intent is captured the day it is
   made, or the day a correction reveals it - never a backfill sweep.
7. A missing INTENT.md section is not a gap to route around; it is the
   question to ask the owner, on the spot.

## Bootstrap steps for a new project

1. Create INTENT.md the day the first ruling worth remembering is made -
   header (this file's purpose, the wiki-lookup convention) plus that
   first section, in the four-field format above.
2. Copy the four reference scripts (intent_log.py, intent_report.py,
   correction_log.py, systems_audit.py) and adapt their paths and any
   project-specific ledger locations; keep their docstrings as the
   canonical spec of the log format and the verdict definitions.
3. Add `intent_report.py` to the project's recurring metrics loop, and
   carry its three trend rules (a minimum-resolved floor, a two-window
   comparison, IMPROVING/STEADY/DECLINING) as tunable constants the owner
   can move, not the manager.
4. Add the `/intent` and `/correct` skills so the correction ritual runs
   the same way every time: what needs correcting, record, what was the
   intent, file it, fix, mark fixed.
5. Add the employee INTENT stamp line to the project's delegation rules
   (its SUBAGENT_METHOD.md instance) so every brief states a reading
   before it builds, the same as the manager does.
6. Add one index line for INTENT.md and one for this file to the
   project's core file, alongside the other portable-method index lines.

Search keys: intent method, intent discipline, why behind a rule, claim
and verdict, correction ritual, agreement rate, systems audit, feedback
loop.
See also: INTENT.md (a live instance of this method, read it for the exact
format); tools/intent_log.py; tools/intent_report.py; tools/correction_log.py;
tools/systems_audit.py; REPORTING_METHOD.md; SUBAGENT_METHOD.md;
WORKFLOW_METHOD.md.
```

### `LESSONS.md`

- Source: `LESSONS.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 101714
- SHA-256: `777e731eed743eb94e09c994b45125aa3803144e5caa816a3df4c065a807cc17`

```text
# LESSONS - the one-right-way book (judgment, not steps)

PURPOSE: One entry per task shape: THE ONE RIGHT WAY first, then what was
  tried, why it failed and what to do instead, then nuance headlines as they
  accumulate, so a future session does the correct thing first instead of
  repeating trial and error.
INTENT: Mazhron 2026-09-20: "so in the future you don't make the same
  mistakes and just do the one correct way first? Then, if that fails, add
  nuanced headlines to that to describe what you did to avoid similar
  pitfalls again and adapt what works for A to work for B" and "we want
  something to push you to write what you learned, as well as push you to
  add to the knowledge base, create new txt files, add to current ones ...
  we want to prevent re-inventing the wheel".

THE LESSON LAW (Mazhron 2026-09-20). WORKFLOWS.md is the steps; this file
is the judgment. Before any task, `Grep "^## " LESSONS.md` the way
WORKFLOWS.md is grepped, and read the entry whose shape matches (the
prompt hook names matching entries by itself when a prompt's words hit an
entry's Keys line). When the Stop hook says LESSON ADVISED, ADVISED MEANS
DO IT: before that turn ends, write or amend the entry for the task shape,
or put the fact in its topic file under a Tags line, or say in one line
why there is no lesson. A lesson is written the moment it is learned, in
the same batch, never in a later pass. Nothing here is deleted: a lesson
that stops being true is marked SUPERSEDED with the date and the reason.

ENTRY SHAPE (each `## ` heading is the task shape, in the words a prompt
would use):
- `Tags: lessons, <area> | <brief>` so KNOWLEDGE_INDEX.md lists it.
- `Keys: a, b c, d` - the terms the prompt hook matches against a prompt
  (a multi-word key hits only when all its words appear).
- THE ONE RIGHT WAY: the thing to do first, one to three lines.
- TRIED / FAILED BECAUSE / DO INSTEAD bullets, one per pitfall, dated.
- NUANCE lines ("when A differs from B") as they accumulate.
- See also: the topic file that holds the detail (one home per fact; the
  lesson is the judgment, the detail stays where it lives).

Lint + ledger: `python tools/lesson_log.py --check` (run_all check group;
docs/history/lesson_runs.txt); `--match "<prompt>"` shows what the prompt
hook would say; `--scan` shows the signals the Stop hook saw.

Search keys: lessons, the one right way, tried failed do instead, pitfalls,
lesson advised, trial and error, knowledge capture, judgment not steps.
See also: WORKFLOWS.md (the steps); docs/index/laws.md "The lesson law";
tools/lesson_log.py; tools/hooks/lesson_advisor.py (the Stop twin);
tools/hooks/prompt_gauge.py (the match line); KNOWLEDGE_INDEX.md.

## Brief a numbers or balance task (an envelope for an employee)
Tags: lessons, delegation, balance | Read the existing spread before briefing a numbers task and stay inside it; ask for the band when there is none
Keys: brief, employee, numbers, balance, envelope, lanes, stats, spread, retune, tune, species numbers, propose values, band

THE ONE RIGHT WAY: before writing the brief, read the existing spread of
the same stat on the species (or upgrades) that already carry it, state
that band in the brief as the envelope, and tell the employee to propose
inside it. If nothing carries the stat yet, ask Mazhron for the band
first, one question, before anyone proposes a number.

- TRIED (2026-09-20, T-0920-WET-1): the manager's brief gave a wide
  envelope (lid to 0.4, anchor to 0.5) for fourteen wetland species.
  FAILED BECAUSE: lid and anchor multiply, so one mature flower cut a
  5x5's evaporation by 63 percent; the grasses and plants already laned
  sat at a tenth of that. Mazhron read the table and pulled every number
  to the grass and plants spread (intent I0048, DIFFERENT, stated).
  DO INSTEAD: the envelope is the existing spread, not a round number;
  the band goes in the brief in the same sentence as the ask.
- NUANCE: a stat that multiplies with a sibling (lid x anchor, cost x
  count) is judged by the product on one cell, not by each value alone.

See also: docs/systems/flora.md "THE LANES SPREAD"; SUBAGENTS.md (the
brief shape); INTENT.md "A new stat band starts inside the existing
spread" (I0048); WORKFLOWS.md "Delegate a task to an
employee".

## Write a guard that names forbidden verbs or calls
Tags: lessons, process | A guard that pattern-matches deletion verbs will refuse its own docstring and its own wiki row; write the prose first, then the pattern, and reword rather than route around
Keys: guard, hook, refuse, deny, forbidden, delete verbs, pattern, preserve guard, bash guard, write a hook

THE ONE RIGHT WAY: write the guard's docstring, its wiki table row and its
README paragraph BEFORE the pattern goes live, or exempt prose files
(.md .txt .rst .csv .html) from the content check in the same edit. When
the guard refuses its own author, reword the text or refine the pattern;
never bypass the guard to land the edit.

- TRIED (2026-09-10, preserve_guard.py): the deletion-call check went live
  with a docstring that named the call it bans. FAILED BECAUSE: the guard
  read its own docstring as a deletion call, twice (the docstring, then
  the tooling.md table row). DO INSTEAD: exempt prose files from content
  checks and describe the banned call in words ("the remove call"), not
  code, inside a script that the guard also reads.
- NUANCE: a PreToolUse guard fires on the settings.json edit that wires it
  (the live watcher), so pipe-test with synthesized stdin first, then
  wire, then trigger once for real.
- NUANCE (2026-09-20, session_end.py): a selftest that builds a sandbox
  repo and removes it afterwards is a script that deletes; the guard
  refused the Write. DO INSTEAD: build the sandbox with tempfile.mkdtemp,
  print its path, and leave it for the OS - a test never needs to clean
  up to be a test.

See also: docs/systems/tooling.md "The hooks"; WORKFLOWS.md "Add or
change a harness hook"; HOOKS_METHOD.md.

## Write an engine resource file (.tres, .tscn) from a script or shell
Tags: lessons, gotchas | A shell write puts a BOM or CRLF in a .tres and Godot's parser fails; write engine resources from Python with utf-8 and newline "\n", never from PowerShell redirection
Keys: tres, tscn, resource file, write species file, species files, data/species, powershell write, redirect, bom, project.godot, comments stripped, editor rewrote

THE ONE RIGHT WAY: edit or write a .tres/.tscn from Python (or the Edit
tool) with encoding utf-8 and newline "\n"; the shell guard refuses a
shell redirect into a .tres for this reason. A hand-written .tscn with a
typed node export needs the node_paths entry in its header or the export
silently stays null. Run `--import` headless after any new asset.

- NUANCE (2026-09-21, project.godot): the Godot editor rewrites
  project.godot whenever it saves settings (Mazhron playing in the
  editor is enough): every `;` comment is stripped, sections are
  reordered, and lines equal to the engine default are dropped
  (renderer/rendering_method went, then came back on restore). A
  comment there is a note that lives until the next editor save. Its
  durable home is the topic file (the FRAME LAW in GODOT_FIELD_NOTES.md,
  testing.md and ui.md; the no-physics law in lag-and-latency.md);
  project.godot carries the values. When the editor has rewritten it: `git show
  <last-good>:project.godot` with the version line carried forward,
  never a hand re-type, and commit it as its own batch so the diff
  shows only the restore. The editor keeps its in-memory copy, so a
  version bump written while it is open shows only after a restart.

See also: docs/index/gotchas.md "Gotcha: writing .tres from PowerShell",
"Gotcha: hand-written .tscn node exports"; .claude/rules/game-code.md.

## Write a long file or script through the shell (heredocs on this Windows setup)
Tags: lessons, process | A long quoted heredoc through the Bash tool dies with "unexpected EOF while looking for matching quote" past roughly a hundred lines; write files with the Write tool and put edit scripts in the scratchpad, then run them
Keys: heredoc, bash tool, write file, long script, edit script, python script, shell write, cat eof, unexpected eof, scratchpad, powershell syntax, wrong shell, exit 2, select-object, call operator

THE ONE RIGHT WAY: a new file of any length goes through the Write tool;
a multi-file edit goes into a Python script written to the scratchpad
with the Write tool and run with one Bash call (assert each replacement
count is 1 so a missed target fails loudly). A heredoc is for ten lines
or fewer.

- TRIED (2026-09-20, building the lesson loop): a 330-line script and a
  70-line edit script as `python - <<'EOF'` heredocs. FAILED BECAUSE: the
  shell reported "unexpected EOF while looking for matching quote" at
  lines 148 and 73 both times; a 118-line markdown heredoc had worked
  minutes earlier, so the cliff is size plus content, not size alone.
- NUANCE (2026-09-30, the same family the other way around): PowerShell
  syntax sent to the Bash tool (`& "exe"`, `Select-Object`) dies with
  exit 2 just as a bashism would in PowerShell; the two shell tools each
  take only their own syntax, so match the tool to the syntax BEFORE
  writing the command, and on an exit-2 with no useful output reread the
  command for the other shell's idioms first.
  DO INSTEAD: Write tool for the file, scratchpad script for the edits;
  both landed first time.
- NUANCE: the shell guard refuses shell writes into settings.json in any
  case, so a settings edit is always the Edit tool after a Read.
- NUANCE (2026-09-20 evening, a 180-line heredoc died the same way with
  "here-document delimited by end-of-file"): reading this file's INDEX
  at session start did not stop the repeat; the entry applies at the
  moment of writing. The rule is mechanical: an edit script over ten
  lines is the Write tool + scratchpad, before the first attempt, never
  as the fallback after the heredoc fails. (Python parses the whole
  script first, so the failed heredoc applied nothing - check with
  `git status` before rerunning, then rerun the scratchpad script.)
- NUANCE (2026-09-21, the line-gate road): a SHORT heredoc is not safe
  either when the text carries a backslash at a line's end (GDScript
  line continuations). The Bash tool's own layer turns the doubled
  backslash into one before Python sees it, so backslash-newline inside
  the Python string becomes a line join: the OLD text never matches
  (count 0) and a NEW text that lands writes the two lines as one, a
  silent parse error in the .gd file. The Write tool passes the script
  verbatim, so any edit whose old or new text holds a backslash goes
  through a scratchpad script, whatever its length. Add to the same
  rule: the .gd files here carry mixed CRLF and LF, so an edit script
  reads with newline="" and normalises CRLF to LF before matching
  (git stores LF; the working copy's CRs are noise).

- TRIED (2026-09-21, the C0001 doc edits): a 120-line Python edit script
  in a quoted heredoc followed by a second command on the same line whose
  arguments carried apostrophes ("it's", "Classic's"). FAILED BECAUSE:
  bash reported "unexpected EOF while looking for matching `'" and ran
  nothing, so no edit landed and the failure had to be diagnosed twice.
  DO INSTEAD: a multi-line edit script is a .py file in the scratchpad,
  written with the Write tool and run by path; commands with quoted
  prose go in their own call, never after a heredoc.
- NUANCE (2026-09-30, the README audit's four lane briefs): an EMPLOYEE
  BRIEF is never a file at all. Four ~60-line briefs went into a heredoc
  Python script meant to write them to the scratchpad, and died on an
  apostrophe inside a quoted question ("Does it check the app I build?")
  plus a stray `$VAR` on the same line. FAILED BECAUSE: the detour added
  a shell layer and a file layer to text whose only reader is the Agent
  tool's prompt field. DO INSTEAD: compose the brief in the Agent call
  itself (the shared preamble pasted into each of the four prompts);
  the scratchpad is for scripts that run, not for prose that is read
  once. Same rule for a note to the other workstation or a lesson: the
  Write or Edit tool, never a shell write.
- TRIED (2026-09-21 evening, the records script): the same 120-line
  quoted heredoc ALONE in its call, with only `echo written` after it,
  written under the auto-mode instruction to prefer Bash. FAILED
  BECAUSE: bash still reported "unexpected EOF while looking for
  matching `'" at the heredoc's last line; the body carried apostrophes
  in prose and a `%s`-formatted string, and the Bash tool's layer does
  not deliver a long quoted heredoc intact whatever follows it. DO
  INSTEAD: the auto-mode "prefer Bash" instruction does not cover this
  case; a scratchpad script is the Write tool, full stop, and the first
  attempt is the Write tool. Two identical failures a day apart is the
  proof.

See also: WORKFLOWS.md "Add or change a harness hook" (the settings.json
rule); tools/hooks/bash_guard.py (rule 5).

## Write a self-test for a shop purchase (a FAIL that was the test's own assumption)
Tags: lessons, testing | A test that buys one level compares against the level BEFORE the buy, never against 1: profiles carry meta start levels, and the same process may run another test's fixture first; GDScript maxi/mini take exactly two arguments
Keys: self-test, MEMTEST, REBIRTHTEST, level_of, meta floor, start level, buy one level, maxi, mini, too many arguments, parse error, FAIL then PASS, test assumption

THE ONE RIGHT WAY: read the level first (`var lv0 := level_of(id)`), buy,
then assert `level_of(id) == lv0 + 1`; pick the fixture line by its data
shape (gated, no requires, a biomass category), never by a name whose
start level you assume. A compound assertion that fails gets split into
named parts with one detail print before the second run, not guessed at.
maxi / mini are two-argument: nest them.

- TRIED (2026-09-21, the line-gate road): asserted the gated line ended at
  level 1 after one buy. FAILED BECAUSE: the fixture (bushes_broad_leaves)
  carries a meta start level of 3 in the test profile, so the buy landed
  on 4; every other part of the step was true. DO INSTEAD: lv0 + 1, and
  the split-and-print step the first time a compound assertion fails.
- TRIED (same batch): `maxi(a, b, 0)` in UpgradeData. FAILED BECAUSE: the
  parse error broke the whole resource script, so MEMTEST read MISSING and
  a REBIRTHTEST check that only touches UpgradeData read false, a failure
  two tests away from its cause. DO INSTEAD: `--verbose` on the first
  MISSING (the parse error is the first SCRIPT ERROR line); nest maxi.

See also: docs/systems/testing.md (the roster); WORKFLOWS.md "Run tests
or probes".

## Harden a guard against a public incident (audit a safeguard)
Tags: lessons, process | Write the incident's exact shapes as probe cases before reading the guard; a selftest only proves the shapes its author imagined
Keys: guard, hook, harden, audit, safeguard, incident, catastrophe, deletion, robust, preserve guard, prevent this, pitfall

THE ONE RIGHT WAY: take the incident apart into the literal commands and
files it used (what wrote the deleter, what ran it, what it walked, what
it touched), write each as a pipe-test case BEFORE reading the guard's
code, run them all, and only then read the guard to see why each ALLOW
happened. Fix by shape, add every probe to the selftest, and write the
guard's prose (docstring, wiki row, kit tier text) with the verbs split
or reworded so the guard never refuses its own author.

- TRIED (2026-09-20, preserve_guard): trusted the 35-check selftest as
  proof of coverage. FAILED BECAUSE: every check was a shape the author
  had imagined; the incident's shape (a remover written to Temp through
  a heredoc, run in a LATER command) sat in the one exemption the guard
  had - a cat heredoc body - and in the one thing it never looked at -
  a script file being executed. Fourteen of twenty-nine probes passed
  straight through. DO INSTEAD: probe with the incident first; the
  selftest is the floor, not the ceiling.
- TRIED (2026-09-20): scanning every script a command NAMES. FAILED
  BECAUSE: grep, cat and diff name scripts too; reading is not running.
  DO INSTEAD: scan a script only when it starts its command segment or
  a runner word (python, pwsh, bash, node, &, timeout ...) precedes it.
- TRIED (2026-09-20): scanning a tracked script whole. FAILED BECAUSE:
  three committed exporters unlink their own temp file, so every run of
  them would have needed a grant. DO INSTEAD: a tracked script is judged
  on its uncommitted ADDED lines only; an untracked one on its whole
  body.
- NUANCE: a guard that scans scripts scans ITSELF while it is modified
  and uncommitted; two-letter helper names in its selftest (the verb
  aliases) and regex sources that contain their own verbs read as
  deletion shapes. Name helpers with four letters, write verbs in
  pattern sources as r[m] / r[i] so the source never matches itself,
  and split string literals ("rm " + "-rf").
- NUANCE: a guard must never crash the turn, but "never crash" was
  implemented as "allow on exception" - fail open. A crude substring
  fallback that refuses on the obvious verbs keeps both.
- NUANCE (Windows): os.walk(followlinks=False) and os.path.islink() do
  NOT stop at a directory junction; a walker deletes through it into
  the target. No script deletes here, so the guard, not the walker, is
  the defence; a script that only walks is fine.

See also: tools/hooks/preserve_guard.py (docstring: HARDENED
2026-09-20); docs/systems/tooling.md "The hooks"; WORKFLOWS.md "Delete
something"; HOOKS_METHOD.md Tier 2d.

## Cut and wire new art from a sheet
Tags: lessons, art | Montage the slices and look at the picture before wiring a single species; some sheets interleave stages and a bad grid is only visible as an image
Keys: slice, sheet, sprite, art, cut, wire art, montage, growth stages, sprites, spritesheet, animal art, plant art, resolution, lower resolution, pixelated, blurry, art_scale, chunky

THE ONE RIGHT WAY: slice, then build one montage of every cut cell and
read it as an image, then wire. A grid cut that looks right in numbers
can interleave stages or catch a black border; the montage shows it in
one glance and the wiring is not redone. Pick the sliced mature height
FROM the on-screen size, not from one flat number: source height x
art_scale x zoom_max must not exceed the source height (nearest filter),
and the cut height should be the same multiple of art_scale as the
category it sits beside.

- TRIED (2026-09-20, the 24-flower batch): every category cut to
  TARGET_MATURE_H 72, then flowers wired at art_scale 0.75 beside
  plants at 0.5 and grass at 0.3. FAILED BECAUSE: the same 72 px were
  stretched 1.5x to 2.5x further on screen than the neighbours', past
  native at zoom 3.0, and 0.75 under a nearest filter drops one pixel
  in four (ragged petal edges) where 0.5 drops every other one cleanly;
  Mazhron saw the flowers as "lower resolution than the small plants
  and grass". Ten times the detail had been in the 800 px panels. DO
  INSTEAD: a per-category mature height in extract_gemini_sheets.py
  (FLOWER_MATURE_H 108 beside TARGET_MATURE_H 72; `--only <category>`
  re-cuts one family), art_scale set so every category lands at the
  same rendered height per source pixel, and the montage compared at
  in-game scale (resize NEAREST by art_scale, then magnify) before
  wiring. Landed 2026-09-21 as v0.99.24: flowers 108 px at 0.5, same
  screen size, montage clean, flora green, build soak PASS.
- NUANCE: 0.5 is the clean factor under the nearest filter (every other
  pixel); a category that must render bigger gets a taller CUT, never
  a bigger art_scale.
- NUANCE (2026-10-06, the re-edited Meadow Grass): a sheet can carry its
  growth order as LEFT-TO-RIGHT ACROSS BOTH ROWS (the owner laid the six
  out so x alone is the order, rows interleaved); the biggest-gap row
  split then swaps stages 2 and 3. The montage shows it as a size dip.
  DO: add the species id to X_ORDER in extract_gemini_sheets.py (sort
  the six by x only) and re-cut `--only <category>`.
- NUANCE (2026-09-26, the flair sheets): joining the PARTS of one decal
  (a flower head above its stem) is a PIXEL-distance question, never a
  bounding-box one. Merging boxes that overlap or sit near each other
  chains transitively - one dense row of a scatter sheet collapsed into
  a single 24-item mega-piece the montage caught in one glance. DO:
  dilate the alpha mask by half the join gap (MaxFilter) and label the
  DILATED mask, then crop each ORIGINAL component group; the gap that
  joins a stem (8 px) never reaches the neighbouring tuft (30+ px).
- NUANCE (2026-09-25, the wood planks): read the montage for the FILL
  art as hard as for the sprites. The Cherry and Dark Oak plank tiles
  showed a thin white stripe at their edges in the montage; wired as
  they were, drawn dimmed under a window, the stripe was a grey band
  beside the frame that Mazhron had to point at. A generated background
  can carry a white margin: tools/cut_ui_borders.py now trims it
  (trim_white) - a stripe in a montage is never "just the tile edge".
- NUANCE (2026-09-29, the nineteen bushes): a new sheet family breaks
  the slicer in ways only the montage and the blob list show, three in
  one batch. TRIED: the existing reading-order pass. FAILED BECAUSE: (1)
  rows by CENTROID misplace a tall mature plant set beside two stacked
  stages (its centre sits between their rows); (2) the grey-junk filter
  meant for grid lines dropped Brittlebush's silver sprout ("only 6
  blobs"); (3) choosing the N largest blobs BEFORE joining parts let half
  of Scarlet Quince's two-piece twig outrank the sprout, and the sprout,
  now a "fragment", welded onto a later stage (taller than the mature).
  DO INSTEAD: rows by BASELINE (bottom edge); join a plant's parts by
  pixel distance (MaxFilter) FIRST and only then pick the N plants;
  strip thin border rules before dilating; fragments to the nearest BOX;
  and SWEEP the join size across every sheet (5..11 all clean, 13 welded
  two Buttonbush panels) and take the middle. When a count fails, dump
  the blob list (area + bbox) before touching a threshold: it names the
  cause in one read. Landed as panels_from_sheet's baseline_gap mode.
- NUANCE (2026-10-02, the twenty-five trees): the join size is a per-FAMILY
  number, not a slicer constant. The bushes' 9 welded two tree crowns
  that touch (American Beech, Umbrella Thorn Acacia: "only 5 blobs");
  the sweep on just those two sheets took seconds (crop to the opaque
  bbox first) and 1..5 cut them, 7 welded. DO: sweep the new family's
  worst sheet before touching the shared constant; give the family its
  own join (TREE_JOIN_PX). A species drawn across TWO sheets (the
  Redwood) has no shared pixel scale between them: scale the earlier
  sheet from the later one's first stage (TREE_SPLIT_RATIO), never from
  its own mature. And read docs/species_edits.json's mtime before an
  art batch: Mazhron had banked the eighteen new trees the evening
  before, three under ids that did not match the sheet names.

See also: ART_METHOD.md; docs/systems/art-pipeline.md "Gemini growth
sheets"; WORKFLOWS.md "Cut and wire new creature or plant art".

## Apply an audit's findings with a batch edit script (anchors quoted from a report)
Tags: lessons, process | An employee quotes a README sentence on one line but the file wraps it; grep every anchor before the script runs and make each replacement skip itself when its new text is already present, so a mid-way failure resumes instead of forcing a split
Keys: batch edit, edit script, anchor, assert count, wrapped line, audit findings, apply findings, readme audit, rep(), resumable, idempotent, backslash, line continuation, multi-line anchor, heredoc assert, one file per script

THE ONE RIGHT WAY: before writing the edit script, `grep -n` every anchor
in the target file as it is wrapped on disk (an employee's quote joins
lines); write the replacement helper so a call whose NEW text is already
present is skipped, not asserted; then a failed assert halfway costs one
rerun of the same script, not a hand-split second script.

- TRIED (2026-09-20, the second README audit): forty replacements in one
  scratchpad script, each asserting its anchor count. FAILED BECAUSE: one
  anchor ("No hook has state that survives being unwired.") was quoted by
  the employee on one line and wrapped across two in the README; the
  assert stopped the script with half the edits applied, and the same
  script could not rerun because the applied anchors now counted zero.
  DO INSTEAD: grep the anchors first; skip-if-done in the helper.
- NUANCE (the same evening, session_end.py): a live pipe-test of a hook
  that ACTS on unbanked work fires for real - the kit sync had restamped
  FLAGS.md after the commit, so the "clear" test made an auto commit.
  Pipe-test such a hook last, after every companion script has run and
  `git status` outside docs/history/ is empty, or feed it a sandbox root.
- NUANCE (2026-09-28, the WOODTEST `travel` check): a multi-line anchor
  that contains a GDScript line continuation (`\` at the end of a line)
  failed its assert through the Bash heredoc even though the file matched
  by eye, and the FIRST two files in the same script were already written
  when it stopped. DO INSTEAD: one short single-line anchor per
  replacement (`var all_ok := tooltip_ok and drops_ok and`, `drops=%s)"`,
  `drops_ok])`), never a block with a backslash in it; and one file per
  script run, so a stop leaves nothing half-applied. Also: a grep across
  several files prints the FILE before its hits - `@export var pause_menu`
  was run_controller.gd's, not main.gd's, so the check reaches it as
  `$RunController.pause_menu`.
- NUANCE (2026-09-30, the fourth README audit, 22 replacements): the
  anchors were composed from `sed -n` output read minutes earlier, not
  grepped, and the script stopped twice before landing: once on an
  anchor that began at a line's start ("  fix a forbidden") where the
  file's line began mid-sentence ("  section, fix a forbidden"), once on
  a numbered-list continuation indented THREE spaces where the bullets
  above it use two. Nothing was half-applied (the write is per file,
  after its edits), so the cost was two reruns, not a split. DO INSTEAD:
  the script gets a `--check` pass that prints every anchor's count and
  writes nothing, run first and always; and an anchor starts at a word
  that begins its line in the file, or mid-line with no leading spaces,
  never at a guessed indentation.

- TRIED (2026-10-06, the fifth README audit): a new README bullet said
  "merge the settings template" 350 lines ABOVE the box row that says
  "drop into `tools/hooks/`", and the parity lint's must-not regex
  `settings template.*into `tools/hooks/`` (written for one sentence)
  matched across the whole file; lint FAIL, selftest FAIL, one reword
  later PASS. FAILED BECAUSE: a CLAIMS regex with `.*` is a file-wide
  order test, not a sentence test, so any new phrase that puts the left
  half before an old right half trips it. DO INSTEAD: run the parity lint
  right after the batch, before the version bump or the graft entry, and
  when a claim regex fails on text you never wrote, reword the NEW phrase
  (here `settings.json` for "settings template") rather than the old
  sentence or the regex.

See also: LESSONS.md "Write a long file or script through the shell";
WORKFLOWS.md "Audit the public README (Rootstock)" and "Add or change a
harness hook"; tools/hooks/session_end.py.

## Read a failing probe or a frame-cost spike (a soak, a ledger FAIL, "transient spikes")
Tags: lessons, testing | A ledger's FAIL with the final figure at baseline is not "transient" until the per-sample series is seen; run the probe short with the machine idle, make it NAME the eater, and fix the eater - never loosen the check to pass it
Keys: soak, soak fail, spike, spikes, transient, window cost, frame cost, probe fail, ledger fail, culprit, slow window, performance, perf

THE ONE RIGHT WAY: a probe that fails on cost is rerun SHORT (2 min)
with nothing else running, and its output must name the system that ate
the time (SpikeTracer's probe ledger; every system reports cost()). Read
the per-sample series, not the ledger's final figure. Fix the named
eater; leave the rule that caught it alone.

- TRIED (2026-09-20, three builds of soak FAILs): read the ledger tails -
  "1, 3, 2 violations, final window at baseline" - and called it
  transient spikes three times, with "one more build's eye" as the plan
  and "flag sustained degradation only" as the proposed fix. FAILED
  BECAUSE: the ledger line carries only the LAST window and a count; the
  violations were a plateau (windows at 4x for 3-6 samples in a row)
  that had drained by the run's end, and the proposed rule change would
  have hidden a real 10 ms/frame cost in play. DO INSTEAD: the culprit
  line (testing.md) - a slow window prints its three biggest eaters;
  the first run with it named water_tiles in every slow window and the
  fix took one @export (perf.md "The water redraw cadence").
- NUANCE: a heartbeat every 20 samples hides a 3-sample plateau; the
  heartbeat now carries winmax= (the slowest of its 20) for exactly this.
- NUANCE: the eater need not be in the sim - here it was a CanvasItem
  _draw that no tick owned, invisible until it reported cost() itself.
  A system missing from the culprit line is the first suspect when the
  named ones do not add up to the window.
- NUANCE (2026-09-21, the .25 build soak): a FAIL whose EVERY window sits
  at ~4x with a tiny board (plants 5, window 2012 ms, clouds the eater)
  while `tasklist | grep -i godot` shows the editor open is the machine,
  not the build: Mazhron's editor instance shares the GPU. Two idle
  reruns at the same version read the old baseline (473 / 498 ms). The
  tell is the shape: a real eater plateaus in some windows; contention
  lifts all of them. Rerun idle before reading anything else.
- NUANCE (2026-10-02, the .51 build soak): the same reading holds when
  only the LAST windows fail (22 violations, all inside a Hurricane
  wipeout at 4.2 min, every earlier window at the 340-500 ms baseline)
  and the sharer is not Godot: `tasklist | grep -i "godot\|gimp"` showed
  GIMP at 923 MB with the 200 MB tree palette open. The idle rerun
  passed at 380 ms. Widen the tasklist to whatever Mazhron edits art
  with; the hurricane's clouds are the costliest window the game has and
  the first to show a shared GPU.

See also: docs/systems/testing.md "The long-soak stability probe";
docs/systems/perf.md "The water redraw cadence"; tools/soak_report.py;
scripts/core/spike_tracer.gd.

---
## Give a system a second face the player can switch back to (keep the old system as an option)
Tags: lessons, design | A second presentation of the same progression is a VIEW over the one data set, never a generated copy; then the switch is free, the save needs no mapping, and a retune of the original moves both faces
Keys: second system, switch back, keep the current, option to swap, new system, two systems, classic, alternate shop, alternate mode, view not copy, memories

THE ONE RIGHT WAY: when Mazhron wants the current system kept as an
option beside a new one built "on the same concepts", find the one
statement of the data both must share (the upgrade levels, the cost
curve) and build the new face as functions over it: new fields on the
same resource for what the new face adds, a Settings switch that only
changes presentation and gates, and per-run state kept beside the shared
save. Never generate a second data folder from the first.

- TRIED (2026-09-21, the Memories shop): the first plan was a generator
  writing chain .tres files into a second folder chosen by the setting.
  FAILED BECAUSE: Mazhron's aside ("if I change the costs of the original
  upgrade in the chain, the others should adjust") cannot hold for
  copies, the save would need a level mapping at every switch, and two
  folders drift. DO INSTEAD: chains as a view over one UpgradeData
  (chain_of(level), the same cost_at), three fields on the resource, the
  gates in UpgradeManager reading Settings, Classic answering "usable"
  for every chain so the old shop is byte for byte the old shop. Three of
  Mazhron's questions (curve continuity, level equivalence, seamless
  switch) answered themselves.
- NUANCE: a rule priced off one example (10,000 for a 127-vitality
  chain) must be checked across the whole table before baking: the
  linear 80x gave a 3.7 billion price on the dearest line; a sub-linear
  power (264 x total^0.75) kept the example and the median sane. Print
  the min / median / max before writing a single .tres.

See also: docs/systems/meta.md "The Memories shop"; NEXT_STEPS.md
"[NS-2]"; tools/memory_chains.py; WORKFLOWS.md "Retune the Memories
chains".

---
## Add a new kind of element to a shared canvas (a second layer on a generated web page)
Tags: lessons, tooling | A canvas that several render functions share is cleared by each one's own selector list; a new element class must join EVERY clear list the same edit, and a headless probe that switches views both ways is the check
Keys: shared canvas, new layer, render path, leftover elements, clear list, querySelectorAll remove, generated page, upgrade web, species web, second view, toggle view, probe both ways

THE ONE RIGHT WAY: when a generated page gains a new kind of element
(a band, a cluster, a chain box) on a canvas that other render functions
also draw on, grep every `querySelectorAll(...).forEach(e => e.remove())`
on that canvas and add the new class to each in the same edit; then the
headless probe switches INTO the new view and BACK OUT and counts the new
class after the switch back (expected 0), not only inside the new view.

- TRIED (2026-09-21, the Memories layer on the upgrade web's tree): the
  layer cleared ".tbox, .gate, .cluster, .clustertitle, .memband" for
  itself and the first probe read 44 boxes and 10 bands, all correct.
  FAILED BECAUSE: the Classic tree and View All kept their own older
  clear lists, so switching back left the ten Rebirth bands drawn under
  the Classic boxes; only the probe's "switch back and count" line saw
  it. DO INSTEAD: one grep for the clear lists before adding the class,
  and the probe's round trip as a standing line (probe_species_web.py's
  shape: the page plus a probe script in headless Chrome, out[] to the
  title).
- NUANCE: node --check proves nothing here; the bug is a missing string
  in a selector, visible only by rendering.

See also: tools/probe_species_web.py; tools/export_upgrade_web.py "THE
MEMORIES LAYER"; docs/systems/tooling.md "The Memories chain table".

---
## Some of the chips are cut off, I need the ability to scroll more to the right (a generated page's canvas clipped at the window edge)
Tags: lessons, tooling | A scroller inside a flex wrapper needs min-width:0 on the wrapper or the wrapper grows to the content and the body clips it; a probe measures geometry only after render() in the view that shows it, since a hidden element reads 0 for every offset
Keys: cut off, clipped, cannot scroll right, horizontal scroll, flex item min-width auto, overflow auto, treewrap, scrollWidth clientWidth, offsetTop 0, display none, hidden view, render vs renderTree, probe geometry, upgrade web, species web

THE ONE RIGHT WAY: when a generated page clips content at the window edge,
measure in headless Chrome first (scroller clientWidth vs scrollWidth,
the wrapper's width vs its parent's): a wrapper equal to the content and
wider than its parent is the flex min-width:auto trap, fixed by
`min-width:0` on the wrapper, never by resizing the content. Any probe
that reads offsets or scroll ranges switches views with the page's own
render() (the function that flips display), then measures, and asserts
the wrapper is no wider than its parent.

- TRIED (2026-09-21, the Memories layer's right edge): assumed the canvas
  width was short and looked for a missing +margin. FAILED BECAUSE: the
  canvas and scroller were sized right (2593 of 2593); #treewrap, a flex
  item of #main with min-width:auto, had grown to 2758px in a 764px window
  and body overflow:hidden clipped it - no scrollbar could exist. DO
  INSTEAD: measure wrapper vs parent before touching sizes; one line of
  CSS (`min-width:0`) was the whole fix.
- TRIED (same day, the probe's four new geometry lines): called
  renderTree() after the card-editor step and every reading was 0
  (treewrap 0, chain 2 moved 0). FAILED BECAUSE: the previous step had
  left state.view on cards, so the tree was display:none and hidden
  elements read 0 for offsetTop, clientWidth and scrollWidth. DO INSTEAD:
  switch with render() (it flips the display) and keep the "wrapper <=
  parent" line as a standing check so a regression reads ERR, not 0.

See also: LESSONS.md "Add a new kind of element to a shared canvas";
WORKFLOWS.md "Probe the upgrade web page after regenerating it";
tools/probe_upgrade_web.py.

---
## A ruling about the parts is not a ruling about the whole (widening a chain ruling to the line gate)
Tags: lessons, design, intent | When a ruling names the parts of a thing (the chains), do not extend it to the thing itself (the line's gate) without asking; state the widening as an assumption in the reply and let the owner rule
Keys: widen a ruling, generalize a ruling, the parts and the whole, chain ruling, line gate, over-read, contradiction rule, memories gate, from the start, rebirth gate

THE ONE RIGHT WAY: when a ruling is phrased about the parts ("the chain
keeps the gates of rebirths"), build exactly that and name any wider
reading as an assumption in the reply: "I read this as also covering the
line's own gate; say if not." The owner answers in a line and the build
is right the first time. If the wider reading changes what a player sees
(a line moving from "from the start" to a gate line), it is a ruling of
its own and waits for a yes under THE CONTRADICTION RULE.

- TRIED (2026-09-21, v0.99.31): read "the chain keeps the gates of
  rebirths (permanent) OR the memory unlock" as covering the LINE's
  requires_rebirths too, and put chain 1 of every gated line behind its
  Classic gate under Memories. FAILED BECAUSE: the ruling was about the
  chains; the line gate is the price of taking the line whole, and a
  split line is not taken whole. Tilling Grasp jumped from "from the
  start" to the 10-rebirth band and Mazhron caught it in the web the same
  afternoon (correction C0001). DO INSTEAD: keep the ruling's scope, and
  where a line is ONE chain (a tool, a Will) it IS the whole, so the
  chain ruling and the line gate coincide there without any widening.

See also: INTENT.md "The split line starts from the beginning";
docs/systems/meta.md "The Memories shop" (THE SPLIT LINE paragraph);
LESSONS.md "Give a system a second face"; docs/index/laws.md "The
contradiction rule".

## Read the screenshot against the data before asking the owner to export (an arrow's target)
Tags: lessons, tooling, web | When a screenshot shows a number the data seems to lack, find which link on disk carries that number before calling it a browser-only edit; a labelled arrow's target is easy to misread in a crowded layer
Keys: screenshot, arrow, export, browser edit, browser-only edit, requires_levels, link label, upgrade web, misread, prerequisite, threshold

THE ONE RIGHT WAY: when the owner's screenshot shows a value the data
"does not have", grep the data for that value first (requires_levels,
thresholds, gates) and name the link that carries it; only when nothing
on disk carries it ask for an export. Say which link you read the arrow
as, so the owner can correct the reading in a line.

- TRIED (2026-09-21, v0.99.31 to .32): read the ">=10" arrow leaving
  Stronger Pulse in the web's Memories layer as the Tilling Grasp link,
  found no threshold on that link, and asked Mazhron at two checkpoints
  to export a browser edit. FAILED BECAUSE: the ">=10" was the Auto
  Click link (click_auto requires_levels = [10], on disk since the gating
  build); the Tilling Grasp link has no threshold on purpose, it opens
  once Stronger Pulse has any level. The owner spent a turn explaining
  data that was already right. DO INSTEAD: `grep -rn "requires_levels"
  data/upgrades/` before the reply; when the value exists on disk, the
  arrow is that link.

See also: docs/systems/tooling.md "The Memories chain table";
WORKFLOWS.md "Probe the upgrade web page after regenerating it";
LESSONS.md "A ruling about the parts is not a ruling about the whole".

## Pull when both machines appended the same generated ledgers (a merge under the preservation law)
Tags: lessons, process, gotchas | Commit the local hook-written ledgers BEFORE pulling, and resolve a generated-file conflict by writing theirs and re-running the generator - never `git checkout --theirs` (the preserve guard refuses the discard verb, and rightly: the write path loses nothing)
Keys: pull, merge conflict, usage ledgers, checkpoint_state, generated files, checkout --theirs, preserve guard refusal, keep_other_ws, regenerate, cross-workstation sync, xlsx binary conflict

THE ONE RIGHT WAY: (1) commit the locally modified hook ledgers first (the
pull aborts on them otherwise), then `git pull --no-rebase`. (2)
checkpoint_state.txt resolves by hand: each WS keeps its own newest line.
(3) Every generated usage file (usage_daily/metrics/employees + the xlsx)
resolves by WRITING the remote side (`git show <merge-head>:<path> >
<path>`, binary-safe from Bash) and then `python tools/usage_report.py` -
the generator rebuilds this machine's rows from its own transcripts and
`keep_other_ws` preserves the other's, so the merged files are correct by
construction. Both pre-merge sides live in git history; nothing is lost.

- TRIED (2026-09-22, the eleven-day catch-up pull): `git checkout
  --theirs <ledgers>` to take WS1's side. FAILED BECAUSE: the preserve
  guard refuses checkout-of-a-path as a discard verb, and a hand-union
  would have duplicated WS1's rows once the generator re-read them.
  DO INSTEAD: the write-then-regenerate path above - it is not a
  workaround of the guard, it is the shape the guard wants: a write that
  discards nothing, then the sanctioned script.
- NUANCE (2026-09-25, the wood-UI pull): three file classes resolve
  differently. APPEND-ONLY ledgers (*_runs.txt, days_index, digest_size)
  union-merge: keep ours then theirs inside each conflict hunk, markers
  dropped - a small Python pass over the markers does 27 files at once.
  GENERATED reports (usage_* + xlsx, wiki_view.html) take theirs or ours
  and let the next loop regenerate. STATE files rewritten in place
  (ledger_heads, checkpoint_state) keep one line per key, newest wins.
  For binary or single-side files, `git show :2:<path>` (ours) /
  `:3:<path>` (theirs) written from Python is the guard-compliant read -
  byte-safe where a PowerShell redirect corrupts and checkout is refused.

See also: WORKFLOWS.md "Leave a note for the other workstation";
docs/index/laws.md (the preservation law); tools/usage_report.py
(keep_other_ws).

## Leave the cross-workstation note the moment the need is spoken (never wait to be told)
Tags: lessons, process, cross-workstation | The instant the manager knows the OTHER machine must do or know something, the note goes in docs/index/notes.md in the SAME batch; telling the owner about the need without writing the note is the failure
Keys: leave a note, WS1, WS2, other workstation, relay, handoff, notes.md, proactive note, unprompted note, next tasks, courier

THE ONE RIGHT WAY: the test lives in the reply itself: any sentence
shaped "WS1 will need to...", "remember for the other machine...", "ask
the manager there to..." is a note that ALREADY EXISTS in
docs/index/notes.md before that reply is sent, committed and pushed with
the batch. The owner never couriers a message between machines and never
has to say "leave a note" - the relay is the manager's own memory across
machines, and standup reads it out on the other side.

- TRIED (2026-09-22, the memory trim): shipped the kit v1.29 batch and
  ended the reply with "ask the manager there to run the trim" - handing
  Mazhron the job of carrying the task to WS1. Mazhron had to say "leave
  a note" as a separate instruction, then ruled: "I shouldn't have to
  tell you to leave a note for WS1 ... If you know WS1 needs to do
  something, you should leave the note for yourself. If WS1 needs to
  know something, you should make the note yourself." FAILED BECAUSE:
  the manager treated the relay as the owner's channel instead of its
  own cross-machine memory. DO INSTEAD: write the note in the same batch
  that created the need; the reply then says "noted for WS1" instead of
  assigning the owner homework.

See also: docs/index/notes.md (the relay); WORKFLOWS.md "Leave a note
for the other workstation"; docs/index/laws.md (the workflow rule).

## Keep track of real time between saves (a telemetry clock that spans sessions)
Tags: lessons, telemetry, persistence | A persisted log's real-time deltas come from its own play clock, never from wall-clock stamps; the log flushes at the world save, not at the window-close notification
Keys: telemetry, real seconds, real_s, wall-clock, unix, play clock, quit, save and exit, resume, next day, several days, flush, WM_CLOSE_REQUEST, get_tree().quit, balance log, run spans sessions

THE ONE RIGHT WAY: when a log measures "real time" between events and
its baseline is persisted, the time source is a counter the log owns
and saves (ticks only while recording is enabled), never a unix stamp
in the baseline. And the log banks itself inside the same function the
world save goes through, because a menu quit calls the engine quit
directly and the window-close notification never fires.

- TRIED (2026-08-24 to 2026-09-24): BalanceLog stamped unix time into
  each segment's baseline and measured the next event from it; the
  flush hung on NOTIFICATION_WM_CLOSE_REQUEST.
  FAILED BECAUSE: a run played over several days put the whole night
  into the first event after the resume (only the day baseline was
  rebased on arrival, not the unix one), and Save & Exit quits through
  get_tree().quit(), which sends no close notification, so the last
  minute of the zone ledger was dropped. Found when Mazhron asked
  whether a run could be played across days (2026-09-24).
  DO INSTEAD: a play clock on the log (Time.get_ticks_msec deltas while
  enabled, baseline dropped when disabled, saved in the log JSON) feeds
  the real_s delta; SaveManager.save_campaign calls BalanceLog.flush()
  so every save path banks the log. Prove it with a save + reload check
  in the self-test.
- NUANCE: any other counter the deltas read must live in the world
  save (RunStats, lifetime vitality and biomass, the day clock do), or
  a reload reads it as fresh from zero.
- RULED (Q0005, Mazhron 2026-09-24): the log LIVES AND DIES WITH THE
  WORLD SAVE. Its only disk write is flush() from save_campaign; no
  per-event, timer or close-notification writes; load_log always reads
  the disk on every world load. A quit without a save then reverts the
  log to the same moment the world reverts to, and the stretch since is
  nixed. Test both halves: resume (flush, reload, next delta) and
  discard (event, no flush, reload, event gone).

See also: docs/systems/meta.md "THE PLAY CLOCK"; scripts/core/balance_log.gd;
docs/history/open_questions.txt (Q0005); WORKFLOWS.md "Track an open
question to Mazhron".

## Anything that can be pressed should wear the new frames (style every Button, or every control of one type, at once)
Tags: lessons, ui, godot | Fill the PROJECT theme at boot; a root-window theme stops at a CanvasLayer and a per-script override is one place per button forever
Keys: theme, Button, stylebox, every button, all buttons, CanvasLayer, project theme, wood_theme.tres, ThemeDB, install_theme, press feedback, pressed, hover, disabled, rebuild, in place, queue_free, canvas item, badge, footer, changing constantly, flicker

THE ONE RIGHT WAY: project.godot names an empty Theme .tres
(gui/theme/custom = assets/ui/wood_theme.tres, written with the Write
tool, never a shell redirect) and one static installer (WoodBox.
install_theme, from Settings._ready before any scene builds) fills its
Button styleboxes for normal / hover / pressed / hover_pressed / disabled
/ focus. Every Button in the game changes at once, CheckBox and the touch
keys inherit the Button type, and a control's own override (map tiles)
still wins. Press feedback is three tints and a 1 px content-margin sink
on the pressed box, not per-button code. Probe the lookup headless first
(a SceneTree script under --script: add a Button under a CanvasLayer and
compare get_theme_stylebox to the box you set) - it takes ten seconds and
settles the question before any wiring.

- TRIED (2026-09-25, the wood buttons): `get_tree().root.theme = theme`
  on the root Window. FAILED BECAUSE: theme lookup walks parent Controls
  and Windows only - it stops at a CanvasLayer - and the HUD, the badges
  and the footer all live under one, so the probe printed false; and
  ThemeDB has no set_project_theme to fall back on at runtime. DO
  INSTEAD: the empty project-theme .tres named in project.godot, filled at
  boot through ThemeDB.get_project_theme() - the probe printed true under
  the CanvasLayer, true for CheckBox, and the override still won.
- NUANCE: one shared StyleBox instance serves every button, so a Random
  wood must roll PER CONTROL (seed = the canvas item id + a generation
  counter), or hover and press would each re-roll the frame under the
  mouse.
- TRIED (2026-09-25 evening, Mazhron: "they shouldn't be changing
  constantly"): leaving the badge strips and the footer as they were -
  queue_free every Button and make new ones on the half-second poll and
  on every tool switch. FAILED BECAUSE: a re-made Button is a NEW canvas
  item, and the per-control seed IS the canvas item; the roll held per
  control exactly as designed while the controls were replaced under it,
  so the HUD wore new woods twice a second. DO INSTEAD: a HUD control that
  lives the whole run updates its Buttons IN PLACE - one Button per key,
  hidden when not shown, text/tip/icon/visibility refreshed - and only a
  window that opens and closes may rebuild, because that is the moment a
  fresh wood is wanted. WOODTEST's `held` check compares the Buttons'
  instance ids across a refresh. The general form: any "seeded by the
  node" look breaks the moment a refresh path re-creates the node.
- NUANCE (the cut, same day): a hollow frame taken apart by geometry
  measures its border as the MEDIAN opaque run across hollow rows, never
  the max (a bark nub at an inner corner read as a border half the frame
  wide) and never a fixed middle band (the bar's underside is thicker
  than its top); see art-pipeline.md "The wood UI frames".
- TRIED (2026-09-26, the dresser clicks: "the new buttons randomize
  everything every time"): detecting "this window just reopened" as
  frames-since-last-draw inside StyleBox._draw (REROLL_GAP 3): a big gap
  meant hidden, so the next draw re-rolled woods and dealt fresh flair.
  FAILED BECAUSE: retained-mode canvas items only redraw when DIRTIED -
  a visible window sitting STILL also stops drawing, so the first
  dresser click after 3 quiet frames (its own emit_changed!) read as a
  reopen and rolled the player's pick away; picking Birch randomized,
  Randomize flair re-rolled the woods too. DO INSTEAD: wire the real
  signal - WoodBox.wear(host, pad) connects the host Control's
  visibility_changed AND its enclosing CanvasLayer's (the big menus
  toggle the LAYER's visible, which a child Control's signal never
  fires for), and the draw never guesses state. The general form: "time
  since last draw" measures DIRTINESS, not visibility; never infer
  hidden/shown from it in a retained-mode renderer.
- NUANCE (2026-09-26, the offline card): "every window" means every
  PanelContainer in the GAME, not every file in scripts/ui/ - the
  while-you-were-away card is built inline in main.gd and kept its old
  StyleBoxFlat through the whole NS-30 sweep until Mazhron saw it. When
  restyling a control type, `Grep "StyleBoxFlat" scripts/` finds the
  inline stragglers the folder sweep misses; each converted window gets
  a self-test flag that its stylebox IS the new kind (OFFLINETEST's
  `card` check is the pattern).

See also: docs/systems/ui.md "The wood frames" (THE BUTTONS AND THE BAR);
docs/systems/art-pipeline.md "The wood UI frames"; WORKFLOWS.md "Cut and
wire the wood UI frames"; scripts/ui/wood_box.gd (install_theme).

## A test that clicks the screen fails headless and passes in a window (FOOTERTEST through --test, 2026-09-25)
Tags: lessons, testing, godot | A synthesized mouse click has nowhere to land without a window; the runner must know which tests are windowed-only, not the person typing the command
Keys: headless, windowed, --windowed, WINDOWED_ONLY, FOOTERTEST, parse_input_event, mouse click, synthesized click, probe FAIL, run_tests, adhoc, --test, capture, _SHOT

THE ONE RIGHT WAY: a test that drives the game through real input (a
synthesized InputEventMouseButton, a screenshot capture, a tutorial
highlight) is listed in tools/run_tests.py WINDOWED_ONLY, and the runner
drops --headless by itself for any batch that holds one; `--windowed`
forces a window for anything else. testing.md names the test as windowed
next to its command. A FAIL line that came from a headless run of a
windowed test stays in the ledger - the fix line follows it.

- TRIED (2026-09-25, after the footer refactor): `python tools/run_tests.py
  --test FOOTERTEST`, trusting that any test the runner lists can run the
  way the groups run. FAILED BECAUSE: the runner passed --headless as it
  does for every group, testing.md called the test "windowed" in prose
  only, and the click on the Upgrades button landed nowhere: "window
  open=false". Nothing in the footer was wrong. DO INSTEAD: put the
  knowledge in the runner (WINDOWED_ONLY), not in prose - the hook forbids
  setting EVERWOOD_*TEST by hand, so the runner is the only door and must
  know the shape of every test it can open.
- NUANCE: a FAIL right after a code change is not evidence against the
  change until the test has run the way it was designed to run. Read
  the FAIL text for what it actually measured (here: the window state,
  not the button) before touching the code.

See also: docs/systems/testing.md (the probes paragraph); tools/run_tests.py
(WINDOWED_ONLY); LESSONS.md "Read a failing probe or a frame-cost spike".

## An append-only tracker is read at its tail, not its first matching line (Q0005 reported open after it was ruled, 2026-09-25)
Tags: lessons, ledgers, reporting | In a ledger where "a resolution is a new line, never an edit", an id's earlier lines are history; only the LAST line for that id is its state - a diff or grep that surfaces the OPEN line proves nothing about today
Keys: open questions, Q0005, append-only, tail, RESOLVED, OPEN, tracker state, last line, diff --check, pull summary, misreport, open_questions.txt

THE ONE RIGHT WAY: before telling the owner a tracked item is waiting
on him (a question, a claim, a flag), read the tracker for EVERY line
carrying that id and report the last one's status. After a pull, the
diff shows lines in whatever order the file holds them - an added OPEN
line in a diff hunk is where the item STARTED, not where it stands.
One grep answers it: `Grep "Q0005" docs/history/open_questions.txt`,
state = the final match.

- TRIED (2026-09-25, the WS1 merge): summarized the pull for Mazhron
  and listed Q0005 as "waiting on you", quoting the OPEN line that had
  scrolled past in a `git diff --check` result. FAILED BECAUSE: the
  tracker is append-only by its own header line; WS1 had ruled and
  logged Q0005 RESOLVED the day it was raised (2026-09-24, the answer
  verbatim, the fix built and self-tested in v0.99.35) - the OPEN line
  I quoted was simply the older sibling of the RESOLVED line two rows
  down. The owner had to point out he had already answered. DO
  INSTEAD: never report an append-only ledger's state from a diff
  fragment; grep the id in the file and read the tail before naming
  anything "open" in a summary.

See also: docs/history/open_questions.txt (the header is the law);
WORKFLOWS.md "Track an open question to Mazhron"; LESSONS.md "Pull when
both machines appended the same generated ledgers".

## I don't understand what the issue is with git and rootstock (a harness block explained as if it were a repo problem, 2026-09-26)
Tags: lessons, harness, kit | When the harness's permission layer blocks a sanctioned action, say plainly "the repo is fine; I was not allowed to press the button" and hand the owner the smallest way to unblock; an explanation that mixes the git state with the permission block reads as if something broke
Keys: rootstock-os, permission classifier, blocked push, kit repo, out of scope, settings.local.json, additionalDirectories, harness block, denied, explanation, correction

THE ONE RIGHT WAY: the kit repo lives OUTSIDE the project working
directory, so on a machine without an allow rule the harness may block
git commands aimed at it. Two separate reports, never blended: (1) the
repo's own state (merged? clean? what commit waits?) and (2) the
harness block ("the command was refused by my permission layer; the
repo is healthy"). Both workstations work in both Everwood and
rootstock-os including push and pull (Mazhron's ruling 2026-09-26), so
the standing fix is an owner-added allow rule in the machine's
.claude/settings.local.json (gitignored, per-machine paths) - Claude
cannot write its own permission rules; that self-granting block is a
security boundary, so hand the owner the exact rule text or /permissions
step and stop.

- TRIED (2026-09-26): explained a blocked rootstock-os push by
  narrating the merge, the sync script's "nothing to push", and the
  classifier denial in one breath. FAILED BECAUSE: the owner could not
  tell whether git was broken, the merge had failed, or something
  needed fixing - the answer was "nothing is wrong; one push needs a
  hand". A second, two-part explanation (ordinary git, then the
  permission block) resolved it in one read. DO INSTEAD: separate "what
  the repos look like" from "what I was allowed to do", and end a
  permission report with the one action that unblocks it.

See also: WORKFLOWS.md "Edit the future-project kit (Rootstock)";
LESSONS.md "Pull when both machines appended the same generated
ledgers".

## Never set EVERWOOD_*TEST by hand, even though CLAUDE.md's verify snippet showed how (the runner is the only door, 2026-09-26)
Tags: lessons, testing, process | A doc snippet that demonstrates a pattern a guard forbids is a stale doc, not a permission; the guard's message names the one right way and the doc is fixed in the same batch
Keys: EVERWOOD_WOODTEST, EVERWOOD_*TEST, run_tests.py, --group, --list, script rule, hook block, verify snippet, CLAUDE.md Verifying changes, stale doc, env var by hand

THE ONE RIGHT WAY: tests run through `python tools/run_tests.py --group
<group>` (`--list` shows the groups) - the groups, the don't-combine laws
and the ledger append live there. The import line (`--headless --path .
--import`) is still run directly; it is not a test. When a guard blocks a
command, the block text IS the instruction - follow it, and if a doc
taught the blocked pattern, fix that doc in the same batch (the workflow
rule: a stale entry is a bug).

- TRIED (2026-09-26, verifying the flair density change): set
  `$env:EVERWOOD_WOODTEST = "1"` and launched Godot by hand, copying
  CLAUDE.md's "Verifying changes" snippet verbatim. FAILED BECAUSE: the
  script-rule hook forbids hand-set EVERWOOD_*TEST - running outside the
  runner skips the group laws and the test_runs.txt append - and the
  CLAUDE.md snippet predated the guard. DO INSTEAD: `python
  tools/run_tests.py --group ui` (WOODTEST's group) on the first try;
  the snippet in CLAUDE.md now points at the runner.

See also: docs/systems/testing.md (the full roster); WORKFLOWS.md "Run
tests or probes"; LESSONS.md "A test that clicks the screen fails
headless and passes in a window".

## Adding several safety hooks at once: the SAFETY table bites every in-between state (the delegation truth set, 2026-09-26)
Tags: lessons, hooks, kit | A guard that checks a file's WHOLE resulting state refuses any edit sequence whose intermediate states are illegal, even when the end state is what the guard wants; the counts lint reads prose numbers as claims
Keys: SAFETY table, format_guard, settings.json, safety wiring, atomic write, intermediate state, Edit refused, whole-file Write, readme_lint, count claim, three hooks, hook count

THE ONE RIGHT WAY: when a batch adds N hooks to format_lint.py's SAFETY
table, land each settings file's N wirings in ONE call - a whole-file
Write (or one Edit whose new_string carries all N entries) - because
format_guard validates the RESULTING file against the FULL table, and
after the table gains its rows, every partial wiring is a refusable
state. Order inside the batch: SAFETY rows first is fine, but from that
moment the settings edit must be atomic. And when the public README
gains prose about the new set, spell numbers that are not the total
carefully: readme_lint reads "<number> hooks" as a count claim against
the real script count ("three hooks" FAILED against truth 15; "a trio"
passed).

- TRIED (2026-09-26, wiring brief_guard + delegation_auditor +
  verify_advisor into the kit template): three sequential Edits, one
  per hook. FAILED BECAUSE: each single edit produced a file where the
  OTHER two SAFETY hooks were "not wired", and the format guard refuses
  any edit that leaves a settings file short of the full table - the
  guard judges states, not intentions. DO INSTEAD: one Write with all
  three entries; the guard passed it first try. The refusals were the
  law working (they proved the new rows enforce), never a bug to route
  around.
- NUANCE: a guard the manager writes WILL fire on the manager's own
  next steps (the preserve guard's author history says the same). Plan
  the batch so the guard lands in its final shape and the guarded files
  change atomically after it.

See also: HOOKS_METHOD.md (Tier 4a + the v1.30 change-log line);
tools/format_lint.py (SAFETY); tools/readme_lint.py (the counts);
LESSONS.md "Harden a guard against a public incident (audit a
safeguard)".

## A test-runs PROPOSE means read the ledger tail first (the FAIL may already carry its fix, 2026-09-26)
Tags: lessons, testing, process | The trends proposal counts FAIL lines in a lagging 10-line window; a fix that landed minutes after the failures still trips it at the next standup, so the ledger tail - not the proposal text - says whether anything is broken now
Keys: test_runs, PROPOSE, FAIL lines, flaky group, quarantine, ledger_trends, lagging window, tail -15, WOODTEST, fix line follows, age out

THE ONE RIGHT WAY: on a "PROPOSE (test_runs.txt): N FAIL lines in the
last 10 runs" line, `tail -15 docs/history/test_runs.txt` BEFORE hunting
a flaky group. If every FAIL is followed by a PASS of the same test at
the same or a later version, the fix already happened (the FAIL lines
stay in the ledger by law - the fix line follows them) and the proposal
is the window lagging, not a live problem. The honest close is one
legitimate run if one is owed - the group at the CURRENT version when
the version moved past the last green line - never green runs fired to
flush the window ("never re-run a green group at an unchanged version").
Only a FAIL with no following PASS is the flaky-or-broken case the
proposal's "fix or quarantine" words are for.

- TRIED (2026-09-26, standup carried "4 FAIL lines in the last 10 runs
  (adhoc)"): the tail showed all four were WOODTEST at 10:30 the prior
  day - dev-loop iterations while WOODTEST gained the layout round-trip
  flag - with 2/2 PASS at 10:31 and ui 7/7 PASS the same afternoon.
  Nothing was flaky; ui at the new version (0.99.46, a UI change) was
  the one run owed, and it passed 7/7.

See also: tools/ledger_trends.py (rule 2, test_fails threshold);
WORKFLOWS.md "Run tests or probes"; docs/systems/testing.md;
LESSONS.md "A test that clicks the screen fails headless and passes in
a window (FOOTERTEST through --test, 2026-09-25)".

## If the hook says checkpoint advised, I shouldn't have to type /checkpoint (the ADVISED line is a step in the reply, not a line to relay)
Tags: lessons, process, checkpoint | The closing check of every reply: did any hook say ADVISED this turn? Each one is work done before the reply ends
Keys: checkpoint advised, ADVISED MEANS DO IT, hook line, relay verbatim, closing check, end of reply, safe to clear, context gauge, 80% rule, C0002, C0003, kit unsynced, lesson advised, changelog unexported, hook warning, warning means do it, the hook law, repeated warning

THE ONE RIGHT WAY: before sending any reply, run the closing check: (1)
is the tree committed and pushed, (2) did a hook this turn say ADVISED -
CHECKPOINT ADVISED, LESSON ADVISED, KIT UNSYNCED - and is the arc closed?
Each ADVISED is an instruction: the checkpoint sequence (session loop,
push, WHERE WE LEFT OFF with both sides verbatim, commit, push, reset,
marker) runs INSIDE that reply, the lesson is written INSIDE that reply,
the kit is synced INSIDE that reply. Relaying the hook line verbatim is
part of the reply, never a substitute for the step. Mazhron then simply
/clears; he never types /checkpoint.

- TRIED (2026-09-28, after shipping v0.99.47): the prompt hook had said
  KIT UNSYNCED and the context gauge had crossed the 80% line; the reply
  synced the kit, reported the ship in full and ended. FAILED BECAUSE:
  the law's text ("ADVISED MEANS DO IT", laws.md since 2026-09-10) lived
  in a file, not in the reply's closing check - the ship report felt like
  the end of the work, and the checkpoint was left as something Mazhron
  would ask for. He had to ask (correction C0002). DO INSTEAD: the
  closing check above, every reply; when in doubt whether the arc is
  closed, it is - ship the step, then checkpoint. A checkpoint costs one
  commit; a missed one costs Mazhron a prompt and a rule restated.
- NUANCE: mid-arc (uncommitted work, an employee running) the checkpoint
  waits for the step to ship - but the reply says so in one line and
  names when it will run, so the advice is answered, not dropped.
- TRIED (2026-09-28 afternoon, the same day): the Stop hook printed
  CHANGELOG UNEXPORTED after three docs-only commits; the replies
  relayed the line and ended, three times, until Mazhron asked "Why am I
  told about the changelog being uncommitted? Should you not just run
  the script?" FAILED BECAUSE: the closing check above listed three
  ADVISED names and this line was a fourth; a warn-only line read as
  information. Half the warnings were also spurious: the hook counted
  the export's own commit, so every export left "1 commit" behind it.
  DO INSTEAD (correction C0003, his words: "A Warning from the hook
  means do it, not relay the message for the user to do"): the closing
  check is "did ANY hook line name work this turn?" - not a list of
  names; each one runs inside the reply (the export is one command and a
  push). A hook's wording is an order to the manager ("MANAGER: run
  ..."), never a note for him. And a warning seen twice for the same
  thing is the failure, not the warning itself.
- TRIED (2026-09-28 evening, the same day again): after the route line
  batch the reply ended "the checkpoint counter has ticked through a full
  arc tonight, so a checkpoint and clear is the natural next step
  whenever you want to stop." FAILED BECAUSE: the closing check asked
  "did a HOOK name work?" and no hook had; the manager's own sentence
  named the checkpoint as due and was treated as advice to the owner.
  DO INSTEAD (correction C0004, his words: "If this is the case, you
  should have just done a checkpoint. Any reference to a checkpoint from
  any valid source should prompt you to do it."): the closing check is
  "does ANYTHING in this turn - a hook, my own reply, the counter - name
  a checkpoint as due?" If the sentence "a checkpoint is the next step"
  is true, the checkpoint runs before the sentence is sent, and the
  reply ends with the marker instead. stop_tick.py now refuses once per
  prompt when a reply names a checkpoint as due without the marker
  (CHECKPOINT NAMED), so the sentence cannot be sent unmade.

See also: docs/index/laws.md "The checkpoint protocol" (REAFFIRMED AS A
CORE LAW, BROADENED TO EVERY HOOK LINE); CLAUDE.md "The hook law"; .claude/skills/checkpoint;
docs/history/corrections.txt (C0002); LESSONS.md "Anything that can be
pressed should wear the new frames" (the same evening's ADVISED lesson,
written on the hook's word).

## Apply a long batch of file edits from the shell (the heredoc that fails to parse, 2026-09-28 and twice 2026-09-29; the sed that eats backslashes)
Tags: lessons, tooling, harness | A Python edit script longer than about ninety lines inside a Bash heredoc fails to parse in this harness's Git Bash, and ANY edit whose text carries a backslash (a regex) loses it through sed or a heredoc; write the script to the scratchpad and run it by path, then run the file's selftest before any ledger line
Keys: heredoc, unexpected EOF, matching quote, bash parse, long script, scratchpad, edit script, batch edit, route_docs, python - <<, Write tool, run by path, backslash, sed -i, regex edit, \b, chr(92), selftest before ledger, false measure

THE ONE RIGHT WAY: a multi-file edit that needs more than a screen of
Python goes into the scratchpad as a .py file through the Write tool,
then `python <scratchpad>/<name>.py` runs it. Short heredocs (a few
dozen lines) are fine. A new tool or hook is written with the Write
tool too, never through a heredoc, because a docstring carries triple
quotes and apostrophes that a shell will parse before Python sees them.

- TRIED (2026-09-28, the route line batch): `python - <<'EOF' ... EOF`
  with a 106-line tool body, then again with a 110-line edit script.
  FAILED BECAUSE: both died with "unexpected EOF while looking for
  matching `''" at the line just past the heredoc's end; the shell never
  saw the terminator, nothing ran, and the second failure cost the whole
  batch of doc edits a rerun. Two shorter heredocs the same hour (about
  ninety lines) parsed and ran. DO INSTEAD: Write the script as a file,
  run it by path; the file is also re-runnable and readable if it asserts.
- TRIED (2026-09-29, the fifth digest trim): a ONE-line regex edit in
  tools/standup.py, first through `python - <<'EOF'` with `\\b` in the
  match string (the pattern never matched: assertion, nothing written),
  then through `sed -i '326s/.*/.../'` (the replacement landed with every
  `\b` turned into `b`; the selftest went 8 FAILED and the digest measured
  1,300 bytes short because no verdict matched). FAILED BECAUSE: the
  shell and sed each consume one layer of backslashes before Python or
  the file sees them, and a regex is nothing but backslashes. Worse,
  the ledger line was appended between the two tries, so for two
  minutes digest_size.txt carried a measurement of a broken tool. DO
  INSTEAD: length is not the test; the CONTENT is. Any edit carrying a
  backslash, a regex, a docstring or mixed quotes goes to a scratchpad
  .py file, built with chr(92) or a raw string, run by path. And the
  order is fixed: edit, selftest, THEN measure and ledger; a ledger
  line written before the selftest is a guess with a timestamp.
- TRIED (2026-09-29, the security audit batch, the third time the same
  day): a 13 KB method file with apostrophes, double quotes and
  backticks, wrapped in a Python raw string, sent through a quoted
  heredoc anyway because the session's auto-mode note prefers Bash.
  FAILED BECAUSE: the same "unexpected EOF while looking for matching
  `''" as 09-28; the shell parsed the body before Python saw it. The
  Write tool wrote the same script to the scratchpad and it ran by
  path on the first try. DO INSTEAD: a harness preference for Bash is
  not a reason; this lesson is the reason. Any file of prose or code
  longer than a screen, or carrying mixed quotes, is a Write-tool
  script run by path, and the heredoc is never the first try.
- NUANCE: the diet guard's OUTPUT DIET line on a command that mentions
  glob or a listing is advice about limiters, not a failure; the parse
  error came from the shell, and the fix is the file, not shorter output.
- TRIED (2026-10-01, the stop-time cross-check, twice in ten minutes):
  a short heredoc Python script whose replacement text held `\n` inside
  a triple-quoted block, then a one-line fix-up script with `\\n`.
  FAILED BECAUSE: the Bash tool's own layer halved the backslashes both
  times, so the file got a real newline inside a string literal and the
  selftest died on "unterminated string literal"; the second try had
  "fixed 3" printed and changed nothing, since `\\n` had become `\n`
  before Python ran. DO INSTEAD: the length test is a trap when the
  script is SHORT: any text with a backslash in it goes through the
  Edit tool (its old/new strings pass verbatim) or a Write-tool
  scratchpad script, even when it is three lines.

See also: WORKFLOWS.md "Section or split a file the big-reads ledger
names" (the batch-edit lesson nuance: one anchor per replacement, one
file per script run); tools/route_index.py (the tool born in this batch);
docs/systems/self-audit.md "The route line".

## A standup proposal is this reply's work (the PROPOSE line is an order, not a menu, 2026-09-29)
Tags: lessons, process, learning loop | A [DO] proposal at standup (an audit, a trim, a loop run) is done in the first reply by a script or an employee; only an [ASK] line is a question for Mazhron
Keys: proposal, PROPOSE, standup proposals, what to work on, learning loop, owner decides, systems audit overdue, digest trim, do it, permission, ask permission, proposal named, DO ASK, C0005, four corrections, name the pattern

THE ONE RIGHT WAY: the first reply after standup relays the digest, then
DOES every PROPOSE [DO] line in that same reply: the systems audit is four
read-only employees plus --record, the digest trim is the loss test plus
a measurement, a stale loop group is one run_all call, dead links are
fixed, an unwritten lesson is written, a stale claim is resolved, a
corrections pattern is named and its law drafted. Only the [ASK] lines
(an open question, a shelf, a declining agreement rate, a game number)
are put to Mazhron, and the reply ends with what was done, not with a
menu. "The owner decides" names the ASK class, never the mechanics.

- TRIED (2026-09-29, the first reply after /clear): the digest carried
  four PROPOSE lines; the reply summarized them under "Proposals" and
  closed with "What do you want to work on: NS-30's flat surfaces, the
  overdue systems audit, the corrections pattern, the core diet, or one
  of the open questions?" FAILED BECAUSE: the learning-loop law's closing
  words, "Mazhron decides", were read as "every proposal is a question";
  an audit an employee runs and a trim a loss test governs carry no
  decision, only work, so offering them was the fourth relay of the week
  (C0002, C0003, C0004 were the same shape with a hook line or the
  manager's own sentence as the source). Mazhron: "If an audit is
  required, and it can be done with a sub-agent, or a script, it doesn't
  need my permission. Just do it." DO INSTEAD: the way above; the tags
  now say which is which, and the Stop hook refuses a reply that names a
  [DO] proposal its ledger still raises (PROPOSAL NAMED).
- NUANCE: an audit's own proposals follow the same split: its DO items
  the manager does in the batch (or briefs next), its ASK items are
  relayed verbatim; an employee still applies nothing.
- NUANCE (the guard's probe case, 2026-09-29): the incident reply was
  written into stop_tick's selftest BEFORE the pattern, per "Harden a
  guard against a public incident", and it failed first: the sentence
  span `[^.
]{0,80}` stopped at the "3.2k" in "about 3.2k tokens and
  wants a trim". A sentence span in a guard regex must not treat every
  full stop as a sentence end; `[^
;]{0,100}` passed. The probe case
  earned its keep in the first minute.

See also: INTENT.md "The proposal law"; "If the hook says checkpoint
advised, I shouldn't have to type /checkpoint" (the same law, the hook
and the reply as sources); tools/ledger_trends.py (ACTION); tools/hooks/
stop_tick.py (PROPOSAL NAMED); WORKFLOWS.md "Audit the operating system".

## An ask is a question with a recommended answer (a statement never asks, 2026-09-29)
Tags: lessons, process, communication | Every [ASK] line put to Mazhron ends with a question mark, carries the manager's recommended answer first, and never shares a list with statements; a reply of "agreed" or "you decide" on any line must be enough
Keys: ask, ASK items, ruling, rulings, are you asking me, statement or question, summaries, can't tell, recommended answer, relay ASK, what do you want, question mark, decision list

THE ONE RIGHT WAY: when a reply puts something to Mazhron, each item is
one numbered line shaped "<the thing in a sentence>. <The question>?
Recommended: <the answer and why in a clause>." Asks and statements never
share a list: findings go in prose or their own list, asks in the ASK
list, and the list is introduced as asks ("These need your ruling").
Any item where the manager's recommendation is good enough says so, so
"you decide" is a valid reply. A relayed audit ASK item is rewritten into
this shape by the manager, never pasted as the auditor's finding.

- TRIED (2026-09-29, the first reply after /clear): the systems audit's
  seven ASK items were relayed as findings ("The between-session cache
  gap past the one-hour TTL is the residual miss cause. No script fixes
  a cadence.") under a heading that said ASK. Mazhron: "Are you asking
  me to make rulings here or are these statements? Sometimes when you
  respond to me and give me summaries, I can't tell if you are asking me
  for something or telling me something." DO INSTEAD: the shape above;
  a finding without a question is a statement however it is labelled,
  and a question without a recommendation makes the owner do the
  manager's thinking.

See also: "A standup proposal is this reply's work" (the DO / ASK split
this entry gives its voice to); INTENT.md "The proposal law"; the
WHERE WE LEFT OFF ASK list in the day file, which follows the same shape.

## Widen a proxy after its first real run (the named corpus, and the selftest that pins a phrase, 2026-09-29)
Tags: lessons, process, learning loop, ledgers | A rule's script proxy must count every home the rule already has, and a verdict phrase changed in the script is changed in its selftest in the same edit
Keys: law_gaps, workflow gap, proxy, named corpus, first real run, false positives, hooks flagged, run_all scripts flagged, selftest FAIL after edit, verdict wording, pinned phrase, employee script widened

THE ONE RIGHT WAY: when a script stands in for a law (a proxy), list every
place the law is already satisfied BEFORE the spec is written, and make the
proxy read all of them: a tool is "named" not only by a WORKFLOWS.md entry
but by tools/run_all.py (the loop is a loop script's workflow), by
.claude/settings.json (a hook's wiring) and by any skill. Then run it once
for real and read the list it produces: every false positive on that first
run is a home the spec forgot. When the widening changes a verdict's
wording, grep the selftest for the old phrase in the same edit, because an
employee's selftest pins the exact string it was told to print.

- TRIED (2026-09-29, tools/law_gaps.py by sonnet, spec by the manager):
  the workflow-rule proxy was specified as "a changed tool that
  WORKFLOWS.md does not name". Its first real run listed 17 gaps, and
  twelve of them were hooks and run_all exporters, which the workflow rule
  already covers by their wiring. FAILED BECAUSE: the spec named one home
  for the rule when the rule has four. DO INSTEAD: the corpus above; the
  list fell to 5, all real.
- TRIED (the same patch): the verdict text gained ", run_all group, hook
  setting or skill" in the script alone; the selftest failed once on the
  old phrase, then passed after the second edit. DO INSTEAD: change the
  script and its selftest in one edit script, grepping the old phrase
  first (the "Apply an audit's findings with a batch edit script" entry's
  anchor rule applies to verdict strings too).

See also: INTENT.md "Everything that can be measured is measured"; tools/
law_gaps.py (the named corpus comment); "Apply an audit's findings with a
batch edit script (anchors quoted from a report)".

## Edit the kit's original, never its grab-copy (refresh_kit reverts the copy silently, 2026-09-29)
Tags: lessons, process, kit, rootstock | A method file exists three times (repo root, the kit folder, the public mirror); only the repo-root original holds an edit, because refresh_kit copies it over the other two on every run
Keys: kit copy reverted, refresh_kit pairs, Future Project MDs, WIKI_METHOD edit lost, sync_kit_repo, grab-copy, original vs copy, method file fix, README audit fix in a method file

THE ONE RIGHT WAY: before a batch edit touches any file under "Future
Project MDs/", ask refresh_kit which original owns it (`python -c "import
sys; sys.path.insert(0,'tools'); import refresh_kit as r; print(r.pairs())"`
or WORKFLOWS "Edit the future-project kit" step 1) and point the edit at
THAT path: the repo-root METHOD.md, tools/<script>.py, .claude/skills/,
.claude/rules/. Then `python tools/refresh_kit.py` carries it to the kit
folder and `python tools/sync_kit_repo.py` to the mirror. A file with no
original (UPGRADES.md, the domain notes, the public README) is edited where
it lives. Check the edit landed with a grep of the ORIGINAL after the
refresh, not of the copy before it.

- TRIED (2026-09-29, the README audit's WARN_TOKENS catch): the batch edit
  script pointed at "Future Project MDs/WIKI_METHOD.md", printed "wrote",
  and the next refresh_kit run copied the untouched repo-root original
  back over it; the sync pushed a mirror without the fix. FAILED BECAUSE:
  the kit folder is a grab-copy, not a home; refresh_kit says nothing
  when it overwrites. DO INSTEAD: the path rule above; the second pass
  edited WIKI_METHOD.md at the repo root and both copies followed.
- TRIED AGAIN (2026-10-06, the fifth README audit): `ls -d */` showed no
  method file at the root (it lists directories only) and a grep of
  refresh_kit.py for the file names found nothing (the pairs are built,
  not spelled out), so the batch pointed at the kit copies again; the
  sync's DRY RUN then printed "refreshed WIKI_METHOD.md" and the copies
  lost the edit. FAILED BECAUSE: two cheap checks that cannot see the
  originals were trusted over the one that can. DO INSTEAD: `find . -name
  <file> -not -path "./Future Project MDs/*"` or the pairs() call above
  BEFORE the script is written; and read "refreshed <file>" in any
  refresh or sync output as "the copy just lost whatever you put there".

See also: WORKFLOWS.md "Edit the future-project kit (Rootstock)";
tools/refresh_kit.py (pairs); "Apply an audit's findings with a batch edit
script" above (the anchor rule; add the path rule to it).

## Close a proposal with the number its rule reads (the measure line by the proposal's own formula, 2026-09-29)
Tags: lessons, process, proposals, ledgers | A "done" the ledger cannot see is not done: the closing measurement is taken exactly the way the trend rule measures, or the proposal fires again
Keys: proposal still raises, PROPOSAL NAMED, measure line, digest_size, digest_warn_bytes, wc -c, like-for-like, closing a DO proposal, ledger_trends formula, HOW line

THE ONE RIGHT WAY: before appending the line that closes a [DO] proposal,
read the rule in tools/ledger_trends.py (or the HOW line the digest prints
for that ledger) for WHAT it measures and HOW, and record that exact
measurement as the closing line; a second line with a richer like-for-like
number is welcome but is never the closer. Verify with `python
tools/ledger_trends.py | grep <ledger>` printing nothing before the reply
ends.

- TRIED (2026-09-29, the fourth digest trim): the trim was real (14562 ->
  13415 bytes like-for-like, the injected text with the hook preamble) and
  the measure line recorded 13415; the rule reads bytes > 12000 on the
  newest line, so the Stop hook fired PROPOSAL NAMED at the reply's end.
  FAILED BECAUSE: the number recorded was a different measurement from the
  one the rule reads (the HOW line says `standup.py | wc -c`, the script's
  own output). DO INSTEAD: the way above; the second line (10855) closed it
  and both lines say what they measure.

See also: tools/ledger_trends.py (the HOW line under digest_size.txt);
docs/systems/self-audit.md "The digest size ledger"; "Apply a long
batch of file edits from the shell" below (the fifth trim's order:
edit, selftest, then measure and ledger).

## Trim every auto-memory store, not just the one that loads (the harness keys a store by the folder a session opens in, 2026-09-29)
Tags: lessons, memory, workstations | One machine can hold several auto-memory stores for one project; a trim that reads only the loaded MEMORY.md misses the others
Keys: auto-memory, memory trim, memory store, MEMORY.md, second store, parent folder, current-state-and-next-steps, banked memory, stub superseded

THE ONE RIGHT WAY: before a memory trim (or any claim about what
auto-memory holds), list every store for the project:
`ls ~/.claude/projects/ | grep -i everwood`, then each one's memory/
folder. A session opened at the repo folder and one opened at its parent
folder read different stores. Bank and stub each store the same way
(WORKFLOWS.md "Reference or restore a banked auto-memory"; WIKI_METHOD.md
"The harness memory").

- TRIED (2026-09-22 to 09-29): WS1's trim task sat open for a week while
  the loaded store (the repo folder's) already looked trimmed: two small
  entries. FAILED BECAUSE: the 14 untrimmed memories, including the
  current-state-and-next-steps.md the 09-29 systems audit named, lived in
  the parent-folder store (slug ...Everwood---Idle-Clicker, no repo
  suffix), which no repo session loads. DO INSTEAD: the listing above; the
  2026-09-29 trim banked all 14 plus the index into docs/systems/
  memory-bank.md.

See also: docs/systems/memory-bank.md "What stayed in auto-memory";
WORKFLOWS.md "Reference or restore a banked auto-memory"; docs/index/
notes.md (WS2's task to check its own stores).

## Copy a hook's stated line shape exactly (a RESOLVED line with a date prefix is invisible to verify_advisor, 2026-09-30)
Tags: lessons, hooks, delegation | When a hook prints the line it wants appended, that text is its parser's grammar; any prefix or reordering makes the line unread and the hook advises the same set forever
Keys: verify_advisor, delegation_pending, RESOLVED line, LEDGER ADVISED, hook parser, line format, append-only, date prefix

THE ONE RIGHT WAY: when a hook says "append `RESOLVED | <id> | OK/CORRECTED
- <words>`", append exactly that: first field the literal word, second the
id, nothing before it. The ledger's other lines carry dates; the RESOLVED
line does not, because tools/hooks/verify_advisor.py reads
`parts[0].startswith("RESOLVED")`. If a set keeps coming back ADVISED after
you resolved it, grep the hook for its parse before resolving it again.

- TRIED (2026-09-29 01:38): the four README-audit lanes were resolved as
  `2026-09-29 01:38 | WS1 | RESOLVED | D10e3e1 | ...`, matching the
  PENDING lines' shape. FAILED BECAUSE: the hook only clears a PENDING
  when a LATER line's FIRST field starts with RESOLVED; the dated lines
  never matched, so the set stayed ADVISED into 2026-09-30. DO INSTEAD:
  the exact shape; a wrong past line is never edited (append-only), a
  correct line is appended after it, naming the original.
See also: tools/hooks/verify_advisor.py; .claude/skills/brief/SKILL.md
"AFTER THE EMPLOYEE RETURNS"; SUBAGENTS.md rule 5.

## Exclude the generated wiki view from any grep over docs (one hit in wiki_view.html is the whole wiki, 2026-09-30)
Tags: lessons, tokens, tooling | docs/wiki_view.html holds every wiki file as one JavaScript line, so a recursive grep that matches it returns megabytes and the tool result is spilled to disk
Keys: wiki_view.html, grep docs, output flood, persisted output, --include=*.md, export_wiki_view, big read

THE ONE RIGHT WAY: a recursive grep over docs/ or the repo root always
narrows to markdown (`--include=*.md`, or the Grep tool's `glob`) or
excludes the view (`--exclude=wiki_view.html`). The view is regenerated by
tools/export_wiki_view.py from the .md files, so it never holds a fact the
markdown does not; matching it adds nothing and costs the whole output.

- TRIED (2026-09-30, the contradiction sweep's verify step): `grep -rn
  "placeholder until" docs *.md` to find a quote. FAILED BECAUSE: the third
  hit was docs/wiki_view.html's DATA line, 1.3 MB, and the harness spilled
  the result to a file; the two lines I wanted were at the top and the
  lint verdicts I also needed were at the bottom, both unread until a
  second call tailed the spill. DO INSTEAD: the include flag; when a
  result does spill, `tail -c` the saved file rather than re-running.
See also: tools/export_wiki_view.py; docs/systems/tooling.md; LESSONS.md
"Copy a hook's stated line shape exactly" (the same batch).

## Walk the transcript tree, never list it (employee sessions live in <session>/subagents/, 2026-09-30)
Tags: lessons, tooling, tokens | A miner of the harness transcripts that lists only the project's top-level folder sees the manager's sessions and none of the employees', which is where most guard denials and most spend happen
Keys: transcripts, subagents folder, os.walk, listdir, guard_replay, usage_window, usage_report, transcript miner, employee transcripts

THE ONE RIGHT WAY: any script that reads ~/.claude/projects/<slug>/ walks it
recursively (os.walk or rglob) and takes every *.jsonl it finds; the
employees' transcripts sit one level down in <session-id>/subagents/. Before
trusting a miner's first table, count the files it opened against
`find <slug> -name "*.jsonl" -mtime -7 | wc -l`.

- TRIED (2026-09-30, guard_replay.py's first real run): collect_calls()
  used os.listdir on the top level, replayed 889 calls, and reported that
  every guard matched its live behaviour exactly. FAILED BECAUSE: 17 of
  the 31 recent transcripts were employee files under subagents/, holding
  five of the six live INDEX FIRST denials; the table was drawn from
  two thirds of the traffic. DO INSTEAD: os.walk (the fix, one hunk); the
  true table was 1261 calls, INDEX FIRST 9 would / 10 live / 1 lost.
See also: tools/guard_replay.py; tools/usage_window.py; tools/usage_report.py
(transcript_dirs, which already walks); LESSONS.md "Widen a proxy after
its first real run".

## Unset ELECTRON_RUN_AS_NODE before any Electron app's CLI from a Claude Code shell (Unity Hub ran as bare Node, 2026-10-05)
Tags: lessons, tooling, workstation | VS Code's Claude Code shell exports ELECTRON_RUN_AS_NODE=1, so an Electron binary launched from it (Unity Hub, any Electron CLI) starts as plain Node and fails "Cannot find module '--headless'"
Keys: Unity Hub, headless, ELECTRON_RUN_AS_NODE, MODULE_NOT_FOUND, Electron CLI, env -u, install editor, Art of War

THE ONE RIGHT WAY: launch an Electron app's command line with the variable
removed: `env -u ELECTRON_RUN_AS_NODE "C:/Program Files/Unity Hub/Unity Hub.exe" -- --headless editors -i`.
The same flag is why `code`, Discord or any Electron tool misbehaves from
this shell; check for it before blaming the tool. A Hub catalogue query
(`editors -r`) can hang on the network; the install needs only the
version and changeset from ProjectSettings/ProjectVersion.txt, so skip the
query and install directly.

- TRIED (2026-10-05, installing Unity 6000.6.4f1 for The Art of War): ran
  the Hub's documented `-- --headless editors -i` from the repo folder,
  then from the Hub folder. FAILED BECAUSE: both printed Node's
  MODULE_NOT_FOUND for '--headless' - the process was Node, not the Hub,
  because the inherited environment carried ELECTRON_RUN_AS_NODE=1.
  DO INSTEAD: `env -u ELECTRON_RUN_AS_NODE` in front; the listing and the
  install then worked first time (editor + three modules in one call).
See also: WORKSTATION_METHOD.md (the kit); docs/systems/mods.md; the Art of War handoff (the local Claude notes at the root of the TheArtOfWar clone under Desktop, Unity).

## Never put a Windows path inside a Python heredoc's string literal (a `\U` in `Desktop\Unity` is a unicode escape, 2026-10-05)
Tags: lessons, tooling, workstation | A backslash-U or backslash-x in a normal Python string is an escape, so a one-off edit script carrying `C:\Users` or `Desktop\Unity` dies with "truncated \UXXXXXXXX escape" before it runs
Keys: unicodeescape, truncated UXXXXXXXX, heredoc, python - <<, Windows path, backslash, raw string, Edit tool

THE ONE RIGHT WAY: an edit that carries a Windows path uses the Edit tool,
or a raw string (r"...") in the script, or forward slashes. A `python -
<<'EOF'` one-off is for text without backslashes; the moment the
replacement text names a folder, switch tools.

- TRIED (2026-10-05, twice in one day: the mods.md See also, then the
  LESSONS See also): wrote the replacement text as a normal "..." literal
  with `Desktop\Unity` inside. FAILED BECAUSE: Python read `\U` as the
  start of a 32-bit unicode escape and refused the whole script with a
  SyntaxError; nothing was written. DO INSTEAD: the Edit tool for that
  line (it worked first time), or r"..." when a script must carry it.
See also: LESSONS "Unset ELECTRON_RUN_AS_NODE before any Electron app's CLI" above (the same day's other workstation trap); WORKSTATION_METHOD.md.

## A force push is a delete: branch the old tip first, then name the grant's target in the one command (the kit mirror, 2026-10-05)
Tags: lessons, git, preservation | The preserve guard refuses --force and --force-with-lease as history rewrites; the lossless shape is an added branch holding the old tip, a recorded two-yes grant, and one push whose command line carries the grant's target text
Keys: force push, force-with-lease, mirror behind, non-fast-forward, rebase rewrote hashes, backup rejected, grant target, preserve guard, pre-rebase branch

THE ONE RIGHT WAY: when a mirror's push is rejected because a rebase
rewrote the hashes it holds, do not reach for --force. Push the old tip
to the mirror as a dated branch first (an added ref needs no grant: the
hashes live on), ask Mazhron twice naming the remote, the ref and the
kept branch, record the grant, then run the single force-with-lease push
with the grant's target string in the same command (the guard matches
that text). "Do what you think is best" is one acknowledgment at most;
the law wants two, said as two. WORKFLOWS "Delete something" step 5b.
See also: tools/hooks/preserve_guard.py; tools/delete_grant.py;
docs/history/delete_grants.txt.

## The digest size proposal measures the LAST standup, not this one (measure the fresh line before trimming, 2026-10-05)
Tags: lessons, process, digest diet | A PROPOSE [DO] on digest_size.txt was computed before this session's digest was appended; read the newest line first, and a post-arc digest that prints moved ledgers in full is context under the loss test, not bloat
Keys: digest size, digest_size.txt, digest diet, digest trim, PROPOSE digest, 12000, digest_warn_bytes, loss test, standup digest bytes, trim by the loss test, measure, stale proposal, ledger tails in full

THE ONE RIGHT WAY: when the standup carries "PROPOSE [DO] (digest_size.txt):
the standup digest is N bytes", `tail -2 docs/history/digest_size.txt`
first. The proposal was computed by ledger_trends from the line the PREVIOUS
standup wrote; the current standup appends its own line after the digest
prints. If the newest line is under digest_warn_bytes the [DO] is the
measurement itself: say so and move on. If it is over, apply the loss test
(INTENT.md "The digest diet") and only then edit tools/standup.py. A digest
that follows an active arc is bigger because every ledger that moved prints
in full ("new since you last looked" is context); that is never a trim.

- TRIED (2026-10-05 14:00, the first reply after /clear): the digest said
  12735 bytes; the reflex was to open standup.py and find a section to cut.
  FAILED BECAUSE: the 12735 line was the 13:08 digest, written after the
  morning arc had moved a dozen ledgers; the 13:59 line for THIS digest was
  already 10953, under the 12000 warn. Cutting would have failed the loss
  test for a number that had already cleared. DO INSTEAD: tail the ledger,
  report the fresh number, let the next trends run clear the proposal.
See also: INTENT.md "The digest diet"; tools/standup.py (THE DIGEST DIET
helpers); docs/systems/self-audit.md "The digest size ledger";
docs/history/digest_size.txt.

## A pasted prompt starts with "<" like a harness wrapper (unwrap pasted_content before the wrapper filter, 2026-10-06)
Tags: lessons, process, digest diet, standup | The owner's four rulings arrived as a pasted_content block; standup's exchange miner dropped it as a harness wrapper, the build session yielded no prompt, and the digest replayed the previous session's exchange as if it were the last one
Keys: pasted_content, pasted prompt, stale exchange, wrong session, THE LAST EXCHANGE, _mine_exchange, unwrap_paste, harness wrapper, startswith("<"), standup digest, loss test, ground truth

THE ONE RIGHT WAY: a harness wrapper (`<command-name>`, `<task-notification>`,
`<system-reminder>`, `<local-command-stdout>`) is NOT the human typing and
stays filtered; a `<pasted_content id="...">` block IS the human typing with
a tag around it. tools/standup.py strips the paste tags first (unwrap_paste)
and only then applies the "starts with <" filter, and --selftest covers both
sides. When a standup's LAST EXCHANGE names a session older than the day
file's WHERE WE LEFT OFF, the miner skipped a prompt: run _mine_exchange on
the newest transcript by hand and look at what it threw away.

- TRIED (2026-10-06 11:55, the first standup after the creative-mode arc):
  the digest replayed the 10:37 planning exchange from session 9c81e03c
  while the checkpoint commit said the mode was built and shipped at 11:45.
  FAILED BECAUSE: the build session's only human prompt after "standup" was
  the pasted rulings, which begin with "<pasted_content", so the miner
  returned None for that transcript and the newest surviving reply was the
  older session's. DO INSTEAD: unwrap the paste tags before the wrapper
  test (done, selftest PASS, kit copy refreshed); treat "session older than
  the day file" as the symptom to look for.
See also: INTENT.md "The digest diet" (the loss test: the exchange is never
cut, so it must also never be the wrong one); tools/standup.py
(_mine_exchange, unwrap_paste); WORKFLOWS.md "Open a session / close an arc".

## A patch script with backslash escapes goes through the Write tool, never a bash heredoc (2026-10-06)
Tags: lessons, process, tooling | Four times in one afternoon a one-off Python patch sent through the Bash tool's heredoc had its escapes rewritten on the way in: a regex word boundary landed as a backspace byte, a GDScript line continuation plus newline landed as literal backslash-n text, a test string broke mid-literal, and the first draft of THIS lesson arrived with backspace bytes in it
Keys: heredoc, backslash, escape, backspace, Write tool, patch script, python stdin, regex word boundary, line continuation, bash tool quoting, one-off edit, cat -A

THE ONE RIGHT WAY: when a one-off edit script contains ANY backslash (a
regex, a GDScript continuation, a Windows path, a newline meant for the
file), write the script to the scratchpad with the Write tool and run it
with `python <path>`; or build the byte with chr(92) / chr(10) so no escape
is parsed twice. Reserve a stdin heredoc for scripts with no backslashes at
all. Verify the written bytes with `cat -A` before running anything that
depends on them: a parse error in main.gd left the windowed capture sitting
open for ten minutes until Mazhron noticed ("the game has been running for
quite a long time with nothing happening").

- TRIED (2026-10-06): the paste-unwrap regex inside a heredoc patch.
  FAILED BECAUSE: the file received a 0x08 byte; the selftest failed and
  the kit copy was refreshed with the broken regex. Then a continuation
  line for the creative self-test arrived as backslash-n text, a GDScript
  parse error, the test printed MISSING and the capture hung. DO INSTEAD:
  Write tool for the script, chr() for the bytes, cat -A to check.
See also: "Never put a Windows path inside a Python heredoc's string
literal" (the same trap from the path side); tools/standup.py unwrap_paste.
```

### `LICENSE`

- Source: `LICENSE` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 1079
- SHA-256: `b6975faf867391465cb06f9b70f537223b7b09bdd13ef9eb0c7daecec3feeef8`

```text
MIT License

Copyright (c) 2026 Travis Rhoda (Mazhron)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### `README.md`

- Source: `README.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 67393
- SHA-256: `45cd54f75c944fe352c165e21c54c2430eec47b682067132a74a3575db1e4a95`

```text
# Rootstock

### A Project Operating System for Claude

**Graft your next project onto proven roots.** Rootstock is a portable,
plug-and-play operating system for running a software project with Claude:
a knowledge wiki that keeps context cheap, a reporting discipline that
makes results permanent, a delegation company of sub-agents that does the
heavy reading for pennies, and session rituals that make clearing your
chat completely lossless.

Grown in [Everwood](https://github.com/Mazhron/Everwood), an idle/clicker
game built end to end with Claude, by **Mazhron (Travis Rhoda)**.

Kit version: **v1.44** (2026-10-06). The graft log `UPGRADES.md` is the
single source of truth; this line is checked against it on every sync.

---

## What loads every session, what Anthropic says, and what guards it

The installed CLAUDE.md is a POINTER file: the project in a paragraph, how
to read, how to verify, the laws no hook enforces, and one line naming the
master index. It stays under Anthropic's own 200-line target for a
CLAUDE.md file. This repository looks large because it is install
instructions, method files and reference scripts, read ONCE by the Claude
doing the install; none of it is a CLAUDE.md and none of it loads into a
session's context.

| What | When it loads | Size (origin project, 2026-09-14) |
|---|---|---|
| CLAUDE.md, the pointer core | Every session, automatically | ~900 tokens, 68 lines |
| A path-scoped rule (`.claude/rules/*.md`) | Only while Claude reads a matching file | a few hundred tokens each |
| The standup digest | Once, at session start / after /clear | ~2.5k-3.5k tokens (was ~4.3k before the digest diet: only verdicts, moved ledgers and the last exchange print in full; four loss-test trims since, the last on 2026-09-29) |
| The master index / wiki (47 files) | NEVER whole. A section at a time, on demand | ~289k tokens on disk, ~0 by default |
| The front door `0 - READ ME FIRST.md` | Once, at install | ~1.8k tokens |

Knowledge has three homes, by WHEN it is needed:

- **ALWAYS.** CLAUDE.md itself: the pointer core.
- **WHEN A MATCHING FILE IS READ.** A `.claude/rules/*.md` file with a
  `paths:` front matter field, loaded by Claude Code itself, not by a hook
  or a Read call.
- **ON DEMAND.** `docs/index/MASTER_INDEX.md`, the one door: every topic
  file, root file, sub-index, law stub, rule and knowledge file, one line
  each, every destination listed directly.

What guards the shape:

- **The token-budget lint** (`check_claude_md.py`) fails past LINE_BUDGET
  200 (Anthropic's own number) or TOKEN_BUDGET 2,000 (the owner's action
  line), and WARNS past WARN_TOKENS 1,500 (retuned from 1,000 in v1.37,
  after it fired every session with no cold unit to move). It also
  requires CLAUDE.md to
  name the master index, the master index to list every topic file,
  sub-index and rule, and it fails a rule file that has no `paths:` field,
  because such a rule would load every session and its tokens belong to
  the core's budget.
- **The standup digest** prints the lint's OK/WARN line every session, so
  the size is visible without asking.
- **The hygiene guard**, a PostToolUse hook, runs the lint the moment
  CLAUDE.md, the master index or a rule is edited.
- **The core diet** (`core_diet.py`) moves a cold section out of the core
  by script, verbatim and reversibly, leaving one stub line in the master
  index. Cold is three signals at once, not a read count: no explicit
  read of the section's lines, no read of the wiki files it points at,
  and no git touch inside the window (30 days by default).

Anthropic's own guidance: https://code.claude.com/docs/en/memory. Its
words: target under 200 lines per CLAUDE.md file, longer files consume
more context and reduce adherence; it gives no token figure of its own.
The 1,000-token number that circulates online is a community estimate,
not Anthropic's.

## The problem: context is the bill

An AI assistant's real cost is not the question you ask. It is the CONTEXT:
the whole conversation, plus every file the model has read, rides along
with EVERY subsequent request. A six-hour session answers its last question
at several times the price of its first one. Every file read wholesale is a
tax you keep paying for the rest of the session.

Everything in Rootstock is a variation on one insight:

> Keep the manager's context small, and let cheap, disposable contexts do
> the reading.

### "Doesn't a wiki make the context HEAVIER?" (what actually loads)

The natural objection: more files means more to read, so the context gets
fat and token-hungry. It would, if the files loaded. They do not. Almost
nothing in Rootstock rides in the context by default:

| What | When it enters context | Size (origin project, 2026-09-14) |
|---|---|---|
| CLAUDE.md, the pointer core | Every session, automatically | ~900 tokens, 68 lines (was ~3.5k that same morning, ~10k before the core diet) |
| A path-scoped rule (`.claude/rules/*.md`) | Only while Claude reads a matching file | a few hundred tokens each |
| The standup digest | Once, at session start / after /clear | ~2.5k-3.5k tokens (was ~4.3k before the digest diet: only verdicts, moved ledgers and the last exchange print in full; four loss-test trims since, the last on 2026-09-29) |
| The wiki (47 files) | NEVER whole. A section at a time, on demand | ~289k tokens ON DISK; ~0 in context |
| Skills | Only the one invoked, when invoked | a few hundred tokens each |
| Hooks | Never (they are scripts; only their one-line output enters) | ~0 |

So a session opens at roughly 3.5k-4.5k tokens of context (the core plus
the digest) for a project whose written knowledge is ~289k. The core is a sliver of the wiki, and a linter
(`check_claude_md.py`) fails when it grows past budget, because THAT is
the one file that is a standing cost. The rule that keeps it small:
CLAUDE.md is a POINTER file, one pointer to `docs/index/MASTER_INDEX.md`;
the index lines live in the master index, and knowledge lives in the topic
files. Since v1.22 the budget is in tokens and a script (the core diet,
below) moves what falls out of use, so the number cannot drift up again
unnoticed.

The rest is reachable, not loaded. Claude greps a file's `## ` headings
(~50 tokens, the file itself never loads), then reads the one section it
needs with offset/limit (~1-2k). The origin project's daily meter shows
85-95% of reads landing as section reads, and a hook says the size out
loud before any whole-file read past ~10k. The "where we left off" record
is a few hundred tokens of verbatim exchange, which replaces the several
thousand it takes to re-explain state to a fresh session by hand.

The honest caveat: dump everything into CLAUDE.md and yes, every session
pays for all of it. That is exactly the failure Rootstock is built
against, and the reason the core is guarded by a linter rather than by
willpower.

### The installed CLAUDE.md: what it holds and how big it is

Knowledge has three homes, by when it is needed. ALWAYS lives in
CLAUDE.md, the pointer core: the project in a paragraph, how to read, how
to verify, the laws no hook enforces, and one pointer to
`docs/index/MASTER_INDEX.md`. WHEN A MATCHING FILE IS READ lives in a
`.claude/rules/*.md` file with a `paths:` front matter field, loaded by
Claude Code itself when Claude reads that kind of file, never by a hook. ON
DEMAND lives in the master index, the one door: every topic file, root
file, sub-index, law stub, rule and knowledge file, one line each.

The origin project's own core sits at 68 lines, ~900 tokens. It stays that
size on its own: the token-budget lint (`check_claude_md.py`) fails past
budget and the budget is never raised, and the core diet (`core_diet.py`,
kit v1.22) runs before it, moving the coldest routed sections VERBATIM out
to sub-index files under the index folder - each move leaves one pointer
line in the master index, and a hard-won section's Tags brief stays
behind as its stub - reversible with `--restore`.

The honest line: the origin's own core had drifted to ~10k tokens before
any of this existed, then to ~3.5k after the first fix. The mechanism took
two rulings the same day: the CEO (the project's owner: you) first ordered the token-budgeted diet,
then asked whether CLAUDE.md should simply point to everything else. A
read of Anthropic's own memory page settled the mechanics, and the second
ruling followed: a pointer core, a single master index, and rules that
load only by path.

### The receipts: 44 metered days of the origin project

None of the above is a guess. The harness writes a full transcript of every
session, and every request in it carries the real API meter; Rootstock's
usage sheet ("reference tools/usage_report.py") totals those meters per
model and per tool by day, week, and month. From Everwood, the origin
project - one machine, 2026-07-22 to 2026-09-03, 7,573 metered requests:

- The model GENERATED ~7.6M tokens. To generate them it RE-READ ~3.8
  BILLION tokens of context - 498 tokens re-read for every token written.
  Cached re-reads are billed at a tenth of the input price and context is
  STILL more than four fifths of the weighted token bill (the weighted
  receipts below give the split). The bill is the context.
- The most expensive tool by far is reading files: ~22.6M tokens of file
  content injected across 955 Reads - nearly 8x all Edits and Writes
  combined - and every injected token is then re-read by every later turn.
  Whatever teaches the model to read less, wins.

And the before/after, same model, same project, from the sheet:

- **The wiki diet** (adopted Aug 24: grep a file's headings, read only the
  section you need). Average file content injected per Read: ~35k tokens
  before (Aug 1-23), ~21k after (Aug 24 - Sep 1), ~10k once the habits
  compounded (Sep 2-3). Same codebase, 71% less paid per read.
- **The checkpoint protocol** (adopted Sep 2: day files make /clear
  lossless, so sessions actually end). In the last days of the
  endless-session era, context had accreted until the model was re-reading
  810-898k tokens PER REQUEST (Aug 26-27). The first two cleared-session
  days averaged ~267k per request - a 69% cut against that peak - while
  Sep 3 did three times the requests of an Aug 26-27 day.

### The weighted receipts (the same window six days on: 50 days, 2026-09-10)

Raw token counts flatter the wrong column. What counts against a plan is
WEIGHTED: input x1, cache write x1.25 (x2 on a one-hour cache), cache read
x0.1 (x0.025 on the model that discounts it), output x5 - the API's own
price ratios. Re-run on those weights, the same machine's 4.2 billion raw
tokens over 50 days were about 366 million weighted, and the split is not
what the raw column suggests:

- Cache READS, the giant raw number, were 41% of the weighted bill. Cache
  WRITES - new context entering the prefix - were 29% at the five-minute
  write rate the pillar shares assume, and the model's own OUTPUT (prose,
  edits, thinking) 13%. Fresh input rounds to zero. The shares stop at
  ~83% because this machine ran the one-hour cache, whose doubled write
  price is the rest: counted at its true rate, writes were the largest
  pillar at ~46%, which is the method file's finding (writes first, reads
  second) from its earlier window.
- Prefix REWRITES nobody chose - a cache that expired, a core file edited
  mid-session - were 24% of the all-time budget. They are now counted per
  day, because a waste with a name gets fixed.

The kit's usage sheet leads with the weighted number and keeps the raw one
as trivia beside it; the fan-out guard meters with the same weights; and
every day is judged against the previous seven ACTIVE days (spend, cache
misses, whole-file reads) with a verdict the standup digest relays the
next morning: CHECK or LOW at 30% over or under, cache misses or heavy
reads at twice the week's rate, the section-read share down 20 points;
today's line is marked partial, and a CHECK is relayed verbatim. A number
without a comparison means nothing.

Different days do different work, so read the percentages as one project's
honest metering, not a controlled benchmark. But the mechanism is
arithmetic, not anecdote: a session that clears re-reads a small context
many times instead of a huge one, and a model that reads sections stops
paying for whole files on every turn that follows.

## The four pillars, and two companions

### 1. The Knowledge Wiki (WIKI_METHOD.md)

Project knowledge lives in a web of small topic files, not in one giant
document and not in the chat. The core instruction file (CLAUDE.md) stays
lean: laws, process, and a one-line-per-file index. Knowledge has three
layers: the core, a topic library (`docs/systems/`) and portable root
notes (an engine fact goes to the engine notes, a genre pattern to the
genre notes, a project detail to the topic library). The method bootstraps
a brand-new project from a single instruction ("Read WIKI_METHOD.md and
set this up for this project"); these are the conventions
that make it work:

- **Read cheap.** Grep a file's headings first (about 50 tokens), then read
  only the section you need. Never read a topic file whole.
- **Headings are search keys.** Every section is named for what a search
  would look for, never "Misc" or "More fixes".
- **Cross-references.** Sections end with "See also" lines pointing at
  related topics WITH their file, so a hop needs no search. Moving a
  section updates every See also that pointed at it; two files that
  grow overlapping coverage merge to one home and leave a pointer.
- **One home per fact.** Engine lessons, genre lessons, and project details
  each live in exactly one layer, because split homes drift.
- **Tags and the knowledge index.** A hard-won section (a lesson, a trap,
  a doctrine) carries a one-line `Tags:` brief, and a script compiles
  every Tags line into a generated knowledge index - the wiki browsed by
  topic instead of by file.
- **The harness memory stays machine-local (the trim ruling).** The
  harness's own per-machine auto-memory never holds a fact the repo can
  own: it does not travel between machines, is never pulled, reviewed or
  linted, so it drifts stale invisibly. It keeps only this machine's exe
  paths, installs and quirks. Repo-shaped memories are banked verbatim
  into a topic file, superseded in place with a stub, and a tally ledger
  counts every later need of a banked fact - enough hits (three on one
  fact, or five in all, inside 30 days) proposes a
  restore, and the owner decides.
- **Incremental growth.** Every file touched during normal work gains
  proper headings and links then and there. No stop-the-world passes.
- **Size before you read (the 10k rule).** A whole-file read past ~10k
  tokens is section-read or handed to an employee; the diet guard refuses
  the first whole read of a big file (once per file per session) with the
  file's own index attached, and warns on every later one. Editing that
  needs the exact text is the one fair exception: the same call repeated
  passes.
- **The output diet.** Every emitted token costs five; every tool result
  is written into context at 1.25x and re-read forever. Edit over Write,
  scripts generate documents, nothing restated that a table already says,
  limiters on chatty commands.

- **Nothing is deleted (the preservation law).** Neither the manager nor
  any employee deletes a file, record or tree without the owner's yes
  given twice, and no script is written that deletes. A file RETIRES to a
  shelf folder; a rarely-read wiki section the owner picks moves VERBATIM to a cold
  shelf (`docs/cold/`, under the hot file's basename, with an append-only
  index; the mover script lists, moves, restores and dry-runs) with a stub
  left behind; a wrong fact is marked superseded in place. A
  hook (described with the rest in the hooks section below) refuses
  delete verbs, work-discarding git verbs and deletion calls
  written into code; the rare real deletion is recorded with the owner's
  two acknowledgments, word for word, before the one command runs.
- **The wiki learns (the learning loop).** Three read-only scripts close
  the loop: a link checker finds dead cross-references, a heat map mines
  the transcripts for reads per section and says WHY a cold page is cold
  (code moved after the doc was last opened is the only kind worth a
  look; cold by read count is never a reason to shelve), and a trends
  script turns ledger tails into PROPOSE lines at standup when a threshold
  crosses. Nothing is applied by a script; and since v1.35 every line
  carries its class: a [DO] proposal (an audit, a digest trim, a stale
  loop group, dead links, an unwritten lesson: anything a script, a hook
  or an employee carries) is done in the reply that reads it, never
  offered as a choice, while an [ASK] proposal (an open question, a
  shelf, a game number) waits for the owner. "The owner decides" names
  the ASK class, not the mechanics. A done [DO] clears by its own
  ledger, never by memory: since v1.36 a named corrections pattern is a
  PATTERN row in the corrections ledger, and the proposal stays quiet
  until a new correction lands.
- **The lessons book (the lesson loop).** Steps live in the process
  registry; judgment lives in LESSONS.md: one entry per task shape, THE
  ONE RIGHT WAY first, then TRIED / FAILED BECAUSE / DO INSTEAD, then
  nuance lines as they accumulate. The prompt hook names the entry to
  read before the first tool call, and since v1.33 the ROUTE line beside
  it: the process-registry entry and the script whose heading, WHEN line
  or search keys the prompt already hits, so "does software already
  handle this" is a lookup and not an inference (Hightower's "infer once,
  export, run without inference", applied to the routing itself). The
  Stop hook asks for the entry the moment a turn shows trial and error;
  a check script lints the shape and a ledger counts advised against
  written; the enforcing hooks live in the hooks section below. The
  origin's first entry: read the existing spread before briefing a
  numbers task.
- **The whole-read ledger.** Beyond the 10k rule above, a per-file ledger
  names which files were read whole and the fix each needs; the manager
  sections or splits them unasked. Pictures are priced by pixels, never
  by their bytes.

A lint script guards the core's line and token budgets (the numbers are
under "What guards the shape" above) and keeps the index honest.

The wiki's growth rule is deliberate: files and indexes are nearly free
(disk for you, section-reads for Claude), so the manager's instinct is FIT
the existing home, else FOUND a new topic file and index on the spot, with
scripts that auto-discover new files so growth needs no wiring. Rootstock
is an ever-expanding web by design: ten thousand small files and four
hundred indexes beat one bloated document that taxes every read. The lint
prints the file count; at round milestones the manager mentions it, purely
as good news.

### 2. The Reporting Discipline (REPORTING_METHOD.md)

Anything repeatable becomes a SCRIPT; every result lands in a LEDGER.

- **The Script Rule.** Tests, builds, imports, exports, probes, reports,
  data regeneration: scripted once, changed only to add a capability or
  fix a defect, never re-typed in chat. A compliant runner owns every
  legal run combination and refuses an illegal one quoting the law,
  parses its own pass/fail, exits non-zero on a failure, appends its own
  ledger line (reporting is never a separate step), names the machine, and
  keeps long soak runs out of the default sweep. Scripted work delegates
  as a one-line brief: run the script, report the verdict.
- **The Baseline Rule.** The first act after a runner exists is a FULL
  baseline recorded in its ledger; a regression is then a visible line
  flip, never a memory.
- **Ledgers.** Every run appends one labeled line to a history file: date
  and time, machine (or agent, identified automatically from hostname or
  user path, never typed), project version, what ran, the result,
  and the failures if any. You read the TAIL, never the whole file, and
  runs compare across versions without re-reading anything. The test
  for a new kind of run: a number that matters enough to mention in a
  conversation matters enough to append. A ledger is never pruned: one
  that grows huge starts a dated continuation file with a pointer left
  behind, because the history is the product.
- **Sheets a human opens get a spreadsheet twin.** The CSV and TXT stay
  for grep and git diffs; the .xlsx has a frozen header, thousands
  separators and a bold total per period - because a sheet nobody can
  skim is a sheet nobody reviews, and numbers nobody reviews change
  nothing. When the spreadsheet library is missing the run still writes
  the CSV and TXT and says the .xlsx was skipped; a ledger run never
  crashes over formatting.
- **Trust the ledger.** A green test at an unchanged version is never
  re-run "for confidence"; the runner warns if you try. This one rides in
  the origin project's always-loaded core rather than in the method file:
  it is the ledger rule's flip side, read before every verification.

The usage sheet and its weighted column - the receipts sections earlier
on this page - are the same discipline pointed at the AI bill itself,
with a pair of rules of its own: the transcripts ARE the ledger, so the sheet
regenerates whole instead of appending, and its rows are keyed by machine,
because each machine sees only its own transcripts.

This is not just thrift. On its first day in Everwood, the discipline
caught three real bugs, because scripted runs with ledgered baselines make
regressions impossible to hand-wave.

### 3. The Delegation Company (SUBAGENT_METHOD.md)

Three roles, always: the human is the **CEO**, the Claude you talk to is
the **MANAGER**, and sub-agents are **EMPLOYEES** with fresh, empty,
disposable contexts. Which model manages is the CEO's standing choice,
asked at setup and revisited as models change - never assumed.

- The manager never reads a big unfamiliar file inline (that plants it in
  the expensive context forever). Past the same ~10k line the wiki's
  read diet draws, an employee reads it in a throwaway context and
  returns a short map instead.
- **Who gets what.** An assignments table per project maps task types to
  models, cheapest first: the cheapest model runs tests, search sweeps and
  mechanical batch edits; the middle tier implements from a precise spec,
  drafts doc sections and does first-pass review; the strong tier takes
  multi-file refactors and gnarly bugs with a written plan; design,
  architecture, rulings, verification and pushes never leave the manager.
  Cheap employees run several at once for independent jobs, never two
  writers on one file. And every dispatch names its model in the call:
  a model-less one inherits the manager's own tier, the tier the owner's
  standing rule keeps out of the employee pool (the fixed line below), so
  the brief guard refuses it (v1.40).
- Every brief is STAMPED by the manager (task, date, workstation, model),
  SELF-CONTAINED, and carries a
  budget line: exceed ~30 tool calls or fail the same step twice, and the
  employee stops and reports instead of running up a bill. The report ends
  with the employee's own closing stamp, a second line: model, effort,
  tokens, confidence, the tools it used, the registry entry it matched (or
  the gap it found) and one INTENT line saying what it understood the task
  to be; the manager logs that line as a claim and resolves it once the
  work is verified, and a reported gap is captured in the same batch. The brief also says how to spend turns (v1.43):
  independent reads and checks go in one turn, never one per turn, since
  every extra turn re-reads the employee's whole growing context.
- **How many at once.** A handful of employees per batch (four is the
  habit), never a burst, never an employee that spawns employees. A task
  that seems to need dozens is a design problem - split it, script it,
  or ask the CEO - never a bigger fan-out. A harness hook refuses the runaway shapes outright and
  only the owner tunes its numbers, through `/runaway` (they live in a
  committed `.claude/fanout_limits.json` that survives a graft). A refusal
  is the owner's standing decision: the manager stops and reports what it
  was fanning out and why, never resumes the same loop and never raises a
  limit to get past it. An employee whose
  task seems to need a deletion stops and reports: the preservation law
  binds staff too.
- Employees write files directly and report the diff, never paste bodies.
- **The fabrication check.** Claims must match the diff, and the stamp's
  tool count must match the harness meter: a claimed read or run with a
  metered tool count of zero was invented. This is not hypothetical: the
  check exists because a delegated audit once "classified" a file it
  never opened (93k tokens of fiction, caught for about 2k because the
  meter said zero).
- **The truthfulness hooks** (v1.30) make the mechanical parts of that
  mechanical: a work brief missing its required lines is refused at
  dispatch; the moment a result lands, a hook reads the harness-metered
  figures (the numbers no model can fake), flags a zero-call "success"
  or a tool count claimed at several times the meter, and appends one
  pending line per delegation; a Stop hook (its tag: LEDGER ADVISED) then refuses to end the turn
  while a delegation sits unverified and unledgered. What stays
  judgment - whether the diff matches the claims - stays audited
  through the ledgers instead.
- **Verify cheaply, in order.** Tests or probes first, a spot-read of the
  diff second, a full read only when those smell wrong: the manager's
  check never costs more than the task did.
- **Attribution.** Every idea and change of plan is attributed and dated,
  so a mistake traces to its maker. When the CEO asks for something that
  contradicts a rule they set earlier, the manager flags the
  contradiction and confirms before building - never silently comply,
  never silently refuse.
- **The scorecard.** An append-only performance ledger tracks every
  employee task (who delegated, task type, model and effort, metered
  tokens, outcome) with correction tallies. The escalation rule: when a
  task type's corrections pass ~25% of its last ~10 tasks, that task type
  is promoted to a stronger model, with a dated line saying so. The
  assignment itself is the manager's (v1.37): any task type may drop a
  tier on trial without asking, and the rate moves it back up (a trial
  is ledgered with "trial" in its line, so the rate counts it); the only
  fixed line is the owner's choice for their project (in the origin
  project the top model is never an employee, to save tokens). Catches -
  real problems an employee flagged that everyone else missed - are
  tallied too, the strongest signal a tier earns its keep. Models
  move on data, not impressions.

The manager keeps design, laws, architecture, verification, and pushes.

### 4. Lossless Sessions (the rituals, packaged as skills)

The endgame: you can clear your chat at any checkpoint and lose NOTHING,
because context lives in files, not in the conversation.

- **The Daily Log.** Each work day gets a file: the CEO's asks, the
  completions, and a WHERE WE LEFT OFF section carrying both sides of the
  final exchange (your last prompt AND the manager's last response).
- **The Checkpoint Protocol.** A counter ticks whenever a reply actually
  changed the tree or the commit (a pure question never ticks) and warns
  at 8 tasks (dire at 15: the Stop hook then refuses to end the turn
  once) or when less than 80% of the context budget
  remains (urgent under 30%); ADVISED MEANS DO IT, so the owner never has to ask - and since
  v1.31 THE HOOK LAW: every line a hook prints that names work (a
  checkpoint, a lesson, a kit sync, a changelog export) is an order the
  manager carries out inside that reply, worded as such, never a note
  relayed for the owner to act on; the same warning seen twice is the
  failure; and since v1.34 the SOURCE is closed too: a reply that names
  a checkpoint as the natural next step has just ordered one, and the
  Stop hook refuses the reply once until it ends with the safe-to-clear
  marker (naming a checkpoint is making it). Under 30% of the context
  budget the checkpoint is urgent and comes before any new work. At an
  arc's end the manager runs the session loop, then asks two questions
  before pushing: was anything this arc done by hand twice (then it is a
  process-registry entry, the loop law), and was anything learned by
  trial and error or corrected (then it is a lesson, the lesson law);
  then pushes, refreshes the day file, and emits the marker:
  "CHECKPOINT - safe to /clear. Nothing in this chat exists only in this
  chat." It refuses with an employee running or work uncommitted. A
  checkpoint is where the method learns, not only where it saves.
- **The proposal law (v1.35).** A standup proposal is a source of the
  same kind as a named checkpoint: a reply that names a [DO] proposal
  its ledger still raises is refused once until the proposal is done
  (PROPOSAL NAMED); only an [ASK] proposal is a question for the owner.
- **The net under it (v1.28).** A session end (/clear, a closed window)
  runs a hook that checks for unbanked work. Nothing unbanked: one ledger
  line. Otherwise it banks the bytes itself - both sides of the final
  exchange from the transcript into the day file as an AUTO section, a
  commit, a push to origin and to the local mirror, the counter reset -
  so a forgotten checkpoint loses nothing. The manager still writes the
  judgment (state, open queue, next likely) at the next real one.
- **Standup.** Every fresh session opens with one script that prints the
  last exchange (mined verbatim from the harness transcript on disk, so
  it survives a mid-arc /clear), the state, ledger tails, the open roadmap, and THE BUDGET:
  yesterday's and today's weighted spend judged against the previous seven
  active days, with the reason when something went wrong. In the origin
  project's measurements, a cleared session re-arms in about 15-20k
  tokens instead of dragging hundreds of thousands.

Nine rituals ship as Claude Code skills, invocable as slash commands:
`/standup`, `/checkpoint`, `/ship`, `/brief`, `/runaway`, `/preserve`,
`/intent`, `/correct`, and `/flag`. `/preserve` is the preservation law's
front (retire a file, shelve a wiki section, or walk the twice-acknowledged
delete grant, in that order); `/flag` is the purpose audit (green, yellow
or red, filed in FLAGS.md); `/intent` records the why of a ruling in the
owner's words; `/correct` walks a correction, asks for the intent, then
makes the fix and logs it;
`/runaway` shows and tunes the fan-out guard's numbers, owner only;
`/brief` composes an employee's work order by the delegation laws. `/ship`
is the one you will use most: sanity-check tests (trusting the ledger),
ask the security question (did this diff touch secrets, env, auth,
headers, CORS, hosting or database rules? then the audit runs first;
v1.39), read the scripted version hint (none, patch or minor from what changed
since the last bump; never major) and bump if warranted, commit with a
player-readable subject, push, push again to the local mirror, run
the build script without deleting old builds, sync the kit if kit files
changed, and export the changelog unprompted; the checkpoint counter
ticks itself and is never ticked by hand.

### The hooks: laws the harness enforces itself (HOOKS_METHOD.md)

A skill runs when invoked; a hook runs when the harness reaches a moment.
Anything a law can enforce mechanically becomes a hook, not a longer
reminder. Fifteen ship in `hooks/`, wired by one settings file:

- **Session start** (startup, resume, /clear and after a compaction)
  injects the standup digest by itself - after a /clear
  the manager has everything back before anyone types a word. Two more
  lines print when they apply: KIT UNSYNCED at the prompt (the kit copies
  and the public mirror disagree) and CHANGELOG UNEXPORTED at the reply.
- **Every prompt** carries a silent context gauge that speaks only when a
  threshold is crossed, and since v1.33 the ROUTE line: the registry
  entries and reference tools the prompt already hits, named before the
  first tool call, and since v1.40 the live usage window: last five hours
  against the worst five hours of the last seven days, spoken only when
  the window is already most of the peak and ledgered when it speaks;
  **every reply** ticks the checkpoint counter when
  work actually happened, and refuses to end the turn once it is dire.
- **Before compaction** a ledger line records what was at stake.
- **Session end** is the checkpoint's net (v1.28): with nothing unbanked
  it writes one ledger line; with unbanked work it mines the final
  exchange from the transcript into the day file, commits, pushes to
  origin and the local mirror, and resets the counter.
- **The lesson advisor** reads each finished turn for trial and error -
  the same command run again after an error, repeated edit misses, a
  FAIL followed by a PASS, a claim resolved DIFFERENT, an employee
  briefed twice, a prompt that reads as a correction - and refuses to end
  the turn once with LESSON ADVISED, so the lesson lands in LESSONS.md
  before the arc moves on. Never the same turn twice; a turn that wrote
  the lesson passes. The same hook holds the manager to its own words:
  a reply that names a checkpoint as due without banking one, or names
  a standup [DO] proposal the trend script still raises, is refused once
  (v1.34, v1.35). The prompt gauge carries the other end: a prompt
  whose words hit an entry's Keys line gets that entry named before the
  first tool call.
- **The shell guard** refuses what the CEO's laws forbid (no force push, no
  skipped hooks, plus the project's own rules). Beside it, at zero runtime
  cost, the kit settings file's permissions.deny block (v1.40) refuses a
  Read or Edit of .env files, key material and credential folders, and
  the destructive shell one-liners.
- **The fan-out guard** is catastrophe-only: it refuses a burst or flood of
  sub-agent spawns or runaway token velocity - each self-clearing - and
  warns on the rest. It exists because a manager once spawned 821 agents
  on "check my markdown files". The default numbers: 8 spawns in a
  minute, 25 in ten, or 10M weighted tokens in two minutes. The CEO tunes
  them with `/runaway`; the manager never raises one on its own.
- **The diet guard** says a file's size before a whole read past ~10k
  tokens and the missing limiter on a chatty command, at the moment of
  the decision; the first whole read of a big file per file per session
  is refused with the file's own index in the refusal, and the same call
  repeated passes; since v1.40 a later whole read of that file, unchanged
  since, is refused once more as already in context (the re-read rule,
  cleared by compaction).
- **The preserve guard** refuses delete verbs (bare names, pipelines and
  the mirror verbs included), work-discarding git verbs (every force
  push included) and deletion calls written into scripts, and reads
  every script a command executes before it runs - the whole file when
  git does not track it, only the uncommitted added lines when it does -
  refusing one that deletes. The session scratchpad and prose
  files pass; one command passes per delete grant the owner acknowledged
  twice. A drive root, the home folder, the repo root, any .git folder,
  a bare wildcard, a `..` climb or a variable target pass never, and a crash in the guard fails closed.
- **The hygiene guard** runs AFTER every file edit and says the law that
  applies to that file: refresh the kit copy (and this README) when a
  portable original changes, add the missing See-also line to a wiki
  section, fix a forbidden character in player-facing text (the only one of
  its rules that blocks), run the engine import after a new asset. It exists because
  this README once fell two versions behind while the law to refresh it
  was already written.
- **The delegation truth set** (v1.30, a trio) watches the Agent
  tool itself: the brief guard refuses a work dispatch whose brief lacks
  the stamp template, the intent line, the budget line or the
  preservation line, and since v1.40 one whose model is missing (which
  silently inherits the manager's own tier) or names that tier outright;
  the delegation auditor reads the metered tool and
  token figures out of every result, names a fabricated report (zero
  metered calls) or an inflated tool count, and appends a pending
  ledger line, and since v1.42 it also runs at the employee's own stop:
  it counts the employee's transcript (a background employee's result
  is only a launch notice, so this is the only meter there is), holds
  the employee once when its self-reported tool count is under 70% of
  the truth by three calls or more (the floor is owner-tuned in
  `.claude/fanout_limits.json`) or its template lines are missing, and
  ledgers the true figures as a METER line in
  `docs/history/delegation_pending.txt`, where every delegation lands as
  PENDING and clears with an appended RESOLVED line, never an edit; the verify advisor refuses to end a turn while a
  delegation is pending without a resolution line. It exists because of
  a public case where a manager said its sub-agents did their job when
  they had not.
- **The format guard** runs BEFORE an edit of the settings file and
  refuses one that would unwire, narrow or mis-point a safety hook (or
  not parse), and AFTER every edit of a kit thing, blocking one that
  leaves the thing without its header (PURPOSE, INTENT, search keys, see
  also) with the rewrite command in the reason. Two more hooks back it
  up: the shell guard refuses shell writes into a settings file, and the
  Stop hook refuses to end a turn while the live wiring is broken, so no
  prompt, brief or contributed patch switches a guard off quietly. It exists because a community kit
  needs a guardrail that does not depend on the reader's good faith.

The contract, plainly, because a worried reader asks these first:

- **Hooks need Claude Code.** They are wired through `.claude/settings.json`,
  which is Claude Code's mechanism. In another client (the Claude app,
  Cowork, an IDE plugin) the laws are prose again; the wiki and the
  rituals still work, the enforcement does not.
- **A hook cannot trap you.** Each Stop hook refuses to end a turn at
  most once per crossing (the checkpoint counter re-blocks only every
  five further tasks; the advisors never repeat the same slice or set),
  and each checks the harness's own loop flag so it can never refuse
  forever. Every other
  refusal is one command, with the reason printed; the next command runs.
- **A broken hook CAN lock you out**, which is the one real hazard: a
  hook that exits with the blocking code (a mis-typed path, a missing
  interpreter) refuses every tool call, not just the one it meant to
  guard. The fix is one line in settings.json; every kit hook answers
  `--selftest` and is tested by piping a fake event into it before it is
  wired. A selftest proves the cases its author imagined; since v1.40 the
  guard replay (`guard_replay.py`) runs the last N days of recorded tool
  calls, employee sessions included, through the guards' judge functions
  in a sandbox and prints per rule what would be refused now, what was
  refused live, the NEW catches and the LOST ones - read the LOST column
  before trusting a guard change.
- **Turning one off** is removing its line from settings.json, for every
  hook outside the safety tier (eleven of them, named by the format lint's
  SAFETY table: the preserve, shell, fan-out, diet, hygiene, format and
  brief guards, the delegation auditor, the verify advisor, the Stop tick
  and the session-end net); unwiring a safety hook is exactly the
  edit the format guard refuses.
- **Installing them** is the hooks README's short walk: copy the scripts,
  fill the shell guard's PROJECT RULES, merge `settings.json` into yours,
  gitignore the state files, run every `--selftest`. The safety wiring is
  the one edit only the CEO approves. No hook keeps
  state a project must migrate: the gitignored state files age out on
  their own.
- **Cost.** Tokens: none (a hook is a script; only its one-line verdict
  enters the context). Time: one interpreter launch per trigger, about
  0.3 seconds, and a shell command runs four of them in a row.
- **What is not built yet.** On the pin board: a notification hook that
  toasts the OS when the manager is waiting on you; it ships when the
  CEO asks. The second idea on that board, a hook refusing an employee's
  report when its stamp is missing, was deferred when the truthfulness
  set landed and then built in v1.42 as part of the auditor's stop-time
  branch: a report without its template lines is held once.

### The intent loop (INTENT_METHOD.md)

A rule tells Claude what to do; the reason tells it what to do in the
case the rule never named. So every ruling gets a section in the
project's INTENT.md: the owner's ask verbatim, the owner's numbered
reasons verbatim, the manager's reading marked as the manager's, and
where the rule lives. Before building, the manager logs its OWN reading
of the ask; employees state theirs in a stamp line. When the owner's
intent is known, the claim resolves SAME, SIMILAR or DIFFERENT, with its
source named (stated, revealed by a correction, or inferred, which is
counted apart so it never inflates the rate). A small toolchain backs it - an
intent log, a correction log, a report script, a systems audit - and the
report turns that log into day, week and month agreement rates per
actor, a text file for Claude and a csv with a spreadsheet twin for you,
and calls the trend improving, steady or declining. The owner's reason, in the owner's words: real data, past
against present, and a trend that says whether the feedback loop works.
One ordering law rides with the audits - security first, then cost, then
efficiency: a number behind a REFUSAL stays in code; a number behind a
PROPOSAL may live in a tunable data file. The fan-out guard's numbers
are the ruled exception, the owner's by name, tuned through `/runaway`.

`/correct` closes the loop from the other side: it asks what about the
last thing needs correcting, records your words verbatim, marks the
claim DIFFERENT, then asks "What was the intent?" and `/intent` files
the why while the mismatch is fresh. A systems audit, ledgered and
proposed on a cadence, has read-only employees look at tokens, process,
knowledge and shipped features and return proposals only. No employee
applies anything; since v1.35 the manager does every standup [DO]
proposal in the reply that reads it (the systems audit's own included,
with the README audit, the digest trim, a stale loop group, dead
links, an unwritten lesson, a stale claim) and relays only the [ASK]
ones; the audit itself runs in the reply whose standup proposed it.

The first systems audit ran on 2026-09-14 (kit v1.21; the night of the
13th's session, ledgered after midnight). Four read-only
employees returned 26 proposals; the owner ruled on every one. What it
found and what changed: habitual scripts were being run by hand and their
ledgers drifted, so THE LOOP LAW now holds (a script that runs more than
once is called by the parent loop, `reference tools/run_all.py`, which
ledgers every group run; the session-start hook runs the session group
once a day; standup shows each group's age; ledger trends proposes when
one goes stale). Four check scripts re-appended identical rows at an
unchanged tree, so they share a trust-the-ledger helper. Three ledgers
the preservation law promised had never been born, so the movers got
selftests and the ledgers exist. Open questions to the owner now have
their own ledger with an age nudge. The standup digest's size, a per-arc
cost line and a cache-miss ledger with causes are measured, not guessed.

### The format law and the purpose audit (CONTRIBUTING.md)

Two guardrails for a kit that is meant to take contributions, ours or
yours:

- **The format law.** Every thing in the kit (a script, a hook, a skill,
  a method file, the hooks README, the front door itself) carries one
  header: `PURPOSE:` (what it
  does, plainly), `INTENT:` (why it exists, in the words of whoever asked
  for it), search keys and see-also links. A lint derives the scope from
  the kit folder itself, names every thing that lacks the header, and
  the publish script refuses to push on a failure. A missing header is
  added BY SCRIPT after a read-only look (`format_lint.py --rewrite`
  inserts only the missing lines), never by hand. The format guard hook
  above makes it a law rather than a reminder.
- **The purpose audit.** Before an update merges, and whenever a thing is
  unflagged or has changed since its last flag, a Claude (or a person)
  reads it, compares what its PURPOSE line says against what the body
  does, and flags it: GREEN does what it says and nothing more; YELLOW
  matches in substance but something is off (fix later, may ship); RED
  does what its purpose does not say or crosses a law (deletes, disables
  a guard, unbounded spend, routes around a refusal) and the owner sees
  it before it ships. The
  ritual is read-only, then flag, then explain: the auditor never edits
  the thing in the audit turn. `FLAGS.md` is the one committed file that
  references every flag, hashed to the exact version reviewed, tallied at
  the top, and open to any reviewer's findings by pull request. The
  tally's stamp moves only when a flag moves, never on a no-change run,
  so the mirror check never warns over noise. A thing with no PURPOSE
  line cannot be GREEN. `/flag`
  walks the ritual; `purpose_audit.py --pending` lists what needs one.
  The kit's own first audit (v1.19) flagged 58 things: 53 green, 5
  yellow, 0 red. v1.20 closed all five the next morning, one of them by
  the first independent read of the front door, which found the header
  undersold what the file installs and the skill list gone stale. Three
  author passes had missed both.

`CONTRIBUTING.md` carries both laws in full, plus what a contributed
update looks like (the header, the graft-log entry, a passing lint, a
flag from someone other than the author when possible, nothing deleted, no em or en
dashes).

### The two companions (WORKFLOW_METHOD.md, WORKSTATION_METHOD.md)

Two smaller disciplines ride with the pillars. Neither saves tokens
directly; both stop a kind of amnesia.

- **The process registry.** A project accumulates multi-step processes
  (the ship order, an art pipeline, a retune round-trip) that nobody
  writes down, so the sequence is re-derived from memory or a vanished
  chat, and a step gets skipped. WORKFLOWS.md holds ONE runbook entry per
  repeatable process: WHEN it applies, the STEPS with the scripts named,
  how to VERIFY. The capture rule: whoever performs such a task checks
  the registry first; a stale entry is a bug fixed in the same batch; a
  missing entry is a gap the manager files in the same batch, or hands to
  the cheapest model as transcription work. Employees never edit it; they
  report gaps on their stamp line. Since v1.37 a script (`law_gaps.py`)
  reads the rule's shadow too: a tool changed in 30 days that no
  registry entry, loop group, hook setting or skill names is a WARN line
  at standup.
- **The workstation inventory.** One document listing every package,
  tool, path and setting the project's scripts and hooks depend on, split
  REQUIRED and OPTIONAL, with the need, the why, and the install command
  for each (WORKSTATION.md), the harness's own settings included (user
  level, project level, what is per-machine and gitignored), plus a
  survey script
  (`workstation_survey.py`) that proves a machine up to par. A second
  machine, a reinstall or a collaborator sets up from a document instead
  of from error messages. The rule: a new dependency goes into the
  inventory and the survey in the same batch that introduced it.

## What it saves, concretely

| Habit it replaces | Rootstock way | The saving |
|---|---|---|
| Reading files wholesale | Grep headings, read one section | A 50k read becomes ~1-2k |
| Re-explaining project state each session | Standup digest from ledgers | 5-10x smaller session opens |
| Marathon sessions that get pricier every turn | Checkpoint + /clear, losslessly | Later turns cost a fraction |
| The manager reading big files | Employee distills in a throwaway context | ~50k permanent becomes ~1k |
| Re-running green tests "to be sure" | Trust the ledger (runner enforces it) | Whole probe runs, skipped |
| Runaway agent loops | Budget line in every brief, plus the fan-out guard | Partial report instead of a bill |
| Reading a 24k-token file inline | The diet guard says the size first; section-read or delegate | ~30k weighted becomes ~3k, and it stops riding every later turn |
| Cost numbers with no baseline | The daily line judges each day against the previous seven | Waste gets a name the next morning |
| A screenshot counted as a 100k read | Pictures priced by pixels | Diet proposals aimed at real habits, not phantom ones |
| A deleted file, a wiped tree | Retire, shelve, or ask twice | Knowledge never lost; a bad script cannot cost a folder |
| Laws forgotten mid-batch | The hygiene guard speaks at the edit | The kit copy and this README stay in step by themselves |

The unglamorous truth this kit encodes: there is no magic compression
trick. The savings come from structure, scripts, and discipline. (The kit's
origin project evaluated the viral "let the AI invent its own compressed
language" idea and declined it with receipts; prompts are under 1% of
session cost. Structure is where the money is.)

## What you need (and what still works without it)

The FULL kit assumes three things: **git**, **Python 3**, and **Claude
Code** (the skills install into `.claude/skills/`; the standup
last-exchange replay and the usage sheet mine Claude Code's local
transcripts in `~/.claude/projects/`). The reference scripts come from the
origin project and degrade gracefully rather than crash, but they are
meant to be adapted - version strings, ledger names, and paths are
per-project.

Missing a prerequisite is fine, and the front door knows what to do about
it: no git means the push/update machinery is skipped while day files,
ledgers, the wiki, and the sub-agent brief rules all still work; no Claude
Code means the skills and transcript miners are skipped and the checkpoint
writes the exchange into the day file by hand. Every skip is recorded in
the install stamp itself, so a later update knows what was never
installed. And the methods are worth taking a la
carte - the day-file ritual, the append-only ledgers, and the brief rules
(stamped, self-contained, budgeted, claims-must-match-the-diff) each stand
alone. An honest partial install beats a pretend full one.

**Installing into an existing project?** The front door's BROWNFIELD RULE
applies: Claude inventories what you already have (your own split
knowledge files and logging scripts count as installed pieces), proposes a
mapping, and gets your approval before touching any existing file - a
production-sensitive file needs a go-ahead naming it, not a general
yes. It never restructures a live repo unasked.

## Quick start

1. Open Claude Code at the root of YOUR project's repo and give it this
   repo's contents (a clone beside it, or the folder copied in; the method
   files end up at your repo root, the domain notes under `reference/`).
   Any capable model; one long session.
2. Say: **read "0 - READ ME FIRST.md" and install the kit.**
3. Answer its STEP 0 questions: project, engine and repo; who manages and
   which employee models are available; one workstation or several; which
   domain-notes files apply; and your update policy (ask, auto, relevant
   or never).
4. Claude builds the operating system in order: the wiki (and the process
   registry the day the first two-step process exists), reporting, the
   session rituals and the workstation inventory, delegation, skills,
   hooks (the one step with human parts: you approve the safety wiring,
   and every hook's `--selftest` must pass), then the loops that measure
   the loop: the learning loop, the
   intent loop, the format law and purpose audit, the README gate, the
   lesson loop, and the route line beside it. Last, the optional boards
   (ideas, roadmap, changelog) and, if the project has a backend, a key,
   an env file, a database or accounts, the security audit's bootstrap
   before the first public release; a project with none writes its
   exemption and moves on.
5. It finishes with a definition of done you can verify yourself: the
   standup script runs clean, the core lint passes (CLAUDE.md under
   Anthropic's 200-line target and its token budget, every rule declared
   by path, the master index complete - the lint keeps all of it true),
   the format lint passes, every hook answers its `--selftest`, FLAGS.md
   flags every kit thing,
   the delegation ledger has one real line, the skills answer to their
   slash commands, and the first commit is in.

That is the whole handoff. The front-door file exists precisely so that a
stranger's Claude needs no other instructions. The front door is an
install runbook read once (~1.8k tokens); it is not a CLAUDE.md and never
loads per session.

## Updating an installed project

Rootstock keeps growing, but an installed project must NEVER be updated by
copying newer kit files over it. An install is an adaptation: Claude
renamed paths, tailored the core file, and your project has since grown its
own knowledge into those files - overwriting them would destroy the very
thing the system protects. So the kit updates CONCEPTS, not files:

- The kit is versioned, and `UPGRADES.md` is its **graft log**: one entry
  per concept added, each with WHAT it is, which kit files CARRY it, how
  to GRAFT it onto an existing install, and, from v1.17 on, which README
  section it touched (so a concept cannot ship without deciding whether
  this page needs to know).
- This page is checked, not trusted. A parity lint derives every count on
  it (laws, skills, hooks, scripts, the box table, the version line) from
  the kit's own files, and the kit's publish script refuses to push while
  any of them disagree. A ledgered README audit cadence (distinct from
  the purpose audit below) proposes a fresh
  cross-reference (four read-only employees, one lane each, reading every
  method file against this page) once the kit has taken more commits or
  days than the owner's thresholds allow since the last one; the trend
  script prints how far past those thresholds the kit sits.
- Installing stamps a line into the project's CLAUDE.md:
  `Rootstock vX.Y installed <date> | updates: <policy>`, with any skipped
  prerequisite recorded on the same line (`| no-git`). An install that
  predates versioning counts as v1.0, and the first update after that
  adds the stamp line as it bumps.
- To update: pull this repo (or hand Claude the new folder) and ask
  Claude to update the kit (any wording; **update rootstock** is enough). Claude reads the graft log's entries newer than
  the project's stamp, applies each concept to the project's OWN files in
  its own names and voice, bumps the stamp and ships the batch: one graft
  batch per update, recorded in the project's own changelog. The one exception to
  never-copy: a file the project does not have at all (a genuinely new
  MD or reference script) is copied in fresh, then adapted and indexed. Anything that would
  contradict a choice you made on purpose gets flagged, never overwritten.
- You don't have to remember any of this: the install wires
  `rootstock_update_check.py` into your project's standup, which checks
  this repo weekly (offline-safe, one ledger line per check) and reports
  newer grafts by itself. What it does on the network: one HTTPS fetch of
  this repo's UPGRADES.md, at most once a week, or a read of a local clone
  if you point it at one. It sends nothing about your project anywhere.
- **You choose the noise level.** The stamp carries your update policy -
  `ask` (default: present the grafts, you pick), `auto` (apply everything,
  report after), `relevant` (only offer grafts that benefit your project;
  skipped ones are never re-offered), or `never` (quiet unless you ask).
  Change it any time by telling Claude "update automatically", "stop
  asking about updates", or "only show me relevant updates".

## Questions people ask

- **Does it need Claude Code?** For the full kit, yes. What carries to
  other clients (the Claude app, Cowork, Cursor, the API): the wiki
  carries fully, it is plain markdown any model can read if the client's
  project instructions point at the front door; the day files, ledgers
  and brief rules carry as method; the skills carry where the client runs
  skills, though ours shell out to Python; the hooks do not carry at all.
- **Isn't a 5k-token CLAUDE.md the opposite of lean?** It would be, and it
  is not one: the file a reader measured was the install runbook, since
  renamed ("0 - READ ME FIRST.md") so the name cannot mislead. The
  per-session CLAUDE.md Rootstock builds is a pointer core: one pointer to
  the master index, the laws no hook enforces, and the process every
  session needs, budgeted in tokens by a lint that fails and never raises,
  with a script that moves cold sections out. See "The installed
  CLAUDE.md: what it holds and how big it is" above.
- **How big is the CLAUDE.md this actually installs?** Anthropic's own
  guidance targets under 200 lines per CLAUDE.md file; it gives no token
  figure. The 1,000-token number that circulates online is a community
  estimate, not Anthropic's. The origin project's installed core is 68
  lines, about 900 tokens, guarded by a lint that fails past 2,000 tokens
  or 200 lines and warns past 1,500 tokens (v1.37; it warned at 1,000
  until the warning fired every session with nothing left to move).
- **Does it improve my prompts?** No, and that is the point. It moves
  the CONTEXT (wiki, ledgers, day files) and the INTERPRETATION (laws,
  hooks, the process registry) out of the prompt and into files read
  every session. A miss gets filed once as a ruling, a memory or a hook
  instead of being rephrased into every prompt after it; and because a
  fresh session is free, a lazy one-line prompt still lands.
- **Does it work with models other than Claude?** The methods are model
  agnostic and the front door makes Claude ASK who manages rather than
  assume. The skills and hooks are Claude Code mechanisms.
- **Is anything sent anywhere?** No. Everything is local files and git.
  The only network calls are the optional weekly fetch of this repo's
  graft log and, when you run the security audit with `--url`, plain
  requests to your own deployment to read its headers; nothing about your
  project leaves your machine.
- **Can I take part of it?** Yes; see "What you need" above. The wiki
  conventions alone are the biggest single saving.
- **Can I use it commercially?** MIT. Yes.
- **Can I drive it from my phone?** Yes, through Claude Code's Remote
  Control: `/remote-control` (alias `/rc`) in a running session prints a
  QR code, the
  Claude app's Code tab scans it, and the phone becomes a second keyboard
  for that SAME session, with its files, tools and hooks. The workstation
  stays on. A checkpoint `/clear` resets the phone's view too and needs
  no re-pairing. Whether a `/clear` typed on the phone fires the
  session-start hook is not stated in Anthropic's docs; the kit records
  it as unconfirmed until one clear from the phone prints the standup
  digest. It needs a Pro, Max, Team or Enterprise login; an API key
  alone, Bedrock, Vertex, Foundry or a custom base URL rule it out. When
  the workstation must go off, a cloud session (claude.ai/code) clones
  the remote and runs on Anthropic's machines, without the engine, hooks
  or test runners, so it suits reading and planning, not building.
  `WORKSTATION_METHOD.md` "Drive a session from a phone" has the
  requirements and limits.
- **Does it check the app I build, or only my process?** Both, since
  v1.39. Everything above audits the process. `SECURITY_METHOD.md`
  audits the app: before the first public release (a URL, a store
  listing, a showcase post), and before any release
  that touched secrets, env files, auth, headers, CORS, hosting or
  database rules, the checklist runs and a ledger line says PASS. It
  exists because a survey of 100 AI-built apps found 37 shipping a
  server-side secret in their frontend JavaScript and 78 missing a
  security header, mostly an env variable renamed `VITE_` or
  `NEXT_PUBLIC_` to silence a build error. The script half
  (`security_audit.py`) greps a build for secret shapes and reads your
  own site's headers, exposed paths and CORS answer, read-only; the
  judgment half (database rules, auth per route) is a checklist an
  employee walks. A key that was ever public is rotated, never merely
  removed.
- **Can I contribute?** Yes, by pull request, under two guardrails that
  apply to the kit's own authors too: every new or changed thing carries
  the header (`PURPOSE:`, `INTENT:`, search keys, see also) or the lint
  refuses it, and every changed thing gets a read-only purpose audit
  (GREEN / YELLOW / RED) filed in `FLAGS.md`, ideally by someone other
  than its author. `CONTRIBUTING.md` has the whole of it. A RED is a
  question for the maintainer, not a rejection.

## What is in the box

| File | What it is |
|---|---|
| `0 - READ ME FIRST.md` | The front door: an install runbook read once (STEP 0 questions, the install order as pointers, definition of done); not a CLAUDE.md |
| `WIKI_METHOD.md` | The knowledge wiki: token mechanics, conventions, bootstrap |
| `LESSONS.md` | The one-right-way book: the lesson law, the entry shape, and the origin's first entries; grepped before any task, fed by the lesson advisor hook |
| `REPORTING_METHOD.md` | Scripts + ledgers: the three rules, runner spec, bootstrap |
| `SUBAGENT_METHOD.md` | The delegation company: org chart, seven laws, assignments table, scorecard, bootstrap |
| `SKILLS.md` | The skills shelf: what each ritual-skill does and the skills rule |
| `skills/` | The nine skills, ready to drop into `.claude/skills/` |
| `rules/` | The first path-scoped rule, `wiki.md`: drop into `.claude/rules/`, loads only when Claude reads a markdown file; write your own game and text rules beside it |
| `HOOKS_METHOD.md` | The hooks: the contract, the fifteen kit hooks, tiers, bootstrap |
| `hooks/` | The fifteen hook scripts and `_hooklib.py`, the shared library they import (drop into `tools/hooks/`), `README.txt` with the per-hook setup steps, plus the settings template (merge into `.claude/settings.json`; since v1.40 it carries a permissions.deny block: destructive shell shapes and Read/Edit of .env files, key material and credentials) |
| `WORKFLOW_METHOD.md` | The process registry: one runbook entry per repeatable task, the capture rule |
| `WORKSTATION_METHOD.md` | The machine inventory: document, survey script, new-machine runbook |
| `INTENT_METHOD.md` | The intent loop: the why file in the owner's words, the claim-and-verdict ledger, the correction ritual, the agreement report, the systems audit, bootstrap |
| `SECURITY_METHOD.md` | The pre-production security audit: the gate before an app, SaaS or site with a backend, a key, an env file or user data goes public; the rotation law, the prefix law, the nine-class checklist (secrets in the client, headers, exposed files, CORS, database rules, auth per route, dependencies, logs, the game-export note), the ledger line, the workflow entry, bootstrap |
| `reference tools/` | 35 working scripts to adapt, not rewrite (`_ledger.py` among them, the ledger helper the rest share). Day one: standup, checkpoint, core lint with a token budget, usage sheet (weighted, with the daily line and the per-arc line), update check, the parent loop (run_all, the loop ledger). Adopt when wanted: tag index, workstation survey, the learning loop (link checker, heat map, ledger trends, big reads), the preservation movers (retire, cold shelf, delete grant), the README gate (parity lint, audit ledger), the intent loop (intent log, correction ledger, intent report, systems audit ledger, open questions), the format law and the purpose audit (format lint, purpose audit, kit refresh), the core diet (core_diet.py, the hot core's mover), trust the ledger for the check scripts, the lesson loop (lesson_log.py: the prompt match, the trial-and-error scan, the lint), the route line (route_index.py: the registry entry and the script a prompt already has, named before the first tool call), the local mirror (backup_push.py: every branch and tag to a bare repo on another drive), the law ledgers (law_gaps.py: the archive sweep and the workflow-rule proxy, WARN lines in the check group), the ship-time version hint (version_hint.py: none, patch or minor from what changed since the last bump; never major), the pre-production security audit (security_audit.py: secret shapes in a build folder, the security headers, the exposed-file paths and the CORS answer of your own deployment, read-only, with a ledger line), the live usage window (usage_window.py: last five hours against the seven-day peak, spoken by the prompt gauge only when it matters, each spoken reading ledgered), the guard replay (guard_replay.py: the guards' judge functions run over the last N days of recorded tool calls, employee sessions included, with the NEW and LOST columns and a ledger line) |
| `UPGRADES.md` | The graft log: kit version + how updates apply to installed projects |
| `CONTRIBUTING.md` | The format law and the purpose audit: the one header every thing carries, the read-only flag ritual, what a contributed update looks like |
| `FLAGS.md` | The flag ledger: every kit thing's latest GREEN / YELLOW / RED, hashed to the version reviewed, tallied, append-only |
| `GODOT_FIELD_NOTES.md` | Domain example: hard-won Godot engine lessons (skip if not Godot) |
| `CLICKER_DESIGN_NOTES.md` | Domain example: idle/clicker genre lessons (skip if not that genre) |

The two domain files double as templates for what YOUR project's
engine-notes and genre-notes files should grow into.

## Origin

Every rule in this kit was paid for in Everwood: the fabrication check
exists because a fabricated report happened; the budget line exists because
runaway loops happened; the keep-old-builds law exists because a deleted
zip cost a dev-log comparison. Nothing here is theoretical. The kit is
model-agnostic by design; in a new project, Claude is required to ASK who
manages rather than assume.

Built by **Mazhron (Travis Rhoda)** with Claude.
Watch the game it grew from: Everwood, on [YouTube @Mazhron](https://www.youtube.com/@Mazhron).
Play it before it launches: [Everwood on itch.io](https://mazhron.itch.io/everwood).

## License

MIT. Take it, graft it, grow something.
```

### `REPORTING_METHOD.md`

- Source: `REPORTING_METHOD.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 11403
- SHA-256: `96a36a6dbaa904d5e0be32affa000751759e044dfe3751c7f4c3d5cbb0e676d8`

```text
# The Reporting Method (portable: scripted runs + history ledgers, for any project)

PURPOSE: A portable method for scripted runs and history ledgers: every
  repeatable run is a script, every run appends one labeled line to an
  append-only ledger, and a recorded baseline lets a regression show up as a
  single line flip between two ledger lines.
INTENT: Ad-hoc runs are amnesia: a test retyped by hand cannot be compared
  run to run, silently skips what someone forgot, and its result vanishes
  into a chat log nobody re-reads, so regressions can survive for weeks
  unnoticed.

PORTABLE FILE: an architecture, not a project. Hand it to any Claude (or any
capable agent) at the start of any project alongside its siblings
(SUBAGENT_METHOD.md, WIKI_METHOD.md) and say "set this up". Nothing here
assumes a game, a language, or a test framework.

THE PROBLEM IT KILLS: ad-hoc runs are amnesia. A test typed by hand today and
retyped slightly differently tomorrow cannot be compared, cannot be delegated
cheaply, silently skips what someone forgot, and its results vanish into a
chat log nobody re-reads. Regressions then survive for WEEKS because nothing
ever says "this passed last Tuesday and fails today."

## The three rules

1. THE SCRIPT RULE. Anything repeatable - tests, builds, imports, exports,
   probes, reports, data regeneration - is a SCRIPT in the repo, and the
   script is the ONLY way that thing is ever run. Scripts are changed only to
   ADD a capability or FIX a defect; commands are never retyped in chat, in
   notes, or in a sub-agent's brief. If a human or an AI "just runs it by
   hand this once," that is the defect - script it.
2. THE LEDGER RULE. Every scripted run APPENDS exactly one labeled line to an
   append-only history file (a docs/history/ directory of plain .txt ledgers,
   one per kind of run). The line carries: date+time | which machine/agent |
   the project version | what ran | the result | failures if any. The files
   travel with the repo (version control), so every machine and every session
   shares one memory. READING RULE: read the TAIL, never the whole file -
   the ledger exists so nobody re-reads anything.
3. THE BASELINE RULE. The first act after building a runner is recording a
   FULL baseline. After any notable change, re-run what it could touch. A
   regression is then a visible line flip - "passed at vX, fails at vY" -
   and the guilty range is two adjacent ledger lines, not an archaeology dig.

## What a runner script must do

- Own the WHOLE inventory of what can run, grouped correctly: every isolation
  law ("A and B must never share a process"), every per-task environment
  requirement, every timing window lives IN the script. An illegal ad-hoc
  combination is REFUSED with the law quoted - never allowed to produce a
  mystery flake.
- Parse its own results (pass/fail per item), print a compact summary, exit
  nonzero on any failure - so it is automatable, chainable with other
  scripts, and delegable to the cheapest sub-agent as a ONE-LINE brief
  ("run <script> --all"). This is where the method compounds with
  SUBAGENT_METHOD.md: scripted work needs no context to delegate.
- Append its ledger line itself (rule 2) - reporting is not a separate step
  anyone can forget.
- Identify the machine/agent automatically where possible (hostname, user
  path) so multi-machine ledgers stay attributable with zero configuration.
- Long/expensive runs (soaks, benchmarks) are excluded from the default
  "--all" and run deliberately - but STILL through the script, STILL ledgered.

## What earns a ledger (not just tests)

Tests are the obvious case; the same shape pays for: progression/balance
probes (compare tuning across versions), benchmark numbers (compare perf
across optimizations), build/export runs, data-regeneration passes. One
ledger file per kind, same line discipline. When a number matters enough to
mention in a conversation, it matters enough to append.

## The usage sheet: mine the harness meter, never self-estimate

A model cannot see its own token meter - but the HARNESS can, and it writes
it down. Claude Code keeps full session transcripts under
~/.claude/projects/<project>/*.jsonl (sub-agent runs in
<session>/subagents/agent-*.jsonl): every assistant message carries the real
API usage (model, input/output/thinking tokens, cache reads/writes) and
every tool call is named. A miner script aggregates that into ONE derived
sheet - totals per day / week / month for each model and each tool, CSV for
humans + a TXT twin - replacing all self-estimated token figures with
metered truth. Dollars stay estimates (price tokens from a table in the
script); the billing dashboard is the only dollar truth. Two laws learned
building it: (a) the transcripts ARE the ledger, so the sheet REGENERATES
whole instead of appending; (b) key rows by machine/workstation - each
machine only sees its own transcripts, so a run must only rewrite its own
rows. Reference implementation: Everwood's tools/usage_report.py
(incremental byte-offset cache; a 274MB transcript parses once, reruns
read only new bytes).

## THE WEIGHTED COLUMN + THE COMPARISON RULE (the CEO's rulings 2026-09-10)
Tags: economy, lessons, process | Only budget-weighted tokens are the headline; a number without a comparison means nothing - every daily figure is judged against the previous seven days with the reason named

THE WEIGHTED COLUMN. The origin CEO, on seeing 200M cache-read tokens:
"The most important token counts are the ones that actually count against
a user's usage amount... my budget is only being hit by 5 million. That
should be the concept for any of the pillars." So every usage sheet
carries a WEIGHTED column beside the raw one and makes it the headline:
input x1, cache write x1.25 (x2 on a 1-hour cache), cache read x0.1 (x0.025
on the model that discounts it), output x5 - the API's own price ratios,
the best public model of an unpublished budget. The raw count stays as
trivia. The same weights drive every other meter in the project (the
fan-out guard's spend), so all numbers agree. Under those weights the
origin project's split was cache WRITES 43%, cache reads 40%, output 17%,
fresh input ~0 (the first reading, 50 days to 2026-09-10; the sheet's
ALL-TIME line is the live figure, and its pillar shares assume the
five-minute write rate, so on a one-hour cache the writes' missing share
is the doubled write price) - which is why the sheet also counts CACHE MISSES (a
request after a session's first whose cache write is most of its prompt:
the cache expired or an early prefix byte changed) - 24% of the origin's
all-time budget was prefix rewrites nobody chose.

THE COMPARISON RULE. The CEO, on the read-diet metric: "there should be a
comparison between the previous several days' averages... A number
without comparison means nothing. Then you can also compare and let the
user know that something didn't work right, or you messed up in one way
or another and somehow token usage was high, or maybe it was low (which
is good)." So the sheet writes a DAILY LINE file - one line per active
day: weighted (raw) | vs the previous 7 active days | top pillar | cache
misses | reads whole (big) / section, share | VERDICT - and the verdict
names the reason: CHECK when spend is 30% over the prior average, or
misses / heavy whole-file reads run at twice it, or the section-read
share drops 20 points; LOW spend when 30% under (good); normal otherwise;
today's line marked partial. The standup digest prints the tail as THE
BUDGET block so the cost of a day is seen the next morning, and a CHECK
verdict is relayed to the CEO verbatim - it is the manager's own report
card. Reference: the kit's usage_report.py (weighted(), daily_lines(),
--quiet) and standup.py (print_budget); the checkpoint fingerprint
ignores the sheet's outputs so the refresh never counts as work.

See also: The usage sheet (above) | THE SPREADSHEET RULE (below) | WIKI_METHOD.md (the read diet + the output diet) | HOOKS_METHOD.md Tier 2c (the diet guard)

## THE SPREADSHEET RULE (Mazhron's ask 2026-09-10 - any sheet a human opens)
Tags: process, lessons | A CSV cannot carry formatting; a sheet meant for human eyes ships as .xlsx with frozen header, separators, bold ruled totals

The origin CEO opened the usage CSV in Excel and asked for four things that
no CSV can carry: the header row FROZEN so labels stay in view while
scrolling; every token/count column formatted as a Number with the
thousands separator (Format Cells > Number, 1000 separator); a TOTAL row
in line UNDER the last record of each period (day, week, month, all) with
the averages beside it in their own columns, the totals BOLD; and a THICK
bottom border under each total so the eye finds the split into the next
period. "I want future Rootstock users to have their Claude automatically
do this when their Claude builds it." So it is a rule: when a script
produces a sheet a person will open (usage, metrics, progression, any
ledger export), it ALSO writes an .xlsx twin with exactly that shape - the
CSV/TXT stay for grep and git diffs, the .xlsx is what the human opens.
Mechanics that worked (openpyxl, pip): `ws.freeze_panes = "A2"`;
`cell.number_format = "#,##0"` on every count column ("#,##0.00" for
money); the TOTAL row appended LAST in its period block, `Font(bold=True)`
on every cell of it and `Border(bottom=Side(style="thick"))`; per-row
totals + averages in the last two columns (total_tok / avg_tok) so a
model's or tool's average sits on its own line, not only in the totals;
an auto-filter on the header; the dependency recorded in the workstation
inventory + survey the same batch (THE WORKSTATION RULE). When the
library is missing the run must still write the CSV/TXT and SAY the
.xlsx was skipped - never crash a ledger run over formatting.
Reference: Everwood's tools/usage_report.py (write_xlsx / _xlsx_sheet).
See also: the usage sheet (section above); WORKSTATION_METHOD.md (the
dependency write-back); REPORTING_METHOD.md bootstrap step for the sheet.

## Evidence this pays (Everwood, the origin project, day one of the method)

The FIRST full baseline through the new runner caught, in one afternoon:
a live-gameplay regression that had silently shipped weeks earlier (half the
off-screen world's insect ecology frozen - found because a routine sweep
finally ran the right test), a parser defect in the runner itself, and a
test still calibrated to a design number the owner had changed versions ago.
Each fix is a readable flip in the ledger. None of it was findable from chat
history, because chat history is not a ledger.

## Bootstrap steps for a new project

1. Create the runner script the day the FIRST repeatable thing exists (one
   test is enough); create docs/history/ beside it.
2. Encode groups/laws in the runner as they are learned - a flake's
   post-mortem always ends with a new law line in the script.
3. Record the full baseline; commit ledger + runner together.
4. Wire every later probe/report script to append to its own ledger.
5. When delegating (SUBAGENT_METHOD.md), briefs for scripted work are one
   line; the employee runs the script and reports its output verbatim.
6. Never prune a ledger; if one grows huge, start a dated continuation file
   and leave a pointer - history is the product.

Search keys: reporting method, scripted runs, history ledger, baseline rule,
  script rule
```

### `SECURITY_METHOD.md`

- Source: `SECURITY_METHOD.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 13190
- SHA-256: `9fab6abb00f2e03f747b4441da61637c297c8a12bbd4ba0268ad4a6072afc291`

````text
# SECURITY_METHOD.md - the pre-production security audit (PORTABLE, part of the future-project kit)

PURPOSE: The pre-production security audit: one checklist, one read-only
  script and one ledger line that every app, SaaS or website with a backend,
  an API key, an env file or user data passes before it goes public, and
  again before every public release that touched secrets, auth, headers,
  config or the database rules.
INTENT: Mazhron 2026-09-29, on a survey of 100 AI-built apps: "I feel like
  this is important to note inside of Rootstock as part of the audit of an
  app, saas or website where applicable before it goes into production,
  goes out to the public, etc. We should create a file for this
  specifically ... to help keep users safe who are making them. Which could
  be me, and very will likely be me in the future when I get my
  programming job."

Founded 2026-09-29 on a Reddit survey (r/claude, u/Donchuan1998): 100
publicly launched apps built with Lovable, Bolt, Cursor and similar tools,
checked with passive, read-only requests only, what any visitor's browser
already downloads. 37 of 100 had at least one potentially exposed secret
in their frontend JavaScript (OpenAI, Stripe and Supabase credentials the
most common). 78 of 100 were missing at least one important security
header. 12 of 100 exposed a development or configuration file such as
/.git/ or .env.bak. 43 of 100 returned a wildcard CORS header. 9 of 100
had no findings. The cause the survey names: AI coding tools optimise for
"it works", not "it is safe"; the commonest pattern was an environment
variable renamed with a VITE_ or NEXT_PUBLIC_ prefix to make a build error
go away, which ships the server-side secret to every visitor. None of it
is sophisticated. It is default mistakes repeated at scale, and a
checklist catches default mistakes. Nothing in the rest of the kit looked
at this; the kit audits its own process and never the app it builds.

Search keys: security audit, secrets, API key, exposed secret, env file,
VITE_, NEXT_PUBLIC_, security headers, CSP, HSTS, CORS, .git exposed,
.env exposed, Supabase RLS, rotate a key, pre-production, go live,
production checklist, public release, source maps, rate limit.
See also: REPORTING_METHOD.md (the script and its ledger are a scripted
run), WORKFLOW_METHOD.md (the registry entry that runs the audit),
SUBAGENT_METHOD.md (the read-only employee that walks the checklist),
CONTRIBUTING.md (the purpose audit of the kit's own things, which this
is not), reference tools/security_audit.py.

## THE SECURITY AUDIT RULE
Tags: process, security, law | No app with a backend, a key, an env file or user data goes public before the audit passes; a key that was ever public is rotated, never merely removed

1. THE GATE: the audit runs, and its ledger line reads PASS or every
   FAIL is answered, BEFORE the first public release of anything that
   has a backend, an API key, an environment file, a database or user
   accounts. "Public" means a URL anyone can open, an app store listing,
   a Product Hunt or showcase post, a "look what I built" link. A
   static page with no keys and no backend is exempt and says so in
   its ledger line.
2. THE RE-RUN: the audit runs again before every public release whose
   diff touched secrets, environment files, auth, HTTP headers, CORS,
   hosting config, or database rules. The ship ritual asks; a release
   that skipped it is a ship-law breach, same as a missing changelog.
3. THE ROTATION LAW: a secret that was ever reachable by the public (in
   a bundle, a repo, a screenshot, a log, a chat) is compromised the
   moment it was reachable. The fix is to ROTATE it at the provider and
   then remove it; removing it from the code is not a fix, git history
   and every visitor's cache still hold it. Rewriting history is a
   separate decision (THE PRESERVATION LAW applies to the repo, the
   rotation does not wait for it).
4. THE PREFIX LAW: an environment variable whose name starts with
   VITE_, NEXT_PUBLIC_, REACT_APP_, PUBLIC_, EXPO_PUBLIC_, NUXT_PUBLIC_
   or GATSBY_ is bundled into the client and shipped to every visitor.
   Only a key the provider itself calls public, publishable or anon
   belongs there. A build error that a prefix would silence is a design
   error: the call belongs on the server (an API route, an edge
   function, a proxy), never in the browser.
5. THE SCRIPT AND THE LEDGER (REPORTING_METHOD): the checks a script can
   make are made by the script (reference tools/security_audit.py) and
   append to docs/history/security_audit_runs.txt; the checks a script
   cannot make (the database rules, the auth on every route, the
   dependency audit) are walked by a read-only employee from the
   checklist below and the manager writes the ledger line with the
   employee's findings. Trust the ledger: an unchanged release at a
   green line needs no re-run.
6. READ-ONLY: the audit touches only what a visitor's browser already
   downloads from YOUR OWN deployment. It never probes a site you do not
   own, never logs in, never sends a payload. It is a mirror, not a
   scanner.

## The checklist (one section per finding class; the survey's order)
Tags: security, checklist | What to check, how, and what passing looks like

### 1. Secrets in the client
- WHAT: any server-side credential in the built JavaScript, the HTML,
  the source maps or a public config file.
- HOW: build for production, then search the OUTPUT folder (dist/,
  build/, .next/static/, out/) and the live site's Sources tab for the
  patterns the script carries: `sk_live`, `sk_test`, `sk-` (OpenAI and
  Stripe secret keys), `AKIA` (AWS access key id), `service_role`
  (Supabase's admin key), `ghp_` / `github_pat_` (GitHub tokens), `AIza`
  (Google API keys, public by design but restricted by referrer or
  they bill you), `xox[bp]-` (Slack), `-----BEGIN` (a private key),
  `password=`, `secret=`, and every name from your own .env that is not
  meant to be public. Search the source maps too (`*.map`), a map ships
  the original source with its comments.
- PASS: only keys the provider calls publishable or anon appear, and
  each of those is restricted at the provider (allowed origins,
  referrers, scopes, row-level rules).
- FAIL: rotate first (rule 3), then move the call server-side.

### 2. Security headers
- WHAT: the response headers on the site's root and on one app route.
- HOW: `curl -sI https://yoursite/` (the script does this) and read:
  `Strict-Transport-Security` (HSTS: HTTPS is forced after the first
  visit); `Content-Security-Policy` (CSP: which scripts, frames and
  connections the page may load; the one header that blunts an injected
  script); `X-Frame-Options: DENY` or the CSP `frame-ancestors`
  directive (nobody can put your login page in an invisible frame);
  `X-Content-Type-Options: nosniff`; `Referrer-Policy`;
  `Permissions-Policy` (camera, microphone, geolocation off unless
  used).
- PASS: HSTS, a CSP, and a frame rule present. The others are warnings.
- FIX: hosting platforms set them in one file (vercel.json, netlify.toml,
  `_headers`, nginx.conf, a Next.js `headers()` export). A CSP is
  written strict and loosened only for the origins the console names.

### 3. Exposed files
- WHAT: files the deployment serves that were never meant to be served.
- HOW: request each path and expect 404 (or 403): `/.git/HEAD`,
  `/.git/config`, `/.env`, `/.env.local`, `/.env.production`,
  `/.env.bak`, `/.env.example` (harmless but shows your variable
  names), `/config.json`, `/config.yml`, `/backup.zip`, `/db.sqlite`,
  `/.DS_Store`, `/server.log`, `/phpinfo.php`, `/wp-config.php.bak`,
  `/.htpasswd`, `/docker-compose.yml`, `/package.json` (shows your
  dependency versions), and the `.map` next to each built script.
- PASS: every one returns 404 or 403, and a 200 on `/.git/HEAD` is a
  FAIL that outranks everything else (the whole repo, history included,
  is downloadable).
- FIX: a deny rule in the host or server config; source maps off in
  the production build, or uploaded to the error tracker only.

### 4. CORS
- WHAT: `Access-Control-Allow-Origin` on the API's responses.
- HOW: `curl -sI -H "Origin: https://evil.example" https://yourapi/route`.
- PASS: the header names your own origins, or is absent on routes that
  no browser calls. A wildcard `*` alone is a warning, not a finding;
  a wildcard together with `Access-Control-Allow-Credentials: true`,
  or an origin reflected back unchecked, is a FAIL (any site can call
  your API as the logged-in visitor).

### 5. Database rules
- WHAT: what the public key alone can read and write.
- HOW (Supabase): every table has Row Level Security ENABLED and at
  least one policy; the anon key is in the client, the service_role
  key is never. Test it: with only the anon key, `select * from` each
  table from a browser console; a table you did not mean to be public
  that returns rows is a FAIL. (Firebase): the rules are not the
  test-mode default (`allow read, write: if true`) and every collection
  has an auth check. (Any ORM with a direct connection string): the
  string is server-side only, check class 1.
- PASS: every table's public read and write matches the design, in
  writing, in the wiki.

### 6. Auth and rate limits on the server routes
- WHAT: which API routes run without a session, and what they cost.
- HOW: list every server route (API routes, edge functions, webhooks,
  cron endpoints); for each one, name who may call it and whether the
  code checks that before doing work. Call the ones that should need a
  session without one and expect 401. Any route that calls a paid
  provider (an LLM, email, SMS, a payments API) has a rate limit or a
  per-user cap, or one visitor's script runs up your bill overnight.
  Webhooks verify the provider's signature.
- PASS: every route has a named caller and a check; every paid route
  has a limit; every webhook verifies.

### 7. Dependencies and the build
- HOW: `npm audit` / `pip-audit` / `cargo audit` clean of critical and
  high; the lockfile is committed; the production build does not ship
  the dev server, the test fixtures, or a `debug=true`.

### 8. Logs, errors and telemetry
- HOW: an error page shows no stack trace to a visitor; logs sent to a
  third party carry no secrets, tokens or personal data; the analytics
  snippet is the one you chose and nothing else loads from an origin
  you cannot name.

### 9. The game and export note (Godot, Unity, web exports)
- A web export ships every script and resource in the PCK to every
  player; anything under res:// is public, an obfuscated string
  included. A leaderboard key, an itch or Steam API secret, a Discord
  webhook, an analytics write key belong in a server the game calls,
  never in a .gd, a .tres or an exported constant. A game with no
  server and no key is exempt from the gate and its ledger line says
  so ("static export, no backend, no keys").

## The ledger line
Tags: security, ledgers | One line per audit, read the tail

docs/history/security_audit_runs.txt, append-only, one line per audit:
`date time | ws | target | PASS/WARN/FAIL counts | note`. The script
writes the counts (`--record` after a run); the manager's note carries
the hand-walked verdict for classes 5-8 from the employee's report and
the count of keys rotated. A release ships against the newest line, and
the ship ritual quotes it.

## The workflow entry (paste into WORKFLOWS.md, adapt the paths)
Tags: security, workflows

```
## Audit the app for exposed secrets before a public release
WHEN: before the FIRST public URL, store listing or showcase post, and
before any release whose diff touched secrets, env files, auth, headers,
CORS, hosting config or database rules (SECURITY_METHOD.md rule 2).
STEPS:
1. `python tools/security_audit.py --dir <build output>` (class 1) and
   `python tools/security_audit.py --url https://<your site>` (classes
   2-4); read the FAIL lines.
2. One read-only employee (sonnet, /brief) walks classes 5-8 against the
   deployment's config and the route list; diff-only report.
3. Every FAIL: rotate first (rule 3), then fix, then re-run step 1.
4. `python tools/security_audit.py --record "<note>"` writes the ledger
   line from the last run's counts; quote it in the ship commit.
VERIFY: security_audit_runs.txt's tail is a PASS at this version.
See also: SECURITY_METHOD.md; the ship workflow.
```

## BOOTSTRAP (new project)
Tags: security, bootstrap

1. At STEP 0 the CEO answers: does this project have a backend, a key,
   an env file, a database or user accounts? NO: write the exemption in
   the wiki's systems index and stop here. YES: continue.
2. Copy reference tools/security_audit.py to tools/, run `--selftest`,
   add the workflow entry above to WORKFLOWS.md, and add the .env
   family to .gitignore before the first commit that could carry one.
3. Add the ship ritual's question: "did this diff touch secrets, env,
   auth, headers, CORS, hosting or database rules? then the audit runs
   first" (one line in the ship skill or WORKFLOWS "Ship a batch").
4. The first audit runs before the first public URL; its line is the
   first in security_audit_runs.txt.
````

### `SKILLS.md`

- Source: `SKILLS.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 8847
- SHA-256: `44cb52a9909612b874721796c4c8ed571aa4f19346e682feed7c56fd3b763346`

```text
# SKILLS.md - the skills shelf (PORTABLE, part of the future-project kit)

PURPOSE: The skills shelf: catalogs each ritual, standup, checkpoint, ship,
  brief, runaway, preserve, intent, correct, as an invocable Claude Code
  skill in .claude/skills/, so a ritual runs from a script instead of from
  memory.
INTENT: Mazhron's ruling 2026-09-03: rituals that live only as law text get
  executed from memory; rituals that live as skills get executed from the
  script.

Founded 2026-09-03 on Mazhron's ruling: rituals that live only as law text
get executed from memory; rituals that live as SKILLS get executed from the
script. A skill is a markdown instruction pack in `.claude/skills/<name>/
SKILL.md`; typing `/<name>` in Claude Code loads it and Claude follows it.
Skills cost nothing at rest - they load only when invoked or clearly needed.

Search keys: skills, slash commands, rituals, plug and play, new project.
See also: SUBAGENT_METHOD.md (delegation the /brief skill enforces),
REPORTING_METHOD.md (the ledgers /standup and /checkpoint read/write),
WIKI_METHOD.md (the conventions every skill assumes), CLAUDE.md (the laws
the skills operationalize).

## The shelf (what each skill does)

- **/standup** - session opener. Runs the standup digest and hands back the
  last exchange (user's prompt + manager's response, both sides, VERBATIM -
  exact words, never paraphrased; mined from the HARNESS TRANSCRIPT, the
  ground-truth record on disk, so it survives a mid-arc /clear) and the
  project state before anything else, then THE BUDGET block (2026-09-10:
  yesterday's and today's weighted spend judged against the previous 7
  active days - a CHECK verdict is relayed verbatim, it names what went
  wrong). Use at every session start and after /clear.
- **/checkpoint** - arc closer. Push, refresh the day file's WHERE WE LEFT
  OFF (both sides of the final exchange VERBATIM + state + next-likely;
  write the reply into the file, then send that exact text), reset the
  task counter, emit the safe-to-clear marker. Refuses mid-arc, with
  uncommitted work, or with a running employee.
- **/ship** - batch shipper. Player-readable commit, push, build zips
  (never deleting old ones), counter tick. Runs after every completed
  batch, unprompted.
- **/brief** - delegation composer. Builds a sub-agent brief per the
  delegation laws (stamp, self-contained context, token budget line,
  diff-only reporting), then verifies cheap and ledgers the outcome.
- **/runaway** - the fan-out guard's numbers, in the owner's hands
  (Mazhron's ask 2026-09-10). Prints every limit current vs default with
  its meaning (`--limits`), takes the owner's changes (`--set`, refusing
  a warn step above its halt), proves the guard still stands
  (`--selftest`), and commits `.claude/fanout_limits.json` - the tuned
  numbers travel with the repo and survive a kit graft. Only the owner
  invokes it to raise a limit; the manager never does on its own.
- **/preserve** - THE PRESERVATION LAW's front (Mazhron 2026-09-11: the
  law lived in prose plus three loose scripts). Takes a target and offers
  the three lawful moves in order: RETIRE a file (`tools/retire.py`, to
  _retired/, ledgered), SHELVE a wiki section (`tools/cold_shelf.py
  --move`, verbatim, stub + index), or - only when neither does the job -
  the DELETE GRANT: the ask naming the exact target and size, the owner's
  yes, the restatement, the second yes, all four recorded verbatim by
  `tools/delete_grant.py`, then the ONE command. Never invoked by an
  employee; never raises a limit or routes around the preserve guard.
- **/intent** - files the WHY of a ruling in Mazhron's own words (Mazhron
  2026-09-13: "there should be a record of that to compare vs my
  intent"). Asks "What was the intent?" when it is not already stated,
  files a dated ASKED/WHY/GENERALIZES-TO/LIVES-IN section in INTENT.md,
  then resolves the open claim (`tools/intent_log.py --resolve ...
  --verdict same|similar|different`) so Claude's reading is measured
  against Mazhron's actual words. Never invoked by an employee.
- **/correct** - the correction ritual (Mazhron 2026-09-13's feedback-loop
  ask). Asks "What about the last thing I did needs correcting?", records
  Mazhron's words BEFORE fixing anything (`tools/correction_log.py
  --record`, which resolves the matching intent claim DIFFERENT by
  itself), fires /intent's "what was the intent?" question while the
  mismatch is fresh, then fixes and logs `--fixed`. /intent and /correct
  form one loop: a wrong build, the words that named it wrong, the why
  behind the right answer, the fix.
- **hooks** are the shelf's involuntary twin (HOOKS_METHOD.md, 2026-09-06):
  a skill runs when invoked; a hook runs when the harness reaches a moment.
  /standup now fires itself at session start, the checkpoint tick fires
  itself at every reply, and shell guards refuse what the laws forbid. A
  ritual that CAN be mechanical becomes a hook, not a longer skill.

- **/flag** - the purpose audit (Mazhron 2026-09-13: "Claude should
  always read-only -> Flag -> Explain"). One kit thing at a time: read it
  without editing, compare what its PURPOSE line says with what it does,
  color it GREEN (does what it says, nothing more) / YELLOW (matches in
  substance, something is off) / RED (does what it does not say, or
  crosses a law - Mazhron sees it first), then file the entry with
  `tools/purpose_audit.py --flag` into the kit's FLAGS.md (SAYS / DOES /
  FLAG, hashed to the version reviewed, tallied at the top). Any Claude
  may flag; a missing header is rewritten by script afterwards, never by
  hand in the audit turn.

## THE SKILLS RULE (standing, Mazhron 2026-09-03)

When a ritual or law is BORN or AMENDED, its skill is added or updated IN
THE SAME BATCH - law text and skill never drift apart. And whenever a skill
changes, REFRESH its copy in the future-project kit folder ("Future Project
MDs/skills/" plus this file) in the same batch, like every other kit file.

## New-project bootstrap (plug and play)

THE MASTER SEQUENCE lives in the kit folder's front door: "0 - READ ME
FIRST, CLAUDE.md" (kit-folder-only file; a new project's Claude reads it
and installs the whole operating system in order: wiki -> reporting ->
delegation -> skills). Skills go LAST because they call the tools the
earlier steps build; each skill degrades gracefully by pointing at its
METHOD file when a tool is missing. Nothing in the skills is
Everwood-specific except named examples (marked "in Everwood").

## Change log

- 2026-09-03 WS1: shelf founded with /standup, /checkpoint, /ship, /brief;
  THE SKILLS RULE established; kit copies created.
- 2026-09-06 WS1: hooks founded as the involuntary twin; /standup,
  /checkpoint and /ship reworded hook-aware (no manual tick; reset last;
  standup not re-run when the SessionStart hook already injected it).
- 2026-09-10 WS1: /runaway added (kit v1.10) - the fan-out guard's
  limits shown and tuned at the owner's word, stored in a committed
  .claude/fanout_limits.json over the script's defaults.
- 2026-09-10 WS1 (evening): /standup relays THE BUDGET block (kit v1.12)
  - the usage sheet's daily line, each day vs the previous seven.
- 2026-09-10 WS1 (night): /checkpoint gains ADVISED MEANS DO IT (kit
  v1.13) - an advisory from the gauge or the counter is acted on at the
  end of that reply, unprompted; the owner simply /clears.
- 2026-09-10 WS1 (late): /brief gains THE PRESERVATION LINE (kit v1.14) -
  every employee brief carries the law that its work contains no
  deletion code and runs no delete command; an employee that needs a
  deletion stops and reports.
- 2026-09-11 WS1: /preserve added (kit v1.16) - the preservation law's
  conversational front: retire, shelve, or the twice-acknowledged delete
  grant, in that order. Same batch: the hygiene guard hook backs THE
  SKILLS RULE mechanically - editing a SKILL.md returns the kit-refresh
  line (copy + shelf entry + README) at the edit.
- 2026-09-13 (Mazhron's intent + correction ruling): /intent and /correct
  join the shelf - the why of every ruling in the owner's words, the
  correction ritual that records the words and asks for the intent at
  once; the intent log compares Claude's reading with the owner's
  (INTENT_METHOD.md).
- 2026-09-13 (kit v1.19): /flag joins the shelf - the purpose audit's
  ritual (read-only, flag green / yellow / red, explain, file in
  FLAGS.md). Nine skills. Every SKILL.md now carries the format header
  (PURPOSE / INTENT after the title) - the format guard blocks a skill
  edit without it.
- 2026-09-30 WS1 (kit v1.41, the fourth README audit): /ship step 1 gains
  THE SECURITY QUESTION (v1.39's graft line the shelf had missed) and
  /brief step 1 THE EMPLOYEE MODEL RULE (v1.40's guard, now stated where
  the brief is composed). Nine skills, unchanged count.
```

### `SUBAGENT_METHOD.md`

- Source: `SUBAGENT_METHOD.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 13026
- SHA-256: `9bb7f822f8062cf3ed661d2651a574ad14cf82349e70b08fff7737faf453cfe1`

```text
# The Sub-Agent Method (portable: the delegation company, for any project)

PURPOSE: A portable architecture for delegating work to sub-agent employees:
  the org chart (CEO, manager, employees), why it saves money, the seven
  laws, the assignments table, the scorecard, and bootstrap steps for a new
  project.
INTENT: An AI's cost is mostly context, not cleverness; delegating the
  reading and the grinding to a throwaway-context employee while the manager
  keeps the thinking saves tokens even when the employee costs the same, and
  multiplies the saving when it costs less.

PORTABLE FILE: this describes an ARCHITECTURE, not a project. Nothing in here
assumes a game, a language, or a specific AI model. Hand it to any Claude (or
any capable agent) at the start of any project and say "set this up" - it
plugs into any workflow. The concepts matter; the specifics are yours to fill.

## The org chart (three roles, always)
Tags: delegation, process, architecture | CEO, manager and employee roles with the cardinal rule: ask the CEO which model manages

- THE CEO - the human. Sets direction, makes rulings, owns the product. The
  CEO can make mistakes too; the ledger and attribution exist so ANYONE's
  mistake - CEO included - can be found and corrected, not hidden.
- THE MANAGER - the strongest AI in the loop. Holds the long-lived context,
  talks to the CEO, makes design/architecture calls, writes the work orders,
  double-checks everything, and answers for all of it. There may be several
  managers (one per workstation/session); they coordinate through the repo.
- THE EMPLOYEES - cheaper/faster models spun up as sub-agents for
  self-contained tasks. They start with EMPTY context, do one job, stamp it,
  and disappear.

**WHO IS THE MANAGER? ASK THE CEO - ALWAYS.** Never assume. The right manager
model changes with time, budget and taste (today's premium model is tomorrow's
mid-tier; a future model may outrank everything current). At setup, Claude
must ask: "Which model manages, and which models are available as employees?"
and record the answer in the project's SUBAGENTS file. Revisit when models
change.

## Why this saves money (the one insight)
Tags: delegation, process, performance | Context cost dominates; delegate reading and grinding to fresh-context employees to multiply savings

An AI's cost is mostly CONTEXT, not cleverness: the long conversation plus
every file the manager reads itself rides along with every single request.
An employee reads those files into ITS OWN throwaway context instead - so
even a same-priced employee saves manager tokens, and a cheaper employee
multiplies the saving. Delegate the reading and the grinding; keep the
thinking.

THE 10k LINE (2026-09-10, from the weighted-usage insight): under budget
weights a file the manager reads inline is written at 1.25x and re-read
every later turn - ~90k weighted over a session for one 24k-token file
at the manager's price. Any "understand this file/system" step past ~10k
tokens is delegated; the manager reads sections or summaries. The kit's
diet guard hook says the size at the moment of the read (warn-only), and
the usage sheet's daily line grades the habit. The exception is an edit
that needs the exact text. Full rule: WIKI_METHOD.md "The read diet".

## The seven laws
Tags: delegation, process, architecture | Seven cardinal laws: brief, stamp, verify cheap, ledger, escalate, fan-out caps and preservation

1. THE BRIEF IS EVERYTHING. Employees know NOTHING - no chat history, no
   project lore. A brief is a work order: exact files/paths, exact spec,
   exact output format, any needed rules PASTED IN (never "see the docs").
   A vague brief is the manager's error, not the employee's. The brief
   also tells the employee HOW to spend its turns (v1.43): independent
   reads, greps and checks go in one turn, never one per turn, because
   every extra turn re-reads the whole growing context; only a step that
   needs the previous result waits.
2. EVERY EMPLOYEE STAMPS ITS WORK. Every brief ends by requiring:
   "STAMP: model=<model> effort=<low|med|high> est_tokens=<rough>
    task=<3-5 words> confidence=<high|med|low>"
   If the platform meters real usage (e.g. a subagent_tokens figure in the
   tool result), the manager records THAT - self-estimates run wildly low
   (models cannot see their own meter; we measured ~20x under).
3. VERIFY CHEAPLY, IN ORDER: (a) run the project's tests/checks, (b)
   spot-read only the diff or output, (c) full read only if a+b smell wrong.
   A double-check that costs more than the task defeats the purpose.
4. LEDGER EVERY DELEGATION. One appended line: date, who delegated, task
   type, model/effort, metered tokens, outcome OK or CORRECTED + what was
   wrong. Keep a running TALLY per model (tasks / corrected / success %).
5. THE ESCALATION RULE. When a task type's corrections exceed ~25% of its
   last ~10 tasks, promote that task type - stronger model or higher
   effort - with a dated, attributed change line in the assignments table.
   The ledger justifies staffing changes; nobody argues from vibes.
   THE ASSIGNMENT IS THE MANAGER'S (the origin project's owner, 2026-09-29:
   "You are the manager, you make the decision. You can downgrade or
   upgrade any task you see fit on a trial basis. If there are enough
   failures, then it needs to move up again."): the manager moves any task
   type down a tier on trial without asking; the ledger's correction rate
   moves it back up; the only fixed line is the owner's (in the origin
   project the top model is never an employee, to save tokens). A trial is
   ledgered with "trial" in its line so the rate counts it.
6. THE FAN-OUT LAW (added 2026-09-10 after a public catastrophe: a
   manager asked to "check my markdown files for consistency" spawned
   821 sub-agents and burned 50M+ tokens in thirty seconds). Employees
   are spent money. A delegation batch is a handful of parallel
   employees (the origin project's habit: 4), never a burst, never an
   employee that spawns employees (fan-out is one level deep and the
   manager's decision), and any bulk-orchestration tool only when the
   CEO asks for it. A task that seems to need dozens is a DESIGN problem
   - split it, script it, or ask the CEO - never a bigger fan-out. THE
   HARNESS BACKS IT, CATASTROPHE-ONLY (HOOKS_METHOD.md Tier 2b, the
   fan-out guard; the origin CEO loosened it from a strict first cut the
   same day: "I just wanted to prevent complete runaway agents and
   gigantic token spend"): it refuses only the runaway shapes - a burst
   of spawns inside a minute, a flood inside ten, or token velocity no
   real work produces (a self-clearing cooldown) - and otherwise only
   warns. No unlock commands; nothing fires on real work. A refusal from
   the guard is the CEO's standing decision: the manager stops, reports
   what it was fanning out and why, and never resumes the same loop.
   The guard's numbers are the CEO's to tune, through the /runaway skill
   (shows every limit current vs default, writes the CEO's changes to a
   committed .claude/fanout_limits.json over the script's defaults);
   the manager never raises one on its own.
7. THE PRESERVATION LAW (added 2026-09-10 after public reports of an
   agent whose script deleted a person's files and another that wiped a
   machine). Nobody in the company deletes: not the manager, not an
   employee, not a script either of them writes. A file that is no
   longer wanted RETIRES to a shelf folder with a ledger line; a wiki
   section that is rarely read moves to a COLD SHELF file, verbatim,
   with a stub at the old heading and an index entry; a wrong memory is
   marked superseded in place. Knowledge is hard-won and the rarely used
   kind is still knowledge. A real deletion needs the CEO's express
   permission given TWICE (the manager asks naming the exact target,
   gets a yes, restates, gets a second yes) and the four texts are
   recorded verbatim before the one command runs. The harness backs it
   (HOOKS_METHOD.md Tier 2d, the preserve guard): delete verbs,
   work-discarding git verbs and deletion calls in new code are refused
   on every shell command and every file write; the session scratchpad
   passes; a drive root, the home folder or the repo root pass never,
   grant or not. Every brief carries the law in one line, and a refusal
   in an employee's report is the law working - the manager moves the
   thing or asks the CEO twice, never routes around it.

## The assignments table (build one per project)

Ask the CEO which models exist in their tier list, cheapest to strongest,
then draft a table mapping the project's RECURRING task types to the
CHEAPEST tier you believe can do each correctly. Generic tiering that has
held up:

- CHEAPEST tier: running test suites and reporting results verbatim; search
  and locate sweeps; regenerating generated artifacts; mechanical batch
  edits from an explicit value list; formatting/housekeeping passes.
  (Cheap enough to parallelize - several at once for independent jobs;
  never two writers on one file.)
- MIDDLE tier: implementing code from a PRECISE written spec (files,
  behavior and the verifying test all named); drafting docs from an
  outline; analyzing tool/telemetry output into a summary; first-pass
  review of another employee's diff before the manager looks.
- STRONG tier (below manager): multi-file refactors, performance hunts,
  gnarly debugging - anything hard but bounded, WITH a written plan.
- MANAGER ONLY: design and architecture, rulings and laws, anything
  touching the CEO's standing rules, conversations with the CEO, final
  verification, and the commits/pushes.

THE EMPLOYEE MODEL RULE (2026-09-30, kit v1.40): every dispatch names its
model explicitly. In the harness, an Agent call with no `model` field
inherits the manager's own model, so a model-less brief runs on the top
tier silently - the one tier the table says is never an employee. The
brief guard refuses a work dispatch whose model is missing or names the
manager's tier; the fix is the table's row, written into the call.

## The scorecard (measure the company - added 2026-09-02, proven same day)

Track, per model AND per manager, from the ledger itself (a small script
parses it - never tally by hand): tasks / ok / corrected / FAILED / success
% / CATCHES (real problems an agent flagged that others missed - the
strongest signal a tier earns its keep) / total tokens / AVERAGE tokens per
task / tokens burned inside failed tasks. And PER-INCIDENT detail, not just
totals: each failure or correction lists the task, the model, what it burned,
and what the fix cost and WHO paid it ("fix ~2k by manager") - so the true
price of every failure is a line item, comparable forever.

TOOL-USAGE TRACKING: every employee's stamp includes a TOOLS line naming
each tool it called and how often; the ledger records the platform-metered
TOTAL beside it. Two payoffs: (a) audit - you can see whether agents do what
their briefs say; (b) THE FABRICATION CHECK - a read/run task whose metered
tool count is ZERO never did the work; it invented a plausible answer.
(Discovered in practice: an auditor "classified" a file it never opened -
93k tokens of confident fiction, caught for ~2k because the meter said 0.)
A large self-report vs metered mismatch is the softer version of the same
signal. Managers ledger themselves too - sessions, self-fixes, token
ESTIMATES clearly marked as estimates, because no model can see its own
meter; the billing dashboard is the only truth.

## Attribution and trust (pairs with a roadmap file, if the project has one)
Tags: delegation, process, architecture | Every idea and change is attributed and dated; contradiction with prior rules is flagged and confirmed

Every idea and every change of plan is attributed (CEO / manager-1 /
manager-2 / employee) and dated, so mistakes trace to their maker and get
corrected - never silently rewritten. Companion rule: if the CEO asks for
something that contradicts a rule they previously set, the manager FLAGS the
contradiction and confirms before building - never silently comply, never
silently refuse.

## Bootstrap steps for a new project

1. Ask the CEO: who manages, which employee models are available, and where
   the delegation file should live.
2. Create the project's SUBAGENTS file with: the org chart (as answered),
   the seven laws, a first-draft assignments table for THIS project's task
   types, an empty ledger + tally.
3. Index it wherever the project indexes its knowledge (one line), so every
   session finds it without scanning.
4. Delegate something small on day one (a test run, a search sweep) to
   prove the stamp/ledger loop end to end - and ledger it, even if perfect.
5. Let the ledger run. Promote or demote models with data, not impressions.

Search keys: sub-agent method, delegation company, manager employee, seven
  laws, org chart
See also: SUBAGENTS.md (this project's instance); WIKI_METHOD.md (the read
  diet, the 10k line)
```

### `UPGRADES.md`

- Source: `UPGRADES.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 112554
- SHA-256: `6fe1109b75b8ee37010c238494663d52cedb3963d1b2c21b6f8cde2961b72b6d`

```text
# UPGRADES.md - the graft log (how Rootstock updates without overwriting)

PURPOSE: The append only graft log: every kit concept update, recorded as
  WHAT it is, which kit files CARRY it, how to GRAFT it onto an installed
  project's own files, and which README section it touched, so installs
  update by concept rather than by overwriting a project's customized files.
INTENT: an installed Rootstock is an adaptation, not a copy, so the kit must
  never update a project by overwriting its files; this log is the one place
  updates travel as grafts instead.

CURRENT KIT VERSION: **v1.44** (this file is the single source of truth for
the kit's version; entries below are append-only, oldest first).

Search keys: updates, upgrade, graft, version, pull changes, kit update.

## Why updates are GRAFTS, never file copies

An installed Rootstock is an ADAPTATION, not a copy: the receiving Claude
renamed paths, tailored CLAUDE.md, rewired scripts, and the project has
since grown its own knowledge INTO those files. Copying a newer kit file
over an installed one would destroy exactly the thing the system exists to
protect. So the kit never updates files in a project - it updates CONCEPTS.
Each entry below is a scion: the idea, where it lives in the kit, and how
to graft it onto a project's own files, whatever they are named there.

## THE GRAFT PROTOCOL (for the Claude performing an update)

1. Find the installed version: the project's CLAUDE.md carries a line
   "Rootstock vX.Y installed <date> | updates: <policy>" (an install that
   predates version marks counts as v1.0 - add the line while you are
   there). The POLICY word is the CEO's standing answer to "should I
   update?": **ask** (default - present newer grafts, CEO picks), **auto**
   (graft everything newer, report after), **relevant** (offer only grafts
   that benefit THIS project; record skips so they are never re-offered),
   **never** (check only when the CEO explicitly asks). The CEO changes it
   any time by saying so ("update automatically", "stop asking about
   updates", "only show me relevant updates").
2. Get the current kit (the CEO hands you the folder, or pull
   github.com/Mazhron/rootstock-os) and read THIS file's entries NEWER
   than the installed version.
3. For each entry, in order: read its GRAFT instructions, then apply the
   concept to the project's OWN files - additive edits in the project's
   own names, paths, and voice. NEVER copy a kit file over an existing
   project file. A file the project does not have at all (a genuinely new
   MD or reference script) may be copied fresh, then adapted and indexed.
4. If a graft contradicts something the CEO customized on purpose, THE
   CONTRADICTION RULE applies: flag it, ask, never silently overwrite
   their choice with ours.
5. Bump the project's "Rootstock vX.Y installed" line to the new version
   and ship the batch. One graft batch per update; the project's own
   changelog records what was grafted.

## The entries

Every entry carries WHAT (the concept), CARRIES (the kit files that hold
it), GRAFT (how it lands on an installed project's own files) and, from
v1.17 on, README (the public-README section the concept touched, or
"none, wording only" - the parity lint refuses a newest entry without it).

### v1.0 - 2026-09-03 - The public release
WHAT: the four pillars as first published: the knowledge wiki
(WIKI_METHOD.md), the reporting discipline (REPORTING_METHOD.md), the
delegation company (SUBAGENT_METHOD.md), the skills shelf (SKILLS.md +
skills/), the front door install order, and the verbatim checkpoint law
(both sides of the final exchange, exact words).
CARRIES: every kit file at publication.
GRAFT: not applicable - this is the baseline an install starts from.

### v1.1 - 2026-09-03 - The usage sheet
WHAT: the harness transcripts (~/.claude/projects/) meter every request
for real - model, input/output/thinking tokens, cache reads/writes, every
tool call named, sub-agents included. A miner script aggregates them into
one regenerated CSV+TXT sheet: totals per day/week/month per model and
per tool, workstation-keyed. Ends self-estimated token figures; shows
where context money actually goes (first finding: file Reads dwarf
everything - the wiki diet is the lever).
CARRIES: REPORTING_METHOD.md section "The usage sheet: mine the harness
meter, never self-estimate"; reference tools/usage_report.py; front door
STEP 2 paragraph.
GRAFT: copy usage_report.py fresh into the project's tools/, adapt its
output paths + the project-name filter in transcript_dirs(), add it to
the project's runner/metrics group, and add the section to the project's
copy of REPORTING_METHOD.md (or its local equivalent). Nothing existing
is touched.

### v1.2 - 2026-09-03 - The graft log itself
WHAT: this update mechanism. The kit carries a version and an append-only
log of concept entries; installs carry a "Rootstock vX.Y installed" line
in CLAUDE.md; updates are performed by grafting newer entries onto the
project's own files per the protocol above.
CARRIES: UPGRADES.md (this file); front door STEP 1 (the version line) +
the UPDATING section.
GRAFT: add the "Rootstock v1.2 installed" line to the project's CLAUDE.md
index. Do NOT copy this file into projects - the graft log lives in the
KIT only, where it stays current; a project needs just its version line.

### v1.3 - 2026-09-03 - The update check + the update policy
WHAT: projects stop discovering updates by luck. A small script reads the
project's install stamp, fetches the kit's UPGRADES.md (local clone or
the public repo over HTTPS), compares versions, prints any newer grafts,
and states what the CEO's update POLICY (ask/auto/relevant/never, kept in
the stamp line) tells the manager to do. Checks are rate-limited to
weekly, never fail offline, and ledger one line per check; wired into
standup, the reminder rides an existing habit instead of being one more
thing to remember.
CARRIES: reference tools/rootstock_update_check.py; the protocol's stamp
+ policy wording above; front door STEP 1 stamp + UPDATING section.
GRAFT: copy rootstock_update_check.py fresh into the project's tools/,
adapt STAMP_FILE/KIT_CLONE at its top, add it to the project's standup
script or runner group, and extend the project's stamp line with
"| updates: ask" (or the CEO's chosen policy - ask them once).

### v1.4 - 2026-09-03 - The last exchange from ground truth
WHAT: standup's verbatim replay of the final exchange (CEO's last prompt +
manager's last response) no longer depends on the day file, which is only
as fresh as the last checkpoint - a mid-arc /clear used to replay a STALE
or condensed exchange (it failed three times in one day before this).
Standup now mines THE LAST EXCHANGE directly from the harness transcripts
(~/.claude/projects/<slug>/*.jsonl, the same ground truth the usage sheet
meters): newest assistant text reply + the user prompt before it, skipping
tool results, command wrappers, and the standup trigger itself. Word for
word, image attachments counted, immune to manager discipline. The
day-file WHERE WE LEFT OFF remains the committed, searchable record.
CARRIES: reference tools/standup.py (print_last_exchange + the transcript
helpers); skills/standup + skills/checkpoint SKILL.md wording; front door
STEP 2 (both the script bullet and the protocol paragraph).
GRAFT: copy the _slug/_transcript_files/_mine_exchange/print_last_exchange
block from reference tools/standup.py into the project's standup script
and call it first; refresh the project's standup + checkpoint skills from
the kit's skills/ copies. Nothing else changes.

### v1.5 - 2026-09-03 - Honest prerequisites + the brownfield rule
WHAT: the first outside review (a stranger's Claude, fed the repo) found
two assumptions the kit never stated - it expects git and Claude Code -
and a real hazard: "install the kit" pointed at a live production repo
invited an unapproved restructure. Now written down: the front door opens
with WHAT THE FULL KIT ASSUMES; STEP 0 gains THE BROWNFIELD RULE
(inventory first, adopt what already exists under other names, propose
the mapping, get explicit CEO approval before editing anything existing,
never a stop-the-world restructure, production-sensitive files
untouchable without a named go-ahead) and MISSING PREREQUISITES (no git
or no Claude Code = a PARTIAL install of the pieces that stand alone,
skips recorded in the install stamp). reference tools/standup.py now
degrades instead of crashing when project.godot, git, CLAUDE.md, or
NEXT_STEPS.md are absent. README gains "What you need (and what still
works without it)".
CARRIES: front door (assumes block + the two STEP 0 rules); reference
tools/standup.py; the kit repo's README.
GRAFT: nothing to apply to healthy installed projects - this entry
protects FUTURE installs. If a project was installed partially, add the
skip markers to its stamp line (e.g. "| no-git") so update checks stop
offering machinery it cannot run.

### v1.6 - 2026-09-05 - The workflow registry (process amnesia killed)
WHAT: the kit remembered commands (the Script Rule) and results (ledgers)
but not CHOREOGRAPHY - the ORDER of a multi-step process. The origin
project ran an art pipeline for weeks with no written recipe and let seven
versions pile up unexported before noticing; after a /clear, order of
operations was re-derived from chat that no longer existed. Now:
WORKFLOWS.md at the repo root is THE PROCESS REGISTRY - one WHEN/STEPS/
VERIFY runbook entry per repeatable multi-step process, pointing at deep
docs rather than duplicating them. THE CAPTURE RULE: whoever performs a
process checks the registry first; a stale entry is a bug fixed in the
same batch; a missing entry is a WORKFLOW GAP captured in the same batch.
Employees never edit the registry - their stamp gains a WORKFLOW line
("matched <entry> | GAP: <uncovered process>") and the manager files the
gap or delegates the write-up to the cheapest model (a write-up is
transcription of the performer's own report, not discovery).
CARRIES: WORKFLOW_METHOD.md (the portable method + entry template +
bootstrap); front door STEP 1 (create the registry) and STEP 3 (the
WORKFLOW stamp line); skills/brief SKILL.md (compose item 5 + the
after-return gap step).
GRAFT: copy WORKFLOW_METHOD.md fresh to the project's repo root and index
it; create the project's WORKFLOWS.md seeded by transcribing its existing
processes (cheap-model work from existing docs and scripts); add the
WORKFLOW line to the stamp template in the project's SUBAGENTS.md
equivalent plus a cheap-tier "workflow write-up" row to its assignments
table; refresh the project's brief skill from the kit copy; add the
capture rule to the project's standing laws in its own voice.

### v1.7 - 2026-09-06 - The hooks (laws the harness enforces itself)
WHAT: every ritual ran from the manager's memory and every law was prose;
after a /clear the CEO had nothing until someone typed "standup", the
checkpoint counter ticked only when remembered, "never delete a build
zip" was a sentence. Claude Code HOOKS - scripts the harness runs at fixed
moments - fix the class. Five ship: SessionStart injects the standup
digest (startup/resume/clear/compact); Stop ticks the checkpoint counter
only when work happened (HEAD or tree-status fingerprint) and REFUSES to
end the turn once at DIRE; UserPromptSubmit prints the context gauge only
when a threshold is crossed; PreCompact ledgers every compaction;
PreToolUse on the shell tools denies what the laws forbid (generic:
--no-verify, plain force push; project block: the origin's build-zip,
runner-only, commit-dash and resource-file rules as templates). THE HOOKS
RULE: a law the harness can enforce mechanically gets a hook, not a
reminder. Manual --tick is retired (double-counts). Tier 3/4 ideas
(wiki/kit hygiene on Write|Edit, subagent stamp check, OS toasts) are
recorded in HOOKS_METHOD.md and the origin project's pin board.
CARRIES: HOOKS_METHOD.md (contract, the five hooks, tiers, bootstrap);
hooks/ (five scripts + _hooklib.py + settings.json template); reference
tools/checkpoint.py (work_fingerprint + hook state, reset stores the
fingerprint); skills/standup, checkpoint, ship (hook-aware wording); front
door STEP 4 (hooks install with the skills).
GRAFT: copy hooks/ into the project's tools/hooks/ (or its scripts folder;
the scripts find the repo root from their own path and import the
checkpoint script from the folder above); adapt bash_guard.py's PROJECT
RULES block to the CEO's laws; install hooks/settings.json as
.claude/settings.json (MERGE into an existing one, never replace arrays);
gitignore .claude/hooks_state.json; add work_fingerprint /
load_hook_state / save_hook_state to the project's checkpoint script (or
copy the reference one); reorder its checkpoint ritual so --reset runs
LAST; strike every "tick by hand" instruction from laws and skills;
pipe-test each hook; add the registry entry "Add or change a harness
hook" and a "The hooks" section to the tooling doc; index HOOKS_METHOD.md.

### v1.8 - 2026-09-06 - The workstation inventory (a machine that installs itself)
WHAT: the whole kit assumes tools already run - Python for scripts and
hooks, the engine for tests and builds, the art programs - and nothing
recorded what they were. A second machine, a reinstall or a
collaborator's laptop meant rediscovering the setup from error messages.
THE WORKSTATION RULE: the project keeps ONE workstation document
(requirement tables with the WHY per row + the install move, split
REQUIRED/OPTIONAL, the non-needs too, one section per known machine with
its deltas, the on-disk layout, and the harness's own settings); every
new dependency is written back to it in the same batch; a survey script
mirrors the tables and prints HAVE/MISSING, exits non-zero on a missing
required item, and ledgers one line; a new machine installs from the
document and is "up to par" when the survey says so. Machine paths go
through candidates + env override, never a lone hardcoded string.
CARRIES: WORKSTATION_METHOD.md (the rule, the table columns, per-machine
sections, bootstrap - including THE ASK: the receiving Claude surveys the
CEO's current machine and writes the first inventory from what it finds);
reference tools/workstation_survey.py (a working CHECKS-table probe with
ledger line; rewrite its rows); front door STEP 2 (the survey installs
with the reporting scripts).
GRAFT: create the project's workstation document from a survey of the
machine you are on (versions, paths, extensions, harness settings) plus
the CEO's answers for what you cannot see; copy the reference survey and
rewrite CHECKS to match; wire it into the parent loop's check group; add
the registry entry "Bring a new workstation up to par"; index the doc in
CLAUDE.md and add the write-back rule to the standing rules.

### v1.9 - 2026-09-10 - The fan-out guard (a runaway the manager cannot cause)

WHAT: a publicly reported catastrophe - a manager asked to "check my
markdown files for consistency" spawned 821 sub-agents and burned 50M+
tokens in thirty seconds - is the one mistake that outspends a month of
work in one turn. The delegation method gains LAW 6, THE FAN-OUT LAW:
sub-agents are spent money; a batch is a handful of parallel employees,
a session a dozen, never a burst, never an employee that spawns
employees, bulk-orchestration tools only at the CEO's per-use word; a
task that seems to need more is a design problem, never a bigger
fan-out. And because a law the manager can forget is not a guard rail,
the hooks gain TIER 2b: a PreToolUse hook on EVERY tool that meters the
session's spend from the transcript and refuses ONLY the runaway shapes
- a burst of spawns inside a minute, a flood inside ten, or token
velocity no real work produces - each clearing itself after a cooldown,
and warns the CEO (a system message) on everything else: spawn count,
session spend, velocity, the orchestration tool. CATASTROPHE-ONLY by
the origin CEO's ruling, hours after a strict first cut (session caps,
locks, CEO-only unlock commands) proved to be a rail on the path
instead of the cliff edge: "I don't want to have to type these commands
all the time and neither will any users who use Rootstock-os. I just
wanted to prevent complete runaway agents and gigantic token spend."
CARRIES: SUBAGENT_METHOD.md law 6; HOOKS_METHOD.md Tier 2b (+ the
cliff-edge lesson in its change log); hooks/fanout_guard.py (the guard,
LIMITS at the top, `--status` / `--resume` / `--selftest`);
hooks/settings.json (the every-tool PreToolUse entry); skills/brief
step 6 (the fan-out check before dispatch); front door THE HOOKS
paragraph.
GRAFT: add law 6 to the project's delegation rules and the fan-out check
to its brief skill; copy fanout_guard.py into the project's hooks
folder, set LIMITS with the CEO (the defaults never fire on real work),
run `--selftest`, gitignore `.claude/fanout_state.json`, wire the
every-tool PreToolUse entry, pipe one real tool call through it; add the
standing rule to the core instructions file and the row to the tooling
doc's hooks table. Nothing for the CEO to type afterwards - that is the
point.

### v1.10 - 2026-09-10 - The runaway numbers belong to the CEO
WHAT: the fan-out guard's limits stop being constants the manager edits
and become the CEO's setting. The origin CEO's ask, hours after the
catastrophe-only ruling: a skill "that allows the user to tune their
own runaway numbers. Calling the skill will give the current numbers
and then allow for changes." The script keeps DEFAULTS; the CEO's tuned
numbers live in a committed `.claude/fanout_limits.json` that overlays
them per key (junk falls back, a missing file means defaults), so a
kit graft never overwrites what the CEO chose. The guard grows
`--limits` (every number current vs default with its one-line meaning),
`--set key=value ...` (refusing a warn step above its halt, writing
nothing on any error) and `--defaults`; its self-test always runs at
DEFAULTS so tuning cannot fail it. The /runaway skill is the
conversational front: show, ask, set, selftest, commit. Only the CEO
tunes; the manager never raises a limit to get past a refusal.
CARRIES: hooks/fanout_guard.py (DEFAULTS + MEANING + load_limits /
set_limits / limits_table, the three flags, six new self-tests);
skills/runaway/SKILL.md; SKILLS.md shelf entry; HOOKS_METHOD.md Tier 2b
("THE NUMBERS ARE THE CEO'S") + change log; SUBAGENT_METHOD.md law 6
(the numbers clause); skills/brief step 6 (never raise a limit to get
past a refusal); hooks/README.txt; front door STEP 4 + THE FAN-OUT
GUARD paragraph.
GRAFT: replace the project's fanout_guard.py with the kit's (keep any
project wording; if the project had edited LIMITS by hand, move those
values into .claude/fanout_limits.json with `--set` and let the script
return to DEFAULTS); copy skills/runaway; add the shelf entry and the
law 6 clause; commit the JSON file (it is NOT gitignored - that is the
point); run `--selftest` and `--limits` once.

### v1.11 - 2026-09-10 - The spreadsheet rule (a sheet a human opens is an .xlsx)
WHAT: the origin CEO opened the usage CSV in Excel and asked for what no
CSV can carry - a frozen header row, thousands separators on every token
column, bold TOTAL rows in line under each period's last record with the
averages beside them, and a thick border under each total so the periods
read apart - "I want future Rootstock users to have their Claude
automatically do this when their Claude builds it." So THE SPREADSHEET
RULE joins the reporting method: any script producing a sheet a person
will open also writes an .xlsx twin in that shape (CSV/TXT stay for grep
and diffs), degrading to CSV-only with a printed note when the library is
missing. The reference usage sheet also grew THE BREAKDOWNS the same day:
averages per request, the context-window "box" (input + cache read +
cache written per request, average and biggest, by month), averages per
tool call, and per-employee runs (one sub-agent transcript = one run,
with its brief's first line) in their own CSV.
CARRIES: REPORTING_METHOD.md "THE SPREADSHEET RULE" section; reference
tools/usage_report.py (write_xlsx / _xlsx_sheet, the breakdowns, cache
v2, TOTAL rows last in their period, total_tok / avg_tok columns); front
door STEP 2 reference-tools paragraph; the openpyxl row for the
workstation inventory + survey.
GRAFT: add the rule section to the project's reporting doc; give every
human-opened sheet an .xlsx writer per the section's mechanics (or adapt
the reference script's two functions); add openpyxl to the workstation
inventory + survey CHECKS; run the sheet once and open the .xlsx to see
the frozen header and the ruled totals.

### v1.12 - 2026-09-10 - The weighted column, the comparison rule, and the diet guard
WHAT: the origin CEO's insight that only BUDGET-WEIGHTED tokens matter
("It's cool to see I used 200 million tokens, but my budget is only being
hit by 5 million. That should be the concept for any of the pillars"),
built end to end the same day. (1) THE WEIGHTED COLUMN: the usage sheet
prices every token by the API's own ratios (input 1, cache write 1.25 /
2 on the 1-hour cache, cache read 0.1 or 0.025, output 5) and makes that
the headline; raw is trivia beside it; the fan-out guard meters with the
same read weight per model. (2) CACHE MISSES counted and priced: a
request after a session's first whose cache write is most of its prompt
is a prefix rewrite - the origin's all-time waste was 24% of its budget.
(3) THE COMPARISON RULE ("a number without comparison means nothing"):
a daily line file, one line per active day judged against the previous
seven - weighted spend, misses, heavy whole-file reads, section-read
share - with a CHECK / normal / LOW verdict and the reason named; standup
prints its tail as THE BUDGET block and a CHECK is relayed verbatim.
(4) THE READ DIET (the 10k rule) and THE OUTPUT DIET (every emitted token
costs 5x) become law in the wiki method; the delegation method gains the
10k delegation line. (5) THE DIET GUARD (hooks/diet_guard.py, Tier 2c):
warn-only PreToolUse on Read|Bash|PowerShell - says a file's size and
sections before a whole read past 10k tokens, and the missing limiter on
a chatty shell shape (git log without a count, bare git diff, recursive
listings, noisy installs), capped per session. Never a refusal.
CARRIES: reference tools/usage_report.py (weighted, misses, read-diet
classes, pillar/diet sections, usage_daily.txt, --quiet, cache v3);
reference tools/standup.py (print_budget, --no-usage); reference
tools/checkpoint.py (usage outputs in FP_IGNORE); hooks/diet_guard.py +
settings.json entry + hooks/README.txt; hooks/fanout_guard.py
(READ_MULT); WIKI_METHOD.md "The read diet" + "The output diet";
REPORTING_METHOD.md "THE WEIGHTED COLUMN + THE COMPARISON RULE";
SUBAGENT_METHOD.md "THE 10k LINE"; HOOKS_METHOD.md Tier 2c + bootstrap
step 7 + change log; SKILLS.md + skills/standup (THE BUDGET block); front
door STEP 2 + THE DIET GUARD paragraph.
GRAFT: add weighted_tok (and the miss columns) to the project's usage
sheet per the reporting section, or adapt the reference script's
weighted() / daily_lines(); have standup print the daily line's tail;
exclude the sheet's outputs from the checkpoint fingerprint; copy
hooks/diet_guard.py fresh (nothing project-specific in it), wire its
PreToolUse entry, run --selftest, gitignore .claude/diet_state.json;
add the two diet sections to the project's wiki method and the 10k line
to its delegation method; if the project's fan-out guard predates this,
add READ_MULT so its meter agrees with the sheet.

### v1.13 - 2026-09-10 - Advised means do it (the checkpoint advisory becomes the act)
WHAT: the origin CEO, seeing a CHECKPOINT ADVISED line relayed for the
second prompt running: "If a checkpoint is advised, you should do it.
That way if you advise a checkpoint a user doesn't need to ask you to
checkpoint, they can simply clear. If the checkpoint is a script, there
is no reason not to just run it at the time a checkpoint is advised."
So an ADVISED line from the prompt gauge or the Stop hook is an
instruction: the manager runs the checkpoint ritual at the end of that
reply, unprompted, provided the arc is closed and the tree is committed;
the CEO then simply /clears. Mid-arc, the manager finishes the current
step, ships it, and checkpoints before taking new work. The hooks' own
wording changed to match ("checkpoint at the end of this reply if the
arc is closed" instead of "suggest ... at the next arc boundary"). The
honest limit stays: the day file stores the manager's final reply word
for word, which no script can see before it is sent, so the script does
the mechanics and the manager writes the two paragraphs.
CARRIES: skills/checkpoint/SKILL.md (the rule at the top + the gauge
paragraph); hooks/prompt_gauge.py + hooks/stop_tick.py (ADVISED
wording); HOOKS_METHOD.md Tier 1 item 2 + change log; SKILLS.md change
log; the origin's core-file checkpoint protocol.
GRAFT: add the ADVISED MEANS DO IT paragraph to the project's checkpoint
skill and its checkpoint law; reword the project's gauge/stop hook
ADVISED strings so they say "checkpoint at the end of this reply if the
arc is closed" (keep the project's own owner name); nothing else moves.

### v1.14 - 2026-09-10 - The preservation law, the cold shelf, the learning loop
WHAT: two of the origin CEO's asks in one evening. (1) THE PRESERVATION
LAW, after public reports of an agent whose script deleted a person's
files and another that wiped a machine: "You nor any of your employees
should ever delete a file, record, etc. without express permission from
the user. There should be no script created to delete either (without
express permission of the user and a complete, double acknowledged
approval of such)... We never want to lose knowledge, all of this is
hard fought, hard earned knowledge, even the rarely used knowledge."
Hence hooks/preserve_guard.py (Tier 2d, a refusal on delete verbs,
work-discarding git verbs and deletion calls written into scripts;
scratchpad and prose pass; one command per double-acknowledged grant;
drive roots / home / repo root never), reference tools/delete_grant.py
(the four verbatim texts, single use, ledgered), reference
tools/retire.py (files move to a shelf folder, ledgered) and reference
tools/cold_shelf.py (rarely-read wiki sections move to docs/cold/
verbatim with a stub at the old heading and an index; --restore
reverses). (2) THE LEARNING LOOP, after "does Rootstock learn?": three
read-only scripts - check_wiki_links.py (dead See-also targets),
wiki_heat.py (read counts per wiki section mined from the harness
transcripts; the cold candidates), ledger_trends.py (ledger tails vs a
thresholds table -> PROPOSE lines printed at standup; nothing applied,
the CEO rules). The audit the law forced found the kit-mirror script
emptying its target before copying; it now refuses a target whose
README does not name the kit and reports stale files instead.
CARRIES: hooks/preserve_guard.py + hooks/settings.json (its PreToolUse
entry) + hooks/README.txt; reference tools/{delete_grant, retire,
cold_shelf, check_wiki_links, wiki_heat, ledger_trends}.py;
HOOKS_METHOD.md Tier 2d + bootstrap step 8 + change log; WIKI_METHOD.md
"The cold shelf" + "The learning loop"; SUBAGENT_METHOD.md law 7;
skills/brief (THE PRESERVATION LINE, step 7); SKILLS.md change log; the
front door's STEP 4 hooks block.
GRAFT: copy the guard + wire its entry + selftest + gitignore the grant
file; copy the three movers and the three loop scripts into tools/ and
wire the loop scripts into the project's check/metrics groups and its
standup (the trends block prints after the budget block); add law 7 to
the project's delegation rules and the preservation line to its brief
skill; add the two registry entries (delete ritual; retire/cold shelf);
give the core file a one-line index entry for docs/cold/INDEX.md and the
law's paragraph. Then AUDIT existing scripts for deletion calls and
bring each to the CEO - convert to a move, or keep with the CEO's word
recorded. Nothing else moves; a project's own shelf folder name and
thresholds are its own.


### v1.15 - 2026-09-10 - Index-first reads, pictures priced by pixels, why cold is cold
WHAT: three corrections to the learning loop, all born the evening the
loop's first proposals were audited. (1) INDEX FIRST in the diet guard:
the first whole read of a big file per session is refused and the
refusal carries the file's own index (headings or function lines with
line numbers, capped at 80); the same call repeated passes with a
warning - the CEO's "section or split ... should not require my
approval" made mechanical. (2) The usage sheet prices an image read by
PIXELS (~w*h/750 after the API downscale, ~1-2k tokens), never by its
base64 bytes: the old sizing made every screenshot a 100k "big read"
and the sheet proposed diet fixes for a habit nobody had. A per-file
big-reads ledger (tools/big_reads.py) names WHICH files were read whole
and the fix each needs; the manager acts on it unasked. (3) The heat
map says WHY a cold file is cold (git activity in the code area it
documents: active-unread / current / dormant / process / reference /
archive) and a whole-file read counts as seeing a section; only
active-unread ever reaches a proposal - cold by read count is never a
shelf reason (the CEO: game work touches certain files at certain times;
the wiki is a human reference too). Trends proposals count only
diet-named CHECKs and judge big reads on the last three active days.
CARRIES: hooks/diet_guard.py (INDEX FIRST, image silence, selftest);
reference tools/{usage_report, wiki_heat, ledger_trends, big_reads}.py;
HOOKS_METHOD.md Tier 2c + change log; WIKI_METHOD.md "The read diet"
(index first, the measurement lesson) + "The cold shelf" (why cold).
GRAFT: refresh the diet guard and run its selftest; copy big_reads.py
into tools/ and add it to the metrics group; if the project's usage
sheet sizes tool results, add image_tokens and bump its cache version;
give wiki_heat an AREA_MAP for the project's own doc->code areas (the
kit copy carries Everwood's as the worked example - replace it); reword
the project's cold proposal to active-unread only. Nothing else moves.

### v1.16 - 2026-09-11 - The hygiene guard, the README check, and /preserve
WHAT: the first PostToolUse hook and the preservation law's front, born
the morning the kit's public README was found two versions behind (the
CEO: "we definitely don't want the readme falling behind again"). (1)
THE HYGIENE GUARD (Tier 3): after every Write/Edit lands, one stateless
script says the law that applies to THAT file at the moment of the edit:
a portable original -> refresh its kit copy, the graft log + version if
a concept changed, the public README if a pillar/skill/hook/box item
changed, then sync; a kit copy edited directly -> edit the original; the
core instructions file -> its lint runs and a FAIL is relayed; a touched
wiki-topic section without a See-also line -> named; a forbidden
character (em/en dash) in player-facing text -> the edit is BLOCKED with
the offending lines; a new asset -> run the import. (2) THE README
CHECK: the kit sync script refuses to push while the public README's
"Kit version:" line lags the graft log's CURRENT KIT VERSION - the one
mechanical place a README-only-in-the-public-repo can be caught. (3)
/preserve: the preservation law lived in prose plus three loose scripts;
the skill takes a target and offers retire, shelve, then the
twice-acknowledged delete grant, in that order, with the exact words
recorded. Lesson: a reminder that fires at the edit is worth ten in a
law file - the README fell behind while the law to refresh it was
already written.
CARRIES: hooks/hygiene_guard.py (+ its PostToolUse entry in
hooks/settings.json, hooks/README.txt); HOOKS_METHOD.md Tier 3 +
bootstrap step 9 + change log; skills/preserve/SKILL.md; SKILLS.md
(shelf entry + change log); the front door STEP 4; WORKFLOW_METHOD's
instance gains a README step in "Edit the future-project kit".
GRAFT: copy hygiene_guard.py, rewrite its CONFIG block for the project
(portable file names, kit folder, skills/hooks dirs, core file + lint
command, wiki dirs, player-text patterns, assets folder), wire the
Write|Edit|MultiEdit PostToolUse entry, run `--selftest` (25 checks).
A project that publishes its own kit: add a "Kit version: vX.Y" line to
the public README and the version check to its sync script. Copy the
/preserve skill and list it on the shelf. A project with no player-
facing text keeps the DASH rule's pattern list empty. Nothing else
moves.

### v1.17 - 2026-09-13 - The README gate (parity lint, graft README line, audit cadence)
WHAT: the 09-13 four-employee audit of the public README found three
prose slips the v1.16 version check could not see (a law count still
"six", settings.json sent to the wrong folder, a mechanic misdescribed)
and a page of mechanics nobody had been asked to write. The CEO: "What
can we do to prevent the Readme from falling behind so far and missing
information like that in the future?" Three layers, cheapest first.
(1) THE PARITY LINT: a script derives every countable README fact from
the kit folder itself - the law count from the delegation method's
numbered list (and its heading's own number word), the skills from the
skills dir (count word + every /name), the hooks from the hooks dir, the
reference-tool count, every box-table row against the kit's top level
and back, the version line - plus a small CLAIMS table of grep-able
prose facts (a must-match and a must-not-match per slip already seen).
The kit sync REFUSES to push on any FAIL; the check group runs it; a
ledger line per run. (2) THE GRAFT README LINE: every graft entry gains
a fourth field, README, naming the public-README section the concept
touched or "none, wording only"; the lint fails while the newest entry
lacks it, so "did this reach the front page?" is decided when the
concept ships, not remembered later. (3) THE AUDIT CADENCE: the audit
itself (read-only employees compare the README against every method
file, the skills, the hooks and the front door) is ledgered with
`--record`; ledger_trends PROPOSES the next one at standup when the kit
folder has moved past a commit count or an age since the last line
(owner's thresholds). Lesson: a version line is one fact; a README is
a hundred, and the ones that drift are the ones no script reads.
CARRIES: reference tools/readme_lint.py (+ its refusal in the kit sync
script and its check-group line), reference tools/readme_audit.py,
reference tools/ledger_trends.py (rule 7 + two thresholds), this file's
README field (from this entry on), the process registry's kit entry
(step 3 rewritten) and its new "Audit the public README" entry.
GRAFT: a project that publishes its own kit or keeps any public README
whose facts derive from files: copy readme_lint.py, rewrite its CONFIG
block (README path, source-of-truth files, box heading, CLAIMS rows),
call it from the publish/sync script as a refusal, add it to the check
group, run `--selftest`. Add the README field to the project's own
graft-log entries from its next entry on. Copy readme_audit.py, graft
rule 7 and the two thresholds into the project's ledger_trends, record
the last audit (or let the "none on record" proposal ask for the
first). A project with no public README skips this entry whole.
README: "Updating an installed project" (the README field + the gate
sentence), "What is in the box" (reference tools: sixteen), the
"Kit version:" line.

### v1.18 - 2026-09-13 - The intent loop (INTENT.md, the comparison ledger, /correct, the systems audit)
WHAT: the CEO, the same morning as the README gate: "I believe Intent would
help cover the 'why' of something which may help you or any Claude make
better decisions in the future. It's not as important that you know to
make looping scripts because you were told to, it's almost more important
that you understand we make looping scripts because 1.) It decreases your
token usage, 2.) It's done the same every time and very structured, 3.)
It's something that triggers without asking." Four parts. (1) THE INTENT
FILE: one INTENT.md per project, one section per ruling - ASKED (the
owner's prompt verbatim), WHY (the owner's numbered reasons verbatim),
GENERALIZES TO (the manager's reading, marked as such), LIVES IN; a brief
pastes the section; a missing section IS the question to ask. (2) THE
COMPARISON LEDGER: before building, the manager logs its OWN reading of
the ask (a CLAIM); employees state theirs in a stamp line; when the
owner's intent is known the claim resolves SAME / SIMILAR / DIFFERENT
with its source named (stated / correction / inferred - self-judged
agreement is counted apart so it never inflates the rate). A script turns
the log into day / week / month / actor agreement rates - txt for Claude,
csv + xlsx for a human - and calls the trend IMPROVING / STEADY /
DECLINING. The owner's why, verbatim: "we 1.) Want to have real data, 2.)
We want to compare past to present, 3.) We want to know if we are
improving, staying the same, or declining because each one of those will
tell us something about our feedback loop." (3) THE CORRECTION RITUAL:
/correct asks "What about the last thing I did needs correcting?",
records the owner's words verbatim, resolves the open claim DIFFERENT by
itself, then asks "What was the intent?" and /intent files the why - one
feedback loop. (4) THE SYSTEMS AUDIT: the loop measured but never thought;
a ledgered, cadence-proposed audit by a handful of read-only employees
in four lanes (tokens, process, knowledge, features) returns proposals
only. Three new trend rules propose on a declining agreement, stale
claims, clustered corrections and audit age. Lesson: knowing the rule
lets a Claude comply; knowing the why lets it decide the case the rule
never named.
CARRIES: INTENT_METHOD.md (the portable method + bootstrap); reference
tools/intent_log.py, correction_log.py, intent_report.py,
systems_audit.py, ledger_trends.py (rules 8-10 + four thresholds);
skills/intent and skills/correct (+ SKILLS.md shelf entries); the /brief
skill's step 8 (paste the intent, require the INTENT line); the front
door's THE INTENT LOOP step.
GRAFT: create INTENT.md from INTENT_METHOD.md's format with the first
ruling the day one is made (never a backfill sweep); copy the four
scripts, adapt paths; add intent_report to the metrics loop; graft rules
8-10 + thresholds into the project's ledger_trends; copy the two skills
and list them on the shelf; add the employee INTENT stamp line to the
delegation rules and the paste-the-section step to the brief ritual; add
INTENT.md and INTENT_METHOD.md index lines to the core file. A project
with no owner rulings yet still creates the empty INTENT.md - the first
correction fills it.
README: "4. Lossless Sessions" (eight rituals, /intent and /correct), a
new "The intent loop (INTENT_METHOD.md)" section after the hooks, "What
is in the box" (INTENT_METHOD.md row, reference tools: twenty), the "Kit
version:" line.

See also: 'Future Project MDs/CONTRIBUTING.md' (the format law); '0 - READ
  ME FIRST, CLAUDE.md' (installs from this log);
  tools/rootstock_update_check.py (reads this file to check for updates).

### v1.19 - 2026-09-13 - The format law, the purpose audit and the kit-sync ruling (CONTRIBUTING.md, FLAGS.md, /flag, the format guard)
WHAT: the CEO, the same day as the intent loop, three rulings in one
prompt. (1) THE KIT-SYNC RULING: "Every time I discuss rootstock-os, or
it's features, scripts, audits, intents, laws , etc. the intention is to
update the future projects and rootstock-os folder and upload to git
with updated readme and files whenever applicable." A kit refresh script
(originals -> copies, the owner-name substitution in scripts, adapted
copies reported not overwritten) runs first inside the sync, and the
prompt hook says KIT UNSYNCED until copies and mirror agree. (2) THE
PURPOSE AUDIT: "Rootstock-os will eventually, hopefully, turn into a
community involved system. Guardrails need to be in place so that
anything written in updates must have a comment describing the purpose
and intent of the 'thing' in the update. Claude MUST compare the purpose
and intent of the thing vs what the thing actually reads whether it's a
script, hook, code or injectable prompt. If there is reason to flag it,
Claude should flag them green, yellow or red. Claude should always
read-only -> Flag -> Explain. There should be a file that directly
references anything that is green, yellow or red flags, tally them and
put them in the git for review. Any Claude can review and put their
findings there for future review." FLAGS.md is that file: one entry per
audit (SAYS from the thing's PURPOSE line, DOES, FLAG, hash of the exact
version), append-only, the tally regenerated at its top by script, STALE
when the thing changes; the /flag skill and a WORKFLOWS entry carry the
ritual; employees may flag (delegation rule 15) and report RED upward.
(3) THE FORMAT LAW: "Any updates, upgrades, hooks, scripts, etc need to
be in the same format so that they work with our current filing system.
Anything without proper format should be flagged, a script should
re-write it after review-only audit. This will be a law and may need
this to be a hook somehow so that no one can inject a prompt that
overrides safety protocols." Every kit thing carries PURPOSE / INTENT /
Search keys / See also (a hook also --selftest + _hooklib, a skill its
frontmatter, the settings template its SAFETY wiring); the format lint
derives the scope from the kit folder, flags the rest, and --rewrite
inserts ONLY the missing lines with the reviewer's words after a
read-only look; the format guard hook (Tier 3b) blocks an unformatted
edit and REFUSES a settings edit that unwires, narrows or mis-points a
safety hook, with the shell guard (no shell writes into a settings file)
and the Stop hook (refuses the turn while the wiring is broken) as
twins. The first audit: four read-only employees flagged every kit thing
in one batch (FLAGS.md carries the result). Lesson: a guardrail for a
community kit cannot depend on the reader's good faith; it has to be a
script that flags, a script that rewrites, and a hook that refuses.
CARRIES: CONTRIBUTING.md (the two laws for contributors); FLAGS.md (the
ledger); reference tools/format_lint.py, purpose_audit.py,
refresh_kit.py; hooks/format_guard.py + its settings.json entries
(PreToolUse and PostToolUse on Write|Edit|MultiEdit); hooks/bash_guard.py
rule (no shell writes into a settings file); hooks/stop_tick.py (the
Stop twin); hooks/prompt_gauge.py (the KIT UNSYNCED line); skills/flag;
SUBAGENT_METHOD.md law + SKILLS.md shelf entry; HOOKS_METHOD.md Tier 3b;
the front door's THE FORMAT GUARD + THE PURPOSE AUDIT step and the
definition of done; the sync script's refresh + first gate + tally.
GRAFT: copy the three scripts and the hook, adapt the CONFIG blocks
(kit folder, hooks/skills dirs, settings path); wire the hook's two
entries; add the settings-file rule to the project's shell guard and the
Stop twin to its stop hook; add format_lint + purpose_audit --pending to
the check group and the refresh + gate + tally to the publish script;
copy CONTRIBUTING.md and let the first status run create FLAGS.md; run
`format_lint.py` and rewrite each failing header BY SCRIPT after a
read-only look (never by hand); then audit every thing once (a handful
of read-only employees, one list each) so FLAGS.md starts with real
data; add the /flag skill to the shelf and the flag rule to the
delegation rules. A project with no public kit still keeps the format
law for its own tools and hooks.
README: "The hooks" (ten, the format guard bullet), "4. Lossless
Sessions" (nine rituals, /flag), a new "The format law and the purpose
audit (CONTRIBUTING.md)" section after the intent loop, "What is in the
box" (CONTRIBUTING.md + FLAGS.md rows, skills: nine, hooks: ten,
reference tools: 23), "Questions people ask" (Can I contribute?), the
"Kit version:" line.

### v1.20 - 2026-09-13 - The first audit's yellows closed (every hook answers --selftest, the front door read independently)
WHAT: the CEO read the five yellows from the kit's first purpose audit
(v1.19) and said "Do it all, make it happen." (1) The three info-only
hooks (session_start, prompt_gauge, pre_compact) now answer
`--selftest` like every guard: module-level work moved into main(), the
pure builders (ledger line, gauge lines, header) factored out so a
selftest never touches stdin, a real ledger or the standup script; live
output byte-identical. Every hook in the kit now carries a selftest,
which the format lint already expected. (2) The diet guard's docstring
and the hooks README stopped saying it "never refuses": it refuses once
per big file (INDEX FIRST, v1.15) and warns on everything else. (3) The
front door got its first full read by a reviewer who did not write it.
The read found the PURPOSE line claimed a four-pillar install while a
third of the file installs the hooks, and the STEP 4 skill list lacked
/correct /intent /flag; both fixed, re-read, GREEN. FLAGS.md: 58
flagged, 58 GREEN, 0 YELLOW, 0 RED.
CARRIES: hooks/pre_compact.py, hooks/prompt_gauge.py,
hooks/session_start.py (the selftests); hooks/diet_guard.py and
hooks/README.txt (the wording); the front door's PURPOSE line and STEP
4 list; FLAGS.md (the re-flags); HOOKS_METHOD.md change log.
GRAFT: copy the three hooks over the installed ones if they were taken
unchanged (their live behaviour is identical; only the structure and
the selftest are new) - if the project adapted them, graft the main()
split and the _selftest() by hand and keep the project's text. Reword
the diet guard's docstring the same way if the install kept the v1.12
wording. Re-flag whatever changed. Then the lesson, which is the real
graft: have a non-author read the front door of YOUR install whole once;
three author passes missed what one independent read found.
README: "The hooks" (the contract bullet: every kit hook answers
--selftest), "The format law and the purpose audit" (the first audit's
outcome line), the "Kit version:" line.

### v1.21 - 2026-09-14 - The first systems audit, ruled and built (the loop law, trust the ledger, the ledgers born, open questions)
WHAT: the systems audit (v1.18) ran for real: four read-only employees,
one lane each, 26 proposals with evidence, nothing applied by the audit.
The CEO ruled on all 26 the same night; this version is what the rulings
built. (1) THE LOOP LAW ("Any script that should be run multiple times
must be called by the main looping script; every action, every
standup"): run_all.py ledgers every group run (loop_runs.txt), the
session-start hook runs the session group once a day and measures the
digest it injects (digest_size.txt), standup shows THE LOOP (each
group's age), ledger_trends proposes on a stale group (rule 13), a big
digest (rule 12) and an old open question (rule 11); probes ride every
build. (2) TRUST THE LEDGER for the check scripts: _ledger.py, one
helper at four append sites (format lint, purpose audit, README lint,
link check) skips an identical result at an unchanged tree - gotcha
found on the way: a ledger's own append changes the tree signature, so
the ledgers exclude themselves. (3) The three preservation ledgers
(retired_files, delete_grants, corrections) had never been born; the
movers got --selftest against a temp dir and the ledgers exist
header-only. (4) open_questions.py: a ledger for decisions only the
owner can make, with age, shown in standup. (5) usage_report: avg tokens
per Read on the daily line, usage_by_arc.txt (checkpoint to checkpoint,
per-commit verdict), cache_misses.txt with causes (first finding: TTL
gaps dominate - the price of coming back after an hour, not a habit).
(6) stop_tick warns CHANGELOG UNEXPORTED; /checkpoint closes the loop
first; /flag's batch rule sends more than five things to one employee
("employee is cheap. Manager is not."). (7) Proposal-only thresholds
moved to .claude/trend_limits.json; guard numbers stay in code
(SECURITY FIRST, then cost, then efficiency - the CEO's order).
CARRIES: reference tools/run_all.py, open_questions.py, _ledger.py
(new); reference tools/standup.py, ledger_trends.py, usage_report.py,
format_lint.py, purpose_audit.py, readme_lint.py, check_wiki_links.py,
retire.py, delete_grant.py, correction_log.py; hooks/session_start.py,
hooks/stop_tick.py; skills/checkpoint, skills/flag; INTENT_METHOD.md
(the loop law + security-first sections); this entry.
GRAFT: adopt run_all.py's GROUPS for your own habitual scripts, then let
the session-start hook call it (the hook degrades to a note when
run_all.py is absent). Wire _ledger.append_unless_identical at every
append site you have that can run twice at one tree. Run the three
movers' --selftest once and let them birth their ledgers. Add the three
trend rules and the limits JSON; keep your guards' numbers in code.
Seed open_questions.txt with whatever your owner has not answered yet.
README: "The intent loop" (the first audit's outcome paragraph), "What
is in the box" (26 scripts, the parent loop, open questions, trust the
ledger).

### v1.22 - 2026-09-14 - The core diet (CLAUDE.md is the hot core; cold sections move by script to sub-indexes; the front door renamed)
WHAT: (1) A Reddit reader measured the kit's front door, then named
"0 - READ ME FIRST, CLAUDE.md", at ~5k tokens and called the kit slop.
The file was an install runbook, never a per-session CLAUDE.md, but the
name invited the misread and the origin's real CLAUDE.md had drifted to
~10k tokens while its own law said "index only". The CEO's ruling: the
core keeps the most-used information and what falls out of the heat map
moves BY SCRIPT into named, growable sub-indexes. (2) THE HOT CORE: the
core lint (check_claude_md.py) now FAILS on a TOKEN budget (bytes/4;
TOKEN_BUDGET, origin 3,500) and requires every docs/index/ sub-index to be
named in the core. (3) THE MOVER: reference tools/core_diet.py measures
every core section's heat (explicit reads of its lines from the
transcript cache, reads of the wiki files it points at, git recency
inside `core_cold_days`), moves COLD routed sections (`Index: <name>`;
`Index: core` pins) verbatim into docs/index/<name>.md with a provenance
comment and, while still over budget, the coldest routed sections next;
each move leaves ONE stub line (`- heading -> docs/index/x.md | brief`,
the brief from the section's Tags line) in the core's "## The
sub-indexes" block. Unrouted cold sections are only PROPOSED.
`--move-section` is the explicit call, `--restore` reverses, `--selftest`
proves the round trip. It runs in the check group BEFORE the lint. (4)
The scanners (wiki_heat, check_wiki_links, export_tag_index,
export_wiki_view, cold_shelf) discover docs/index/*.md as wiki files.
(5) THE FRONT DOOR is renamed "0 - READ ME FIRST.md" and cut to
pointers (~1.8k tokens from ~4.5k): each step points at its method
file's bootstrap section instead of restating it. (6) THE DIGEST DIET:
standup prints the day file's STATE/NEXT lines but not its copy of the
exchange when the transcript block already replayed it, and one tail
line per ledger instead of two. (7) The origin's CLAUDE.md went from
~10k tokens to ~3.5k: the standing rules to docs/index/laws.md, the
long-form library + kit rules to library.md, versioning/changelog to
process.md, engine gotchas to gotchas.md, the folder map to code.md.
CARRIES: reference tools/core_diet.py (new); reference tools/
check_claude_md.py, run_all.py, standup.py, wiki_heat.py,
check_wiki_links.py, export_tag_index.py, cold_shelf.py;
hooks/hygiene_guard.py (the front door's name); WIKI_METHOD.md "The hot
core and the sub-indexes" + the architecture layer 1; the front door
"0 - READ ME FIRST.md" (renamed, rewritten); this entry.
GRAFT: give your core lint a TOKEN budget (bytes/4) and fail on it; copy
core_diet.py, adapt CORE_NAME / INDEX_DIRNAME / the trend-limits key,
run `--selftest`, put it in the check group BEFORE the lint; stamp your
core's sections with `Index: <name>` (laws, library, process, gotchas,
code are the origin's names - use your own) and `Tags: ... | brief`;
run `--move-section` for what should leave now and let the loop handle
the rest; teach your wiki scanners the docs/index/ folder; if your
project's install file carries "CLAUDE.md" in its name and is not one,
rename it. Trim your standup the same two ways if its digest passes
~24k bytes.
README: "Doesn't a wiki make the context HEAVIER?" (the table's core and
digest rows), the new "The installed CLAUDE.md: what it holds and how
big it is" subsection, "Quick start" (the front door's name), "Questions
people ask" (the Reddit question), "What is in the box" (the front door
row, 27 scripts, core_diet).

### v1.25 - 2026-09-14 - The digest diet (the standup prints what the manager acts on; the loss test)
WHAT: after the core diet and the pointer core, the standup digest was
the largest fixed load at session start (~4.3k tokens on the origin).
Measured by block, LEDGER TAILS was 35% of it (33 ledgers, one full line
each, most unchanged for days) and several blocks repeated another (the
daily usage line, the open questions, the day index, the summary twin of
every *_runs ledger). The CEO's condition: "the most important pieces are
context and efficiency. As long as there is no loss there, I'm happy."
THE LOSS TEST: a line leaves the digest only when it duplicates another
block, or carries no verdict and is one `tail -1` away by a path the
digest already prints. Never cut: THE LAST EXCHANGE (the verbatim law)
and WHERE WE LEFT OFF. The rest: a ledger's newest line prints in full
only when it carries a verdict (CHECK, FAIL, RED n, STALE, WARN, UNSYNCED,
a cliff) or is newer than the previous standup (digest_size.txt's last
line); the others collapse to `name date` on shared "quiet" lines;
duplicated ledgers are skipped; commits 12 -> 5; RECENT DAYS prints each
day's first clause. Same session, before/after: 17.4 KB -> 6.3 KB (-64%).
The warn threshold followed the size down (digest_warn_bytes 24000 ->
12000), so growth is caught at the new floor, not the old ceiling.
CARRIES: reference tools/standup.py (SHOWN_ELSEWHERE, has_verdict,
line_stamp, last_standup_stamp, tails_plan, wrap_names, first_clause,
--selftest); reference tools/ledger_trends.py (the lowered default);
REPORTING_METHOD.md is unchanged (the ledgers themselves are untouched).
GRAFT: copy standup.py fresh (keep the project's version-source block);
lower digest_warn_bytes in the project's trend_limits.json to about twice
its post-diet digest size; add the project's own verdict words to
_VERDICT if its ledgers use others; add any ledger another block already
prints to SHOWN_ELSEWHERE. Then run the digest twice and diff: every line
that left must fail the loss test.
README: "What actually loads" tables (the digest row: ~1.6k-2k tokens).

### v1.24 - 2026-09-14 - The quiet audit (FLAGS.md's stamp means last changed, not last run)
WHAT: the purpose audit's tally block carries an "Updated" stamp, and the
loop runs the audit at every standup, so the stamp was rewritten every
session even when no flag, row or count had moved. The mirror check saw
one byte-different kit file and the prompt hook said KIT UNSYNCED on
every prompt over nothing (the origin's open question Q0003). The CEO
ruled option 2, fix the cause, over the cheap fix of teaching the mirror
check to ignore that line: the audit now compares the fresh tally block
against the one in the file with the stamp masked, and skips the write
when nothing else changed. The stamp now means LAST CHANGED; the runs
ledger (purpose_audit_runs.txt) still records every run. A generated
line inside a committed file must not churn on a no-op run: a sync
warning that fires on noise trains everyone to ignore it.
CARRIES: reference tools/purpose_audit.py (regenerate() returns False on
a stamp-only difference; selftest covers both branches); FLAGS.md (the
generated tally, unchanged in shape).
GRAFT: copy purpose_audit.py fresh over the project's adapted copy (the
change is inside regenerate() and one helper; keep any local KIT_DIR or
ledger-path edits). If the project's mirror check or sync hook was taught
to ignore the Updated line as a workaround, drop that exception in the
same batch. Any other generated stamp in a committed file gets the same
treatment: rewrite on change, never on a run.
README: "The format law and the purpose audit" (one sentence: the tally
stamp moves only when a flag moves).

### v1.23 - 2026-09-14 - The pointer core (CLAUDE.md points, the master index lists, rules load by path; Anthropic's 200-line target guarded)
WHAT: (1) THE SECOND RULING on the core, the same day as v1.22. The CEO
asked whether a single MASTER_INDEX would be the right call ("Claude.md
should simply point to everything else") and had the manager read
Anthropic's memory page (code.claude.com/docs/en/memory) before ruling.
The page settles the mechanics: target under 200 lines per CLAUDE.md;
`@path` imports and rules WITHOUT a paths field load at launch, so moving
must-read text into them "helps organization but doesn't reduce context";
a `.claude/rules/*.md` file WITH `paths:` front matter loads only when
Claude reads a matching file; CLAUDE.md is guidance and hooks are the
enforcement layer; block HTML comments are stripped before injection.
The CEO's must-read chain enforced by hook was dropped by his own
verdict ("your response is likely more correct than mine"); the master
index and the smallest-possible core were kept. (2) KNOWLEDGE HAS THREE
HOMES, by when it is needed: ALWAYS -> CLAUDE.md, the pointer core (the
project in a paragraph, how to read, how to verify, the laws no hook
enforces, one pointer to the master index; the origin: 68 lines, ~900
tokens, from ~3.5k); WHEN A MATCHING FILE IS READ -> path-scoped rules
(the origin: game-code.md for scripts/scenes/shaders, player-text.md for
.tres/ui/store/changelog text, wiki.md for every .md; each moved VERBATIM
with the core diet's provenance comment so --restore still works; the
format header sits in a stripped HTML comment, free); ON DEMAND ->
docs/index/MASTER_INDEX.md, THE ONE DOOR (every topic file, root file,
sub-index, law stub, rule and knowledge file, one line each, every
destination direct). The cross-workstation notes moved to
docs/index/notes.md; standup prints their headlines from there. (3) THE
GUARD: check_claude_md.py now fails past LINE_BUDGET 200 (Anthropic's
number) or TOKEN_BUDGET 2,000 (the CEO's action line), WARNS past
WARN_TOKENS 1,000, requires CLAUDE.md to name the master index, the
master index to list every docs/systems and docs/index file and every
rule, and fails on a rule with no paths field (it would load every
session; its tokens are counted against the core). standup prints the
lint's OK/WARN line under "== THE CORE" so the owner sees the size every
session; the hygiene guard runs the lint the moment CLAUDE.md, the master
index or a rule is edited. (4) core_diet.py's stub block now lives in the
master index, not the core (selftest proves the round trip both ways;
a pre-v1.23 core still holding its own block restores cleanly). (5)
check_wiki_links treats the master index like the core (every docs/
mention must resolve); refresh_kit carries PORTABLE_RULES (rules/wiki.md
travels; game and text rules stay per project). (6) WORKFLOWS gained "Add
or change a path-scoped rule"; the front door's STEP 1 and definition of
done name the master index, the rules and the size line.
CARRIES: rules/wiki.md (new, the first kit rule); reference tools/
check_claude_md.py, core_diet.py, standup.py, check_wiki_links.py,
refresh_kit.py; hooks/hygiene_guard.py (CORE_CONTRACT); WIKI_METHOD.md
(architecture layer 1 + "The hot core and the sub-indexes": the second
ruling and the three homes); the front door STEP 1 + definition of done;
this entry.
GRAFT: rewrite your core as a pointer file (identity, how to read, how to
verify, the laws no hook enforces, ONE line naming docs/index/
MASTER_INDEX.md); build the master index from the core's old library
lines and its sub-index stub block; move each part-of-the-codebase rule
set VERBATIM into `.claude/rules/<topic>.md` with a `paths:` list first
and the core-diet provenance comment; copy rules/wiki.md and adjust its
paths; take the new check_claude_md.py (set LINE_BUDGET 200, TOKEN_BUDGET
and WARN_TOKENS to your owner's numbers, never raise them later),
core_diet.py, standup.py, check_wiki_links.py, refresh_kit.py and the
hygiene guard; run core_diet --selftest and check_claude_md; confirm a
rule loads by opening a matching file and running /context.
README: the new top section "What loads every session, what Anthropic
says, and what guards it" (right after the intro), the "Doesn't a wiki
make the context HEAVIER?" table (core row ~900 tokens / 68 lines), "The
installed CLAUDE.md: what it holds and how big it is" (rewritten for the
three homes), "Quick start" (the core lands under Anthropic's target),
"What is in the box" (the rules/ row, 27 scripts), "Questions people ask"
(the size question answered with Anthropic's number).

### v1.26 - 2026-09-20 - The lesson loop (LESSONS.md, the one right way first; LESSON ADVISED)
WHAT: the kit learned WHAT (the wiki, the tag index) and captured HOW in
steps (WORKFLOW_METHOD.md), but judgment - do this first, here is what
looked right and was not, here is what changes when A differs from B -
had no home and nothing pushed the manager to write it. The CEO's ask:
"something to push you to write what you learned, as well as push you to
add to the knowledge base ... so in the future you don't make the same
mistakes and just do the one correct way first". THE LESSON LAW: one
book, LESSONS.md, one entry per task shape (heading in a prompt's words;
Tags + Keys lines; THE ONE RIGHT WAY; dated TRIED / FAILED BECAUSE / DO
INSTEAD; NUANCE lines; See also to the detail's home), grepped before any
task the way the process registry is. Both ends are mechanical: the
prompt hook names the entries whose Keys hit the prompt (THE LESSON
LINE, at most three, with line numbers); the new Stop hook scans the
turn's transcript slice for trial-and-error signals (the same command run
again after an error, repeated edit misses, a FAIL then a PASS, an intent
claim resolved DIFFERENT, an employee briefed twice, a correction prompt)
and refuses to end the turn once with LESSON ADVISED (a block reaches the
manager; a systemMessage does not); never the same slice twice; a turn
that edited the book passes as WRITTEN. The correction ledger prints
LESSON ADVISED after a DIFFERENT. Measured: lesson_runs.txt (MATCHED /
ADVISED / WRITTEN / CHECK); `lesson_log.py --check` in the check group
lints the entries; ledger_trends rule 14 proposes when advised lines pile
up with no entry written. Origin lesson on the first day: a long heredoc
through the shell tool fails on Windows past ~100 lines; the Write tool
and a scratchpad edit script are the one right way.
CARRIES: LESSONS.md (new: the law, the entry shape, the origin's first
five entries); hooks/lesson_advisor.py (new); hooks/prompt_gauge.py (THE
LESSON LINE); hooks/settings.json (the second Stop entry); hooks/
README.txt; reference tools/lesson_log.py (new); reference tools/
correction_log.py (the LESSON ADVISED print); reference tools/
ledger_trends.py (rule 14 + lesson_advised_unwritten); reference tools/
run_all.py (check group); reference tools/_ledger.py (the ledger name);
hooks/hygiene_guard.py (LESSONS.md in KIT_MDS); HOOKS_METHOD.md (Tier 1
item 5 + change log); skills/checkpoint/SKILL.md (step 0 asks for the
lesson); the front door STEP 4; this entry.
GRAFT: copy LESSONS.md to the project root and keep its top (the law and
the entry shape); retire the origin's entries to a cold shelf or keep
the ones that carry (the heredoc one carries to any Windows project);
copy lesson_log.py to tools/ and lesson_advisor.py to tools/hooks/; take
the new prompt_gauge.py or graft its LESSON LINE block (six lines in
main, two selftest lines); add the Stop entry beside stop_tick's; add
`.claude/lesson_state.json` to .gitignore; add `["tools/lesson_log.py",
"--check"]` to run_all's check group and `lesson_runs.txt` to _ledger's
LEDGER_BASENAMES; graft rule 14 and the `lesson_advised_unwritten` key
into ledger_trends (and trend_limits.json if the project has one); add
LESSONS.md to the hygiene guard's KIT_MDS if the project keeps a kit; add
the LESSON ADVISED print to correction_log's DIFFERENT path; add the
read-cheap line and the law line to the core (two lines each); add the
"Write or amend a lesson" workflow entry and the checkpoint step 0
sentence; run every --selftest and pipe-test the Stop hook once for real.
README: "The hooks" (the eleventh hook, the count), "What is in the box"
(the LESSONS.md row, the hooks count, the reference tools count and the
lesson loop in the adopt list), and the new bullet "The lessons book (the
lesson loop)" under the wiki pillar.

### v1.27 - 2026-09-20 - The preserve guard hardened (the 48,000-file report: the script that runs is read first)
WHAT: a public report the same day - an agent asked to rebuild a mirror
wrote a remover to Temp, ran it in a later command, and its os.walk went
through Windows directory junctions (islink() is False for a junction)
into the live tree and the repo's .git: 48,000 files, the object store
emptied, git unable to restore anything. The CEO: "We need to prevent
this at all costs ... make sure what we have is robust enough". Probed
with the incident's own shapes before reading the guard, fourteen of
twenty-nine passed straight through: a heredoc body written to a
SCRIPT file was exempt (the cat/tee exemption), a script being EXECUTED
was never looked at, a bare-name target (rm build) needed a path
character, a pipeline into the remove cmdlet had no argument to match,
robocopy /MIR and rsync --delete were unknown, git checkout of a path,
switch --discard-changes, force-with-lease, branch -f and filter-branch
were open, .git/objects and a variable target ($DIR) were grantable, and
a crash in the guard allowed the call. All closed: the guard now reads
every script a command executes (the whole file when git does not track
it, the uncommitted added lines when it does; grep/cat/diff is reading,
not running), scans heredoc bodies aimed at script files, takes bare
names and pipelines, knows the mirror verbs and the remaining git
shapes, refuses any .git folder and any variable target with no grant
possible, and falls back to a crude substring check on a crash (fail
closed). Seventy-two selftest checks. The guard refused its own
hardening five times (two-letter helper names that read as verbs,
pattern sources that matched themselves) - reworded every time, never
routed around; that is the new LESSONS.md entry.
CARRIES: hooks/preserve_guard.py (the whole hardening); hooks/README.txt
(the line); HOOKS_METHOD.md (Tier 2d: HARDENED, RUN, FAILS CLOSED);
LESSONS.md ("Harden a guard against a public incident"); the origin's
docs/systems/tooling.md row and WORKFLOWS.md "Delete something" NEVER
line (project-side, described here so a graft knows to mirror them);
this entry.
GRAFT: take the new hooks/preserve_guard.py whole (no project-specific
lines in it; the never-list reads the repo root from _hooklib) and run
`python tools/hooks/preserve_guard.py --selftest`; note that a tracked
script with an uncommitted diff that ADDS a deletion call is refused
when run until committed or granted, and a committed script that
cleans its own temp file is untouched; add the NEVER line to the
project's delete workflow entry and the tooling row; copy the LESSONS.md
entry if the project keeps a lessons book. Expect the guard to refuse
edits to itself whose new text names a verb: split the literal or write
the verb as r[m].
README: "The hooks" (the preserve guard bullet: bare names, pipelines,
mirror verbs, every force push, executed scripts read first, .git and
variable targets, fail closed); no count changed.

### v1.28 - 2026-09-20 - The auto-checkpoint on session end, and the local mirror
WHAT: two asks the same evening. (1) The CEO: "Can we make /clear
automatically check for a checkpoint, and if none was done, perform a
checkpoint before clearing?" The harness fires SessionEnd at /clear
(and logout, stdin closed, other; resume is a suspension) with the
transcript path and a 60 s budget; it cannot hold the clear back and
the manager is gone. So a twelfth hook does the MECHANICS alone, only
when work is unbanked (a change outside the ledger folder or a commit
off origin): the final exchange mined verbatim from the transcript into
the day file as an AUTO section (the old one kept as SUPERSEDED), a
"Checkpoint (auto)" commit, a push to origin and the mirror, the
counter reset. Nothing unbanked = one ledger line. The judgment
paragraphs are still the manager's, at the next real checkpoint. (2)
After the 48,000-file report the CEO asked what a bare mirror is and
named a drive: a reference tool pushes every branch and tag of the
project and the kit repo to bare repos on another disk, from the ship
and checkpoint rituals, the session loop and the new hook. Branches
were assessed the same day as not the safeguard for that failure.
Also in this version: the second README audit (four read-only lanes,
T-0920-RA-1..4) - twelve prose slips fixed, nine new CLAIMS rows so
they cannot recur, six mechanics the README never said.
CARRIES: hooks/session_end.py (new); hooks/settings.json (the
SessionEnd block, timeout 55); hooks/README.txt (the line);
HOOKS_METHOD.md (Tier 1 #6, the heading's count, the change log);
reference tools/backup_push.py (new); reference tools/run_all.py (the
backup group inside session); reference tools/format_lint.py (the
SAFETY row); reference tools/readme_lint.py (nine CLAIMS rows);
skills/ship + skills/checkpoint (the mirror step, the net paragraph);
this entry.
GRAFT: copy hooks/session_end.py whole and merge the SessionEnd block
into .claude/settings.json (timeout 55; the harness's SessionEnd
budget is 60 s); it imports checkpoint.py and standup.py from tools/,
so both reference tools must be installed. Run `--selftest` (18
checks; the throwaway repo stays in the OS temp folder - the preserve
guard refuses a script that removes its own sandbox). For the mirror:
`git init --bare <other drive>/<name>.git`, `git remote add backup
<that path>` in each repo, copy backup_push.py and set its REPOS list,
add the backup group to run_all's GROUPS and the session composite,
add the step to the ship and checkpoint skills. Add session_end.py to
format_lint's SAFETY table so unwiring it is refused. Expect the first
/clear after installing to write "already checkpointed" to
docs/history/session_end_runs.txt when the tree was clean.
README: "The hooks" (Twelve, the Session end bullet); "4. Lossless
Sessions" (the checkpoint thresholds, the net bullet, the standup
miner); "What is in the box" (hooks/ row names _hooklib.py and
README.txt, 29 reference tools, the local mirror); plus the audit's
fixes across pillars 1-3, the hooks, the intent loop, the companions,
Quick start and Updating.

### v1.29 - 2026-09-22 - The memory trim (harness auto-memory is machine-local only)
WHAT: the CEO, told that the harness's per-machine auto-memory "costs
tokens every session", asked whether it fights the kit: "Doesn't that go
against the concept of Rootstock?" Mostly no - only the memory INDEX
loads each session and the bodies read on demand, which is the kit's own
shape. The real conflict found: auto-memory is per-machine and
per-folder, never pulled, reviewed or linted, so any cross-machine
project fact stored there is a shadow copy of what the repo owns,
drifting stale invisibly (the origin's copy still said a version 76
releases old). THE TRIM RULING: auto-memory keeps ONLY machine-local
facts the repo cannot carry (exe paths, installs, PATH quirks);
repo-shaped memories are banked VERBATIM into a topic file with
provenance, superseded in place with stubs (the preservation law covers
memories too), and a tally ledger counts every later need of a banked
fact - the CEO's condition: "I want a ledger of what we're losing and if
we reference them enough, we'll rethink our strategy." A threshold
(first pass: 3 hits on one fact, or 5 total, inside 30 days) raises a
PROPOSE to restore; the owner decides (the learning loop).
Also in this version: the link checker skips fenced code blocks - banked
memory bodies quote [[links]] to files that never were wiki pages, and
quoted text is not a live link (found the day the first bank shipped:
seven false DEADs).
CARRIES: WIKI_METHOD.md ("The harness memory" section, after the
architecture); WORKSTATION_METHOD.md (the closing paragraph of the
Claude-side settings section); reference tools/check_wiki_links.py (the
fenced-block skip in passes b and c); this entry.
GRAFT: read the project's MEMORY.md index and split its entries:
machine-local (keep; verify the paths still hold) versus repo-shaped
(bank the body VERBATIM into a topic file + its master-index line, with
a provenance line naming the repo file that owns the LIVE fact; rewrite
the memory file as a SUPERSEDED stub pointing at the bank; open a
history ledger - memory_bank_refs or your name for it - whose header
carries the line format and the rethink threshold; register the
reference-or-restore steps in the process registry). Run it once per
machine - each workstation has its own memory store; the repo carries
the ruling so the other machine's manager can follow it.
README: "1. The Knowledge Wiki" (the harness-memory bullet).

### v1.30 - 2026-09-26 - The delegation truth set (Tier 4a hooks)
WHAT: three hooks that make the delegation truthfulness rules mechanical,
born of the CEO's ask ("Can we make these processes more fool proof in
any way through hooks or are we at maximum hookiness") and the public
case he relayed: a manager that said its sub-agents did their job when
they had not. brief_guard.py (PreToolUse on Agent|Task) refuses a work
dispatch whose brief is missing the stamp template, the intent line, the
budget line or the preservation line - a malformed brief costs a
refusal, never a spent employee; read-only searcher types pass.
delegation_auditor.py (PostToolUse on Agent|Task) reads the
harness-metered tool/token figures out of every result (the numbers no
model can fake): 0 metered calls on a work task is the fabrication tell,
a TOOLS line claiming >3x the meter is a truthfulness signal, a report
missing its template lines is named; one PENDING line per work
delegation is appended to docs/history/delegation_pending.txt, resolved
only by a NEW `RESOLVED | <id>` line (the tail is the state).
verify_advisor.py (Stop) refuses a turn end once per unresolved set
while a PENDING id lacks its RESOLVED line. All three sit in the format
guard's SAFETY table, so unwiring them is refused. The stated ceiling:
hooks force evidence to exist and numbers to agree; whether the diff
matches the claims stays the manager's judgment. The SubagentStop stamp
check stays pinned as ~redundant with the auditor.
CARRIES: hooks/brief_guard.py, hooks/delegation_auditor.py,
hooks/verify_advisor.py, hooks/settings.json (the three wirings),
hooks/README.txt (the Tier 4a install paragraph + the verify_state
gitignore line), HOOKS_METHOD.md (Tier 4a section + change log),
reference tools/format_lint.py (the three SAFETY rows); this entry.
GRAFT: copy the three hook scripts fresh into the project's hooks
folder, merge the three settings entries, add the SAFETY rows to the
project's format_lint copy, gitignore .claude/verify_state.json, run
each script's --selftest, then pipe-test the loop once for real (a
synthesized Agent result with 0 metered calls through the auditor, watch
the advisor block, append the RESOLVED line, watch it pass). Name the
harness backing beside the project's delegation rules (its SUBAGENTS.md
counterpart) so the manager book and the guards tell one story.
README: "4. The Sub-Agent Company" (the truthfulness hooks bullet) and
the hook count in "6. The Hooks".

### v1.31 - 2026-09-28 - The hook law (a warning from a hook is an order to the manager)
WHAT: The origin CEO, after the Stop hook's CHANGELOG UNEXPORTED line was
relayed to him three replies running instead of acted on: "I don't mind
getting the warning if you forget or something is missed, but I shouldn't
see it repeatedly, it's something you should be doing consistently. A
Warning from the hook means do it, not relay the message for the user to
do. This should be in Rootstock as well." ADVISED MEANS DO IT (v1.13)
covered the lines tagged ADVISED; this broadens it to EVERY line a hook
prints that names work (CHECKPOINT ADVISED, LESSON ADVISED, KIT UNSYNCED,
CHANGELOG UNEXPORTED, LEDGER ADVISED): each is executed inside that reply,
a hook words its line as an order to the manager and never as a note for
the CEO, and the same line seen twice is the failure. Two mechanics ship
with it: stop_tick.py's changelog count now skips commits whose subject
starts with "changelog:" (the exporter's own commit - before, every export
left "1 commit unexported" behind it and the warning cried wolf), and its
line reads "MANAGER: run `python tools/export_changelog.py` and push before
this reply ends". The selftest carries the incident shape (anchor at the
export commit's parent, range ending at the export commit, must count 0).
CARRIES: hooks/stop_tick.py (the count, the wording, the probe),
HOOKS_METHOD.md (THE HOOK LAW under the checkpoint tier + change log),
LESSONS.md (the C0002/C0003 entry: the closing check is "did ANY hook
line name work this turn?"), hooks/README.txt; this entry.
GRAFT: copy stop_tick.py fresh (or port `_commits_since_anchor`: `git log
--format=%s anchor..HEAD`, count subjects not starting with "changelog:")
and run its --selftest; in the project's CLAUDE.md replace the checkpoint
law line with the hook law in one line ("any ADVISED / UNEXPORTED /
UNSYNCED line a hook prints is an instruction done inside that reply,
never relayed for the CEO to do"); add the broadening to the project's
LESSONS entry for ADVISED.
README: "The Checkpoint Protocol" bullet in "5. The Reporting Method"
(ADVISED MEANS DO IT becomes the hook law) and the "Kit version:" line.

### v1.32 - 2026-09-28 - Remote Control: the phone drives the same session
WHAT: The origin CEO asked whether Claude Code on a phone could attach to
a running session and ask the manager to do things, and whether the
checkpoint /clear ritual survives it; then "document this somewhere in
Rootstock for future use and understanding if I or another user is
interested." The answer, from the harness docs: Remote Control
(`/remote-control`, alias `/rc`) pairs the Claude mobile app to the SAME
local session (same context, files, tools, hooks) through a QR code; the
workstation must stay on; a /clear resets the conversation on the phone
too, so a checkpoint clear needs no re-pairing; /clear, /compact,
/context and /usage work from the phone while resume and plugin stay
local; whether a phone-typed /clear fires the SessionStart hook's clear
trigger is not stated in the docs and is recorded as unconfirmed with
the one-clear check that settles it. A cloud session is the alternative
when the machine must go off, without the workstation's tooling.
CARRIES: WORKSTATION_METHOD.md ("Drive a session from a phone (Remote
Control)" under the Claude-side settings section); this entry.
GRAFT: nothing to install; read the section, then add one instance line
to the project's WORKSTATION.md counterpart once a phone has been paired
there (which login, whether the clear trigger fired from the phone).
README: "Questions people ask" (the phone question) and the "Kit
version:" line.

### v1.33 - 2026-09-28 - The route line (which workflow or script, a lookup not an inference)
WHAT: The origin CEO read Kelsey Hightower's Zero Token Architecture
("infer once, export the logic, run it without inference") and asked
where the article went further than Rootstock. The answer: the script
rule already exports the logic, hooks already run at zero tokens, but
WHICH exported thing handles a prompt was still the manager's inference
every turn. His word: "lets get done what you think should get done."
prompt_gauge.py now prints a ROUTE line naming the WORKFLOWS.md entries
and the reference tools whose heading, WHEN line or Search keys the
prompt hits (reference tools/route_index.py, reusing lesson_log's
matcher: a multi-word key 2 points, a single word 1, under four content
words nothing; a workflow needs 3, a tool 2, two of each at most). No
ledger: a route is a pointer and the tool it names keeps its own. The
same batch adds THE STEP COUNT to the systems audit's PROCESS lane
(count the steps a model drives in each ritual and propose which become
one command) and pins "Rootstock as a Claude Code plugin" on the origin's
board, unlocked by a second project that wants the kit; a server layer
(the CEO's Firebase aside) was ruled out as the article's "another system
to monitor the agent".
CARRIES: hooks/prompt_gauge.py (the ROUTE block + two selftest cases),
reference tools/route_index.py (new), HOOKS_METHOD.md (item 3 + change
log), hooks/README.txt (the route paragraph), 0 - READ ME FIRST.md (the
lesson-loop step names it); this entry.
GRAFT: copy route_index.py to tools/ beside lesson_log.py and
prompt_gauge.py fresh (or port the ROUTE block: import route_index,
print match_lines(prompt) under the hook tag, swallow every exception);
run both --selftest. It needs the format law's Search keys on tools and
a WORKFLOWS.md whose entries carry WHEN: lines; a project without those
gets silence, not errors. Add the step-count sentence to the project's
systems-audit workflow entry.
README: "The lessons book (the lesson loop)" bullet in "1. The Knowledge
Wiki" (the prompt hook also names the workflow and the script), the
reference tools count and box line in "What is in the box", and the
"Kit version:" line.

### v1.34 - 2026-09-28 - The checkpoint named check (naming a checkpoint is making it)
WHAT: The route line batch's reply closed with "a checkpoint and clear is
the natural next step whenever you want to stop." The origin CEO: "If
this is the case, you should have just done a checkpoint. Any reference
to a checkpoint from any valid source should prompt you to do it"
(correction C0004). v1.13 made an advised checkpoint a step, v1.31 made
every hook line an order; this closes the SOURCE: the manager's own
reply, the counter, the gauge and the roadmap are valid sources like a
hook line, and a sentence saying a checkpoint is next is an order the
manager gave itself. Mechanically: stop_tick.py reads the turn's reply
text from the transcript (every assistant text block since the last
typed prompt, through lesson_log's reader) and refuses once per prompt
with CHECKPOINT NAMED when the reply names a checkpoint as due (the word
within a sentence of next / natural / due / advised / ready / should /
whenever / now) and lacks the safe-to-clear marker. A reply that made
the checkpoint ends with the marker and passes; a bare mention of the
counter or the state file passes; stop_hook_active stops a loop.
CARRIES: hooks/stop_tick.py (CP_DUE_RE, checkpoint_named, reply_text,
the block, five selftest cases), HOOKS_METHOD.md (item 2 + change log),
hooks/README.txt; this entry.
GRAFT: copy stop_tick.py fresh (or port checkpoint_named + reply_text and
the block before the dire check; it imports lesson_log, so that
reference tool must sit in tools/); run --selftest. In the project's
CLAUDE.md widen the hook law by one clause: "and any reference to a
checkpoint as due from any valid source (a hook, the manager's own
reply)". Add the C0004 line to the project's ADVISED lesson.
README: "The Checkpoint Protocol" bullet in "5. The Reporting Method"
(the source clause) and the "Kit version:" line.

### v1.35 - 2026-09-29 - The proposal law (a DO proposal is done, never asked)
WHAT: The first reply after a /clear relayed the digest's four PROPOSE
lines ("the systems audit is 14 days overdue ... the digest wants a
trim") and asked what to work on. The origin CEO: "If an audit is
required, and it can be done with a sub-agent, or a script, it doesn't
need my permission. Just do it. If the standup digest requires a trim,
it doesn't need my permission. Do it. These need to be added to
rootstock." (correction C0005, the fourth relay of one week: v1.13 an
ADVISED checkpoint, v1.31 a hook warning, v1.34 the manager's own
sentence, now a standup proposal - one law: a line that names work as
due, from any valid source, is an order done in that reply; the owner is
asked only what only the owner can answer). The learning loop's "the
owner decides" names the ASK class, never the mechanics. Mechanically:
ledger_trends.py tags every PROPOSE line [DO] (a script, hook, employee
or diet carries it) or [ASK] (an open question, a shelf, a declining
rate, a game number), exposes the DO ones that clear when done and a HOW
line per ledger; session_start.py's preamble says the DO lines are the
first reply's work; stop_tick.py refuses once per prompt with PROPOSAL
NAMED when the reply names a [DO] proposal its ledger still raises. The
same batch ran the overdue systems audit (four read-only lanes, their
DO items done or briefed, their ASK items relayed) and the second digest
trim under the loss test (a moved line that only repeats the previous
all-clear collapses; a long roadmap entry prints first clause ... last).
CARRIES: reference tools/ledger_trends.py (ACTION, CLEARS, HOW, tagged,
open_do, the header line), hooks/stop_tick.py (_PROPOSAL_WORDS,
proposal_named, open_do_proposals, the block, six selftest cases),
hooks/session_start.py (the preamble sentence), reference tools/
standup.py (all_clear, roadmap_line, the tails plan, twelve selftest
cases), HOOKS_METHOD.md (item 2 + change log), hooks/README.txt; this
entry.
GRAFT: copy the four scripts fresh or port: in ledger_trends add ACTION /
CLEARS / HOW and print tagged lines; in stop_tick add proposal_named +
the block after the checkpoint-named block (it imports ledger_trends, so
that reference tool sits in tools/); in session_start extend the
preamble; in standup add all_clear + roadmap_line. Run every --selftest.
In the project's CLAUDE.md rewrite the learning-loop law: "a [DO]
proposal is done in the reply that reads it, never asked; the owner
decides only [ASK] ones". Add the lesson (a standup proposal is this
reply's work) and the INTENT section in the CEO's words.
README: "The wiki learns (the learning loop)" bullet in "1. The Knowledge
Wiki" (the DO / ASK classes), "The Checkpoint Protocol" bullet in "4.
Lossless Sessions" (the proposal source), the systems-audit paragraph in
"The intent loop", and the "Kit version:" line.

### v1.36 - 2026-09-29 - The pattern row (a named corrections pattern stops re-proposing)
WHAT: The first standup after v1.35 raised the same two [DO] proposals
the previous reply had already done: "4 corrections in the last 7 days -
name the pattern" (named in laws.md the night before) and "the digest is
13655 bytes - trim" (trimmed; the 00:38 measure was inflated by ~2 KB of
new-since ledger lines that print in full by the loss test and expire at
the next standup). A proposal that was done must not fire again until
its ledger moves: the corrections count stays high for seven days by
design, so the ledger needed a row that says "named". correction_log.py
gains --pattern <ids> --law "..." [--intent-ref ...], which appends a
PATTERN line (ten columns, the id field holds the range, next_id ignores
it); ledger_trends.py raises the corrections proposal only when no
PATTERN line is newer than the newest RECORD in the window, and its text
now names the recording command. The digest proposal stays as it is: it
reads the newest measurement, and a "measure" trigger line appended
after a trim is the honest way to close it.
CARRIES: reference tools/correction_log.py (pattern(), --pattern, the
docstring paragraph, one selftest case), reference tools/ledger_trends.py
(the PATTERN check in the corrections block); this entry.
GRAFT: copy both reference tools fresh, or port pattern() + the CLI
branch and the four-line check. In the project's WORKFLOWS.md "Correct a
mistake" add the step: when ledger_trends proposes a pattern, name it,
draft the law, then record it with --pattern in the same reply.
README: "The wiki learns (the learning loop)" bullet in "1. The Knowledge
Wiki" (one sentence: a done DO proposal clears by its ledger, the
pattern row being the corrections case) and the "Kit version:" line.

### v1.37 - 2026-09-29 - The manager's model call, the law ledgers, the version hint, the keep-warm trial
WHAT: One owner message answered seven asks at once, and four of the
answers were the same sentence: "You are the manager, you make the
decision." (1) THE MODEL CALL: "You can downgrade or upgrade any task you
see fit on a trial basis. If there are enough failures, then it needs to
move up again ... I believe Fable is the only one you cannot use per my
decision to save on tokens." The escalation rule (v1.x, the ~25% line)
already said what moves a task type UP; nothing said the manager may move
one DOWN without asking. Now the rule carries that clause, and the origin
project ran two haiku trials the same night (one OK, one report-shape
correction: the script was right, the stamp lines were missing). (2) THE
LAW LEDGERS: "everything that can be measured should be, or else we can't
learn from it. It's just dust in the wind. Make the call." Three laws had
no ledger; two can be read by script (an actioned cross-workstation note
still in notes.md; a tool changed in 30 days that no runbook, loop group,
hook setting or skill names) and got reference tools/law_gaps.py, two
append-only ledgers, WARN lines only, in the check group. The third (the
contradiction rule) was left out on purpose: only a reader can see a
contradiction, and a manual row would measure the manager's memory. Its
first run caught a real unswept note. (3) THE VERSION HINT: "Do it if it
makes sense": reference tools/version_hint.py prints none / patch / minor
from what changed since the last version commit (never major, the
owner's call) as the ship ritual's step 2 first reading. (4) THE KEEP-WARM
TRIAL: asked whether the between-session cache gap could be prevented at
all. The cache lives one hour after its last read and no harness setting
lengthens it; but the miss ledger showed 113 of 146 TTL-gap misses were
pauses of one to twelve hours inside a session, and a ping re-reads the
context at about a tenth of a rewrite, so an in-session cron ping every
30 minutes, capped at 16 pings, is cheaper than the miss for any pause
under ten hours. Documented as a WORKFLOWS entry with its own retire
test (the miss buckets must shrink), armed by the manager, measured at
the next systems audit. Also that day: the warn line of the core lint
retuned 1000 to 1500 (the 2000 budget untouched) after it fired every
session with no cold unit to move, and the lesson that an ask put to the
owner is a numbered question with a recommended answer, never a
statement under an ASK heading.
CARRIES: SUBAGENT_METHOD.md rule 5 (the assignment clause), reference
tools/law_gaps.py (new), reference tools/version_hint.py (new), skills/
ship/SKILL.md (step 2), reference tools/check_claude_md.py (WARN_TOKENS
1500 with the reason), WIKI_METHOD.md (the two warn-threshold mentions,
caught by the 2026-09-29 README audit), LESSONS.md (the ask shape); this
entry.
GRAFT: copy the two new tools; add law_gaps.py to run_all's check group;
add the version hint to the ship skill's step 2; paste the assignment
clause into the project's SUBAGENTS.md escalation rule; the keep-warm
entry is optional and needs a harness with in-session cron (Claude
Code's CronCreate); write the INTENT sections in the owner's words.
README: "The scorecard" bullet in "3. The Employee System" (the
assignment clause), the reference-tools box row (the count and the two
new names) and the "Kit version:" line.

### v1.38 - 2026-09-29 - The fourth digest trim (a ledger line the last exchange wrote is a duplicate)
WHAT: The 10:29 standup read 14515 bytes and proposed the trim; the 00:41
third trim had found nothing fixed to cut, so the question was where the
overage lived. It lived in the "new since the last standup" rule doubling
THE LAST EXCHANGE: the largest tail line (the keep-warm REPORT, 1.1 KB)
was written by the manager one minute before the /clear, and the exchange
that wrote it is replayed verbatim at the top of the same digest. Three
loss-test cuts in standup.py: a no-verdict ledger line stamped inside the
last exchange's window (user prompt time to manager reply time, both from
the transcript) collapses to `name date ^exchange` (a verdict inside the
window still prints in full; print_last_exchange returns the window in
place of True); THE LOOP prints the run_all groups that share a last-run
stamp on one line (seven lines to three); the auto "changelog: export"
commits leave the commit list, git log has them. 14562 to 13415 bytes
like-for-like on the same session; 12086 for the next standup, the rest
being 01:37 audit lines that expire. Sixteen new selftest cases; the
measure line closes the proposal (v1.36). The lever left is the number
of ledgers, not the digest.
CARRIES: reference tools/standup.py (in_window, tails_plan's window
argument, loop_rows, keep_commit, the docstring paragraph, the selftest
cases); this entry.
GRAFT: copy standup.py; if your standup's last exchange comes from another
source than the transcript, return its (first, last) stamps from
print_last_exchange, or pass window=None to keep the previous behaviour;
no settings change.
README: the "Kit version:" line only (the reference-tools box row keeps
its count).

### v1.39 - 2026-09-29 - The pre-production security audit (SECURITY_METHOD.md, security_audit.py)
WHAT: The kit audited its own process and never the app it builds. A
Reddit survey (r/claude, u/Donchuan1998, 2026-09-29) of 100 publicly
launched AI-built apps, checked with what any visitor's browser already
downloads: 37 had a server-side secret in their frontend JavaScript
(OpenAI, Stripe, Supabase), 78 were missing a security header, 12 served
/.git/ or an .env file, 43 answered a wildcard CORS header, 9 were clean.
The cause it names: an env variable renamed VITE_ or NEXT_PUBLIC_ to make
a build error go away, which ships the secret to every visitor. Mazhron:
"important to note inside of Rootstock as part of the audit of an app,
saas or website where applicable before it goes into production ... to
help keep users safe who are making them." SECURITY_METHOD.md is the
new method file: THE SECURITY AUDIT RULE (the gate before the first
public release and before any release that touched secrets, env, auth,
headers, CORS, hosting or database rules; the rotation law: a key that
was ever public is rotated, never merely removed; the prefix law; the
script-and-ledger split; read-only against your own deployment), the
nine-class checklist (secrets in the client, headers, exposed files,
CORS, database rules, auth and rate limits per route, dependencies,
logs, the game-export note that anything under res:// is public), the
ledger line, the WORKFLOWS entry to paste, and the bootstrap. The
reference tool security_audit.py runs the four classes a script can:
--dir greps a production build for secret shapes (file, line and
pattern name printed, never the match), --url reads the headers,
requests the exposed paths expecting 404, and sends a foreign Origin
to read the CORS answer; --record appends the counts and the hand-
walked note to docs/history/security_audit_runs.txt through _ledger's
dedup; --selftest serves a bad and a good site on localhost and checks
sixteen cases. The origin project (a Godot game with no backend and no
keys) is exempt by rule 1 and says so in its first ledger line.
CARRIES: SECURITY_METHOD.md; reference tools/security_audit.py; the
front door's STEP 5 line; this entry.
GRAFT: copy SECURITY_METHOD.md and security_audit.py (to tools/); run
--selftest; paste the method file's WORKFLOWS entry into your registry
and add the one-line question to your ship ritual ("did this diff touch
secrets, env, auth, headers, CORS, hosting or database rules? then the
audit runs first"); add the .env family to .gitignore; if the project
has no backend and no keys, write the exemption in its systems index
and stop. No settings change, no hook.
README: "What is in the box" (the SECURITY_METHOD.md row and the
reference-tools row's count and list) and "Questions people ask" (the
new "Does it check the app I build, or only my process?" answer).

### v1.40 - 2026-09-30 - Four takes from serio-focus (the re-read dedup, the employee model rule, the live usage window, the guard replay) and the secret-file deny list
WHAT: Mazhron asked for a discovery read of serio-focus
(github.com/serio-ngo/serio-focus, Apache-2.0, a Claude Code plugin that
governs tokens and fan-out) against Rootstock: "see what it does in
comparison to Rootstock, same, similar, different, better or worse. Do
not install anything." The verdict: a different animal (a token governor
next to an operating system), the same one-home-per-fact law arrived at
independently, and four places where it was ahead. Mazhron: "I want to
add the things you suggest we add and edit it to Rootstock. Always should
make things better if we can." Credit to its author for all four ideas.
(1) THE RE-READ RULE in diet_guard.py: a later whole Read of a big file
(the 10k line) that this session already read whole and that is unchanged
since (mtime + size fingerprint) is refused once with "RE-READ (diet
guard): ... already in context; Grep the section or Read with
offset/limit; if the context was compacted since, repeat once", and the
repeat passes; pre_compact.py calls forget_session_reads() so the marks
never outlive a compaction. serio-focus applies it to every file; the kit
keeps it to big files, where the waste is. (2) THE EMPLOYEE MODEL RULE in
brief_guard.py: a work dispatch whose tool_input.model is missing, or
names Fable, is refused with the other brief gaps. The harness fact that
made it urgent: an Agent call with no model inherits the parent's model,
so every model-less dispatch had been running on the manager's own tier
against Mazhron's ruling ("Fable is the only one you cannot use"). (3)
THE USAGE WINDOW (reference tools/usage_window.py + one line in
prompt_gauge.py): the budget line was retrospective (the next standup's
"+150%"); the plan's own limits are rolling five-hour and seven-day
windows. The tool mines the same transcripts as usage_report.py,
incrementally (a gitignored cache; 0.1s warm), and prints last 5h, the
peak 5h inside the last 7 days, the share, and 7d; the gauge prints it
only when the last 5h is already most of the 7-day peak (owner-tuned:
window_warn_share 0.8 and window_floor_weighted 1000000 in
.claude/fanout_limits.json) and ledgers that reading in
docs/history/usage_window_runs.txt. (4) THE GUARD REPLAY (reference
tools/guard_replay.py): the hooks' selftests check invented cases; this
replays the last N days of recorded tool calls, employee transcripts
included, through the four PreToolUse guards' pure judge functions in a
sandbox (a fresh state per session, no ledger append, no command run)
and prints per rule: replayed, would refuse now, refused live, NEW
CATCHES and LOST; --record ledgers it in docs/history/guard_replay_runs.txt
with WARN when anything was lost. Its first true run: 1261 calls in 7
days, INDEX FIRST 9 would / 10 live / 1 lost (a shell read judged at
today's file size), everything else exact. Also: the settings template
gains a permissions.deny block (the destructive shell rules the origin
project already carried plus Read/Edit of .env files, key material and
credentials), zero runtime cost. Not taken, and why: the commit/push
hold (the ship-every-batch ruling stands), the first-N-lines read cap
(INDEX FIRST is the better answer), the flat deny list without a grant
path, the output style.
CARRIES: hooks/diet_guard.py, hooks/brief_guard.py, hooks/pre_compact.py,
hooks/prompt_gauge.py, hooks/settings.json (the permissions.deny block);
reference tools/usage_window.py, reference tools/guard_replay.py;
HOOKS_METHOD.md (the settings note); this entry.
GRAFT: copy the four hooks over yours and run each --selftest; copy the
two tools to tools/ and run their --selftest; merge the permissions.deny
block into your .claude/settings.json (validate with python -m json.tool);
add the two window keys to .claude/fanout_limits.json only if the
defaults are wrong for your plan; add `.claude/usage_window_state.json`
to .gitignore; run `python tools/guard_replay.py --days 7 --record` once
and read the LOST column before trusting a guard change; put the replay
in your check loop.
README: "The hooks" (the diet guard and brief guard sentences), "What is
in the box" (the reference-tools row's count and list, the hooks row's
settings-template words).

### v1.41 - 2026-09-30 - The fourth README audit: the two grafts v1.39 and v1.40 named but never wrote (the ship question, the employee model rule)
WHAT: Four read-only sonnet lanes read kit v1.40 against the public
README (T-0930-RA-1..4). The README was close; the drift was upstream.
v1.39's GRAFT line told every project to "add the one-line question to
your ship ritual" and the kit's own ship skill never got it; v1.40's
employee model rule lived in brief_guard.py and the README's hooks
section while SUBAGENT_METHOD.md and the brief skill, the two things a
manager reads before dispatching, said nothing. Both are written now:
/ship step 1 asks THE SECURITY QUESTION (secrets, env, auth, headers,
CORS, hosting or database rules touched? the audit runs first; a
project with no backend answers by its standing exemption); /brief
step 1 and SUBAGENT_METHOD.md's assignments section carry THE EMPLOYEE
MODEL RULE (every dispatch names its model; a model-less call inherits
the manager's tier; the brief guard refuses). The README took 22 edits:
one numeric WRONG explained (the weighted shares stop at ~83% because
the pillar shares assume the five-minute write rate and this machine
runs the one-hour cache, so writes are the largest pillar at ~46%, which
is what the method file's earlier 43% said; REPORTING_METHOD.md now
dates its snapshot), the first-audit date reconciled in INTENT_METHOD.md
(the night of 09-13, ledgered 09-14), the "sent anywhere" answer naming
the security audit's own --url requests, "public URL" widened to "public
release (a URL, a store listing, a showcase post)" in the README and the
front door, Quick start's step 4 carrying the front door's STEP 5, and
the hooks section gaining the usage window, the deny block, the guard
replay and the lesson advisor's two named checks it had never mentioned.
Six CLAIMS rows so none recurs; lint PASS at 91 checks.
CARRIES: skills/ship/SKILL.md (step 1); skills/brief/SKILL.md (step 1);
SUBAGENT_METHOD.md (the assignments section's closing rule);
REPORTING_METHOD.md (the dated split); INTENT_METHOD.md (the audit
date); 0 - READ ME FIRST.md (STEP 5's wording); reference
tools/readme_lint.py (six CLAIMS rows); this entry.
GRAFT: copy the two skills over yours (or add the two step-1 lines to
your own); paste THE EMPLOYEE MODEL RULE paragraph into your
SUBAGENT_METHOD.md after the assignments table; copy readme_lint.py if
you run the README gate. No settings change, no hook change.
README: "The four pillars" (pillar 3's "Who gets what" and pillar 4's
/ship sentence), "The hooks" (the usage window, the deny block, the
guard replay, the named checks), "Quick start" (step 4's last sentence),
"Questions people ask" (the network answer, the security answer's
"public release"), "What is in the box" (the usage-window words).

### v1.42 - 2026-10-01 - The stop-time cross-check (delegation_auditor.py on SubagentStop: the employee's transcript is the meter, a self-count miss holds it once)
WHAT: The rule-3 tightening the 09-30 checkpoint named, and the finding
underneath it. The delegation auditor's PostToolUse branch sees the Agent
call's RESULT; a background employee's result is only the launch notice,
so 24 of the first 25 PENDING lines carried tools=? tokens=? and the
cross-check had been blind since the trio was born. The SubagentStop
event fires when the employee itself stops, foreground or background.
The same script is now wired there: it finds the employee's own
transcript (this build hands the MANAGER's file under transcript_path -
the first live run metered 116 calls and 428k tokens, the whole session -
and the employee's under agent_transcript_path, which is tried first,
then <session>/subagents/agent-<id>.jsonl), counts its tool_use blocks
(nine of nine matched the harness's figure exactly on the calibration
day), sums output + cache-write tokens once per message id, and judges
the union of the hand-back text, the last text block and
last_assistant_message - the stop and the hand-back land in either order
(foreground: hand-back first; background: the stop, then the hand-back,
then a second stop). A missing template line, or a TOOLS line under
selfcount_floor (0.7, owner-tuned in .claude/fanout_limits.json) of the
meter by three or more calls, HOLDS the employee once with the true
count in the reason; stop_hook_active plus an ASKED line at the ledger's
tail guarantee once. A METER line then lands in delegation_pending.txt
(task id from the brief's stamp, tools, tokens, claimed, verdict; "held
once"; "pre-hand-back" on the earlier of a background employee's two).
The PostToolUse branch gains the same miss tier (under the 3x rule) and
recognises the launch notice even when the result echoes the brief.
Replayed over the week's nine employees: the four misses the manager
had ledgered by hand (26 of 43, 27 of 41, 41 of 70, 18 of 27) held,
the three honest reports passed. Five live haiku runs proved the event
fires for both modes. The Tier 4 pin "SubagentStop refuses an
employee's stop when its report lacks the stamp" is built, as part of
this, not as the deferred separate hook.
CARRIES: hooks/delegation_auditor.py (main_subagent_stop,
employee_transcript, read_transcript, stop_verdict, selfcount_miss,
asked_before, launched_async; 20 new selftest cases); hooks/settings.json
(the SubagentStop block); reference tools/format_lint.py (the SAFETY
row); HOOKS_METHOD.md (Tier 4a's new bullet); hooks/README.txt;
SUBAGENT_METHOD.md's manager book in the origin project (rule 3's
mechanical line); this entry.
GRAFT: copy delegation_auditor.py and run --selftest; add the
SubagentStop block to your settings (the format guard refuses the edit
if format_lint.py's SAFETY table does not know the row yet, so copy
format_lint.py first); run one cheap employee and read the METER line
at the tail of docs/history/delegation_pending.txt; add selfcount_floor
to .claude/fanout_limits.json only if 0.7 is wrong for your employees.
README: "The hooks" (the delegation truth set's auditor sentence).

### v1.43 - 2026-10-05 - The one-turn line (an employee batches its independent tool calls into one turn)
WHAT: The one piece of a public reply worth taking. Mazhron described
Rootstock under a post (sub-agents orchestrated by the top model, cheap
models for cheap tasks, scripts for anything repeatable, hooks against
fan-out, indexed knowledge so agents read small); Ken Brown answered
"make your subagents stateless and single use, have them do a fast pass
read only for their one task, and call all tools in a single call".
Two of those were already law 1 and law 3 (an employee starts with an
empty context and one self-contained brief; readers are read-only by
assignment, writers stay writers because that is where the cheap models
earn their keep). The third was true and unwritten: nothing told an
employee to fire its independent reads in ONE turn, and every extra turn
re-reads the employee's whole growing context. Now the brief carries it
verbatim: "Independent reads, greps and checks go in ONE turn, never one
per turn; only a step that needs the previous result waits." It is a
skill line, not a guard line: the delegation auditor's tools= count
against the transcript's turn count is the measure, and a guard comes
only if the ledger shows employees ignoring it.
CARRIES: skills/brief/SKILL.md (item 3, THE ONE-TURN LINE);
SUBAGENT_METHOD.md (law 1's last sentence); the origin project's
SUBAGENTS.md rule 7 (the inside-an-employee sentence); this entry.
GRAFT: add the verbatim line to your brief template under the budget
line; add the sentence to your delegation rules' parallelism rule. No
hook, no settings change, no new file.
README: "The company" (the stamped-brief bullet's last sentence).

### v1.44 - 2026-10-06 - The fifth README audit: six slips lived upstream in the method files, not the README
WHAT: The audit's four read-only lanes (T-1006-RA-1..4) found the README
right and its sources wrong six times, the reverse of the usual drift:
the front door still said the core lint warns past 1,000 tokens (v1.37
moved it to 1,500) and put the install stamp "in the core's index"
(UPGRADES and the README say CLAUDE.md itself); WIKI_METHOD's learning
loop still said the manager never applies a proposal unasked (the
proposal law's [DO]/[ASK] split, 2026-09-29, superseded that);
REPORTING_METHOD labelled the 2026-09-10 weighted window 44 days (it is
50; 44 days is the raw window to 09-03); HOOKS_METHOD's Tier 4 pin still
deferred the SubagentStop stamp refusal that v1.42 built; CONTRIBUTING's
safety list named seven hooks when format_lint's SAFETY table, the code,
names eleven, and its format-law list omitted the front door that
carries the header; WORKFLOW_METHOD never mentioned law_gaps.py, the
shadow check the README credited to it. All six fixed at the source.
The README's own slips: "while a file is open" for a path-scoped rule
(Claude Code loads it when Claude READS the file), a 93% weighted share
in the raw-window receipt that the weighted section's 83% contradicted,
the stale "deferred outright" sentence, and "a flag from someone other
than the author" without CONTRIBUTING's "when possible". Twenty LACKS
and POORLY edits beside them: the three knowledge layers and the
bootstrap instruction, the comparison rule's thresholds, the runner's
non-zero exit and own ledger line, the cold shelf's folder and mover,
the auto-memory trim numbers, the employee's closing stamp (workflow and
INTENT lines, the claim the manager logs), the fan-out refusal rule and
where its numbers live, the checkpoint's dire consequence and the 30%
floor, the mirror push and the self-ticking counter in /ship, the
session-start triggers and the two UNSYNCED/UNEXPORTED lines, the
auditor's three-call floor and delegation_pending.txt's line shapes, the
safety tier named, the hooks' install walk, the graft batch's ship step,
where to open Claude Code and the hooks' human parts in Quick start. Five
CLAIMS rows keep the slips from recurring. Skipped by design: LICENSE
and README.md rows in the box (the lint derives the box from the kit
folder, which holds neither), and the long run-on splits (the reference
tools cell, the truthfulness and checkpoint bullets) - a rewrite pass,
not an audit edit.
CARRIES: 0 - READ ME FIRST.md (STEP 1: 1,500 and the stamp's home);
WIKI_METHOD.md ("The learning loop" step 3); REPORTING_METHOD.md ("THE
WEIGHTED COLUMN" window label); HOOKS_METHOD.md ("Tier 4 (still
pinned)"); CONTRIBUTING.md ("THE FORMAT" list, the SAFETY list);
WORKFLOW_METHOD.md ("Who writes it", THE SHADOW CHECK bullet); the origin
project's tools/readme_lint.py (five CLAIMS rows); this entry.
GRAFT: if your install copied any of the six method files before this
version, re-read the six sections named under CARRIES and apply the
corrected sentence to your copy; if your core lint still warns at 1,000
tokens, move it to 1,500; if your proposal step still waits for the
owner on every line, adopt the [DO]/[ASK] split. No hook, no settings
change, no new file.
README: "What loads every session" (the rules row), "The receipts", "1.
The Knowledge Wiki", "2. The Reporting Discipline", "3. The Delegation
Company", "4. Lossless Sessions", "The hooks", "The format law",
"Quick start", "Updating an installed project", "What is in the box".
```

### `WIKI_METHOD.md`

- Source: `WIKI_METHOD.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 27545
- SHA-256: `373cb436f79565d85466b27374208f944590d2cccb0f9322d7f7b2295bdc46b0`

```text
# The Knowledge Wiki Method

PURPOSE: A portable system for organizing a project's knowledge (a lean
  CLAUDE.md core, a docs/systems topic library, portable root notes) so an
  AI assistant finds anything in three cheap hops, Glob, Grep for headings,
  then a targeted Read, without wasting tokens.
INTENT: Developed on Everwood so a future project can bootstrap the same
  system with one instruction, keeping token costs low without losing
  findability.

A portable system for organizing a project's knowledge so an AI assistant
(Claude) finds anything in three cheap hops and never wastes tokens reading
what it does not need. Developed on Everwood (2026-08); written so a future
project can bootstrap it with one instruction: **"Read WIKI_METHOD.md and
set this up for this project."**

---

## Why it works (the token mechanics)

Claude's file access has three operations with very different costs:

1. **Glob** (file names) - nearly free.
2. **Grep** (content search) - searches WITHOUT loading the file; only the
   matching lines return. Grepping a 5,000-line file for its headings costs
   ~50 tokens. This is the load-bearing fact.
3. **Read** - the only real cost, and it takes offset/limit: read lines
   200-260 and pay only for those. What is read once stays in context for
   the session.

Plus one standing cost: the instruction file (CLAUDE.md) is loaded IN FULL
every single session. Everything else is opt-in.

Therefore: keep the always-loaded core tiny, make every other file findable
by name, every section findable by heading, and every related topic
reachable by an explicit pointer - and lookups cost tens of tokens instead
of thousands.

## The architecture (three layers, one home per fact)

1. **THE POINTER CORE - CLAUDE.md** (always loaded): the project in a
   paragraph, how to read, how to verify, the laws no hook enforces, and
   ONE pointer to the master index. Under Anthropic's 200-line target
   (the lint fails past LINE_BUDGET 200 / TOKEN_BUDGET 2,000, warns past
   1,500 since 2026-09-29, 1,000 before; the origin lands ~900 tokens, a
   fresh install lower). Rules that
   only matter for part of the codebase live in .claude/rules/ with
   `paths:` front matter and load only while a matching file is read.
   Everything else is one line in docs/index/MASTER_INDEX.md, the one
   door, and what falls out of use in the core moves there BY SCRIPT
   (the section below).
2. **THE TOPIC LIBRARY - docs/systems/*.md** (read on demand): one file
   per subject (soil, fauna, ui, performance...). Read ONLY when touching
   that subject. Grows without limit; the core never grows with it.
3. **PORTABLE NOTES - repo root** (carried to future projects): engine
   lessons (GODOT_FIELD_NOTES.md), genre lessons (CLICKER_DESIGN_NOTES.md),
   and this file. Rule: engine fact -> engine notes; genre pattern -> genre
   notes; project detail -> topic library. ONE home per fact - split homes
   drift.

## The harness memory (machine-local facts only; the trim ruling)

The harness keeps its own per-machine, per-folder auto-memory OUTSIDE the
repo (in Claude Code: %USERPROFILE%\.claude\projects\<slug>\memory\ - an
always-loaded MEMORY.md index over bodies read on demand). It looks like a
fourth knowledge layer; the rule (the CEO's trim ruling, 2026-09-22) is
that it never holds a fact the repo can own. It does not travel between
machines, is never pulled, reviewed or linted, and drifts stale invisibly
- the repo is the shared, versioned home. Auto-memory keeps ONLY
machine-local facts the repo cannot carry: this machine's exe paths,
installs, PATH quirks. (The workstation file's per-machine inventory is
the repo-side record of the same ground; the two must agree.)
THE TRIM, when auto-memory has grown repo-shaped facts: bank each body
VERBATIM into a topic file (provenance line + a pointer to the repo file
that owns the LIVE fact), rewrite the memory file as a superseded stub
pointing at the bank, and open a tally ledger in the history folder - one
line each time a banked fact is needed again (date | machine | section |
what needed it). A threshold (first pass: 3 hits on one fact, or 5 total,
inside 30 days) raises a PROPOSE to restore that fact to auto-memory; the
owner decides (the learning loop). Nothing is deleted - the preservation
law covers memories too; a wrong memory is marked superseded in place.

## The three-hop lookup

1. The CORE's index line picks the FILE (no file is opened).
2. `Grep "^## " <file>` returns the live section index - every heading
   with its line number (~50 tokens; can never rot like a hand-written
   table of contents, because the headings ARE the index).
3. `Read <file> offset=<line> limit=<n>` loads just that section - and the
   section's closing `See also:` line names each connected topic WITH its
   file, so the next hop needs no search at all.

## The conventions (the law)

- **HEADINGS ARE SEARCH KEYS.** Every section starts `## <searchable
  nouns>` naming what a search would look for ("## Vision cones", never
  "## More fixes" or "## Misc"). A file of unheadlined prose is invisible
  to hop 2 - headline it the first time you touch it.
- **CROSS-REFERENCES.** Sections end with one line:
  `See also: topic -> file.md | topic -> file.md`
  pointing at everything this topic interacts with, wherever it lives -
  other library files, the portable notes, design docs. (Example: a
  creature's section points to the plants it eats in flora.md, its sprites
  in art-pipeline.md, its upgrades in meta.md.)
- **READ CHEAP.** Grep headings first; Read sections only; never read a
  topic file whole except in a deliberate full pass.
- **ONE INDEX LINE PER FILE** in the core, with a description good enough
  to pick the right file without opening any. A lint script keeps the
  index and the disk in sync and alarms when the core bloats
  (reference implementation: Everwood's tools/check_claude_md.py).
- **GROW INCREMENTALLY - THIS IS THE STANDING PRACTICE, NOT A PROJECT.**
  Never stop work for a library-wide pass. Instead, EVERY TIME a file is
  written, updated, or created - every feature, upgrade, fix, ruling -
  the touched sections get proper headings and See also lines then and
  there, cross-referencing whatever already exists. The web thickens as a
  side effect of normal work until everything connects to everything.
- **NEW FILES WHENEVER A SUBJECT OUTGROWS ITS HOME** - plus its index
  line, plus See also lines linking it into the web both ways.
- **RESOLVED/HISTORICAL notes move to a history file** so live files stay
  current; superseded sections say so where they stand.
- **TAGS + THE KNOWLEDGE INDEX (Mazhron approved 2026-09-03).** A section
  whose content is hard-won (a lesson, a trap, a doctrine) carries, directly
  under its heading: `Tags: tag1, tag2 | one-line brief of the takeaway`.
  Starter tags: lessons, gotchas, architecture, performance, process,
  design, economy - invent a new one only when none fits. A script compiles
  every Tags line into a GENERATED index file (one section per tag, one
  clickable line per entry linking to the fact's TRUE home - no
  duplication), so a HUMAN browsing the wiki gets every pitfall and lesson
  at their fingertips, and new files/tags grow the index automatically
  (reference implementation: Everwood's tools/export_tag_index.py ->
  KNOWLEDGE_INDEX.md). Tag new hard-won sections as they are written -
  same incremental law as headings.

## The expansion doctrine (files are cheap - grow fearlessly)
Tags: process, architecture | Default to new topic files and indexes; storage and tail-reads are nearly free, cramming is not

Mazhron's ruling, 2026-09-03. The economics that make the whole method work:
a txt/md knowledge file costs the user almost nothing (disk) and costs
Claude almost nothing (it is only read section-by-section, on demand). A
script is a one-line run, chained into the repeatable "run everything"
chain. What is EXPENSIVE is the opposite instinct: cramming unlike
knowledge into a file where it does not belong, making every file longer,
every grep noisier, and the web harder to traverse.

So the manager's filing instinct, in order:
1. FIT: new knowledge goes into the existing topic file + index where it
   belongs (one home per fact).
2. FOUND: if it does not fit any current home - a different genre, a
   different domain, a kind of information likely to recur - CREATE the
   new topic file and its index line ON THE SPOT, and wire it into the
   scripts (or better: write scripts that AUTO-DISCOVER new files, like a
   tag-index exporter that sweeps whole directories, so growth needs no
   wiring at all).
3. NEVER HESITATE on file count. Ten thousand small files and four hundred
   indexes that are cheap to hop beat one bloated file that taxes every
   read. An ever-expanding web IS the design goal, not a smell.
4. THE MILESTONE HEADS-UP: if the user sets a file limit, honor it; and
   when the knowledge-file count crosses a round milestone (~1000), the
   manager MENTIONS it once - purely informational, growth is good, no
   action required (a lint script can print the count so nobody counts by
   hand).

See also: conventions -> this file | one home per fact -> this file |
tag index -> tools/export_tag_index.py (reference).

## Bootstrapping a NEW project (what Claude does on request)

1. Create/diet CLAUDE.md into the lean core: laws + process + index,
   inside a line budget. Move existing deep knowledge verbatim into topic
   files under docs/ (or create the first few empty topic files the
   project obviously needs).
2. Write the index (one line per topic file) and a lint script that
   checks core size + index/disk sync; wire it into the workflow ("run it
   whenever the core grows").
3. Copy the portable notes from the previous project (engine notes, genre
   notes, this file) into the repo root and index them.
4. Add THE WIKI CONVENTION block to CLAUDE.md (read-cheap, search-key
   headings, See also lines, incremental growth, one home per fact).
5. From then on, follow the standing practice: every write expands the web.

## The read diet: size before you read (the 10k rule)
Tags: lessons, economy, process | A whole-file read past ~10k tokens is section-read or delegated; the harness knows the size before the read, so a warn-only hook says it at the cliff edge

Born 2026-09-10 from the origin CEO's weighted-usage insight: only the
tokens that count against the plan matter, and under those weights (input
1, cache write 1.25-2, cache read 0.1 or 0.025, output 5) everything the
manager reads is WRITTEN into the context at 1.25x and re-read every later
turn. A 24k-token file read inline costs ~30k weighted up front and rides
in every request for the rest of the session; the same file section-read
costs 2-4k; the same file understood by an employee in a throwaway
context comes back as a 2k summary at the employee's price.

THE RULE: know the size before you read. The signals are free - the byte
size on disk (divide by four), the heading index from a grep, the line
count. A whole-file read past ~10k tokens is either SECTION-READ (grep the
headings, read one section by offset/limit or `sed -n A,Bp`) or DELEGATED
(an "understand this file/system" step goes to an employee; the manager
takes the summary). The one fair exception: an EDIT that needs the exact
text - say so and proceed.

WHY NOT A COUNT IN EVERY HEADING (the CEO's first idea): a hand-typed
token count goes stale the moment the section grows and costs output at
5x to maintain. The count is GENERATED instead, at the cliff edge: the
kit's diet guard hook (HOOKS_METHOD.md Tier 2c) reads the file size before
the Read or the cat runs. INDEX FIRST (the CEO's order 2026-09-10 PM,
"section or split as necessary ... should not require my approval"): the
first whole read of a big file in a session is REFUSED and the refusal
carries the file's own index (headings or function lines with line
numbers, ~1-3% of the file), so the next call reads one section; the
same call repeated passes with a warning only - the editing exception
needs no words. The usage sheet's daily line then grades the day (heavy
whole-file reads, section-read share) against the previous seven, and
the big-reads ledger (tools/big_reads.py) names WHICH files were read
whole and the fix each needs (section it, index it, grep it). THE
STANDING ORDER: the manager sections or splits what that ledger names
without asking. THE MEASUREMENT LESSON (2026-09-10): the first "21 big
reads a day" were screenshots - an image is priced by PIXELS (~1-2k
tokens), never by its base64 bytes; a diet metric that counts pictures
as text proposes fixes for a habit nobody has. Check what a metric
counts before acting on it.

See also: The output diet (below) | HOOKS_METHOD.md Tier 2c (the diet guard) | SUBAGENT_METHOD.md "Why this saves money" (the 10k delegation line) | REPORTING_METHOD.md (THE WEIGHTED COLUMN + THE COMPARISON RULE)

## The output diet (every emitted token costs 5x)
Tags: lessons, economy, process | Output is weighted 5x and every tool result is written at 1.25x; the manager's emit habits are a budget lever, not a style choice

Same origin, same day (the CEO: "a permanent rule not only for this
machine but for Rootstock-os as a whole"). Under the budget weights the
manager's OUTPUT - prose, edits, briefs, thinking - is a fifth of the bill
at five times the price of input, and every TOOL RESULT is context written
at 1.25x and re-read forever. So the emit habits are law:

- EDIT over WRITE: a Write re-emits the whole file; an Edit emits the
  change. (A NEW file is one Write, never incremental appends.)
- SCRIPTS GENERATE DOCUMENTS: tables, indexes, ledgers, changelogs, sheets
  are produced by scripts (the Script Rule); the manager never types what
  a script can render.
- NEVER RESTATE: a result the table, the ledger or the diff already
  carries is pointed at, not repeated in prose. A reply leads with the
  outcome and stops when the content stops.
- LIMITERS ON CHATTY COMMANDS: git log with a count, git diff with a path
  or --stat, listings with a depth or a filter, installs with -q, test
  runs through the runner that prints one verdict. The diet guard hook
  says the limiter when one is missing (warn-only, capped per session).
- BRIEFS ARE SELF-CONTAINED, NOT PADDED: an employee's brief is output too.
- EFFORT MATCHES THE TASK: thinking is output; routine doc and ledger
  sessions run at lower effort, the high setting is for design and
  debugging (where the platform exposes the knob).

See also: The read diet (above) | HOOKS_METHOD.md Tier 2c | REPORTING_METHOD.md "The Script Rule" | SUBAGENT_METHOD.md law 1 (the brief)

## Maintenance honesty

- When MOVING a section between files, update the See also lines that
  pointed at it (grep the topic name across the library - cheap).
- When two files accumulate overlapping coverage, merge to one home and
  leave a pointer in the other.
- The index description is part of the interface: when a file's scope
  shifts, its index line shifts with it.
- Cross-references are for NAVIGATION, not prose: one compact line, plain
  arrows, no sentences.

## The cold shelf (rarely-used knowledge moves, never dies)
Tags: architecture, process, lessons | Prune means MOVE: cold sections go to docs/cold/ verbatim, indexed, with a stub left at the old heading; nothing is ever deleted

THE PRESERVATION LAW, knowledge side (the origin CEO, 2026-09-10, when the
manager proposed "pruning" dead knowledge): "the knowledge should never
be lost... all of this is hard fought, hard earned knowledge, even the
rarely used knowledge." So the wiki has a COLD SHELF:
- docs/cold/<same basename as the hot file>.md holds sections moved out
  of the hot file VERBATIM (heading + body byte for byte, one provenance
  comment under the heading: moved from where, when, why, how many lines).
- The hot file KEEPS the heading, with a two-line stub under it: "Moved
  to the cold shelf <date> (<reason>): docs/cold/<file> - read only when
  this topic comes up." + a See-also to the index. Heading greps still
  land, and the record of the move is at the old address.
- docs/cold/INDEX.md is the append-only index (date | moved/restored |
  hot file | heading | lines | reason | shelf file). It gets ONE line in
  the core file's library index, and a shelf file is read ONLY when a
  stub or the index says the topic moved there - never preemptively.
- The mover is a script (tools/cold_shelf.py: --move, --restore, --list,
  --check, --dry-run); it contains no deletion code and refuses to
  overwrite anything on the shelf. --restore brings a section back and
  leaves a "restored" note on the shelf, so the shelf is history too.
- CANDIDATES come from the heat map (tools/wiki_heat.py mines the harness
  transcripts for read counts per section; "cold" = untouched by any read,
  whole reads included, for --days). The OWNER picks what moves. A script
  proposes; a human rules; nothing moves on its own.
- COLD BY READ COUNT IS NOT A SHELF REASON (the CEO's ruling 2026-09-10:
  "in a game situation, we only touch certain files at certain times ...
  we built the wiki not only for your reference, but for a human
  reference"). The heat map therefore says WHY each cold file is cold,
  from git activity in the code area it documents: active-unread (the
  code moved AFTER the doc was last opened - the one class worth a look:
  a heading that is not a search key, a stale section, or knowledge that
  was not needed), current (opened since the code last moved), dormant
  (the code did not move), process (laws, registry, roadmap - read when
  the ritual calls), reference (lore, store copy, changelog - for humans)
  and archive (history, the shelf). Only active-unread ever reaches a
  proposal. The origin project's first count of 367 cold sections was
  180 changelog entries, 25 shipped-roadmap entries, history, and a
  counting flaw (a whole-file read did not count as seeing a section):
  zero system sections were actually cold. Audit the audit before acting.
Why this shape and not deletion: the token cost of a cold section is one
heading line in every heading grep and a share of every whole-file read
of its host. Moving it removes that cost; deleting it would also remove
the knowledge, and the knowledge was the point. The stub costs two lines.
See also: the learning loop -> this file (next section); THE PRESERVATION
LAW -> SUBAGENT_METHOD.md law 7 | HOOKS_METHOD.md Tier 2d; the mover ->
tools/cold_shelf.py; the candidates -> tools/wiki_heat.py.

## The hot core and the sub-indexes (the core diet: CLAUDE.md never bloats again)
Tags: architecture, economy, lessons | CLAUDE.md is a pointer core under Anthropic's 200-line target; knowledge has three homes (always / when a matching file is read / on demand behind the master index); sections that fall out of use move by script, one stub line each, verbatim and reversible

The origin project's CLAUDE.md grew from ~250 lines to ~10k tokens in
three weeks while its own law said "index only" - laws were promoted in
full text, index lines became paragraphs, and nothing measured it. A
Reddit reader measured the kit's front door instead (it was named
"...CLAUDE.md") and called the whole thing slop. The CEO's ruling
(2026-09-14): "CLAUDE.md is the main index that keeps the most used
information (similar to your heatmap concept) and once they fall out of
the high-use heatmap, they get moved (by script) to the appropriate index
out of CLAUDE.md ... These indexes can grow much more than the CLAUDE.md
file. They will need to have appropriate names for the files and sections
inside that connect to the appropriate knowledge txt files."

THE SECOND RULING (Mazhron 2026-09-14, after reading Anthropic's memory
doc, code.claude.com/docs/en/memory): "Claude.md should simply point to
everything else ... Claude.md doesn't need to load 2-5k tokens each
time, Claude.MD just needs to guide Claude on where to go to get the
information Claude needs which Claude will add to it's cache/context as
needed only." Anthropic's page settles the mechanics: target under 200
lines per file; imports and unscoped rules load at launch, so moving
must-read text into them "helps organization but doesn't reduce
context"; a rule with a `paths:` field loads only when Claude reads a
matching file; CLAUDE.md is guidance, hooks are the enforcement layer.
So KNOWLEDGE HAS THREE HOMES, by WHEN it is needed:
- ALWAYS -> CLAUDE.md, the pointer core: the project in a paragraph, how
  to read, how to verify (build commands belong here, Anthropic says),
  the laws no hook enforces, one line each. Nothing else is restated.
- WHEN A MATCHING FILE IS READ -> .claude/rules/<topic>.md with `paths:`
  front matter (game code rules for scripts/, text rules for data/ and
  ui/, wiki hygiene for every .md). The harness loads them itself; no
  hook, no Read call, no output tokens. A rule WITHOUT paths loads every
  session, so the lint counts its tokens against the core budget.
- ON DEMAND -> docs/index/MASTER_INDEX.md, THE ONE DOOR: every topic
  file, root file, sub-index, law stub, rule and knowledge file, one
  line each, and every destination listed DIRECTLY (each hop costs a
  Read; never chain three files to reach a fact).
A must-read chain enforced by hook was considered and rejected: a file
Claude must read every session costs the same as if it sat in CLAUDE.md
plus a Read call, and a hook cannot make Claude read, only inject or
block. The saving is in loading rules only when they apply.

THE LAW:
1. CLAUDE.md is THE POINTER CORE, budgeted in lines AND tokens: the lint
   (check_claude_md.py) FAILS past LINE_BUDGET (200, Anthropic's target)
   or TOKEN_BUDGET (bytes/4; 2,000, the owner's action line), WARNS past
   WARN_TOKENS (1,500; 1,000 until 2026-09-29), requires CLAUDE.md to
   name the master index and
   the master index to list every docs/systems and docs/index file and
   every rule, and fails on a rule with no `paths:` field. The answer is
   never a raised budget. standup prints the OK/WARN line every session
   so the owner sees the size; the hygiene guard runs the lint the moment
   CLAUDE.md, the master index or a rule is edited. The origin lands at
   ~900 tokens / 68 lines; a fresh install lower.
2. Every `## `/`### ` section of the core is a UNIT. A unit that should
   be movable carries `Index: <name>` (its sub-index); `Index: core` pins
   it. A hard-won unit carries `Tags: ... | brief` - the brief becomes
   its stub, so the core still states the law in one sentence.
3. HEAT (tools/core_diet.py, the check group, BEFORE the lint): explicit
   reads of the unit's lines (the transcript cache wiki_heat keeps), reads
   of the wiki files the unit points at (its follows), and whether git
   touched it inside the window (`core_cold_days`, trend_limits.json,
   30). A unit with none of the three is COLD.
4. THE MOVE (by script, in the loop): `--move` moves every COLD routed
   unit VERBATIM into docs/index/<name>.md (a wiki file: headings are
   search keys, each section keeps its Tags and See-also lines that
   connect it to its knowledge files, a provenance comment records the
   origin) and, while the core is still over budget, the coldest routed
   units next. Each move leaves ONE line in the MASTER INDEX's "## The
   sub-indexes" block: `- <heading> -> docs/index/<name>.md | <brief>`
   (the block lived in CLAUDE.md itself until the pointer core).
   A COLD unit with no Index line is only PROPOSED - a human names its
   home. `--move-section` is the manager's explicit call; `--restore`
   reverses a move (the unit returns after the unit it followed).
5. THE SUB-INDEXES grow without limit (docs/index/laws.md, library.md,
   process.md, gotchas.md, code.md in the origin) and are read like any
   wiki file: `Grep "^## "` then the section. The scanners (wiki_heat,
   check_wiki_links, export_tag_index, export_wiki_view, cold_shelf)
   discover docs/index/ as wiki files; the lint requires every sub-index
   to be named in the master index, and the master index in the core.
6. NOTHING IS DELETED (the preservation law): a move is verbatim,
   stubbed, ledgered (docs/history/core_diet.txt regenerated,
   core_diet_runs.txt appended) and reversible. The laws that matter most
   are HOOKS anyway (the hooks rule) - the prose in the core is a pointer,
   the guard is the law.

What this is NOT: the cold shelf. The cold shelf takes rarely-READ topic
sections out of hot topic files, by a human's choice. The core diet takes
sections out of the one ALWAYS-LOADED file, by script, on heat and budget,
because that file's size is the only standing cost in the system.

See also: the architecture (layer 1) above; the cold shelf below;
tools/core_diet.py; tools/check_claude_md.py; docs/index/MASTER_INDEX.md;
.claude/rules/; WORKFLOWS.md "Diet the core (move a CLAUDE.md section to
a sub-index)" and "Add or change a path-scoped rule"; INTENT.md "The core
diet" (both rulings); the hooks rule -> HOOKS_METHOD.md;
https://code.claude.com/docs/en/memory (Anthropic: size, rules, imports).

## The learning loop (ledgers measure, scripts propose, the owner rules)
Tags: architecture, process | Three read-only scripts close the loop: dead links, section heat, and ledger trends turned into PROPOSE lines at standup

The origin CEO asked (2026-09-10) whether the system learns. Honest
answer: the model cannot change its weights; the PROJECT learns, in
files, and only where discipline puts the lesson down. The loop that
makes learning less dependent on discipline:
1. MEASURE - every ritual appends a ledger (tests, builds, usage, links,
   heat, employees, compactions, grants, retirements).
2. NOTICE - tools/ledger_trends.py reads the ledger tails against a
   THRESHOLDS table (`--limits` prints it) and emits PROPOSE lines: the
   read diet slipping (CHECK verdicts, big whole-file reads), a flaky
   test group, dead wiki links, a cold-shelf sweep due, an employee
   model past the escalation rule, too many compactions. Standup prints
   the block right after THE BUDGET. When the proposal set changes, one
   line lands in docs/history/proposal_runs.txt - the loop has history.
3. RULE - a proposal is tagged [DO] or [ASK] (the proposal law,
   2026-09-29): a [DO] (an audit, a diet, a loop run, anything a script
   or an employee carries) is done in the reply that reads it, never
   offered as a choice; an [ASK] is the owner's, answered yes, no, or
   later. A proposal that keeps recurring
   with a no is a threshold to retune, not a rule to force.
4. GROW - the yes becomes a law, a hook, a threshold change or a cold-
   shelf move, filed per the conventions; the next ledger line shows
   whether it worked.
What it still is not: automatic. Edges in the wiki exist only where a
session wrote them (the link checker catches the dead ones, not the
missing ones); heat is lexical (a Read at a line range mapped to the
CURRENT headings, approximate for old reads); and nothing rewrites a
rule by itself, by design - the CEO ruled that a script never deletes
and the same spirit governs what a script may decide.
See also: the cold shelf -> this file (previous section); the scripts ->
tools/check_wiki_links.py | tools/wiki_heat.py | tools/ledger_trends.py;
the ledgers discipline -> REPORTING_METHOD.md; the escalation rule ->
SUBAGENT_METHOD.md law 5.

Search keys: wiki method, knowledge library, three-hop lookup, CLAUDE.md
  core, hot core, sub-index, core diet, token budget, docs systems library
```

### `WORKFLOW_METHOD.md`

- Source: `WORKFLOW_METHOD.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 7430
- SHA-256: `e51d3419cd9e4fecfe0f94e84a39fd08054d9083c71a09b6ef2ef1a77c372ee8`

```text
# The Workflow Method (portable: the process registry, for any project)

PURPOSE: A portable process registry method: every repeatable multi-step
  process gets one runbook entry, WHEN, STEPS, VERIFY, in a single registry
  file, so the choreography between scripts and ledgers is never lost to
  context clearing or memory.
INTENT: Process amnesia: a project accumulates processes whose order nobody
  writes down because it seems obvious right now, so after context clears
  the sequence gets re-derived from a chat log that no longer exists, or a
  step is silently skipped for weeks; scripts remember commands and ledgers
  remember results, but nothing remembered the choreography until this
  method.

PORTABLE FILE: an architecture, not a project. Hand it to any Claude (or any
capable agent) at the start of any project alongside its siblings
(WIKI_METHOD.md, REPORTING_METHOD.md, SUBAGENT_METHOD.md) and say "set this
up". Nothing here assumes a game, a language, or a team size.

THE PROBLEM IT KILLS: process amnesia. A project accumulates PROCESSES -
how art gets cut and wired, in what order a release ships, which script runs
before which - but nobody writes the ORDER down, because each step's tool is
documented somewhere and the sequence "is obvious right now". Then the
context clears, and the manager re-derives the pipeline from a chat log that
no longer exists, or worse, skips a step (a changelog goes stale, an export
never lands) without anyone noticing for weeks. The origin project ran an
art pipeline for weeks with no written recipe and let seven versions pile up
unexported before this method existed. Scripts remember COMMANDS
(REPORTING_METHOD.md); ledgers remember RESULTS; nothing remembered the
CHOREOGRAPHY. This file is for the choreography.

Search keys: workflows, process registry, order of operations, runbook,
how do we do X, pipeline documentation, missing process.
See also: registry template below; SUBAGENT_METHOD.md (who captures gaps);
WIKI_METHOD.md (headings + one-home-per-fact); REPORTING_METHOD.md (the
Script Rule this method choreographs).

## The registry: one place to look
Tags: process, architecture | Every repeatable multi-step process has a runbook entry in one root file

WORKFLOWS.md at the repo root is THE REGISTRY: one entry per repeatable
multi-step process. When anyone - manager, employee, or the CEO - asks "how
is this done here?", the answer starts in that one file, always. An entry is
a RUNBOOK, not an essay:

    ## <Task name as a search key ("Ship a batch", "Cut and wire a creature")>
    WHEN: the trigger (what event or request starts this).
    STEPS: the numbered order of operations - each step names its script,
      tool, or file. The ORDER is the payload; a wrong order is a defect.
    VERIFY: how you know it worked (test group, ledger line, visual check).
    See also: <deep doc> - the entry points at true homes, it does not
      duplicate them.

ONE HOME PER FACT still rules (WIKI_METHOD.md): deep knowledge about a step
stays in that step's own doc; what lives HERE is the sequence, the wiring
between steps, and the names of the scripts involved. If an entry's STEPS
section grows past a screen, the detail wants its own doc and the entry
keeps the skeleton plus a pointer - the registry stays cheap to read whole.

## The capture rule: no undocumented process survives contact
Tags: process, lessons | Whoever performs a task checks the registry; a missing or wrong workflow is captured in the same batch

Before performing any repeatable multi-step task, CHECK THE REGISTRY (its
headings are the index - grep them). Then one of three things is true:

1. THE ENTRY EXISTS AND IS RIGHT: follow it. Deviating from a written
   workflow without updating it is the same defect as retyping a scripted
   command by hand (REPORTING_METHOD.md rule 1).
2. THE ENTRY EXISTS BUT IS WRONG OR GREW A STEP: fix it in the same batch
   as the work. The registry is only trustworthy if a stale entry is
   treated as a bug, not a quirk.
3. THERE IS NO ENTRY: the performer has just discovered a WORKFLOW GAP.
   The task still gets done - and the gap gets captured in the same batch,
   by the cheapest hands that can do it (next section).

The moment a "how do we do X?" question is answered from memory or from
chat archaeology instead of from the registry, that answer is written into
the registry before the batch closes. Answering the same process question
twice from memory is the failure this method exists to prevent.

## Who writes it: gap capture is cheap-model work
Tags: process, delegation | Employees report gaps in their stamp; write-ups delegate cheap because the report already contains the steps

The division of labor (pairs with SUBAGENT_METHOD.md):

- EMPLOYEES DON'T EDIT THE REGISTRY - they REPORT. Every employee brief's
  stamp block gains one line:
      WORKFLOW: matched <entry name> | GAP: <process performed with no entry>
  A GAP line costs the employee nothing (it just performed the steps) and
  hands the manager a ready-made capture task.
- THE MANAGER FILES OR DELEGATES. A workflow write-up is TRANSCRIPTION,
  not discovery: the performing agent's report (or the manager's own just-
  finished transcript) already contains every step in order. That makes it
  ideal cheap-model work - brief a bottom-tier employee with the raw report
  and the entry template, and spot-check the result against the template.
  The manager writes it personally only when the workflow encodes a ruling
  or a law (those need the manager's judgment about WHY the order is law).
- THE MANAGER'S OWN TASKS OBEY THE SAME RULE: performing a process with no
  entry obligates the capture, whoever performed it.
- THE SHADOW CHECK (v1.37): a script (reference tools/law_gaps.py, in the
  check group) reads the rule's shadow too: a tool changed in the last 30
  days that no registry entry, loop group, hook setting or skill names is
  a WARN line at standup.

## What earns an entry (and what doesn't)

EARNS: any process with more than one step whose ORDER or WIRING someone
would have to rediscover - release/ship sequences, asset pipelines, data
tuning round-trips (export, edit, apply, verify), delegation rituals,
session open/close rituals, update/sync procedures.
DOES NOT EARN: single-script actions (the script IS the workflow - the
Script Rule already covers it); one-off tasks that will never recur; pure
knowledge with no sequence (that is wiki material). When in doubt, ask:
"if the context cleared right now, would the next session know the ORDER?"
If no, it earns an entry.

## Bootstrap steps for a new project

1. Create WORKFLOWS.md at the repo root the day the project has its FIRST
   two-step process (a build that needs an export first is enough). Index
   it from the project's core file (CLAUDE.md or equivalent).
2. Seed it by walking the processes that already exist - each one is a
   cheap-model transcription task from existing docs and scripts.
3. Add the WORKFLOW line to the employee brief template in the project's
   SUBAGENTS.md (or equivalent) so gap reporting starts on day one.
4. Adopt the capture rule as law: task done + no entry = entry written in
   the same batch. Wire it into the project's definition of "batch done".
5. Registry entries follow the wiki conventions (searchable headings,
   See-also links, Tags on hard-won ones) so the wiki view and tag index
   pick them up for free.
```

### `WORKSTATION_METHOD.md`

- Source: `WORKSTATION_METHOD.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 9577
- SHA-256: `48ecaa94d7c312c92de590c0dc02ab3885e8164f99a811e1b84847feecf60caf`

```text
# WORKSTATION_METHOD.md - the machine inventory that installs itself (PORTABLE, part of the future-project kit)

PURPOSE: The machine inventory method: one workstation file records what
  every script, hook and ritual needs, why, what the origin machine has, and
  how to install it, so any Claude can get a new machine up to par and write
  back what it adds.
INTENT: Mazhron's ask 2026-09-06: "we should have a new workstation document
  that lists our complete setup, all the installation packages, software we
  installed (such as python), etc. so that any Claude can get any
  workstation up to par ... so that any user could simply set up a new
  workstation based on their current. Their Claude would add their setup to
  the document."

Founded 2026-09-06 on Mazhron's ask: "we should have a 'new workstation'
document that lists our complete setup, all the installation packages,
software we installed (such as python), etc. so that any Claude can get
any workstation up to par ... so that any user could simply set up a new
workstation based on their current. Their Claude would add their setup to
the document." Everything else in the kit assumes the tools already run:
Python for the scripts and hooks, the engine for tests and builds, the
art programs for the pipeline. Nothing recorded WHAT those were. A second
machine, a reinstall, or a collaborator's laptop meant rediscovering the
setup from error messages. This file makes the setup a document that a
Claude can read and act on.

Search keys: workstation, new machine, setup, install, prerequisites,
inventory, survey, up to par, second workstation, onboarding, remote
control, phone.
See also: WIKI_METHOD.md (where the doc lives in the library),
REPORTING_METHOD.md (the survey is a scripted run with a ledger),
HOOKS_METHOD.md (the hooks are the first thing that breaks on a bare
machine), WORKFLOW_METHOD.md (the registry entry that runs the setup).

## THE WORKSTATION RULE
Tags: process, architecture | The machine inventory lives in a file; new machines install from it, and every gain is written back the same batch

1. THE DOCUMENT: the project keeps ONE workstation file (Everwood:
   WORKSTATION.md at repo root) with a requirement table - what is
   needed, WHY (which script or ritual depends on it), what the origin
   machine has (version + path), and how to install it - split into
   REQUIRED and OPTIONAL. Plus one section per known machine (its
   inventory and its deltas) and the on-disk layout the scripts assume.
2. THE WRITE-BACK: whenever a machine gains something a script, hook or
   ritual depends on - a package, a tool, an extension, a path, an env
   var - the manager records it in the document IN THE SAME BATCH, with
   its why. A dependency that lives only in a script's import line or a
   hardcoded path is a workstation bug.
3. THE SURVEY: a script (Everwood: tools/workstation_survey.py) mirrors
   the requirement table as a CHECKS list and prints HAVE / MISSING per
   line, exits non-zero when a required item is missing, and appends one
   summary line to a ledger (docs/history/workstation_runs.txt). "Up to
   par" is what the survey says, not what anyone remembers. It sits in
   the parent loop's check group so it runs with the other lints.
4. THE INSTALL: on a new machine, the receiving Claude reads the document
   and installs the REQUIRED table top to bottom (the scripting language
   first - hooks need it from the first session), then runs the survey
   until it says yes, then adds the machine's own section. Machine
   paths never get hardcoded singly: a candidates list + env override
   (the origin's run_tests.py / make_builds.py pattern) so both machines
   stay first-class.

## What the requirement table records (one row per need)

| column | meaning |
|---|---|
| need | the thing, with the name scripts call it by (`python`, `node`) |
| why | the script, hook, law or ritual that depends on it - the reason it is in the table at all |
| origin has | version + path on the machine that wrote the row |
| install | the exact install move (site, installer option, pip line, env var) |

Record the NON-needs too ("no gh CLI, pushes over HTTPS"; "no ffmpeg,
PIL does it") - a new Claude otherwise installs them defensively.

## Per-machine sections

Each known machine gets a section: its name as the project's ledgers
know it (WS1/WS2 in Everwood), the survey line that proved it up to par,
and its DELTAS from the origin (a portable install at a different path,
a different drive, a missing optional). Anything that does not travel
via git (per-machine art palettes, harness transcripts, local settings)
is named there so nobody looks for it on the other machine.

## The Claude-side settings belong in it too

The harness's own configuration is part of the setup: the user-level
settings (effort level etc.), the project-level settings that travel
with the repo (the hooks), what is per-machine and gitignored (hook
state), and where the harness keeps transcripts. A new machine that has
the code but not the harness setup is not up to par.

The harness's per-machine auto-memory obeys the same split: it holds
machine-local facts ONLY (exe paths, installs, PATH quirks - the facts
this file's per-machine sections record on the repo side); any fact the
repo can own lives in the repo. Repo-shaped memories get banked and
tallied, not deleted - WIKI_METHOD.md "The harness memory" carries the
full trim ruling.

## Drive a session from a phone (Remote Control)

Tags: remote control, phone, mobile, clear | the phone attaches to the SAME local session; a checkpoint /clear keeps the link

Claude Code's Remote Control attaches the Claude mobile app (iOS or
Android; there is no separate mobile Claude Code) to a session already
running on the workstation: same conversation, same context, same local
files, tools and hooks. The phone is a second keyboard, not a second
session; the workstation does the work. Recorded 2026-09-28 from the
harness docs (code.claude.com/docs/en/remote-control.md and /mobile.md)
after the origin CEO asked whether a phone could ask the manager to run
things, and whether the checkpoint ritual survives it.

- START: type `/remote-control` (alias `/rc`) in the running session
  (terminal or the VS Code extension). It prints a session link and a
  QR code. On the phone: the Claude app, the Code tab, scan the code or
  pick the session from the list. Type `/remote-control` again to end
  the link and keep the session.
- THE PHONE CAN: read the conversation live, send prompts, send photos
  or files (they arrive as attachments), switch model or effort, run
  most slash commands. Terminal-bound commands (resume, plugin) stay on
  the workstation.
- NEEDS: a Pro, Max, Team or Enterprise login through /login (an API
  key alone, Bedrock, Vertex, Foundry or a custom ANTHROPIC_BASE_URL rule
  it out; CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC turns it off). The
  workstation stays on, awake and online: a sleep reconnects on wake, a
  closed window ends the link. One link per running session.
- THE CHECKPOINT RITUAL IS UNCHANGED: the docs say "When you run /clear,
  the conversation resets on connected devices too", so the link
  survives a checkpoint clear and the phone shows the fresh session
  without re-pairing. /clear, /compact, /context and /usage are on the
  docs' list of commands that work from the phone. UNCONFIRMED (the
  hooks page names the terminal, IDE extensions, the desktop app and
  cloud sessions, not Remote Control by name): whether the SessionStart
  hook's clear trigger fires for a /clear typed on the phone. The check
  is one clear from the phone: the standup digest arriving proves it;
  until then a clear typed on the workstation is the certain path.
- THE ALTERNATIVE when the workstation must go off: a cloud session
  (claude.ai/code) clones the git remote and runs on Anthropic's
  machines. It has none of the workstation's engine, hooks or test
  runners, so it suits reading and planning, not building.

See also: HOOKS_METHOD.md (the SessionStart hook and its clear trigger),
REPORTING_METHOD.md (the checkpoint protocol the clear belongs to), the
project's WORKSTATION.md counterpart (its per-machine instance line).

## BOOTSTRAP (new project)

1. Day one, right after the wiki: create WORKSTATION.md (or your name for
   it) with the REQUIRED table for what you already depend on - usually
   the scripting language, the engine/runtime, git, the editor + the
   Claude Code extension - and the OPTIONAL table for the art/design
   tools. One row per need, with its why. THE ASK: a receiving Claude
   surveys the CEO's CURRENT machine (versions, paths, extensions) and
   writes the first inventory section from what it finds, then asks the
   CEO what it could not see (Steam drives, cloud tools, accounts).
2. Copy the reference survey ("reference tools/workstation_survey.py")
   and rewrite its CHECKS table to match your rows; keep the ledger line.
   Wire it into the parent loop's check group.
3. Add the registry entry "Bring a new workstation up to par" (WHEN: a
   new or reinstalled machine; STEPS: install REQUIRED top to bottom,
   clone into the layout, survey until YES, add the machine section;
   VERIFY: the survey's ledger line).
4. Index the file in CLAUDE.md with one line; add the WRITE-BACK rule
   to the standing rules ("a new dependency goes into the workstation
   doc in the same batch").
5. First survey run = the origin machine's inventory section. From then
   on every new dependency writes itself back as part of normal work.
```

### `hooks/README.txt`

- Source: `hooks/README.txt` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 9800
- SHA-256: `2ca7039e6fc8333f27e3155b615c83e429c645eaf6dce5edf92f2a7d2d41dba1`

```text
Rootstock hooks (kit v1.30). Install per HOOKS_METHOD.md 'Bootstrap':

PURPOSE: Installation notes for the Rootstock hooks folder: what each hook
  file needs filled in or wired (bash_guard.py's PROJECT RULES,
  fanout_guard.py's numbers via the runaway skill, hygiene_guard.py's CONFIG
  block) and the gitignore entries a new project needs.
INTENT: gives a receiving project the exact per-hook setup steps so the kit
  installs correctly instead of by trial and error.
  tools/hooks/  <- these .py files (bash_guard.py: fill PROJECT RULES)
  .claude/settings.json  <- settings.json (merge if one exists)
  .gitignore  <- .claude/hooks_state.json, .claude/settings.local.json,
                 .claude/fanout_state.json, .claude/diet_state.json,
                 .claude/verify_state.json
The scripts import the checkpoint script from the folder above them
(reference tools/checkpoint.py carries work_fingerprint + hook state).
fanout_guard.py (Tier 2b, the catastrophe-only circuit breaker): keep
its DEFAULTS, run `python tools/hooks/fanout_guard.py --selftest`, wire
its every-tool PreToolUse entry. It refuses only a burst or flood of
sub-agent spawns or runaway token velocity (all self-clearing) and
warns on the rest; nothing for the CEO to type. The CEO tunes the
numbers through the /runaway skill (skills/runaway): `--limits` shows,
`--set key=value` writes .claude/fanout_limits.json - COMMIT that file,
it is the CEO's setting and travels with the repo.
diet_guard.py (Tier 2c, kit v1.12; INDEX FIRST kit v1.15): nothing to
fill in. Wire its Read|Bash|PowerShell PreToolUse entry (settings.json
has it) and run `python tools/hooks/diet_guard.py --selftest`. It refuses
exactly once: the FIRST whole read of a file past ~10k tokens per session
comes back as the file's own index; the same call repeated passes with a
warning. Everything else is warn-only: a file's size before a later big
read, the missing limiter on a chatty shell command.
preserve_guard.py (Tier 2d, kit v1.14, a REFUSAL): nothing to fill in.
Wire its Bash|PowerShell|Write|Edit|MultiEdit|NotebookEdit PreToolUse
entry (settings.json has it), run `python tools/hooks/preserve_guard.py
--selftest`, gitignore .claude/delete_grant.json. It refuses delete
verbs (bare names, pipelines, mirror verbs included), work-discarding
git verbs (force pushes included), deletion calls written into scripts,
and (v1.27) any untracked script a command executes that carries a
deletion shape - read before it runs, whatever wrote it; a variable
target is refused outright; the session scratchpad and prose files pass; one command
passes per grant recorded by reference tools/delete_grant.py (the
CEO's two acknowledgments, verbatim). Movers that replace deletion:
reference tools/retire.py (files) and reference tools/cold_shelf.py
(wiki sections). Audit the project's existing scripts for deletion
calls when installing and bring each to the CEO.
hygiene_guard.py (Tier 3, kit v1.16, the first PostToolUse hook):
rewrite its CONFIG block for the project (the portable MD names, the
kit folder, the skills/hooks dirs, the core file + its lint command,
the wiki dirs to lint, the player-text patterns, the assets folder),
wire its Write|Edit|MultiEdit PostToolUse entry (settings.json has it),
run `python tools/hooks/hygiene_guard.py --selftest`. No state file.
After every edit it says the law that applies to that file: refresh the
kit copy (and the public README), add the missing See-also line, fix a
forbidden character in player-facing text (the one BLOCK), run the
import after a new asset. The /preserve skill (skills/preserve) is the
preservation law's front: retire, shelve, or the twice-acknowledged
delete grant, in that order.
format_guard.py (Tier 3b, kit v1.19, a REFUSAL and a BLOCK): nothing to
fill in; it imports reference tools/format_lint.py (copy that to tools/
first and adapt its CONFIG block: kit folder, hooks/skills dirs,
settings path). Wire BOTH entries from settings.json (PreToolUse and
PostToolUse on Write|Edit|MultiEdit), run `python tools/hooks/format_guard.py
--selftest`. Before an edit of a settings file it refuses one that would
unwire, narrow or mis-point a SAFETY hook (or not parse); after an edit
of any kit thing it blocks one that leaves the thing without its header
(PURPOSE / INTENT / Search keys / See also) and names the rewrite
command. Add the settings-file rule to bash_guard.py (the kit copy has
it in GENERIC RULES) and the Stop twin from stop_tick.py. Then run
`python tools/format_lint.py` once: every tool and hook it names gets
its header by `--rewrite` after a read-only look, never by hand; and
`python tools/purpose_audit.py` creates FLAGS.md for the first audit
(see CONTRIBUTING.md and skills/flag).

THE LOOP LAW (kit v1.21, 2026-09-14): session_start.py runs the parent
loop's session group (reference tools/run_all.py) once a day before the
digest and ledgers the digest's size (digest_size.txt); stop_tick.py warns
CHANGELOG UNEXPORTED when commits sit past a changelog anchor (silent
without one; since v1.31 the export's own "changelog:" commit never
counts, and the line is an order to the manager - THE HOOK LAW, run the
export in that reply). A project without run_all.py gets a one-line note, never a
failure. Both hooks' --selftest cover the new paths.
THE CHECKPOINT NAMED CHECK (kit v1.34): stop_tick.py also refuses once
per prompt when the reply names a checkpoint as due (next / natural /
due / advised / should / now near the word) without the safe-to-clear
marker; it reads the reply from the transcript through reference
tools/lesson_log.py, so copy that beside it. Nothing to fill in.
THE PROPOSAL NAMED CHECK (kit v1.35): stop_tick.py also refuses once per
prompt when the reply names a standup proposal tagged [DO] (the systems
audit, the README audit, the digest trim, a stale loop group, dead
links, an unwritten lesson, a stale claim) while reference
tools/ledger_trends.py still raises it; doing it clears the ledger and
the second Stop passes. It imports ledger_trends, so copy that beside
lesson_log.py. session_start.py's preamble names the law ([DO] lines
are the first reply's work, [ASK] lines are questions). Nothing to fill in.

lesson_advisor.py (Tier 1, kit v1.26, THE LESSON LOOP, a once-per-slice
REFUSAL): nothing to fill in. Copy LESSONS.md to the project root (keep
the law and the entry shape at its top; retire the origin's entries or
keep the ones that carry), copy reference tools/lesson_log.py to tools/,
wire its Stop entry (settings.json has it, beside stop_tick.py), gitignore
.claude/lesson_state.json, run `python tools/hooks/lesson_advisor.py
--selftest` and `python tools/lesson_log.py --selftest`, add
`["tools/lesson_log.py", "--check"]` to run_all's check group. After a
turn that showed trial and error it refuses to end the turn once with
LESSON ADVISED; the manager writes the LESSONS.md entry and ends the turn.
prompt_gauge.py carries the other end (THE LESSON LINE): a prompt whose
words hit an entry's Keys line gets the entry named before the first
tool call. Pipe-test once for real: echo '{"transcript_path": "<a
transcript .jsonl>"}' | python tools/hooks/lesson_advisor.py.
THE ROUTE LINE (kit v1.33): copy reference tools/route_index.py to
tools/ beside lesson_log.py; prompt_gauge.py imports it and prints ROUTE
with the WORKFLOWS.md entries and the tools whose heading, WHEN line or
Search keys the prompt hits, two of each at most. It needs a WORKFLOWS.md
whose `## ` entries carry a WHEN: line and tools whose docstrings carry
Search keys (the format law); silent otherwise. `python
tools/route_index.py --match "<prompt>"` shows what it would say.

THE DELEGATION TRUTH SET (Tier 4a, kit v1.30, three hooks): nothing to
fill in. brief_guard.py (PreToolUse on Agent|Task, a REFUSAL): a dispatch
to a work agent type whose brief is missing the stamp template, the
INTENT line, the budget line or the preservation line is refused with
the pieces named; read-only searcher types (Explore, Plan) pass.
delegation_auditor.py (PostToolUse on Agent|Task): reads the
harness-metered tool/token figures out of every sub-agent result - 0
metered calls on a work task is the fabrication tell, a TOOLS-line
mismatch and a malformed report warn - and appends one PENDING line per
work delegation to docs/history/delegation_pending.txt; on SubagentStop
(2026-10-01) it meters the employee's own transcript, holds the employee
once over a missing template line or a self-count under 70% of the
meter, and appends the METER line with the true figures. verify_advisor.py
(Stop, a once-per-set REFUSAL): a PENDING id with no later `RESOLVED |
<id>` line refuses the turn end once - verify, ledger, resolve, or say
why not; gitignore .claude/verify_state.json. Wire all three
(settings.json has them; the format guard's SAFETY table holds their
wiring), run each `--selftest`, then pipe-test the loop once for real:
a synthesized Agent result with totalToolUseCount 0 through
delegation_auditor.py, watch verify_advisor.py block, append the
RESOLVED line, watch it pass. The CEO's rule names stay the manager
book's (SUBAGENT_METHOD.md rules 3, 5, 9, 13, 14).

session_end.py (Tier 1 #6, kit v1.28, THE AUTO-CHECKPOINT): nothing to
fill in. Wire its SessionEnd entry (settings.json has it; timeout 55 -
the harness caps SessionEnd at 60 s total). It needs checkpoint.py and
standup.py in tools/ (the reference tools) and, for the mirror push,
tools/backup_push.py with a `backup` remote on each repo (optional: a
missing remote is a skip). Test: `python tools/hooks/session_end.py
--selftest` (18 checks in a throwaway repo under the OS temp folder),
then `echo {"reason":"clear"} | python tools/hooks/session_end.py` on
a clean pushed tree and read docs/history/session_end_runs.txt's tail:
"already checkpointed".
```

### `rules/wiki.md`

- Source: `rules/wiki.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 2084
- SHA-256: `d1946e44f5274480abdbe04fa3cffb5688032c99e9bf698f72a294bf7097f31e`

```text
---
paths:
  - "**/*.md"
---
<!--
PURPOSE: path-scoped rule carrying the wiki convention at the moment a markdown file is read: headings are search keys, every section ends with See also, the core stays a pointer file, nothing is deleted
INTENT: Mazhron 2026-09-14: CLAUDE.md should simply point to everything else; the wiki hygiene rule belongs where wiki files are edited, not in the always-loaded core
Search keys: wiki rule, headings, see also, tags line, grow the wiki, read cheap, pointer core, preservation, cold shelf
See also: WIKI_METHOD.md; docs/index/MASTER_INDEX.md; WORKFLOWS.md "Diet the core"; tools/check_wiki_links.py; tools/hooks/hygiene_guard.py (SEE-ALSO)
(this comment is stripped before the rule enters context)
-->
# Wiki rules (loaded because a markdown file is open)

- READ CHEAP: `Grep "^## " <file>` first (the section index), then Read
  ONLY the section. Never a topic file whole unless doing a full pass.
- HEADINGS ARE SEARCH KEYS; every `## ` section ends `See also: topic -> file`;
  a hard-won section carries `Tags: t1, t2 | brief`.
- GROW THE WIKI: a subject that outgrows its home gets a topic file in
  docs/systems/ and ONE line in docs/index/MASTER_INDEX.md. New always-true
  knowledge goes to a sub-index or a path-scoped rule, never into CLAUDE.md
  (the lint fails past its budgets; WORKFLOWS.md "Diet the core").
- EVERY FILE TOUCHED gets headings + See-also then and there, no
  stop-the-world passes.
- NOTHING IS DELETED: retire, cold-shelve (docs/cold/INDEX.md) or mark
  superseded; a wiki section moves verbatim with a provenance comment.
- FEATURE RULINGS LIVE WITH THE FEATURE (Mazhron 2026-09-26: per-feature
  knowledge accumulates where the feature lives): a ruling about one
  feature lands in that feature's docs/systems/ topic file under
  `## Rulings` (date + his verbatim words, newest first); the WHY behind
  a project-wide or subtle ruling goes to INTENT.md, cross-linked both
  ways. Before building on a feature, read its Rulings section.
- Internal docs may use dashes; player-facing text may not (player-text.md).
```

### `skills/brief/SKILL.md`

- Source: `skills/brief/SKILL.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 4651
- SHA-256: `d2e900a4a326fa4ba85aefe4757ae8cdf5e4852360eb975baef41f4ca79d2912`

```text
---
name: brief
description: Compose and dispatch a sub-agent (employee) brief that follows the delegation laws - stamped, self-contained, budget-capped, diff-only reporting - then verify cheap and ledger the outcome. Use whenever delegating a task.
---

# /brief - delegate a task by the laws

PURPOSE: Compose and dispatch a sub-agent (employee) brief that follows the
  delegation laws, stamped, self-contained, budget-capped, diff-only
  reporting, then verify cheap and ledger the outcome.
INTENT: So delegated work stays safe and reviewable: the employee starts
  self-contained, is capped at about 30 tool calls, never deletes, respects
  the fan-out limits, and the manager logs an intent claim and ledgers the
  outcome afterward.

Read SUBAGENTS.md RULES + ASSIGNMENTS first (never the ledger unless
appending/auditing). Then compose the brief with ALL of:

1. STAMP: task id, date, workstation, assigned model (from the assignments
   table; escalate a task type's model when its correction rate passes ~25%).
   THE EMPLOYEE MODEL RULE (kit v1.40): the Agent call's `model` field is
   set explicitly, always - a call without one inherits the manager's own
   model, and the manager's tier is never an employee; the brief guard
   refuses a work dispatch whose model is missing or names that tier.
2. SELF-CONTAINED CONTEXT: everything the employee needs inline or by exact
   file/section pointer - an employee starts with an EMPTY context and must
   not wander the repo discovering things.
3. TOKEN BUDGET LINE, verbatim: "If you exceed ~30 tool calls or fail the
   same step twice, STOP and report what you have."
   THE ONE-TURN LINE (rule 7, kit v1.43, 2026-10-05 - a public reply to
   Mazhron's Rootstock comment, Ken Brown: "call all tools in a single
   call"), verbatim: "Independent reads, greps and checks go in ONE turn,
   never one per turn; only a step that needs the previous result waits."
   Every extra turn re-reads the employee's whole growing context; the
   auditor's tools= count against its turn count shows who obeys.
4. REPORT FORMAT: write files directly; report `git diff --stat` + changed
   hunks + a short summary. NEVER paste whole file bodies back.
5. THE WORKFLOW LINE (rule 11): for a repeatable multi-step task, NAME the
   WORKFLOWS.md entry and paste its STEPS into the brief; the employee's
   stamp ends with "WORKFLOW: matched <entry> | GAP: <uncovered process> |
   n/a".
6. THE FAN-OUT CHECK (rule 12): before dispatch, count. A handful of
   employees in this batch (4 is the habit), no employee that spawns
   employees, no Workflow tool unless Mazhron asked for it. Needs dozens?
   That is a design problem - split, script, or ask - not a bigger
   fan-out. If the fan-out guard refuses a spawn (8 in a minute, 25 in
   ten, or runaway token velocity - the owner's numbers via /runaway),
   stop and report; never resume the same loop and never raise a limit
   to get past it.

7. THE PRESERVATION LINE (rule 13, 2026-09-10), verbatim in every brief:
   "THE PRESERVATION LAW: your work contains NO deletion code and runs no
   delete command; move or retire instead (tools/retire.py,
   tools/cold_shelf.py); a harness hook refuses writes containing
   deletion calls. If the task seems to need a deletion, STOP and report."
8. THE INTENT LINE (rule 14, 2026-09-13): if the task rests on a ruling
   whose why matters, `Grep "^## " INTENT.md` and PASTE the relevant
   section into the brief (never "see INTENT.md"). Every brief ends by
   requiring "INTENT: <one line: what you understood the task to be, in
   your own words>" after the STAMP/TOOLS/WORKFLOW lines.

AFTER THE EMPLOYEE RETURNS
- Log the INTENT line as a claim (`python tools/intent_log.py --claim
  --actor <model> --task "..." --mine "<the line>"`) and resolve it once
  verified (SAME / SIMILAR / DIFFERENT, source inferred or stated); a
  correction goes through /correct (tools/correction_log.py, actor = the
  model) which resolves the claim DIFFERENT itself.
- Verify cheap, in order: tests/probes first, spot-read the diff second,
  full read only on smell.
- Watch for fabrication (it has happened): claims must match the diff.
- LEDGER the outcome in SUBAGENTS.md (append-only, with correction tally).
- A reported WORKFLOW GAP gets captured in the same batch: write the
  WORKFLOWS.md entry, or brief a haiku with the employee's report + the
  entry template (WORKFLOW_METHOD.md).

The manager keeps: design, laws, architecture, verification, pushes.

Search keys: delegation, employee brief, sub-agent, stamp, fabrication check.
See also: SUBAGENTS.md (this project's table); SUBAGENT_METHOD.md (portable).
```

### `skills/checkpoint/SKILL.md`

- Source: `skills/checkpoint/SKILL.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 4956
- SHA-256: `622a04cc7810f20a8c7763a7dff63a6d8ba272e675e17b06719e1c0e99fd96ae`

```text
---
name: checkpoint
description: Close an arc safely - push, refresh the day file's WHERE WE LEFT OFF with both sides of the final exchange, reset the task counter, and emit the safe-to-clear marker. Use at arc end or when the checkpoint counter warns.
---

# /checkpoint - close the arc so the chat can be cleared losslessly

PURPOSE: Close an arc safely: push, refresh the day file's WHERE WE LEFT OFF
  section with both sides of the final exchange verbatim, reset the task
  counter, and emit the safe-to-clear marker.
INTENT: Mazhron's ruling 2026-09-10, ADVISED MEANS DO IT: the owner never
  has to ask to checkpoint, they simply /clear afterward, so after /clear
  the owner should have nothing lost, everything they need is given back
  unprompted.

ADVISED MEANS DO IT (the owner's ruling 2026-09-10): when the prompt
gauge or the Stop hook says CHECKPOINT ADVISED, run this sequence at the
END OF THAT REPLY, unprompted - the owner never has to ask, they simply
/clear afterwards. Mid-arc: finish the current step, ship it, then
checkpoint before taking new work.

PRECONDITIONS (refuse and say why if any fail):
- No employee (sub-agent) running.
- No uncommitted work; never checkpoint mid-arc.

SEQUENCE
0. Close the loop (THE LOOP LAW, 2026-09-14): `python tools/run_all.py
   session` (regen + check + metrics append their ledgers; the session-
   start hook also runs it once a day, so this is usually seconds). If the
   Stop hook said CHANGELOG UNEXPORTED, run `python tools/export_changelog.py`
   now. Ask once: was anything this arc done by hand twice? Then it is a
   WORKFLOW GAP - write the WORKFLOWS.md entry (or brief a haiku) before
   pushing. Ask a second time: was anything this arc learned by trial and
   error, or corrected? Then it is a LESSON (THE LESSON LAW, 2026-09-20):
   write or amend the LESSONS.md entry before pushing.
1. Push everything (tree clean, remote up to date), then
   `python tools/backup_push.py` (THE LOCAL MIRROR + THE BROWSABLE COPY).
2. Refresh the NEWEST day file's `## WHERE WE LEFT OFF` section
   (docs/history/days/YYYY-MM-DD-WS#.md; create today's file + a
   days_index.txt line if it does not exist). The section carries:
   - USER'S LAST PROMPT (VERBATIM - copied word for word, unabridged,
     in a fenced quote block; NEVER condensed or paraphrased)
   - MANAGER'S LAST RESPONSE (VERBATIM) - BOTH sides, always. MECHANICS:
     the response stored is the checkpoint reply itself, so write this
     section containing the reply you are ABOUT to send, then send
     exactly that text. The user must recognize their own words at the
     next standup - a paraphrase is a failed checkpoint.
     (SAFETY NET: standup independently mines the true final exchange
     from the harness transcript, so a mid-arc /clear no longer loses
     post-checkpoint work - but this section remains the committed,
     searchable record; keep writing it faithfully.)
   - STATE (version, tree, what shipped this arc)
   - OPEN QUEUE / NEXT LIKELY
3. Commit + push the day-file refresh.
4. Run `python tools/checkpoint.py --reset` LAST - it also stores the
   Stop hook's work fingerprint, so the checkpoint commit itself is not
   counted as a task.
5. End the reply with the marker, verbatim:
   "CHECKPOINT - safe to /clear. Nothing in this chat exists only in this chat."

The counter TICKS ITSELF (Stop hook, 2026-09-06) whenever a reply changed
the tree or HEAD - never tick by hand, it double-counts. Relay its warnings
(advised at 8, dire at 15 - at dire the Stop hook refuses to end the turn
once and the prompt hook repeats the line) verbatim.

THE CONTEXT GAUGE (Mazhron's 80% rule, 2026-09-04): every tick/status
also prints the live context load, probed from the harness transcript.
REGARDLESS of the task count, once less than 80% of the auto-compact
budget remains, CHECKPOINT at the end of the current reply if the arc
is closed (ADVISED MEANS DO IT); under 30% remaining, treat it as
URGENT and checkpoint before taking new work. Auto-compact is a lossy summary - the day file + standup are
lossless, so clearing early is always the cheaper path. Relay the
gauge line and its warnings verbatim, like the task warnings.

THE NET UNDER THIS RITUAL (the owner's ask 2026-09-20): the SessionEnd
hook (tools/hooks/session_end.py) runs at /clear. With nothing unbanked
it writes one ledger line; with unbanked work it does steps 1-4 by
itself, mechanically (the exchange mined from the transcript, an AUTO
section, a "Checkpoint (auto)" commit, origin + mirror, the reset) and
leaves NEXT LIKELY unwritten. It exists so a forgotten checkpoint loses
nothing; it is not a reason to skip this ritual.

IF THE SCRIPTS/DAY FILES ARE MISSING (new project): bootstrap them per
REPORTING_METHOD.md, or ask the user for their future-project kit.

Search keys: checkpoint, safe to clear, day file, context budget, arc end.
See also: standup skill (resumption side); ship skill (per-batch, smaller).
```

### `skills/correct/SKILL.md`

- Source: `skills/correct/SKILL.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 3010
- SHA-256: `6cb191eb4ac57ebe138a3854c78aa32252b01e1138d2adbfc3470ba383698198`

```text
---
name: correct
description: Walk a correction - ask what needs correcting, record the owner's words, resolve the intent claim DIFFERENT, then fire /intent, then fix - invoked when the user says "correct", "correction", "that's wrong", "not what I meant", "fix that", or invokes /correct.
---

# /correct - record the words, ask the why, then fix

PURPOSE: Walk a correction: ask what needs correcting, record the owner's
  words, resolve the open intent claim DIFFERENT, fire /intent, then fix the
  thing.
INTENT: Mazhron's ruling 2026-09-13: a correction is not just a fix, it is
  evidence about a misread intent; recording it before fixing means a lost
  session loses nothing, and asking what the intent was right after captures
  the mismatch while it is still fresh.

THE POINT (Mazhron's ruling 2026-09-13): a correction is not just a fix,
it is evidence about a misread intent. Recording it before fixing means a
lost session loses nothing, and asking "what was the intent?" right after
means the mismatch gets captured while it is still fresh.

1. ASK exactly: "What about the last thing I did needs correcting?" and
   wait for the answer.
2. RECORD IT before fixing anything:
   `python tools/correction_log.py --record --actor <fable, or the
   employee's model if an employee built the thing> --shipped "<what was
   built, 3-10 words>" --wrong "<Mazhron's words, VERBATIM>" [--intent-id
   <the open claim's id, from python tools/intent_log.py --pending or
   --last>] [--intent-ref "<INTENT.md heading if known>"]`
   - the script resolves the named intent claim DIFFERENT with
     source=correction by itself; nothing else to do for that step.
3. SAY BACK, in one line, what will be fixed. Then ask exactly: "What was
   the intent?" and run the /intent skill's steps on the answer - this is
   the feedback loop: correction, then why, while the mismatch is fresh.
4. FIX the thing.
5. `python tools/correction_log.py --fixed <id> --fix "<commit subject or
   note>"` and ship.
6. If the correction reveals a rule that will recur, add the law where it
   belongs (a CLAUDE.md standing rule or the relevant method file) with a
   pointer to the INTENT.md section just filed.

RULES
- Never argue the correction inside this skill. THE CONTRADICTION RULE
  lives elsewhere: if the correction contradicts an earlier ruling, say so
  in one line and ask - never silently comply, never silently refuse.
- Never record a paraphrase - Mazhron's words go in --wrong exactly as
  said.
- The record is written BEFORE the fix, so a lost session loses nothing.
- An employee's mistake is still recorded here (actor = its model) and
  also tallied in SUBAGENTS.md's ledger by the manager - two ledgers, one
  event.

Search keys: correct, correction, that's wrong, not what I meant, fix
that, correction ritual, feedback loop.
See also: tools/correction_log.py; /intent skill (fired as step 3);
INTENT.md; SUBAGENTS.md (employee corrections tally, rule 6 escalation);
WORKFLOWS.md "Correct a mistake".
```

### `skills/flag/SKILL.md`

- Source: `skills/flag/SKILL.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 4784
- SHA-256: `f69f0ee277a81f29d5fdf06cebf8d912d6913fa3b1704de462aafcf433bd2ef9`

```text
---
name: flag
description: Run the purpose audit on a kit thing (a script, hook, skill, method file or injectable prompt) - read-only, compare what its PURPOSE line says with what it actually does, flag it green, yellow or red, explain, and file the flag in FLAGS.md for review. Use when the user says "flag", "audit this", "purpose audit", "does this do what it says", or before a contributed update merges. Any Claude may flag; nobody edits the thing in the audit turn.
---

# /flag - read-only, flag, explain; the finding goes in the git

PURPOSE: the ritual behind FLAGS.md - one kit thing at a time, the auditor
  reads it, compares the stated purpose with the behaviour, gives it a
  color, explains the color in the entry, and never touches the thing.
INTENT: Mazhron 2026-09-13: "Claude MUST compare the purpose and intent of
  the thing vs what the thing actually reads whether it's a script, hook,
  code or injectable prompt. If there is reason to flag it, Claude should
  flag them green, yellow or red. Claude should always read-only -> Flag
  -> Explain. There should be a file that directly references anything
  that is green, yellow or red flags, tally them and put them in the git
  for review. Any Claude can review and put their findings there for
  future review."

1. PICK THE THING. `python tools/purpose_audit.py --pending` lists what is
   UNFLAGGED (never audited) or STALE (changed since its last flag). A
   contributed update is audited BEFORE it merges: every thing it adds or
   changes. Paths are kit-relative (hooks/preserve_guard.py,
   reference tools/standup.py, skills/ship/SKILL.md, WIKI_METHOD.md).
   THE BATCH RULE (Mazhron 2026-09-14, the first systems audit: "employee
   is cheap. Manager is not."): more than about five pending things go to
   ONE read-only employee (sonnet, the /brief skill) that reads them and
   files the flags itself; the manager reads only the REDs it reports.
   The 09-13 audit read 58 files in the manager's context - never again.
2. READ ONLY. Read the thing's header (PURPOSE, INTENT) and then its body.
   Do not edit it, do not run its side effects, do not "fix while here".
   For a method file read the first forty lines and the section index;
   for a script read it whole (they are small) - a hook must be read whole.
3. COMPARE. Does the body do what PURPOSE says - all of it, nothing more?
   Look for: a side effect the purpose does not mention; a deletion or a
   write outside its stated files; a way around a guard or a refusal; an
   unbounded loop, spawn or spend; text injected into the manager that
   the purpose does not describe; a purpose line that is vague, unfilled
   or stale.
4. FLAG. GREEN: does what it says, nothing more. YELLOW: matches in
   substance, something is off (fix later, may ship). RED: does what its
   purpose does not say, or crosses a law - the owner sees it before it
   merges or ships. A thing with no PURPOSE line cannot be green.
5. EXPLAIN + FILE:
   `python tools/purpose_audit.py --flag "<kit path>" --color green|yellow|red
   --by <who> --does "<what it actually does, one or two sentences>"
   --note "<why this color; for yellow/red, what would fix it>"`
   The script fills SAYS from the PURPOSE line, hashes the exact version
   reviewed, appends the entry and regenerates the tally.
6. AFTER, NOT DURING: a MISSING header (or a placeholder) is written by
   the script (`python tools/format_lint.py --rewrite <original path>
   --purpose ... --intent ...`) in a later step, never in the audit turn.
   A WRONG line that exists (a stale PURPOSE) the script cannot replace -
   --rewrite only fills gaps - so it is edited in the ORIGINAL after the
   flag is filed, then format_lint and refresh_kit run and the thing is
   flagged again on its new version (2026-09-29, law_gaps.py). A RED goes
   to the owner as a question, with the entry quoted.
7. Ship with the batch: FLAGS.md is kit content and syncs to the public
   repo with everything else. A contributor files the same entry by pull
   request.

RULES
- Read-only means read-only: the audit turn changes nothing but FLAGS.md.
- Never flag what you did not read; never green what has no PURPOSE line.
- No em or en dashes in an entry (the script refuses them).
- An employee may flag (SUBAGENTS.md rule 15) and reports RED upward; the
  manager brings a RED to Mazhron.

Search keys: flag, purpose audit, green yellow red, read-only audit, does
it do what it says, contributed update review, FLAGS.md.
See also: tools/purpose_audit.py (the writer + the tally); tools/
format_lint.py (the header + the rewrite); "Future Project
MDs/CONTRIBUTING.md" (the law for contributors); "Future Project
MDs/FLAGS.md"; WORKFLOWS.md "Audit a kit thing's purpose (flag it)";
INTENT.md "The purpose audit".
```

### `skills/intent/SKILL.md`

- Source: `skills/intent/SKILL.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 3438
- SHA-256: `c4ee487a4b854b37dc8a52e47864c999eb91a506ac597dcf3fadc0a893e12667`

```text
---
name: intent
description: Record the WHY of a ruling in the owner's words and resolve the open intent claim - invoked when the user says "intent", "the why", "what I meant", after a correction, or when the manager hits a "what did the user mean by this?" question.
---

# /intent - file the why in the owner's own words, then close the claim

PURPOSE: Record the WHY of a ruling in the owner's own words in INTENT.md
  and resolve the open intent claim comparing the manager's reading against
  it.
INTENT: Mazhron's ruling 2026-09-13: a ruling is not just a rule, it is a
  WHY, and knowing the why lets Claude or any employee make the same call
  next time without asking.

THE POINT (Mazhron's ruling 2026-09-13): a ruling is not just a rule, it
is a WHY - and knowing the why lets Claude or any employee make the same
call next time without asking. INTENT.md holds one section per ruling;
this skill is how a section gets filed and how the running comparison
(Claude's reading vs Mazhron's actual intent) gets closed out.

1. GET THE WORDS. If Mazhron has not yet stated the intent in this
   conversation, ask exactly: "What was the intent?" and wait. If he
   already stated it, quote it back and confirm before filing - never
   file words that were not actually said.
2. FILE THE SECTION in INTENT.md, in the existing format:
   - a searchable `## <nouns>` heading naming what a search would look for
   - `ASKED (Mazhron YYYY-MM-DD): "..."` - his prompt VERBATIM, never
     paraphrased
   - `WHY (verbatim): "..."` - his reasons, numbered where he numbered them
   - `GENERALIZES TO (manager's reading): ...` - marked as the manager's
     own reading, never presented as his words
   - `LIVES IN: ...` - the law, file or script the rule lives in
   - a `Tags: intent, ... | one-line brief` line
   - a `See also:` line
   If a section for this ruling already exists, extend it - append a
   dated ASKED/WHY pair under the existing heading - rather than filing a
   duplicate.
3. RESOLVE THE OPEN CLAIM:
   `python tools/intent_log.py --pending` to find the claim, then
   `python tools/intent_log.py --resolve <id> --theirs "<Mazhron's words>"
   --verdict same|similar|different --source stated|correction
   --intent-ref "<the heading just filed>"`
   - SAME: the manager's claimed reading matched.
   - SIMILAR: matched in substance, a detail differed and was adjusted.
   - DIFFERENT: a rebuild or correction was needed.
   Source is `correction` when the /correct skill led here, `stated`
   otherwise.
4. POINT THE LAW. If a rule in CLAUDE.md or a method file carries this
   ruling, add one line to it: "(intent: INTENT.md '<heading>')" - one
   line, nothing else about that law moves.
5. Ship with the current batch - no separate commit needed for this alone.

RULES
- Mazhron's words are sacred: verbatim, no cleanup, no dashes added where
  he did not write them.
- Never write an intent Mazhron did not state. A guess belongs only in
  GENERALIZES TO, marked as the manager's reading.
- No employee ever invokes this skill - filing intent is the manager's
  job; an employee that hits the question relays it up instead.

Search keys: intent, the why, what I meant, record intent, file a ruling,
resolve claim, same similar different.
See also: INTENT.md (the sections themselves); tools/intent_log.py;
/correct skill (fires this as its third step); INTENT_METHOD.md
(portable); WORKFLOWS.md "Record an intent".
```

### `skills/preserve/SKILL.md`

- Source: `skills/preserve/SKILL.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 4957
- SHA-256: `4e00a52fb581e39633bb8a79750b2fb4470e59355d0e54f95c6ed6e19a052090`

```text
---
name: preserve
description: Retire a file, shelve a wiki section, or walk the twice-acknowledged delete grant - THE PRESERVATION LAW's conversational front. Use when the user says "preserve", "retire", "shelve", "cold shelf", "delete", "remove", "get rid of", "clean up", or when a task would otherwise delete anything. Never invoked by an employee; never used to route around the preserve guard.
---

# /preserve - move it, shelve it, or ask twice; never just delete

PURPOSE: Retire a file, shelve a wiki section, or walk the twice-
  acknowledged delete grant; the conversational front for the preservation
  law.
INTENT: The owner's ruling 2026-09-10: neither the manager nor any employee
  deletes a file, record or tree without the owner's express permission
  given twice, and no script is written that deletes; knowledge is hard-won
  and never lost.

THE PRESERVATION LAW (the owner's ruling, 2026-09-10): neither the manager
nor any employee deletes a file, record or tree without the owner's
express permission given TWICE, and no script is written that deletes.
Knowledge is hard-won and never lost. The preserve guard
(tools/hooks/preserve_guard.py) refuses delete verbs, work-discarding git
verbs and deletion calls in new code; this skill is how the lawful moves
happen. The three moves are offered IN THIS ORDER; a later one is taken
only when the earlier ones cannot do the job.

1. NAME THE TARGET. Say exactly what would go and why (path, size, what
   references it). If the invocation carried a path (`/preserve
   scripts/old_thing.gd`), use it; otherwise ask. A wildcard, a folder
   the owner did not name, or "everything under X" is never a target.
2. RETIRE (files and folders inside the repo):
   `python tools/retire.py <path> [...] --reason "..."` - moves to
   _retired/<same relative path> (Godot resource types get a .retired
   suffix; the folder carries .gdignore; collisions get a numeric suffix,
   nothing overwritten) and appends docs/history/retired_files.txt.
   `--dry-run` previews; `--list` reads the ledger. If the target was
   referenced (a scene, an autoload, an index line, a See-also), fix the
   references in the same batch. Done: commit with a player-readable
   subject; no build unless game content moved.
3. SHELVE (a rarely-read wiki section that thins a hot file):
   `python tools/cold_shelf.py --move <file.md> "<## heading>" --reason
   "..."` - the section goes VERBATIM to docs/cold/<file>, a two-line stub
   stays under the hot heading, docs/cold/INDEX.md gains a line.
   `--dry-run` first; `--check` verifies every stub; `--restore` reverses.
   Cold by read count is NEVER a shelf reason on its own (the owner,
   2026-09-10) - only the owner picks what shelves, usually from
   wiki_heat.txt's ACTIVE-UNREAD list or by hand.
4. DELETE GRANT (rare by design - a branch, a stash, a generated tree, a
   file the owner wants GONE, when a move truly is not the answer):
   a. Ask, naming the EXACT target and size: "This will delete X (n
      files, y KB). Do you approve?" Wait for a yes.
   b. Restate and ask again: "To confirm: delete X and nothing else?"
      Wait for the second yes.
   c. Record all four texts verbatim:
      `python tools/delete_grant.py --target "<path>" --ask "<q>"
      --ack1 "<yes 1>" --ack2 "<yes 2>"` (single use, 15 minutes,
      ledgered in docs/history/delete_grants.txt; drive roots, the home
      folder and the repo root are refused here and by the guard).
   d. Run the ONE deleting command that names the target. The guard lets
      it through once and marks the grant used.
   e. `python tools/delete_grant.py --status` says USED; report the
      ledger line. Nothing else is gone.
5. Ship the batch per /ship (the retired_files / delete_grants ledger
   lines ride with it).

RULES
- The order is the law: retire before shelve before delete. Offer the
  cheaper move first even when the owner said "delete".
- Only the manager runs this, at the owner's word. An employee that needs
  a deletion STOPS and reports (SUBAGENTS.md rule 13 / the brief's
  preservation line).
- A refusal from the preserve guard is the owner's standing decision:
  never reword a command to slip past it, never write a script that
  deletes. Move the thing, or ask twice.
- A wrong memory or a wrong wiki fact is marked superseded in place, not
  removed.

IF A SCRIPT IS MISSING (new project): retire.py, cold_shelf.py and
delete_grant.py live in the kit's "reference tools/" (HOOKS_METHOD.md
Tier 2d bootstrap). Ask the owner for their future-project kit before
improvising a move.

Search keys: preserve, retire, cold shelf, shelve, delete grant, delete
something, remove a file, preservation law, never delete.
See also: WORKFLOWS.md "Delete something (the grant ritual)" + "Retire a
file or move a wiki section to the cold shelf"; HOOKS_METHOD.md (Tier
2d, the preserve guard); WIKI_METHOD.md (the cold shelf); SKILLS.md (the
shelf); SUBAGENTS.md rule 13.
```

### `skills/runaway/SKILL.md`

- Source: `skills/runaway/SKILL.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 3476
- SHA-256: `5cbde4d6d880f1803c4a6c364911b2afb3d4263c781ba01f22952022a00acab9`

```text
---
name: runaway
description: Show and tune the fan-out guard's runaway numbers (spawn burst and flood caps, token velocity halt, the warning steps). Use when the user says "runaway", asks what the guard's limits are, or wants them changed. Only the owner tunes - never invoke it to raise a limit on your own.
---

# /runaway - the guard's numbers, in the owner's hands

PURPOSE: Show and tune the fan-out guard's runaway numbers (spawn burst and
  flood caps, token velocity halt, the warning steps).
INTENT: The guard refuses only runaway shapes so real work is never blocked,
  and only the owner tunes its numbers, never the manager on its own, so a
  limit only moves when the owner has actually seen the guard speak on
  honest work.

The fan-out guard (tools/hooks/fanout_guard.py, a PreToolUse hook on every
tool) refuses only runaway shapes and warns on the rest. Its DEFAULTS live
in the script; the owner's TUNED numbers live in `.claude/fanout_limits.json`
(COMMITTED - they travel with the repo and survive a kit graft). This skill
is the conversational front for that file.

1. Run `python tools/hooks/fanout_guard.py --limits` and relay the table
   in plain words: each of the nine numbers, current vs default (a `*`
   marks a tuned one), and what crossing it does. Lead with the three
   REFUSALS (burst_cap per machine, flood_cap per session, velocity_halt),
   then the warn-only steps. Say whether the file exists.
2. If the invocation carried changes (`/runaway burst_cap=12 flood_cap=40`),
   apply them straight away; otherwise ask which numbers change and to
   what. Offer, never enforce: the defaults never fire on real work, so a
   limit is worth raising only when the guard has actually spoken on
   honest work; velocity_warn must stay below velocity_halt (the script
   refuses otherwise); windows are seconds, caps are counts, velocity is
   WEIGHTED tokens (input 1, cache write 1.25, cache read 0.1, output 5).
3. `python tools/hooks/fanout_guard.py --set key=value ...` (several at
   once; underscores and commas in numbers are fine). A refusal prints
   why and writes nothing - relay it verbatim. `--defaults` forgets all
   tuning and removes the file.
4. `python tools/hooks/fanout_guard.py --selftest` must still print PASS.
   It always runs at DEFAULTS, so tuning cannot break it; a FAIL means
   the script, not the numbers.
5. Show the new table, then commit `.claude/fanout_limits.json` with the
   batch (a player-readable subject; a harness change, no build, no kit
   refresh - the kit ships the defaults and each project keeps its own
   file). Nothing to restart: the guard reads the file on every call.

RULES
- Only the owner tunes. The manager never runs `--set` unprompted and
  never raises a limit to get past a refusal - a refusal from the guard
  means stop and report (SUBAGENTS.md rule 12 / SUBAGENT_METHOD.md law 6).
- Lowering is always safe to do at the owner's word; raising deserves the
  one-line reminder in step 2, then the owner's answer stands.

IF THE SCRIPT IS MISSING (new project): the hooks are not installed yet.
Ask the owner for their future-project kit (HOOKS_METHOD.md Tier 2b
carries the guard and its bootstrap) before improvising limits.

Search keys: runaway, runaway numbers, fan-out limits, agent cap, spawn
cap, token velocity, tune the guard, fanout_limits.json.
See also: HOOKS_METHOD.md (Tier 2b); SKILLS.md (the shelf); SUBAGENTS.md
rule 12; brief skill step 6 (the fan-out check).
```

### `skills/ship/SKILL.md`

- Source: `skills/ship/SKILL.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 3298
- SHA-256: `10347918c3b7522a580547c5c52e69a9a2d28eb6c1a766df58d594556560de45`

```text
---
name: ship
description: Ship a completed batch - commit with a player-readable subject, push, and (in projects with builds) refresh build zips without deleting old ones. Use after every completed work batch, unprompted.
---

# /ship - the per-batch ship ritual

PURPOSE: Ship a completed batch: commit with a player-readable subject,
  push, and (in projects with builds) refresh build zips without deleting
  old ones.
INTENT: Mazhron 2026-09-04: Without my asking the changelog should be
  updated. The ritual runs every step, tests, version, commit, push, builds,
  kit sync, changelog, unprompted after each batch so nothing is forgotten.

Run after EVERY completed batch of work; the user should never have to ask.

1. Sanity: tests/checks relevant to the batch are green (trust the ledger -
   do not re-run identical green runs). THE SECURITY QUESTION (kit v1.39):
   did this diff touch secrets, env, auth, headers, CORS, hosting or
   database rules? Then the security audit runs first (WORKFLOWS "Audit
   the app for exposed secrets before a public release"); a project with
   no backend and no keys answers no by its standing exemption.
2. Version: `python tools/version_hint.py` prints the first-pass reading
   (none / patch / minor from what changed since the last bump; never
   major, that is the owner's call). Bump if the batch warrants it (MINOR for a notable batch, MAJOR
   for a core-pillar milestone) in the project's single version source.
3. Commit: subject = one-line player-readable hook (it becomes the public
   changelog); body = player-readable detail bullets, same voice. Follow the
   project's text doctrines (in Everwood: no em/en dashes in player-facing
   text, including commit subjects).
4. Push, then `python tools/backup_push.py` (THE LOCAL MIRROR: every
   branch and tag to the bare `backup` remote of this repo and the kit
   repo, on another drive, then THE BROWSABLE COPY: the working folder
   robocopied beside the mirror, add/update only; a missing remote or
   drive is a skip line).
5. Builds (projects that ship binaries): run the build script
   (`python tools/make_builds.py` in Everwood). NEVER delete older build
   zips - old versions are the "before" side of dev-log comparisons.
6. Kit sync (projects that publish a kit): if the batch touched any
   future-project-kit file, run the kit sync script (in Everwood:
   `python tools/sync_kit_repo.py` pushes the public Rootstock repo; it
   REFUSES while the README's version lags or the README parity lint
   fails - fix the README or the kit, never bypass).
7. The checkpoint counter ticks itself (Stop hook) - relay any warning
   the hook prints; never tick by hand (it double-counts). Hookless
   machines only: `python tools/checkpoint.py --tick`.

Changelog EXPORT ships with the batch, unprompted (user ruling
2026-09-04: "Without my asking the changelog should be updated").
In Everwood, make_builds.py runs the export itself; a batch that
ships WITHOUT a build runs `python tools/export_changelog.py` by
hand before the batch counts as done. (This reverses the old
"user-triggered" line - 0.99.2..0.99.9 piled up under it.)

Search keys: ship, commit ritual, batch end, build zips, changelog voice.
See also: checkpoint skill (arc-level close); REPORTING_METHOD.md (ledgers).
```

### `skills/standup/SKILL.md`

- Source: `skills/standup/SKILL.md` at `0001a40c74a76d0ab7a8898778ac786e994bbb74`
- Bytes: 2514
- SHA-256: `d710290d082adb0a7c5206ca0589fd8fd00b13cc0699ebccf518c8c39b01526c`

```text
---
name: standup
description: Open a session - print the standup digest and hand back the last exchange (prompt + response) and project state before anything else. Use at session start, after /clear, or whenever the user says "standup".
---

# /standup - the session opener

PURPOSE: Open a session: print the standup digest and hand back the last
  exchange (prompt and response) and project state before anything else.
INTENT: The script mines the true final exchange from the harness
  transcript, ground truth on disk, so after a clear the owner has nothing
  and this gives it back unprompted, even after a mid-arc clear.

1. If a [HOOK session_start] block is already in context, the digest
   was injected automatically - do NOT run the script again. Otherwise
   run `python tools/standup.py` from the repo root.
2. Relay THE LAST EXCHANGE block FIRST and VERBATIM: the user's last
   prompt AND the manager's last response exactly as the script prints
   them, word for word in quote blocks - never summarized, condensed, or
   paraphrased (the user must recognize their own words). The script mines
   these from the HARNESS TRANSCRIPT (ground truth on disk), so they are
   the true final exchange even after a mid-arc /clear - trust the script's
   block over the day file's checkpoint-time copy. Then relay state and
   next-likely from WHERE WE LEFT OFF. After a /clear the user has nothing -
   give it back unprompted.
3. Then THE BUDGET block: relay its last line or two (yesterday and
   today so far: weighted spend vs the previous 7 active days, top
   pillar, cache misses, reads). A CHECK verdict is relayed VERBATIM -
   it names what went wrong (spend, misses, heavy whole-file reads); a
   LOW spend line is good news worth one sentence.
4. Then summarize the rest of the digest briefly: version, open roadmap
   items, ledger tails worth noting, anything blocked.
5. End by asking what to work on, or naming the next-likely step.

RULES
- Never re-read notes/day files wholesale when the digest covers them;
  open a full file only where the digest points.
- Never re-run green tests at an unchanged version (trust the ledger).

IF THE SCRIPT IS MISSING (new project): this project lacks the reporting
kit. Ask the user for their future-project kit (SKILLS.md + REPORTING_METHOD.md
carry the bootstrap) before improvising a summary.

Search keys: session start, standup, resume after clear, where we left off.
See also: checkpoint skill (the other end of the loop); REPORTING_METHOD.md.
```
