# A4 tooling verification

Task A4, gpt-6.1-sol, high, completed 2026-10-07. The previously blocked tools are installed in the isolated local environment `/workspace/vendor/prework-tools`: Ruff **0.11.13** and pre-commit **4.2.0**, matching `pyproject.toml`. The hook cache uses the existing `astral-sh/ruff-pre-commit` revision **v0.11.13**. Python is **3.12.14**; Node is **v24.19.0**.

The root agent performed the authorized network installation and hook-cache initialization. Subsequent checks used the prepared cache. The environment and cache are outside the repositories and are not committed.

```bash
python -m venv /workspace/vendor/prework-tools
/workspace/vendor/prework-tools/bin/python -m pip install --no-cache-dir --retries 0 --timeout 30 'ruff==0.11.13' 'pre-commit==4.2.0'

# From the independent staging repository /workspace/medical-assistant:
PATH=/workspace/vendor/prework-tools/bin:$PATH PRE_COMMIT_HOME=/workspace/vendor/prework-tools/cache /workspace/vendor/prework-tools/bin/pre-commit install-hooks --config .pre-commit-config.yaml
```

Initial Ruff validation found 74 lint findings: 71 long lines, one import-order finding, and two assigned test lambdas. The formatter changed both Python files. Remaining long lines were split without changing string values; the two test callbacks became named functions returning the same expressions. Before/after Python syntax trees match after normalizing import order and those two callback declarations. Application behavior, configuration values, caller contracts, and application decisions were preserved.

| Check | Standalone staging | Imported native copy |
| --- | --- | --- |
| Ruff lint | PASS | PASS, scaffold directory only |
| Ruff format check | PASS, two files | PASS, two files |
| Existing pre-commit configuration | PASS, both hooks | PASS, explicit scaffold Python paths |
| `npm run check` | PASS | PASS |
| `npm test` | PASS, 25 Python and 8 Node tests | PASS, 25 Python and 8 Node tests |
| `git diff --check` | PASS | PASS |

Standalone verification and hook activation:

```bash
cd /workspace/medical-assistant
/workspace/vendor/prework-tools/bin/ruff check .
/workspace/vendor/prework-tools/bin/ruff format --check .
PATH=/workspace/vendor/prework-tools/bin:$PATH PRE_COMMIT_HOME=/workspace/vendor/prework-tools/cache /workspace/vendor/prework-tools/bin/pre-commit validate-config .pre-commit-config.yaml
PATH=/workspace/vendor/prework-tools/bin:$PATH PRE_COMMIT_HOME=/workspace/vendor/prework-tools/cache /workspace/vendor/prework-tools/bin/pre-commit run --all-files --config .pre-commit-config.yaml
PATH=/workspace/vendor/prework-tools/bin:$PATH PRE_COMMIT_HOME=/workspace/vendor/prework-tools/cache /workspace/vendor/prework-tools/bin/pre-commit install --config .pre-commit-config.yaml
npm run check
npm test
git diff --check
```

The standalone repository has its own `.git`; its hook was installed at `.git/hooks/pre-commit`. Commits in this environment use the same `PATH` and `PRE_COMMIT_HOME` so they reuse the verified tool versions and cache.

The imported copy under `red-pen-ios/prework/medical-assistant` shares the native repository's Git root. Its configuration was therefore exercised with explicit file paths. A native root hook was not installed or replaced: an unrestricted `--all-files` run there would apply scaffold rules to unrelated native Python files.

```bash
cd /workspace/git-repositories/red-pen-ios
/workspace/vendor/prework-tools/bin/ruff check prework/medical-assistant
/workspace/vendor/prework-tools/bin/ruff format --check prework/medical-assistant
PATH=/workspace/vendor/prework-tools/bin:$PATH PRE_COMMIT_HOME=/workspace/vendor/prework-tools/cache /workspace/vendor/prework-tools/bin/pre-commit run --config prework/medical-assistant/.pre-commit-config.yaml --files prework/medical-assistant/scripts/prework.py prework/medical-assistant/tests/test_prework.py
git diff --check
cd prework/medical-assistant
npm run check
npm test
```

The existing scaffold CI file remains manual-only. Its imported nested `.github/workflows/scaffold.yml` is an artifact, not an active native GitHub workflow; this task did not activate or dispatch it. Native production preflight and CI evidence are recorded separately by the delivery owner. These tooling results establish the existing scaffold's mechanical checks, not medical, design, pedagogical, or architectural approval.
