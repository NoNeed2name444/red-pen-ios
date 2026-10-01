#!/usr/bin/env bash
# Builds parity.swift with the accuracy suite's sources and runs it on a
# cases.json written by sensors.mjs.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cases="${1:?cases.json}"
out="${2:-$root/build/parity}"
mkdir -p "$out"
files=$(python3 - "$root" <<'PY'
import sys, re
root = sys.argv[1]
text = open(f"{root}/tools/swift_suites.txt").read().replace("\\\n", " ")
for line in text.splitlines():
    parts = line.split()
    if len(parts) > 2 and parts[0] == "suite" and parts[1] == "accuracy":
        subs = {"$S": "ios/RedPen/Shared", "$M": "ios/RedPen/Models", "$F": "ios/RedPen/Features"}
        srcs = []
        for p in parts[3:]:
            for k, v in subs.items():
                p = p.replace(k, v)
            srcs.append(f"{root}/{p}")
        print(" ".join(srcs))
PY
)
# top-level code compiles only from a file named main.swift
cp "$root/tools/verification-bench/parity.swift" "$out/main.swift"
swiftc -O -module-name Parity -o "$out/parity" "$out/main.swift" $files 2>&1 | grep -E "error" || true
"$out/parity" "$cases"
