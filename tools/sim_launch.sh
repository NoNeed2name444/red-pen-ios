#!/bin/bash
# Usage: sim_launch.sh <path/to/App.app> <simulator udid> <out dir> [seconds]
# Installs an app on a simulator, launches it the way a tap on its icon does
# (no test runner, no launch arguments), waits, and records whether it is
# still running, its console, the simulator's log for it, any crash report
# and a screenshot. Exit status 0 only when the app is alive at the end.
set -u
APP="$1"; UDID="$2"; OUT="$3"; WAIT="${4:-30}"
mkdir -p "$OUT"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
echo "bundle=$BUNDLE exe=$EXE" | tee "$OUT/result.txt"
plutil -convert xml1 -o "$OUT/Info.plist" "$APP/Info.plist" || true
codesign -d --entitlements - --xml "$APP" > "$OUT/entitlements.plist" 2>&1 || true

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
MARK=$(mktemp); sleep 1
if ! xcrun simctl install "$UDID" "$APP" > "$OUT/install.txt" 2>&1; then
  echo "install=FAILED" | tee -a "$OUT/result.txt"; cat "$OUT/install.txt"
fi
xcrun simctl launch --terminate-running-process \
  --stdout="$OUT/stdout.txt" --stderr="$OUT/stderr.txt" \
  "$UDID" "$BUNDLE" > "$OUT/launch.txt" 2>&1
echo "launch_status=$?" | tee -a "$OUT/result.txt"
cat "$OUT/launch.txt"
PID=$(grep -oE '[0-9]+$' "$OUT/launch.txt" | tail -1)
xcrun simctl io "$UDID" screenshot "$OUT/screen-3s.png" > /dev/null 2>&1 &
sleep 3; wait
sleep "$WAIT"
ALIVE=no
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then ALIVE=yes; fi
xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -F "UIKitApplication:$BUNDLE" > "$OUT/launchctl.txt" || true
echo "pid=$PID alive_after_${WAIT}s=$ALIVE" | tee -a "$OUT/result.txt"
xcrun simctl io "$UDID" screenshot "$OUT/screen.png" > /dev/null 2>&1 || true

xcrun simctl spawn "$UDID" log show --last 3m --style compact --info --debug \
  --predicate "process == \"$EXE\"" > "$OUT/log-process.txt" 2>&1 || true
xcrun simctl spawn "$UDID" log show --last 3m --style compact \
  --predicate "eventMessage CONTAINS \"$BUNDLE\" OR eventMessage CONTAINS \"$EXE\"" > "$OUT/log-system.txt" 2>&1 || true
mkdir -p "$OUT/crashes"
find "$HOME/Library/Logs/DiagnosticReports" -newer "$MARK" -type f \( -name '*.ips' -o -name '*.crash' \) \
  -exec cp {} "$OUT/crashes/" \; 2>/dev/null || true
ls "$OUT/crashes" | tee -a "$OUT/result.txt"

# the lines worth reading, for the step summary
python3 - "$OUT" "$EXE" <<'PY' > "$OUT/key.txt"
import json, os, re, sys
out, exe = sys.argv[1], sys.argv[2]
print(open(os.path.join(out, "result.txt")).read().strip())
for name in ("stderr.txt", "stdout.txt"):
    p = os.path.join(out, name)
    if os.path.exists(p):
        lines = open(p, errors="replace").read().splitlines()
        if lines:
            print(f"--- {name} (last 25 of {len(lines)})")
            print("\n".join(lines[-25:]))
pat = re.compile(r"fault|Fatal|fatal|exception|Exception|terminat|Terminat|crash|abort|signal|SIGABRT|SIGTRAP|EXC_|Unexpectedly|Could not|entitlement|NSInternal", re.I)
for name in ("log-process.txt", "log-system.txt"):
    p = os.path.join(out, name)
    if os.path.exists(p):
        hits = [l for l in open(p, errors="replace").read().splitlines() if pat.search(l)]
        if hits:
            print(f"--- {name}: {len(hits)} matching lines (last 30)")
            print("\n".join(l[:400] for l in hits[-30:]))
cdir = os.path.join(out, "crashes")
for f in sorted(os.listdir(cdir)):
    text = open(os.path.join(cdir, f), errors="replace").read()
    print(f"--- crash report {f}")
    try:
        head, body = text.split("\n", 1)
        j = json.loads(body)
        print("exception:", json.dumps(j.get("exception")))
        print("termination:", json.dumps(j.get("termination"))[:600])
        if j.get("asi"): print("asi:", json.dumps(j.get("asi"))[:1500])
        if j.get("lastExceptionBacktrace"):
            imgs = j.get("usedImages", [])
            print("last exception backtrace:")
            for fr in j["lastExceptionBacktrace"][:25]:
                im = imgs[fr["imageIndex"]]["name"] if fr.get("imageIndex") is not None and fr["imageIndex"] < len(imgs) else "?"
                print("  ", im, fr.get("symbol", ""), "+", fr.get("symbolLocation", ""))
        imgs = j.get("usedImages", [])
        for t in j.get("threads", []):
            if t.get("triggered"):
                print("crashed thread:", t.get("name", ""), t.get("queue", ""))
                for fr in t.get("frames", [])[:30]:
                    im = imgs[fr["imageIndex"]].get("name", "?") if fr.get("imageIndex") is not None and fr["imageIndex"] < len(imgs) else "?"
                    src = f' ({fr.get("sourceFile")}:{fr.get("sourceLine")})' if fr.get("sourceFile") else ""
                    print("  ", im, fr.get("symbol", "?"), "+", fr.get("symbolLocation", ""), src)
    except Exception as e:
        print("(not JSON:", e, ")")
        print(text[:3000])
PY
cat "$OUT/key.txt"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
[ "$ALIVE" = yes ]
