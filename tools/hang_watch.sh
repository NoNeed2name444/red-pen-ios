#!/usr/bin/env bash
# For finding what freezes the app now and then in the 3D map's UI tests (the
# screen stops changing, a query times out, the app cannot be ended), on the
# Mac that runs the simulator:
#   tools/hang_watch.sh watch <simulator udid> <dir> > /dev/null 2>&1 &
#     every 2 seconds notes each app thread's state and CPU time
#     (threads.txt: U is stuck in the kernel, T held) and any process that
#     samples or reports on others (others.txt); every 10 seconds the Mac's
#     memory, swap, load and busiest processes, and the threads of the
#     simulator's GPU host (host.txt); launches.txt has when each app process
#     came and went;
#   tools/hang_watch.sh collect <simulator udid> <dir>
#     stops the watch, then keeps the simulator's log for the app (with the
#     app's own report of where it is stuck, GraphHangReporter, category
#     "hang"), the Mac's GPU lines and any crash or hang reports.
# It only looks: sampling the app held it still, so the tests could not end
# it (plan.md step 6d). The design preview runs both and uploads <dir>
# (design-preview.yml). What it found: the app never froze (it kept drawing
# at about 50 frames a second); the Mac was out of memory while the
# simulator's first boot was still settling, and XCTest's request to end
# the app stalled for over a minute.
set -u
mode="${1:-}" udid="${2:-}" dir="${3:-}"
if [ -z "$mode" ] || [ -z "$udid" ] || [ -z "$dir" ]; then
  echo "usage: $0 watch|collect <simulator udid> <dir>" >&2
  exit 2
fi
mkdir -p "$dir"

case "$mode" in
  watch)
    seen=" " alive=" " tick=0
    while [ ! -e "$dir/stop" ]; do
      now=$(date '+%T') live=" "
      # by name only (the runner boots one simulator): matching whole
      # command lines reads every process's memory, which on a Mac short of
      # it stalled this watch for two minutes and added to the strain
      for pid in $(pgrep -x RedPen); do
        live="$live$pid "
        case "$seen" in *" $pid "*) ;; *) seen="$seen$pid "; echo "$now $pid started" >> "$dir/launches.txt" ;; esac
        { echo "== $now $pid"; ps -M -p "$pid" 2>&1 | cut -c1-100; } >> "$dir/threads.txt"
      done
      for pid in $alive; do
        case "$live" in *" $pid "*) ;; *) echo "$now $pid gone" >> "$dir/launches.txt" ;; esac
      done
      alive="$live"
      # anything sampling the app or reporting on it (XCTest may, when a
      # query times out)
      others=$(ps -A -o pid,ppid,stat,etime,ucomm |
        awk '$5 ~ /^(spindump|sample|ReportCrash|tailspin|hangtracer|osanalytics|debugserver|lldb)/')
      [ -n "$others" ] && printf '== %s\n%s\n' "$now" "$others" >> "$dir/others.txt"
      if [ $((tick % 5)) -eq 0 ]; then
        { echo "== $now"
          sysctl -n vm.swapusage vm.loadavg kern.memorystatus_vm_pressure_level
          vm_stat | awk 'NR > 1 { sub(/^ +/, ""); printf "%s; ", $0 } END { print "" }'
          ps -A -r -o pid,pcpu,rss,time,stat,ucomm | head -n 10
          ps -A -m -o pid,pcpu,rss,time,stat,ucomm | head -n 8
          for host in $(pgrep -x SimMetalHost); do ps -M -p "$host" | cut -c1-100; done
        } >> "$dir/host.txt" 2>&1
      fi
      tick=$((tick + 1))
      sleep 2
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
