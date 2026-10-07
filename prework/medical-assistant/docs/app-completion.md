# Application scaffold completion

Verified 2026-10-07. B3 and D1–D3/E1–E3 are complete for the requested mechanical scaffold scope. Authoritative schemas, routes, record operations, curriculum parameters, classifiers, generators and medical content remain injected by callers. The design-system module stays empty; no clinical verdict or final pedagogical copy was added.

## Changes

- The shell subscribes to isolated state snapshots, displays asynchronous loading/results, invalidates stale requests on navigation, and releases subscriptions on destroy. Caller data is cloned before entering state and rendered literally by default.
- Annotation logic is a module with exact item-attestation filtering, duplicate manifest rejection, caller-schema validation and Map-based identities (including `__proto__`). JSONL imports support CRLF. Failed imports cannot leave stale active input.
- Annotation storage failures preserve usable session state. Session edits take precedence over stale persistent reads when storage writes fail, and the UI reports that changes are only in memory. Reimporting the same schema retains those edits. Downloaded JSONL still requires authoritative Python validation.
- Read-only record transport, BKT updates/event replay, injected intent classification, literal evidence rendering and MCQ choice-reference validation remain caller-configured. Evidence and generated questions remain pending review.

## Verification

From this directory, install dependencies with `npm ci --ignore-scripts` and browsers with `npx playwright install --with-deps chromium`. Run `npm test` and `npm run test:browser`. An existing compatible browser can be selected with `CHROMIUM_PATH`.

This execution used Node 24.19.0, Playwright 1.62.1, and `/usr/bin/chromium` via `CHROMIUM_PATH=/usr/bin/chromium npm run test:browser`. The default Playwright-downloaded executable was absent; the installed Chromium passed all five browser tests with process/network permissions supplied by the sandbox. Test servers bind loopback and adapters use synthetic fixtures, not live providers.

Results: **10 JavaScript module tests and 5 real-browser tests pass** (Python results are in `pipeline-completion.md`). Browser checks cover shell asynchronous state and navigation, literal injection strings, annotation save/restore/JSONL download, invalid labels/schemas, unavailable or corrupt storage, quota-only write failures with both empty and stale readable storage, and evidence/intent/MCQ/BKT adapters. The quota regression uses different old and new labels, proving the latest session value survives a stale read. No synthetic record was installed as production data.

Serve these ES modules over HTTP, for example `python3 -m http.server 8080 --bind 127.0.0.1`, then open `/app/annotation.html`; opening a module directly through `file://` is not the supported flow.

The delegated implementation used gpt-6.1-sol/high. The inherited root executor completed review, the strengthened quota test and final verification after the worker hit its usage limit. No model escalation or live inference was performed.
