# Stethoscore Android source selection

Audit snapshot: 13 October 2026. Selected repository: `NoNeed2name444/red-pen-ios`, branch `personal`, commit **`be11a567cff6f96d74266cdadba63415b832a32c`** (9 October 2026, 16:03:43 UTC).

## Evidence

- All **119 actual iOS branch heads** were inspected by name, SHA, timestamp and subject. `red-pen-ios-refs.tsv` has 120 rows because its `origin` row is the symbolic default alias. See `ios-branch-inspection.md` for a disposition for every branch.
- A local `git ls-tree` inspection succeeded for **all 119 branch roots**, recording the `ios`, `server`, `android` and `plan.md` entries where present. **83** branches contain at least one of those source/plan paths; the remaining roots do not. Exact tree/blob hashes are in `ios-branch-trees.json`. No network or complete historical checkout was needed for this tree inspection.
- `personal` and `claude/medical-assistant-orchestration-javb9y` resolve to exactly the same selected SHA. No application development branch has a later head timestamp in this snapshot.
- `CLAUDE.md` explicitly identifies `personal` as the working branch. The selected `plan.md` says it incorporates M3 Neurons, source verification, the map fixes, launch gap fixes, and the latest neumorphic UI follow-ups. It identifies `d16846d` as the underlying application update, with the selected head updating the plan.
- `previews` at `1bb98105725d3e8bfa7ad0279a974834e948c2fb` has the subject **“iOS preview of d16846d”**. `swift-tests` at `3133d976260492d153dfc3a59161b5957f26022b` is newer (16:12:33 UTC) but is generated test output, not a newer app version.
- `design/launch-gaps` at `b74dd06943c8c0b2448d4f3d2b0a8822c5664509` (13:44:20 UTC) and `design/map-lighter` at `babed7487286b182091044e6d72b4453deb59030` (12:56:39 UTC) are older than `personal`. Their relevant work is described as incorporated by `plan.md`.
- The application subtrees differ: `personal:ios/RedPen` = `ecdec91890fb4f6b033343be93f97c6542b55af9`; `design/launch-gaps:ios/RedPen` = `48f8e3d0250754a2d31a0580acad10c1a9e733da`; `main:ios/RedPen` = `e57686044ccfb5810b9b82ab03adb63119fbdf7f`. Therefore neither the default branch nor the launch-gap branch is an exact copy of the selected latest application.
- `aahp/personal` at `cece1a4dbd6d54650dc623563fd5f25934536b97` is explicitly described in the selected plan as an experimental T0033 result kept out of the session branch; it is not used as the Android base.

## Scope and limits

This checkout is shallow and blob-filtered. A history-deepening fetch was interrupted, so ancestry and an exhaustive historical file review are **not** claimed. Selection is based on complete branch-head metadata, available tree hashes, the current application source and the source repository's own state record. Generated screenshots and benchmark logs must not be mistaken for newer source releases.

Repository-level alternatives are documented separately in `Chat-me.md`, `Claude-Code.md`, and `red-pen-transcribe.md`. Those repositories contain orchestration/research or transcription components, not a newer complete native Stethoscore application.

## Port provenance

The Android port should cite the exact selected commit, carry over compatible server code and data contracts, and translate the native presentation and study logic to Kotlin. It should not claim a mechanical Swift-to-Kotlin conversion or full platform parity until the remaining features in `feature-parity.md` have been implemented and verified.

Branding is **Stethoscore**. The root README and older iOS README retain obsolete “Red Pen” descriptions and do not describe the current feature set. Current source files, `CLAUDE.md`, and the latest state in `plan.md` take precedence.
