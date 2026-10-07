# Supporting repository verification

Observed 2026-10-07 without live model calls, task execution or orchestrator workflow dispatch. Existing source contracts were tested; no source edits were needed in these three repositories.

| Repository snapshot | Verification | Outcome |
| --- | --- | --- |
| Chat-me `cb02cd49` (`prework/container-20261007`) | `DATABASE_PATH=/tmp/prework-chatme-tests.sqlite python -m pytest -q` using installed project development dependencies | 170 tests pass in 0.49s; one upstream Starlette deprecation warning. The default sandbox stalled TestClient; the same suite passed with process/network permissions. |
| Claude-Code `993f8d84` (`main`) | Local runner health with a temporary absent credential file and generated local shared secret; unauthenticated task-endpoint request | `/health` 200, plan credentials false, app-server false, protected endpoint true; request rejected 401. No Codex task or app-server was started. |
| red-pen-transcribe `bacceb01` (`main`) | All 11 `tests/test_*.py` executable scripts | 10 pass after installing soundfile/numpy/genanki; one pre-existing MedGemma rule failure. APKG deck tests ran rather than being skipped. |

## Existing rule failure reserved for Claude

`tests/test_medgemma.py` expects `verdict("renal vein", "renal artery")` to return `disagree`. `tools/medgemma_check.py:76` returns `agree` with score 0.5 because its existing default floor is inclusive (`score >= floor`). The other 12 checks in that script pass. No model was loaded or called. Changing the medical verdict policy or its threshold is reserved for Claude by the production-prework instructions, so the failure is recorded without changing the rule or weakening the test. This supporting-repository finding does not mean the new scaffold tests failed.

## Native baseline

The red-pen-ios `tools/preflight.sh HEAD` baseline ran 23 server/governance test files. Two subprocess tests failed under the default sandbox; both (`server/tests/claims.test.mjs`, `tests/asr/asr-bench.test.mjs`) passed with process/network permissions, leaving all 23 verified. No native Swift source changed in this pass, so no new Mac build was necessary. Previous preview run 37552836652 is now fully successful (iPhone tour, iPhone graph, iPad and publication), superseding its old pending status.

The root executor ran these checks after delegated execution stalled. No clinical judgment, source threshold change, architecture decision, remote deployment or live provider validation is claimed.
