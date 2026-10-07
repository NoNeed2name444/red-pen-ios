#!/usr/bin/env bash
# Before a push: everything that can be checked here, in seconds, so CI only
# confirms. Run from anywhere in the repository:
#   tools/preflight.sh            against origin/personal
#   tools/preflight.sh <ref>      against another base
# Checks: the Swift suites whose files changed (Linux; the Apple-only few are
# left to macOS CI), every server and governance test, and that the Swift
# Playgrounds core packages still assemble and keep no file that names a type
# they drop.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
base="${1:-origin/personal}"
export PATH="/opt/swift/usr/bin:$PATH"
fail=0
echo "== Swift suites touched since $base"
if command -v swiftc >/dev/null; then
  python3 tools/swift_suites.py --affected "$base" --platform linux -j 8 | tail -n 25 || fail=1
else
  echo "no Swift toolchain here (install: see tools/README or skip); CI will run them"
fi
echo "== Server and governance tests"
n=0; for t in server/tests/*.test.mjs tests/*/*.test.mjs; do
  [ -f "$t" ] || continue
  if ! node "$t" > /tmp/preflight-node.log 2>&1; then echo "FAIL $t"; grep -E "^FAIL|Error" /tmp/preflight-node.log | head -5; fail=1; fi
  n=$((n+1))
done; echo "$n files run"
echo "== Playgrounds core packages"
if git diff --name-only "$base" -- ios tools | grep -q .; then
  for v in core core1 core2 core3; do
    out=$(python3 tools/make_swiftpm.py ios/RedPen "Stethoscore Personal" com.cramdown.personal "/tmp/preflight-$v.zip" --without "$v" 2>&1) \
      && echo "$v: $(echo "$out" | head -1)" || { echo "$v: FAILED"; echo "$out" | tail -5; fail=1; }
  done
else echo "nothing under ios/ or tools/ changed"; fi
[ $fail = 0 ] && echo "PREFLIGHT OK" || echo "PREFLIGHT FAILED"
exit $fail
