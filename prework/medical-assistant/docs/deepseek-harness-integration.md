# A2: DeepSeek Harness integration

Status: **local integration prepared; live provider calls deferred by the user**. The requested CLI and web profile flags were verified locally. No Claude process or orchestrator was started.

Current completion-pass installs, endpoint tests and browser outcomes are in
[provider-completion.md](provider-completion.md); dated evidence below is historical.

## Retry (2026-10-06)

The root executor verified the exact requested npm package, `@deepseek-ai/dsh`, through the registry with sandboxed network permission. It resolves to version `0.2.0-rc.2`, tarball `https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-0.2.0-rc.2.tgz`, with repository `git+https://github.com/deepseek-ai/deepseek-harness.git` and source directory `apps/cli`. The package was installed into `/workspace/vendor/deepseek-harness`; its npm install completed with exit 0, 540 packages added. The installed package reports `0.2.0-rc.2` and the same upstream repository metadata. Runtime results are recorded separately below. No similarly named package was substituted. The integration author remains `gpt-6.1-sol` / medium. File hashes and non-secret local outcomes are retained in [deepseek-harness-source-evidence.json](deepseek-harness-source-evidence.json).

The earlier child network request stalled and was cancelled; acquisition was moved to the root executor. No provider credentials, model inference, or orchestrator was invoked.

| Retry check | Actual result |
| --- | --- |
| Installed CLI `--version`, `--help`, and `node --check` | Exit 0; version `0.2.0-rc.2`. |
| `web --help` | Exit 0; supports `--host`, `--port`, `--no-open`, and trusted-host options. |
| `web --dump-default-config` | Exit 0; composed 45,644-byte default tree without mounting the app. No provider credentials were present. |
| Isolated profile | `DSH_HOME=/workspace/vendor/deepseek-harness/state`; initialized 0600 profile files, `dsh-base` + `dsh-web-app`, empty external dependencies and user patch. System `HOME` was preserved. |
| Web startup | Root permitted-runtime launch printed loopback URL `http://127.0.0.1:3080`; Unauthenticated GET returned HTTP 401, confirming its authentication fence; authenticated UI verification is recorded separately. |
| Test scripts | Published npm CLI has no test/build scripts. Full upstream tests were not run. |
| Plugin support | Installed CLI genuinely supports `plugin --profile web add <package>` through pnpm; installed peer compatibility is enforced. No exemptions were created. |

[setup-deepseek-harness.sh](../scripts/setup-deepseek-harness.sh) reproduces the verified exact package installations with isolated tool directories and enforces their repository/version identity. It is syntax checked; the complete script was not rerun after the successful root operations. Set `DEEPSEEK_HARNESS_DIR=/workspace/vendor/deepseek-harness` to reuse this checkout. The script prepares the profile and leaves launch/provider entry explicit.

The verified launch command uses the installed exact npm binary, equivalent to the requested npx entry point while retaining its inspected version:

```bash
cd /workspace/red-pen-ios/prework/medical-assistant
DSH_HOME=/workspace/vendor/deepseek-harness/state \
  node /workspace/vendor/deepseek-harness/node_modules/@deepseek-ai/dsh/lib/bin.js \
  web --host 127.0.0.1 --port 3080 --no-open
```

Installed Settings → Models client code contains a provider directory backed by `llm.listProviders` / `llm.listConfigurableProviders`, a “Custom model API” card, and “Fetch available models” actions. This is source evidence, not a completed browser interaction. The baseline profile does not prove that the four requested provider cards or models are available. Real keys are absent; Settings → Models credential saving and provider inference remain blocked. The root executor verified `dsh-freeroute@0.8.23` against registry metadata and the intended maintainer repository `git+https://github.com/dushaobindoudou/dsh-freeroute.git`. Its peers are React `>=18` and `@deepseek-ai/dsh-typert-protocol >=0.1.5-rc.2`. The supported CLI install first failed with exit 254 because pnpm attempted to create its data directory outside writable roots. A bounded retry used command-scoped `PNPM_HOME=/tmp/dsh-pnpm-home` and forwarded `--store-dir /tmp/dsh-pnpm-store`, preserving system `HOME`. It installed the exact plugin and added its bundle to the isolated profile. Configuration composition passes and includes the `freeroute` entry (45,701 bytes); no compatibility exemption was added. After the root executor restarted its own web process, authenticated read-only checks verified `/freeroute/health` HTTP 200 (`ok=true`, version `0.8.23`) and `/freeroute/v1/models` HTTP 200 with exactly one `auto` model. This verifies the plugin host is mounted; it does not demonstrate a configured upstream or successful inference.

The installed plugin README warns that its optional Free panel can require a frontend rebundle. Installation alone does not establish panel visibility or `freeroute/auto` availability. Published plugin test scripts reference test/source directories omitted from the npm artifact, so those tests were not run.

## Resumed-session observation (2026-10-07)

The resumed worker initially found no listeners on ports 3001 or 3080 through its own `/proc/net/tcp` and `/proc/net/tcp6`. This did not establish that the root services had stopped: a subsequent read of the original Harness process network namespace (`/proc/22093/net/tcp`) found port 3080 listening. The root launcher retry failed with `EADDRINUSE` on loopback 3080, confirming a collision with the existing service. That failed launch produced no supported authentication URL, so the browser helper sent no request. Use the service network namespace for current health checks; avoid inferring service termination from the default worker namespace.

