#!/usr/bin/env bash
# Before a push: everything that can be checked here, in seconds, so CI only
# confirms. Run from anywhere in the repository:
#   tools/preflight.sh            against origin/personal
#   tools/preflight.sh <ref>      against another base
# Checks: the Swift suites whose files changed (Linux; the Apple-only few are
# left to macOS CI), that every suite lists the files defining the Ward names
# its files use as macOS or Linux builds it (tools/swift_suite_closure.py, no
# compiler), every server and governance test, and that the Swift
# Playgrounds core packages still assemble and keep no file that names a type
# they drop.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
base="${1:-origin/personal}"
export PATH="/opt/swift/usr/bin:$PATH"
fail=0
# This run's own scratch, so sessions running preflight side by side never share files.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "== Swift suites touched since $base"
if command -v swiftc >/dev/null; then
  # Kept whole, so a failing suite is named even when it falls outside the
  # last 25 lines; the status is the script's own, not the pipe's.
  python3 tools/swift_suites.py --affected "$base" --platform linux -j 8 > "$tmp/suites.log" 2>&1 || fail=1
  tail -n 25 "$tmp/suites.log"
  if grep -Ev '^PASS |^[0-9]+/[0-9]+ suites passed$|^no suites to run$' "$tmp/suites.log" > "$tmp/suites.bad"; then
    echo "-- every suite line that is not PASS:"; cat "$tmp/suites.bad"
  fi
else
  echo "no Swift toolchain here (install: see tools/README or skip); CI will run them"
fi
echo "== Ward names every suite uses and lists (the Apple-only few as macOS reads them)"
python3 tools/swift_suite_closure.py || fail=1
echo "== Server and governance tests"
n=0; for t in server/tests/*.test.mjs tests/*/*.test.mjs; do
  [ -f "$t" ] || continue
  if ! node "$t" > "$tmp/node.log" 2>&1; then echo "FAIL $t"; grep -m 5 -E "^FAIL|Error" "$tmp/node.log"; fail=1; fi
  n=$((n+1))
done; echo "$n files run"
echo "== Playgrounds core packages"
# The list is taken whole, then tested. Piped into grep -q under pipefail, git
# diff could die of SIGPIPE when grep quit early, and the step was skipped.
# No pipe in this script feeds a reader that stops early.
changed=$(git diff --name-only "$base" -- ios tools) \
  || { echo "cannot list what changed since $base; building the packages anyway"; fail=1; changed=unknown; }
if [ -n "$changed" ]; then
  for v in core core1 core2 core3; do
    out=$(python3 tools/make_swiftpm.py ios/RedPen "Stethoscore Personal" com.cramdown.personal "$tmp/$v.zip" --without "$v" 2>&1) \
      && echo "$v: ${out%%$'\n'*}" || { echo "$v: FAILED"; echo "$out" | tail -5; fail=1; continue; }
    python3 tools/playgrounds_gaps.py ios/RedPen "$tmp/swiftpm_build/Stethoscore Personal.swiftpm" \
      || { echo "$v: a kept file names a type only dropped files declare; add a stand-in (tools/playgrounds_stubs)"; fail=1; }
  done
else echo "nothing under ios/ or tools/ changed"; fi
[ $fail = 0 ] && echo "PREFLIGHT OK" || echo "PREFLIGHT FAILED"
exit $fail
