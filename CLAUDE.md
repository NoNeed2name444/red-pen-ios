# Stethoscore (red-pen-ios): working rules

The owner has only an iPhone and an iPad. Anything needing a Mac runs in GitHub Actions.
The handoff and the plan live in the Chat-me repo: docs/architecture/handoff/context.md (wins on app state) and plan.md.
The owner's design targets: docs/design/targets-2026-10-01.md (no Rank, Clerk badge or XP; the app stays Stethoscore).

## Decisions
- Build on, and decide from, the deep research and the verification layer in Chat-me: docs/architecture/research (the §22 briefs and their verdicts), the Task 4 audit, and the medical verifier (now in Chat-me's api/, agents/, orchestration/, governance/). The Worker's accuracy engine is the spine; the verifier folds in as modules. Cite the brief a decision follows.
- Order of work: what can be checked here (Linux, node, Python) first; what changes how the app looks last, batched into Mac runs.

## Before you push: check here, let CI confirm
- `tools/preflight.sh` (about a minute): the Swift suites your change touches, on Linux; every server test; the three Playgrounds core packages. Fix what it finds before pushing.
- Swift 6.4 for Linux is at /opt/swift (install: swift.org release for Ubuntu 24.04 into /opt/swift if missing).
- Suites are listed in tools/swift_suites.txt; run them with `tools/swift_suites.py [--only a,b] [--affected <ref>]`. A new suite goes there, and a suite that needs Compression or CryptoKit goes in tools/swift_suites_mac_only.txt.
- Keep test-covered logic in Foundation-only files; fence Apple-only imports with `#if canImport(...)`.

## Reading CI: a few lines, never whole logs
- `tools/ci_status.py <branch|sha> [--wait]`: one line per run and, for a failure, its first error lines. Exit 0 green, 1 failed, 2 running.
- Swift suites run on Linux (job "linux") and the Apple-only few on macOS (job "mac"); macOS machines (five at a time) are for the app build, screenshots (preview/<name> to shots/<name>) and recordings.

## Branches and commits
- personal is the working branch; keep the session branch a copy of it. Work on design/<name> (app-build runs there). Never force-push; no pull requests unless asked.
- Commit messages: a plain-English subject and a body saying why.
- The Swift Playgrounds zip (tools/make_swiftpm.py, variants core, core1, core2) is how the app reaches the owner's iPad: a kept file must not name a type its variant drops (tools/playgrounds_cut.py); keep added lines small.

## Never
- Propose Modal, a Whisper fallback, GEMINI_API_KEY in the app, Gemini 3.6 Flash, challenge-a-friend, ranks or leaderboards, or a personal self-learning model.
- Paste or commit secrets; use paid AI outside Pro (PRO_PAYS); deploy the Worker without the owner's word.
