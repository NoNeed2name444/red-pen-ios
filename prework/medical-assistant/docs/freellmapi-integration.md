# A1: FreeLLMAPI integration

Status: **partial: source and dependencies installed; provider credentials and Claude setup remain pending**. The retry obtained the requested repository and built/verified its CLI. Runtime validation is recorded below. No orchestrator was started.

## Retry on 2026-10-06

The root executor cloned the requested public repository into `/workspace/vendor/freellmapi` at `a6b2158c7c36ce19f888d0411846a1a0f2aa3f06`, then ran `npm install --cache /tmp/freellmapi-npm-cache` with sandboxed network permission: exit 0, 839 packages added. The assigned integration worker remained `gpt-6.1-sol` / medium. Child network permission acquisition stalled and was cancelled; the successful root operation supersedes the earlier proxy acquisition blocker.

The checkout README, root/CLI packages, complete environment template and authentication/configuration source were inspected. A new upstream `.env` was generated with a random local encryption key, `HOST=127.0.0.1`, and `PORT=3001`; it has mode 0600 and is ignored by upstream Git. The encryption key is not a provider credential or unified API key; no value is logged or committed.

| Retry verification | Result |
| --- | --- |
| `npm run build -w cli` | Exit 0; CLI 0.7.0 built. |
| `node cli/dist/index.js --help`, `node --check cli/dist/index.js` | Exit 0; requested commands exist. |
| `npm run test -w cli` | Exit 0; 6 files, 156 tests passed with mocked catalog/transport. |
| `npm run dev` in default child sandbox | Exit 1 before HTTP startup: tsx IPC `listen EPERM` at `/tmp/tsx-1000/17710.pipe`. The root executor subsequently started the same command with sandboxed network permission: startup log confirms API loopback 3001 and Vite loopback 5173; HTTP verification is recorded in the next row. |
| Root permitted-runtime `npm run dev` and `GET /api/auth/status` | API 3001 and Vite 5173 startup confirmed; HTTP 200; dashboard setup required, unauthenticated. Root exec session 13213 was running at verification. |
| `bash -n scripts/setup-freellmapi.sh` | Exit 0. |

Earlier builtin bootstrap/hook probes were interrupted after stalling; the full upstream suite is not claimed. No provider inference, provider account registration, or Claude process was invoked.

`setup-claude` reads its models from the live gateway and writes below `os.homedir()/.claude`; this inspected version has no project-local output option, and `CLAUDE_CONFIG_DIR` does not redirect setup writes. An override of `HOME` was not used. Provider credentials are absent, no authenticated dashboard account was established and the gateway-generated unified credential was not retrieved, and `claude` is unavailable. Consequently the requested `setup-claude` and `launch` remain blocked; no global configuration was changed.

## Earlier acquisition evidence from 2026-10-06

| Command or inspection | Result |
| --- | --- |
| `timeout 20 git clone https://github.com/tashfeenahmed/freellmapi.git /workspace/medical-assistant/vendor/freellmapi` | Exit 128: `Failed to connect to proxy port 8080 ... Could not connect to server`. No checkout obtained. |
| `curl --connect-timeout 3 --max-time 6 -I https://registry.npmjs.org/freellmapi` | Exit 7: same unreachable inherited proxy. Registry/package availability remains unverified. |
| `curl --connect-timeout 3 --max-time 6 -I http://localhost:3001` | Exit 7: no listener. |
| `node --version`, `npm --version`, `git --version` | v24.19.0, 11.9.0, 2.52.0. Node/npm satisfy inspected upstream engine ranges. |
| `command -v claude` | No executable found. |
| Cloud environment status | Current observations; network policy unrestricted/enforced. No configured secrets, runtime variables, or outbound identities. No Gemini/Groq/OpenRouter/Cerebras keys available through this runtime configuration. |
| GitHub connector reads | Succeeded for public metadata, README, root package, `.env.example`, installation guide, CLI package and README. Connector access does not restore shell Git/npm access. |

In the earlier attempt, `npm install`, `cp .env.example .env`, `npm run dev`, `npx freellmapi setup-claude`, and `npx freellmapi launch` were not run because their prerequisites were absent. Running installation in the empty project directory would not install the requested repository. No keys were invented or printed.

Relevant upstream excerpts and URLs are retained in [freellmapi-source-evidence.json](freellmapi-source-evidence.json). The observed `main` head was `a6b2158c7c36ce19f888d0411846a1a0f2aa3f06`; source files were read from mutable `main`. The earlier connector inspection established the workspace `dev` script, API port 3001, dashboard provider entry, and documented CLI commands. The local retry above separately validates installation, CLI tests, and API availability.

## Resume provider and Claude setup

To reuse the verified checkout, run `FREELLMAPI_SOURCE_DIR=/workspace/vendor/freellmapi bash scripts/setup-freellmapi.sh` from this project. The script clones the requested repository into `vendor/freellmapi`, runs `npm install`, copies `.env.example` only if `.env` is absent, replaces its example encryption placeholder with a locally generated encryption key, and binds the server to loopback. This encryption key is for local storage, not a fabricated provider or unified API key. An existing `.env` is preserved and must be checked locally for valid configuration. The script is syntax checked; the retry validated repository installation separately at `/workspace/vendor/freellmapi`. Set `FREELLMAPI_SOURCE_DIR=/workspace/vendor/freellmapi` to reuse that checkout.

Start the gateway in a separate terminal:

```bash
cd /workspace/vendor/freellmapi
npm run dev
```

Open `http://localhost:3001`, complete the first dashboard account setup, and add the available real Gemini (Google), Groq, OpenRouter, and Cerebras provider keys on the Keys page. Do not assume environment variables import provider keys: upstream documents dashboard storage or declarative startup configuration. Retrieve the gateway's unified API key from the Keys page header.

Verify the dashboard responds with `curl --fail http://localhost:3001`. With the real unified key supplied through `FREELLMAPI_API_KEY`, verify `GET /v1/models` and a small inference request using the upstream API reference before claiming the provider pool works. A responding dashboard alone does not establish inference readiness.

When the gateway is verified, the unified key is available, Claude Code is installed, and the task permits proceeding:

```bash
export FREELLMAPI_URL=http://localhost:3001
# Supply FREELLMAPI_API_KEY securely from the dashboard; do not commit it.
npx freellmapi setup-claude --url http://localhost:3001
npx freellmapi launch
```

The requested `--api-key <unified-key>` flag is documented upstream; the environment variable shown above is also documented and avoids placing the credential in the command line. `setup-claude` changes Claude's configuration; `launch` starts Claude Code. These remain pending and were deliberately not executed in this blocked A1 run.
