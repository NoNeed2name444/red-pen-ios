#!/usr/bin/env bash
set -euo pipefail
umask 077

# Prepare the verified CLI and web plugin. No credentials, model tasks, or probes.
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
harness_dir="${DEEPSEEK_HARNESS_DIR:-$project_dir/vendor/deepseek-harness}"
for command in node npm pnpm; do
  command -v "$command" >/dev/null || { printf 'Missing prerequisite: %s\n' "$command" >&2; exit 1; }
done
mkdir -p -- "$harness_dir"
npm install --save-exact --prefix "$harness_dir" --cache "$harness_dir/.cache/npm" '@deepseek-ai/dsh@0.2.0-rc.2'
node --input-type=module - "$harness_dir" <<'JS'
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const root=process.argv[2];
const pkg=JSON.parse(readFileSync(join(root,'node_modules/@deepseek-ai/dsh/package.json'),'utf8'));
if(pkg.name!=='@deepseek-ai/dsh'||pkg.version!=='0.2.0-rc.2'||pkg.repository?.url!=='git+https://github.com/deepseek-ai/deepseek-harness.git') {
 throw new Error('Installed Harness identity does not match the inspected package.');
}
JS
harness_cli="$harness_dir/node_modules/@deepseek-ai/dsh/lib/bin.js"
# DSH_HOME and PNPM_HOME are documented tool-specific directories; HOME is preserved.
DSH_HOME="$harness_dir/state" PNPM_HOME="$harness_dir/.cache/pnpm-home" \
  node "$harness_cli" plugin --profile web add 'dsh-freeroute@0.8.23' \
  --store-dir "$harness_dir/.cache/pnpm-store"
node --input-type=module - "$harness_dir" <<'JS'
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const root=process.argv[2];
const pkg=JSON.parse(readFileSync(join(root,'state/profiles/web/node_modules/dsh-freeroute/package.json'),'utf8'));
if(pkg.name!=='dsh-freeroute'||pkg.version!=='0.8.23'||pkg.repository?.url!=='git+https://github.com/dushaobindoudou/dsh-freeroute.git') {
 throw new Error('Installed freeroute identity does not match the inspected package.');
}
JS
printf 'Prepared %s. Provider keys remain to be configured through Settings → Models.\n' "$harness_dir"
printf 'Launch the installed CLI with DSH_HOME=%q and web --host 127.0.0.1 --port 3080 --no-open.\n' "$harness_dir/state"
