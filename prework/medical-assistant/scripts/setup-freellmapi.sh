#!/usr/bin/env bash
set -euo pipefail
umask 077

# Prepare pinned source only. No provider calls or global Claude configuration writes.
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
freellmapi_dir="${FREELLMAPI_SOURCE_DIR:-$project_dir/vendor/freellmapi}"
readonly source_ref="a6b2158c7c36ce19f888d0411846a1a0f2aa3f06"
readonly source_url="https://github.com/tashfeenahmed/freellmapi.git"
setup_timeout="${SETUP_TIMEOUT_SECONDS:-180}"
[[ "$setup_timeout" =~ ^[1-9][0-9]*$ ]] || { printf 'SETUP_TIMEOUT_SECONDS must be a positive integer.\n' >&2; exit 2; }
for command in git node npm timeout; do
  command -v "$command" >/dev/null || { printf 'Missing prerequisite: %s\n' "$command" >&2; exit 1; }
done
if [[ ! -d "$freellmapi_dir" ]]; then
  mkdir -p -- "$(dirname -- "$freellmapi_dir")"
  timeout "$setup_timeout" git clone --no-checkout "$source_url" "$freellmapi_dir"
  git -C "$freellmapi_dir" checkout --detach "$source_ref"
fi
if [[ ! -d "$freellmapi_dir/.git" ]] ||
   [[ "$(git -C "$freellmapi_dir" remote get-url origin)" != "$source_url" ]] ||
   [[ "$(git -C "$freellmapi_dir" rev-parse HEAD)" != "$source_ref" ]] ||
   ! git -C "$freellmapi_dir" diff --quiet HEAD --; then
  printf 'Checkout identity/content differs from the verified source pin; preserve it and select another FREELLMAPI_SOURCE_DIR.\n' >&2
  exit 1
fi
if [[ ! -f "$freellmapi_dir/package.json" || ! -f "$freellmapi_dir/package-lock.json" || ! -f "$freellmapi_dir/.env.example" ]]; then
  printf 'Incomplete checkout at %s; no install attempted.\n' "$freellmapi_dir" >&2
  exit 1
fi
cd -- "$freellmapi_dir"
timeout "$setup_timeout" npm ci --cache "$freellmapi_dir/.cache/npm" --fetch-retries=0 --fetch-timeout=30000
if [[ ! -e .env ]]; then
  cp .env.example .env
  node --input-type=module <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
const content = readFileSync('.env', 'utf8');
const updated = content.replace(/^ENCRYPTION_KEY=.*$/m, `ENCRYPTION_KEY=${randomBytes(32).toString('hex')}`)
  .replace(/^# HOST=::$/m, 'HOST=127.0.0.1');
writeFileSync('.env', updated, { mode: 0o600 });
NODE
fi
printf 'Prepared %s. Existing .env was preserved. Run npm run dev there, then complete dashboard setup.\n' "$freellmapi_dir"
