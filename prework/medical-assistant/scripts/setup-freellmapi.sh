#!/usr/bin/env bash
set -euo pipefail
umask 077

# Prepare only. Provider credentials and Claude setup require the live dashboard.
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
freellmapi_dir="${FREELLMAPI_SOURCE_DIR:-$project_dir/vendor/freellmapi}"
for command in git node npm; do
  command -v "$command" >/dev/null || { printf 'Missing prerequisite: %s\n' "$command" >&2; exit 1; }
done
if [[ ! -d "$freellmapi_dir" ]]; then
  mkdir -p -- "$(dirname -- "$freellmapi_dir")"
  git clone https://github.com/tashfeenahmed/freellmapi.git "$freellmapi_dir"
fi
if [[ ! -f "$freellmapi_dir/package.json" || ! -f "$freellmapi_dir/.env.example" ]]; then
  printf 'Incomplete checkout at %s; no install attempted.\n' "$freellmapi_dir" >&2
  exit 1
fi
cd -- "$freellmapi_dir"
npm install
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
