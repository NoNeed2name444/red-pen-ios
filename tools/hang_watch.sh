#!/usr/bin/env bash
# For finding what freezes the app now and then in the 3D map's UI tests (the
# screen stops changing, a query times out, the app cannot be ended), on the
# Mac that runs the simulator:
#   tools/hang_watch.sh watch <simulator udid> <dir> > /dev/null 2>&1 &
#     samples the threads of every app process the tests start, several
#     times while it lives, with its threads' states and CPU time, and the
#     simulator's SpringBoard and backboardd beside it once it has run long;
#   tools/hang_watch.sh collect <simulator udid> <dir>
#     stops the watch, then keeps the simulator's log for the app, the Mac's
#     GPU lines and any crash or hang reports.
# A frozen app shows the same stack on its main thread sample after sample.
# The design preview runs both and uploads <dir> (design-preview.yml).
set -u
mode="${1:-}" udid="${2:-}" dir="${3:-}"
if [ -z "$mode" ] || [ -z "$udid" ] || [ -z "$dir" ]; then
  echo "usage: $0 watch|collect <simulator udid> <dir>" >&2
  exit 2
fi
mkdir -p "$dir"

# a two-second sample of one process's threads; sudo, as the runner may not
# be let into the process otherwise
snap() {
  local pid="$1" name="$2"
  { echo "== $(date '+%T') $name"; ps -M -p "$pid" 2>&1; } >> "$dir/ps.txt"
  sudo -n /usr/bin/sample "$pid" 2 -mayDie -file "$dir/$name.txt" > /dev/null 2>&1 ||
    /usr/bin/sample "$pid" 2 -mayDie -file "$dir/$name.txt" > /dev/null 2>&1 || true
}

# one app process, from its launch until it ends (or the watch stops)
follow() {
  local pid="$1" start=$SECONDS at other name
  for at in 6 12 20 30 45 70 100 150 220 320 450; do
    while [ $((SECONDS - start)) -lt "$at" ]; do
      [ -e "$dir/stop" ] && return
      if ! kill -0 "$pid" 2> /dev/null; then
        echo "$(date '+%T') $pid ended after about $((SECONDS - start)) s" >> "$dir/launches.txt"
        return
      fi
      sleep 1
    done
    snap "$pid" "app-$pid-$at"
    case "$at" in
      45 | 220)
        # the kernel's view too (what each thread waits on), and the
        # simulator's own screen and app managers
        sudo -n /usr/sbin/spindump "$pid" 3 10 -file "$dir/app-$pid-$at-spindump.txt" > /dev/null 2>&1 || true
        for name in SpringBoard backboardd; do
          for other in $(pgrep -x "$name"); do snap "$other" "$name-$other-at-$pid-$at"; done
        done ;;
    esac
  done
}

case "$mode" in
  watch)
    seen=" "
    while [ ! -e "$dir/stop" ]; do
      for pid in $(pgrep -f "Devices/$udid/.*/RedPen\.app/RedPen( |$)"); do
        case "$seen" in *" $pid "*) continue ;; esac
        seen="$seen$pid "
        echo "$(date '+%T') $pid started" >> "$dir/launches.txt"
        follow "$pid" &
      done
      sleep 1
    done ;;
  collect)
    touch "$dir/stop"
    sleep 3
    # the app's own lines, and every line naming it (RunningBoard ending it,
    # the test manager launching it), over the whole run
    xcrun simctl spawn "$udid" log show --last 3h --style compact --info \
      --predicate 'process == "RedPen" OR eventMessage CONTAINS "com.cramdown.app"' \
      > "$dir/sim-log.txt" 2>&1 || true
    # the Mac's own word on its GPU (a stalled or restarted GPU shows here)
    log show --last 3h --style compact \
      --predicate 'eventMessage CONTAINS[c] "gpu" OR subsystem CONTAINS[c] "metal" OR process CONTAINS[c] "metal"' \
      2>&1 | tail -n 4000 > "$dir/host-gpu.txt" || true
    # crash and hang reports, the Mac's and the simulator's
    for reports in "$HOME/Library/Logs/DiagnosticReports" \
      "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Logs/DiagnosticReports"; do
      [ -d "$reports" ] || continue
      find "$reports" -maxdepth 2 -type f \( -name 'RedPen*' -o -name '*.hang' -o -name '*spin*' \) \
        -exec cp {} "$dir/" \; 2> /dev/null || true
    done
    ls -la "$dir" | head -n 80 ;;
  *)
    echo "usage: $0 watch|collect <simulator udid> <dir>" >&2
    exit 2 ;;
esac
