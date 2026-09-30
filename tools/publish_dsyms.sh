#!/bin/bash
# The app's debug symbols (dSYM), kept so crash reports can be read.
#
# MetricKit's call stacks are addresses: binary UUID + offset. Turning them
# into function names and lines needs the dSYM of that exact build, which only
# exists on the Mac that built it. This uploads the app's dSYM to the "dsyms"
# release as <UUID>.zip; .github/workflows/diagnostics-triage.yml downloads the
# ones its reports need and symbolicates them. A release asset rather than a
# branch file: dSYMs are large, and a release asset may be 2 GB.
#
# Usage (after an xcodebuild with -derivedDataPath ios/build, on macOS):
#   GH_TOKEN=... tools/publish_dsyms.sh ios/build/Build/Products
# Never fails the build: without it, crash reports simply stay as offsets.
set -u
ROOT="${1:-ios/build/Build/Products}"
OUT="${RUNNER_TEMP:-/tmp}/dsyms-out"
mkdir -p "$OUT"
found=0
while IFS= read -r dsym; do
  [ -n "$dsym" ] || continue
  # one UUID per architecture; device builds are arm64 only
  for uuid in $(dwarfdump --uuid "$dsym" 2>/dev/null | awk '/UUID:/ {print $2}'); do
    (cd "$(dirname "$dsym")" && zip -qry "$OUT/$uuid.zip" "$(basename "$dsym")") || continue
    found=$((found + 1))
    echo "dSYM $uuid <- $(basename "$dsym")"
  done
done < <(find "$ROOT" -maxdepth 3 -name '*.app.dSYM' -type d 2>/dev/null)
if [ "$found" = 0 ]; then echo "no app dSYM found under $ROOT (DEBUG_INFORMATION_FORMAT=dwarf-with-dsym?)"; exit 0; fi
gh release view dsyms >/dev/null 2>&1 || gh release create dsyms --prerelease --title "Debug symbols" \
  --notes "The app's dSYMs by UUID, for reading crash reports (tools/publish_dsyms.sh, diagnostics-triage.yml)." >/dev/null 2>&1 || true
gh release upload dsyms "$OUT"/*.zip --clobber || echo "upload failed: crash reports from this build stay as offsets"
exit 0
