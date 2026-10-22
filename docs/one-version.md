# One version

There is one version of the app: the branch `design/integration`, with the
iPhone app, the server and the tools (the Android app joins it later). No task
pushes a branch of its own, so nothing merges back to quietly undo newer work.

## How a task lands

1. Start from the tip, in a local worktree (a local branch there is fine; it is
   never pushed): `git fetch origin design/integration`, then
   `git worktree add -b <task> <dir> origin/design/integration`.
   That tip is the task's base, B (the task packet's `base`); B stays the same
   when later tips are taken in.
2. Before landing, take in the latest tip: fetch, then
   `git merge origin/design/integration`. Never rebase or force. In a conflict,
   keep both sides' work.
3. Pass the gate and the checks against that tip:
   `python3 tools/no_undo.py --base <B> --onto origin/design/integration --change HEAD`
   prints `no-undo: OK`, and `bash tools/preflight.sh origin/design/integration`
   prints `PREFLIGHT OK`.
4. Land by fast-forward: the task's commits land on the one version directly
   (`git push origin <task tip>:design/integration`, refused unless it is a
   fast-forward). If the tip moved meanwhile, go back to step 2.

## What the gate refuses

`no_undo.py` fails, naming each commit and its subject, when the change undoes
work that landed after B: it removes or alters a line a newer commit wrote (U1),
brings back a line a newer commit removed (U2), deletes or renames away a file a
newer commit changed, or replaces a binary one changed (U3), or, given the
task's `--scope`, changes a path outside it (U4). Keep that work; a rewrite the
owner approved passes with `--allow <commit>`, and only that one.

## Rules

- No test may be changed only so that it accepts a regression; a test changes
  only when the behaviour it checks was meant to change, in the same commit.
- Never two tasks on the same files at once; a task waits for the files it needs.
- Never force-push, and never land a change the gate or preflight refused.
