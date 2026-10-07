# Local provider integration completion

The user selected **Complete without live provider calls** on 2026-10-07. A1/A2 preparation covers pinned installation scripts and local service/plugin checks. Actual Gemini, Groq, OpenRouter and Cerebras credentials, remote model probes, inference, and Claude setup/launch are deferred by the chosen scope. No provider credential is fabricated; local encryption keys are storage keys only.

## Reproducible preparation

From `prework/medical-assistant`:

```bash
FREELLMAPI_SOURCE_DIR=/workspace/vendor/freellmapi \
  SETUP_TIMEOUT_SECONDS=180 bash scripts/setup-freellmapi.sh
DEEPSEEK_HARNESS_DIR=/workspace/vendor/deepseek-harness \
  SETUP_TIMEOUT_SECONDS=180 bash scripts/setup-deepseek-harness.sh
```

FreeLLMAPI uses immutable Git commit `a6b2158c7c36ce19f888d0411846a1a0f2aa3f06` and lockfile `npm ci`. Existing checkouts with another origin or HEAD are refused; existing `.env` is preserved. DSH uses `@deepseek-ai/dsh@0.2.0-rc.2`, `dsh-freeroute@0.8.23`, and checks installed repository/version metadata. DSH_HOME and PNPM_HOME stay inside the chosen vendor directory; system HOME and Claude configuration remain untouched. Each network step is bounded by SETUP_TIMEOUT_SECONDS; an invalid bound exits 2.

## Evidence

- Current environment status inspected 2026-10-07: observations current, unrestricted HTTP policy enforced; no configured secrets, runtime variables or outbound identities.
- Both preparation scripts: `bash -n` exit 0. Both reject `SETUP_TIMEOUT_SECONDS=invalid` with exit 2 before any acquisition.
- Existing source-evidence JSON files retain the previous exact installations, CLI tests and HTTP checks, including FreeLLMAPI auth-status HTTP 200 and authenticated DSH plugin health/models HTTP 200. These are historical results from the preceding session.
- Fresh worker initially has no `/workspace/vendor` checkout and no installed `claude` command. A network-permission tool request stalled before producing shell output and was aborted; it does not establish a failed download. The successful fresh root results below supersede that initial absence.

## Deferred work

The preceding session did not confirm Settings → Models or Free panel visibility; the fresh check below resolves that browser gap. Provider configuration and inference are intentionally deferred, so no live-provider or saved-credential success is claimed. A future enabled session must provide real credentials through supported tools and verify each provider before claiming readiness for production traffic.

## Fresh root verification, 2026-10-07

Both bounded scripts completed successfully: FreeLLMAPI installed 839 packages from its pinned Git/lockfile, and DSH installed 540 packages plus the pinned freeroute plugin. CLI build succeeded and all 156 FreeLLMAPI CLI unit tests passed (six files, mocked external integrations).

Fresh FreeLLMAPI `/api/auth/status` returned HTTP 200 with `needsSetup: true`, `authenticated: false`; the Vite dashboard at `http://localhost:5173` returned HTTP 200. The service's generated local encryption key and any local authentication URL are omitted from artifacts.

The owned DSH local authentication URL returned HTTP 200; cookie-authenticated `/freeroute/health` and `/freeroute/v1/models` both returned HTTP 200. These are local plugin checks, not remote model probes. Provider configuration, inference, and Claude setup/launch remain deferred as stated above.

Fresh Chromium verification reached Settings → Models → Free after acknowledging the local preview notice. The panel displayed freeroute 0.8.23, zero requests and zero model entries; its providers show “Key needed.” Automatic default workspace creation failed under the restricted home directory, so a writable workspace must be selected before starting sessions. No session was started. The Settings/Models visibility blocker is resolved; live setup remains deferred.