The root executor then stopped only the owned prior Harness process and relaunched the same pinned CLI with the isolated profile. On 2026-10-07, the new startup produced the supported private authentication URL; repeated authenticated read-only checks returned HTTP 200 for both `/freeroute/health` (version `0.8.23`, `ok=true`) and `/freeroute/v1/models` (one `auto` model). No inference was invoked.

The default worker browser attempt failed during Chromium startup with `TargetClosedError`; its crashpad socket operation returned `Operation not permitted` and the process exited with SIGTRAP before navigating. The root executor subsequently ran the browser with runtime/network permission: the initial `networkidle` attempt timed out. A single revised attempt used `domcontentloaded`, bounded body/Settings readiness, and bounded Settings navigation. It received HTTP 200 and reached the Settings-navigation stage, then failed with `TimeoutError` before confirming the Settings view. No exception message, token, credentials, or screenshot was logged. Settings → Models and the optional Free panel remain unverified in a live browser; no requested-provider visibility result is claimed. Provider credentials, model probes and inference remain pending.

## Earlier observed evidence (2026-10-06)

| Check | Result |
| --- | --- |
| `command -v dsh` | No installed executable. |
| `timeout 20 npm exec --yes --fetch-retries=0 --fetch-timeout=10000 --package=@deepseek-ai/dsh -- dsh --help` | Exit 1 before CLI execution: registry fetch for `@deepseek-ai/dsh` failed with `connect EPERM 172.31.0.93:8080`, the inherited proxy. npm also could not write its default log directory. No repeated installation retries. |
| `curl --connect-timeout 3 --max-time 6 -I http://127.0.0.1:3080` | Exit 7, no listener. |
| Current cloud runtime configuration from A1 | No configured secrets, runtime variables, or outbound identities; no real Groq/Gemini/Cerebras/OpenRouter keys available. |
| `git remote -v` | No configured remote; push destination unavailable. |
| Public source inspection | GitHub connector successfully read official Harness README/web/model guides and the freeroute maintainer README. |

In the earlier attempt, the requested `npx @deepseek-ai/dsh web` was not executed after package acquisition failed during the bounded help probe. `dsh plugin --profile web add dsh-freeroute` was not executed because no CLI was installed. The browser UI was not available to inspect. At that time, package version, installed provider catalog, saved credentials, plugin compatibility, and inference behavior were unverified. The retry supersedes package acquisition and launcher verification; provider configuration and inference remain pending.

## Source-backed resume instructions

The official [Harness README](https://github.com/deepseek-ai/deepseek-harness/blob/master/README.md) documents `npx @deepseek-ai/dsh web` and the default URL `http://127.0.0.1:3080`. The official [web guide](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/index.md) documents Settings → Models and choosing a workspace. The official [provider guide](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/providers.md) describes adding third-party providers or a custom model API, discovering models, and selecting a default. These sources were read from mutable `master`; this is documentation evidence, not a runtime result.

Use the verified isolated launch command in the retry section to reuse the installed package and preserve its profile. The upstream `npx @deepseek-ai/dsh web` command resolves the same npm CLI but does not pin this inspected version unless a version is included.

Use the URL printed by the running process. Open Settings → Models; add the available real free-tier Groq, Gemini (Google), Cerebras, and OpenRouter credentials using the installed catalog's provider cards. If a provider is absent, use the documented Custom model API flow with that provider's verified endpoint, protocol, and model IDs. Do not invent provider IDs or assume all four ship in the installed catalog. Save credentials through the UI; do not commit credential files. Add/select `/workspace/red-pen-ios/prework/medical-assistant` as the workspace without initiating an orchestrator task.

The [freeroute maintainer README](https://github.com/dushaobindoudou/dsh-freeroute/blob/main/README.md), read from mutable `main`, documents the requested installation:

```bash
dsh plugin --profile web add dsh-freeroute
```

If `dsh` is available only through npx, invoke the same subcommand through `npx @deepseek-ai/dsh plugin --profile web add dsh-freeroute`. The command is supported by the installed CLI; actual plugin installation and runtime loading are recorded in the retry section. The plugin documentation describes Settings → Models → Free, keyed upstream cards, model probes, and `freeroute/auto`. It lists OpenRouter among builtin upstreams; other requested providers must be checked against the installed/remote catalog or configured through supported custom gateways. The README also contains a note about some web-panel builds requiring frontend bundling, so panel availability must be verified after installation rather than presumed.

## Completion criteria still pending

The authenticated read-only HTTP checks above established that the web host and plugin loaded during the verified root session. Complete the live browser check and confirm Settings → Models shows the saved requested providers and selectable models with credentials redacted. Run each provider's connection/model probe and one small inference using a verified free model; record served provider/model and actual outcome without credential values. Confirm the Free panel and `freeroute/auto` selector if the installed plugin exposes them. These checks are required before marking A2 done; a listening web server alone is insufficient.

## Completion continuation (2026-10-07)

The user selected completion without live provider calls. Credential entry, provider probes, model discovery against upstream providers, and inference are deferred. The prior authenticated local plugin checks above remain historical evidence; a UI timeout does not imply plugin failure. This continuation does not claim a fresh browser success.

The exact Harness/freeroute version and repository checks remain enforced. npm and plugin installation now have `SETUP_TIMEOUT_SECONDS` bounds (default 180 seconds); npm fetch retries are disabled with a 30-second fetch timeout. Tool-specific state/cache locations preserve system `HOME`. `bash -n` passed and an invalid timeout was rejected with exit 2 before acquisition. See [provider-completion.md](provider-completion.md) for current scope and observations.
