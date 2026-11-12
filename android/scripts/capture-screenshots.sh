#!/usr/bin/env bash
# Usage: capture-screenshots.sh            the screenshot test (ScreenshotTest), as every push runs it
#        capture-screenshots.sh tour       the app tour (TourTest)
#        capture-screenshots.sh matrix K   the window matrix (T0139) for profile kind K: small, medium,
#                                          large, tablet7, tablet10, fold-shots, fold-tests or flip (WindowShots,
#                                          the turns, the folds, split and free-form sizes, RotationStateTest, and
#                                          FoldLayoutTest on the fold); ScreenshotTest is the plain run's. The fold
#                                          is two jobs: fold-shots, its nine WindowShots passes (flat, book and
#                                          tabletop, folded, three turns each), and fold-tests, FoldLayoutTest in
#                                          three turns and RotationStateTest through its states
# HANG_LIMIT_SECONDS=N sets how long one instrumentation run may take before it counts as hung (T0248): the default
# is 480 for a WindowShots pass and 300 for every other run. A hung run leaves test-results/hang-<pass>-<test>-*.txt
# and screenshots/hang-<pass>-<test>.png, is force-stopped, and fails like any other failed run.
set -euo pipefail
mkdir -p screenshots test-results
trap 'timeout -k 10 120 adb logcat -d > test-results/logcat.txt 2>&1 || true' EXIT
sdkmanager --version | tee test-results/sdkmanager-version.txt
grep -h "^target=" "${ANDROID_AVD_HOME:-$HOME/.android/avd}/test.ini" | tee test-results/avd-target.txt
grep -qx "target=android-37.0" test-results/avd-target.txt
adb wait-for-device
# the whole output first, then the test: `grep -q` at the end of a pipeline can leave adb a broken pipe, which under pipefail fails it
for attempt in $(seq 1 60); do
  package_path=$(adb shell pm path android || true)
  if [[ "$package_path" == *package:* ]]; then break; fi
  sleep 2
done
package_path=$(adb shell pm path android)
[[ "$package_path" == *package:* ]]
# Wait for the full boot, then give the launcher time to settle: on the software GPU a
# launcher still starting up raises "Pixel Launcher isn't responding" over every screen.
for attempt in $(seq 1 90); do
  if [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; then break; fi
  sleep 2
done
[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]
# Keep system crash and not-responding dialogs off the screen; the test also checks for them.
adb shell settings put global hide_error_dialogs 1
adb shell settings put secure anr_show_background 0
sleep 20
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null || true
adb shell getprop ro.build.version.release | tee test-results/android-release.txt
adb shell getprop ro.build.version.sdk | tee test-results/android-sdk.txt
grep -qx '37' test-results/android-sdk.txt
adb shell settings put system font_scale 1.0
adb shell input keyevent 82
adb install -r -t built-apks/outputs/apk/debug/app-debug.apk
adb install -r -t built-apks/outputs/apk/androidTest/debug/app-debug-androidTest.apk
runner=com.stethoscore.app.test/androidx.test.runner.AndroidJUnitRunner
# The hang guard (T0248). Every instrumentation run below goes through run_instrument, which holds it to a time limit.
# When the limit runs out it collects the evidence a stuck run leaves nowhere else (hang_evidence), force-stops the
# app and its test package, and returns 1 with instrument_hung=1: the caller fails the run the way it fails any run,
# so the step ends within minutes with the evidence in the artifact, not at the job's 40 with an empty log.
instrument_hung=0
hang_limit() { # default seconds
  if [ -z "${HANG_LIMIT_SECONDS:-}" ]; then echo "$1"
  elif [[ "$HANG_LIMIT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then echo "$HANG_LIMIT_SECONDS"
  else echo "HANG_LIMIT_SECONDS=$HANG_LIMIT_SECONDS is not a whole number of seconds; using $1" >&2; echo "$1"; fi
}
# One piece of evidence: the command's output, at most [lines] lines, into [file]. Bounded to 60 seconds; never fails.
hang_step() { # file lines command...
  local file=$1 lines=$2
  shift 2
  { timeout -k 5 60 "$@" 2>&1 | tr -d '\r' | head -n "$lines" > "$file"; } || true
}
hang_evidence() { # label
  local out="test-results/hang-$1" shot="screenshots/hang-$1.png" pids pid pkg
  mkdir -p screenshots
  # the log first, before the thread dump below adds its own lines to it
  hang_step "$out-logcat.txt" 6000 adb logcat -d -b all -t 6000
  # an ART thread dump of the app: SIGQUIT makes it write every thread's stack to logcat; keep the last dump that
  # starts at the app's command line, to its end, at most 400 lines
  pids=$(timeout -k 5 60 adb shell pidof com.stethoscore.app 2>/dev/null | tr -d '\r') || true
  if [ -n "$pids" ]; then
    # (the shell user may not signal an app's process; run-as does it as the app, which is a debug build)
    for pid in $pids; do
      timeout -k 5 60 adb shell kill -3 "$pid" > /dev/null 2>&1 || timeout -k 5 60 adb shell run-as com.stethoscore.app kill -3 "$pid" > /dev/null 2>&1 || true
    done
    sleep 3
    { timeout -k 5 60 adb logcat -d -b all -t 3000 2>&1 | tr -d '\r' | awk '
        /Cmd line: com\.stethoscore\.app/ { n = 0; on = 1 }
        on { buf[++n] = $0 }
        /----- end [0-9]+ -----/ { on = 0 }
        END { for (i = 1; i <= n && i <= 400; i++) print buf[i] }' > "$out-threads.txt"; } || true
    [ -s "$out-threads.txt" ] || echo "no thread dump of com.stethoscore.app in the last 3000 logcat lines (pid $pids)" > "$out-threads.txt"
  else
    echo "no process com.stethoscore.app (pidof printed nothing)" > "$out-threads.txt"
  fi
  hang_step "$out-activity-top.txt" 150 adb shell dumpsys activity top
  { timeout -k 5 60 adb shell dumpsys window windows 2>&1 | tr -d '\r' | grep -E 'mCurrentFocus|mFocusedApp|Window #' > "$out-windows.txt"; } || true
  hang_step "$out-meminfo.txt" 40 adb shell dumpsys meminfo com.stethoscore.app
  hang_step "$out-top.txt" 25 adb shell top -b -n 1
  { timeout -k 5 60 adb exec-out screencap -p > "$shot" || rm -f "$shot"; } || true
  [ -s "$shot" ] || rm -f "$shot"
  # stop the work on the device: the instrumentation may still be running there after its adb client was killed
  for pkg in com.stethoscore.app com.stethoscore.app.test; do
    timeout -k 5 60 adb shell am force-stop "$pkg" || true
  done
}
run_instrument() { # pass log default-limit instrument-arguments...
  local pass=$1 log=$2 limit status=(0 0) rc=0 s t0 test_name label
  limit=$(hang_limit "$3")
  shift 3
  instrument_hung=0
  t0=$SECONDS
  timeout -k 10 "$limit" adb shell am instrument -w -r "$@" | tee "$log" || status=("${PIPESTATUS[@]}")
  # timeout ends with 124 when its limit ran out, or 137 when it had to kill; 124 or 137 from adb itself is not a hang
  if { [ "${status[0]}" -eq 124 ] || [ "${status[0]}" -eq 137 ]; } && [ $((SECONDS - t0)) -ge $((limit - 1)) ]; then
    instrument_hung=1
    # the test that was running: the last one the instrumentation named (INSTRUMENTATION_STATUS: test=...)
    test_name=$(sed -n 's/^INSTRUMENTATION_STATUS: test=//p' "$log" | tr -d '\r' | tail -n 1) || true
    label=$(printf '%s-%s' "$pass" "${test_name:-no-test}" | tr -c 'A-Za-z0-9._-' '-')
    echo "HANG $pass: no result after ${limit} s, last test started: ${test_name:-none}; evidence in test-results/hang-$label-*.txt and screenshots/hang-$label.png" | tee -a test-results/hang.txt
    hang_evidence "$label"
    return 1
  fi
  # not a hang: the status the pipeline always had (the last that failed, under pipefail)
  for s in "${status[@]}"; do if [ "$s" -ne 0 ]; then rc=$s; fi; done
  return "$rc"
}
# "tour": only the app tour (TourTest), every listed row in light and dark, into screenshots/tour/.
if [ "${1:-}" = tour ]; then
  mkdir -p screenshots/tour
  tour_source=app/src/androidTest/java/com/stethoscore/app/TourTest.kt
  tests=$(grep -c '@Test' "$tour_source")
  shots=$(grep -oE 'r[0-9]{3}-[a-z0-9-]+-(light|dark)' ../tools/tour_screens_android.txt | sort -u | wc -l)
  echo "expecting OK ($tests tests) and $shots tour pictures" | tee test-results/expected.txt
  [ "$tests" -gt 0 ] && [ "$shots" -gt 0 ]
  run_instrument tour test-results/instrumentation.txt 300 -e class com.stethoscore.app.TourTest com.stethoscore.app.test/androidx.test.runner.AndroidJUnitRunner
  adb pull /sdcard/Download/stethoscore-tour/. screenshots/tour/ || true
  grep -qF "OK ($tests tests)" test-results/instrumentation.txt
  test "$(find screenshots/tour -name '*.png' | wc -l)" -eq "$shots"
  exit 0
fi
if [ "${1:-}" != matrix ]; then
# What the run must show, read from the test itself: one result per @Test, one picture per shot("...") name.
# (the ScreenshotTest class's own @Tests: WindowShots, below it in the file, is the window matrix's)
# \b keeps a call like RotDiag.snapshot("...") from counting as a picture: "snapshot(" ends in "shot("
test_source=app/src/androidTest/java/com/stethoscore/app/ScreenshotTest.kt
tests=$(awk '/^class WindowShots/{exit} /@Test/{c++} END{print c+0}' "$test_source")
shots=$(grep -o '\bshot("[^"]*")' "$test_source" | sort -u | wc -l)
echo "expecting OK ($tests tests) and $shots pictures" | tee test-results/expected.txt
[ "$tests" -gt 0 ] && [ "$shots" -gt 0 ]
run_instrument screenshot-test test-results/instrumentation.txt 300 -e class com.stethoscore.app.ScreenshotTest com.stethoscore.app.test/androidx.test.runner.AndroidJUnitRunner
# Pull first, so a failed run still uploads the pictures it took.
adb pull /sdcard/Download/stethoscore-screenshots/. screenshots/ || true
grep -qF "OK ($tests tests)" test-results/instrumentation.txt
test "$(find screenshots -name '*.png' | wc -l)" -eq "$shots"
# The home-screen widgets (WidgetShots, T0200): drawn by Glance in the app's process, light and dark,
# into the app's external files; pulled into screenshots/widgets and counted apart from the ones above.
widget_source=app/src/androidTest/java/com/stethoscore/app/WidgetShots.kt
widget_tests=$(grep -c '@Test' "$widget_source")
widget_shots=$(( $(grep -o 'shots("[^"]*"' "$widget_source" | sort -u | wc -l) * 2 ))
echo "expecting OK ($widget_tests tests) and $widget_shots widget pictures" | tee test-results/expected-widgets.txt
[ "$widget_tests" -gt 0 ] && [ "$widget_shots" -gt 0 ]
mkdir -p screenshots/widgets
run_instrument widgets test-results/instrumentation-widgets.txt 300 -e class com.stethoscore.app.WidgetShots "$runner"
adb pull /sdcard/Android/data/com.stethoscore.app/files/widgets/. screenshots/widgets/ || true
grep -qF "OK ($widget_tests tests)" test-results/instrumentation-widgets.txt
test "$(find screenshots/widgets -name '*.png' | wc -l)" -eq "$widget_shots"
exit 0
fi

# MARK: the window matrix (T0139)
kind="${2:?matrix needs a profile kind}"
# the fold's two jobs share its profile (the stills are named for it) and split its work
part=all
case "$kind" in fold-shots) kind=fold; part=shots ;; fold-tests) kind=fold; part=tests ;; esac
start=$(date +%s)
mkdir -p screenshots/window
test_source=app/src/androidTest/java/com/stethoscore/app/ScreenshotTest.kt
window_tests=$(awk '/^class WindowShots/{w=1} w && /@Test/{c++} END{print c+0}' "$test_source")
[ "$window_tests" -gt 0 ]
adb shell wm size | tee test-results/wm-size.txt
adb shell wm density | tee test-results/wm-density.txt
# Whether the screen in use stands tall in its natural way up (a phone, a flip, a fold's cover
# screen) or wide (a tablet, an open book fold): measured again for every pass, as a fold or
# unfold changes the screen, and kept per posture for the check of the turned stills at the end.
natural_tall() {
  local size
  size=$(adb shell wm size | tr -d '\r' | awk -F': ' '/Physical size/{print $2}')
  [ -n "$size" ] || { echo "no physical size from wm size" >&2; return 1; }
  [ "${size#*x}" -gt "${size%x*}" ] && echo true || echo false
}
: > test-results/natural-tall.txt
# the device states this image has, verbatim (the foldables' postures come from here)
adb shell cmd device_state print-states > test-results/device-states.txt 2>&1 || true
cat test-results/device-states.txt
# the identifier of the first device state named like $1 and not like $2 (print-states: "DeviceState{identifier=N, name='...'")
state_id() { grep -iE "$1" test-results/device-states.txt | grep -viE "${2:-^$}" | grep -oE 'identifier=[0-9]+|\b[0-9]+\b' | head -1 | grep -oE '[0-9]+' || true; }
# expected stills, added up pass by pass, against the pulled PNGs at the end
expected=0
passes=0
rotate() {
  adb shell settings put system accelerometer_rotation 0
  adb shell settings put system user_rotation "$1"
  sleep 2
}
# One line tagged ROT-DIAG (T0245): the two rotation settings, the window manager's rotation lines, the resumed
# activity, wakefulness, the displays' states, the device state and the physical size. Read it in the step's log
# (grep ROT-DIAG, with the timestamps) and in test-results/rot-diag.txt; the tests print the same fields between
# their own tests (INSTRUMENTATION_STATUS: ROT-DIAG=...). It never fails the run.
rot_diag() { # label
  local rot win act pow disp state size
  rot="user_rotation=$(adb shell settings get system user_rotation | tr -d '\r') accelerometer_rotation=$(adb shell settings get system accelerometer_rotation | tr -d '\r')" || true
  win=$(adb shell dumpsys window displays | tr -d '\r' | grep -oE '(mCurrentRotation|mRotation|mUserRotationMode|mUserRotation|mLastOrientation|mFixedToUserRotation)=[^ ,]+|cur=[0-9]+x[0-9]+ app=[0-9]+x[0-9]+' | sort -u | tr '\n' ' ' || true)
  act=$(adb shell dumpsys activity activities | tr -d '\r' | grep -E 'ResumedActivity' | sed 's/^ *//' | cut -c1-140 | head -3 | tr '\n' '|' || true)
  pow=$(adb shell dumpsys power | tr -d '\r' | grep -oE 'mWakefulness=[A-Za-z]+' | head -1 || true)
  disp=$(adb shell dumpsys display | tr -d '\r' | grep -oE '\bmState=[A-Z_]+' | sort | uniq -c | tr -s ' \n' ' ' || true)
  state=$(adb shell cmd device_state state 2>&1 | tr -d '\r' | head -3 | tr '\n' '|' || true)
  size=$(adb shell wm size | tr -d '\r' | tr '\n' ' ' || true)
  echo "ROT-DIAG $1: $rot; window: ${win:--}; resumed: ${act:--}; ${pow:--}; displays: ${disp:--}; device_state: ${state:--}; wm: ${size:--}" | tee -a test-results/rot-diag.txt
}
# After a posture change (a fold or an unfold): the device awake and the keyguard away, since closing a foldable can
# put it to sleep, and an activity started on a sleeping device is created but never resumed, so its compose tree
# never exists ("No compose hierarchies found"); then what is on show.
settle_device() { # label
  local i power
  adb shell input keyevent KEYCODE_WAKEUP || true
  adb shell wm dismiss-keyguard || true
  for i in $(seq 1 20); do
    # the whole output first, then the test: `grep -q` in this pipeline would stop at its first match and
    # leave tr and adb a broken pipe, which under pipefail makes the pipeline fail with the device awake
    power=$(adb shell dumpsys power | tr -d '\r' || true)
    if [[ "$power" == *mWakefulness=Awake* ]]; then break; fi
    sleep 1
  done
  sleep 2
  rot_diag "$1"
}
# One WindowShots run: every key screen at the posture and turn given, in [modes], and at [sizes] if any.
shots_pass() { # posture orient rotation modes sizes
  local posture=$1 orient=$2 rotation=$3 modes=$4 sizes=${5:-}
  rotate "$rotation"
  local n_modes n_sizes tall
  tall=$(natural_tall)
  echo "$posture $tall" >> test-results/natural-tall.txt
  rot_diag "$posture $orient pass start (rotation $rotation, naturalTall $tall)"
  n_modes=$(echo "$modes" | tr ',' '\n' | grep -c .)
  n_sizes=$( [ -n "$sizes" ] && echo "$sizes" | tr ',' '\n' | grep -c . || echo 1)
  expected=$((expected + window_tests * n_modes * n_sizes))
  passes=$((passes + 1))
  local pass="window-$posture-$orient${sizes:+-sized}"
  local log="test-results/$pass.txt"
  # rotation: the user_rotation value just set; each test sets it again before its activity starts (PassDisplay)
  run_instrument "$pass" "$log" 480 -e class com.stethoscore.app.WindowShots -e profile "$kind" -e posture "$posture" \
    -e orient "$orient" -e rotation "$rotation" -e modes "$modes" ${sizes:+-e sizes "$sizes"} -e naturalTall "$tall" $runner || true
  # a hung pass has its evidence and is failed; the device is not asked for more diagnostics
  if [ "$instrument_hung" = 1 ]; then return 1; fi
  rot_diag "$posture $orient pass end"
  # the verdict is this line (the run above is `|| true` so the pass-end diagnostics always print)
  grep -qF "OK ($window_tests tests)" "$log"
}
orient_passes() { # posture
  shots_pass "$1" natural 0 light
  shots_pass "$1" left 1 light
  shots_pass "$1" right 3 light
}
fold_layout_passes() {
  local tests
  tests=$(grep -c '@Test' app/src/androidTest/java/com/stethoscore/app/FoldLayoutTest.kt)
  for r in 0 1 3; do
    rotate $r
    run_instrument "fold-layout-$r" "test-results/fold-layout-$r.txt" 300 -e class com.stethoscore.app.FoldLayoutTest $runner
    grep -qF "OK ($tests tests)" "test-results/fold-layout-$r.txt"
  done
}
rotation_state() { # the device states to fold through, comma separated, or none
  local tests
  tests=$(grep -c '@Test' app/src/androidTest/java/com/stethoscore/app/RotationStateTest.kt)
  rotate 0
  rot_diag "RotationStateTest start (foldStates: ${1:-none})"
  run_instrument rotation-state test-results/rotation-state.txt 300 -e class com.stethoscore.app.RotationStateTest ${1:+-e foldStates "$1"} $runner
  grep -qF "OK ($tests tests)" test-results/rotation-state.txt
}
# Split screen at its exact window sizes (dp, an 8 dp divider), portrait splits stacked and landscape side by side.
split_sizes() { # long short
  local long=$1 short=$2 room=$(( $1 - 8 ))
  echo "${short}x$((room/3)),${short}x$((room/2)),${short}x$((room*2/3)),$((room/3))x${short},$((room/2))x${short},$((room*2/3))x${short}"
}
# A real split and a free-form window where the image allows them: what was tried and what came back.
real_windows() {
  {
    echo "# split: am start --windowing-mode 6 (multi-window), then a second app adjacent"
    adb shell am start -W --windowing-mode 6 -n com.stethoscore.app/.MainActivity 2>&1 || true
    adb shell am start -W --windowing-mode 6 --activity-launch-adjacent -a android.settings.SETTINGS 2>&1 || true
    sleep 3; adb shell screencap -p /sdcard/Download/real-split.png && echo "real-split.png taken"
    adb shell dumpsys activity activities 2>&1 | grep -iE 'windowingMode|mBounds' | head -20 || true
    echo "# free-form: enable_freeform_support, force_resizable_activities, --windowing-mode 5"
    adb shell settings put global enable_freeform_support 1
    adb shell settings put global force_resizable_activities 1
    adb shell am force-stop com.stethoscore.app
    adb shell am start -W --windowing-mode 5 -n com.stethoscore.app/.MainActivity 2>&1 || true
    sleep 3; adb shell screencap -p /sdcard/Download/real-freeform.png && echo "real-freeform.png taken"
    adb shell dumpsys activity activities 2>&1 | grep -iE 'windowingMode|mBounds' | head -20 || true
    adb shell am force-stop com.stethoscore.app
  } | tee test-results/real-windows.txt
  adb pull /sdcard/Download/real-split.png screenshots/window/ || true
  adb pull /sdcard/Download/real-freeform.png screenshots/window/ || true
}

case "$kind" in
  small|large|tablet7)
    orient_passes open
    rotation_state ;;
  medium)
    orient_passes open
    shots_pass open natural 0 dark
    # medium phone, 412 x 915 dp
    shots_pass split natural 0 light "$(split_sizes 915 412)"
    real_windows
    rotation_state ;;
  tablet10)
    orient_passes open
    # 10-inch tablet, 1280 x 800 dp
    shots_pass split natural 0 light "$(split_sizes 1280 800)"
    # free-form: a small window and one resized larger
    shots_pass free natural 0 light "480x640,1000x700"
    real_windows
    rotation_state ;;
  fold|flip)
    open=$(state_id 'OPEN' 'HALF|CLOSE')
    half=$(state_id 'HALF')
    closed=$(state_id 'CLOSE|FOLD' 'HALF|UNFOLD')
    echo "device states: open=${open:-none} half=${half:-none} closed=${closed:-none}" | tee test-results/postures.txt
    if [ "$part" != tests ]; then
      # each posture the image has, by device_state, else the emulator console's fold and unfold
      # a fold must not put the device to sleep: the key and the value below are unverified guesses at the platform's fold-lock setting, so what holds is the wake after each posture (settle_device)
      adb shell settings put secure fold_lock_behavior_setting stay_awake_on_fold_key || true
      adb shell settings put system fold_lock_behavior_setting stay_awake_on_fold_key || true
      adb shell svc power stayon true || true
      if [ -n "$open" ]; then adb shell cmd device_state state "$open"; else adb emu unfold || true; fi
      settle_device "posture flat"
      orient_passes flat
      if [ "$kind" = fold ]; then
        if [ -n "$half" ]; then
          adb shell cmd device_state state "$half"
          settle_device "posture half open"
          # half open, upright: the book; turned, the fold lies across: the tabletop
          shots_pass book natural 0 light
          shots_pass tabletop left 1 light
          shots_pass tabletop right 3 light
        else echo "no half-open state on this image: book and tabletop proved by FoldLayoutTest only" | tee -a test-results/postures.txt; fi
      fi
      if [ -n "$closed" ]; then adb shell cmd device_state state "$closed"; else adb emu fold || true; fi
      settle_device "posture folded"
      orient_passes folded
      adb shell cmd device_state state reset || adb emu unfold || true
      settle_device "posture reset"
    fi
    if [ "$part" != shots ]; then
      [ "$kind" = fold ] && fold_layout_passes
      rotation_state "$(echo "${closed:-},${open:-}" | sed 's/^,//; s/,$//')"
    fi ;;
  *) echo "unknown profile kind: $kind"; exit 2 ;;
esac
rotate 0
adb pull /sdcard/Download/stethoscore-screenshots/window/. screenshots/window/ || true
echo "expecting $expected window stills from $passes passes of $window_tests screens" | tee -a test-results/expected.txt
got=$(find screenshots/window -name 'w-*.png' | wc -l)
echo "got $got window stills in $(( ($(date +%s) - start) / 60 )) minutes" | tee -a test-results/expected.txt
test "$got" -eq "$expected"
[ "$part" = tests ] && exit 0
# every turned still is wider than tall where the screen it was taken on stands tall (and the
# other way round), by that pass's own measure (w-<profile>-<posture>-...: natural-tall.txt)
python3 - test-results/natural-tall.txt screenshots/window <<'PY'
import struct, sys, pathlib
measured = {}
bad = []
for line in pathlib.Path(sys.argv[1]).read_text().split("\n"):
    if not line.strip(): continue
    posture, tall = line.split()
    if measured.setdefault(posture, tall) != tall: bad.append(f"{posture}: measured both ways up")
for p in sorted(pathlib.Path(sys.argv[2]).glob("w-*.png")):
    w, h = struct.unpack(">II", p.read_bytes()[16:24])
    turned = "-left-" in p.name or "-right-" in p.name
    posture = p.name.split("-")[2]
    if posture not in measured: bad.append(f"{p.name}: no measure for {posture}"); continue
    if turned and (w <= h) == (measured[posture] == "true"): bad.append(f"{p.name}: {w}x{h}")
print("turned stills the wrong way round:", bad or "none")
sys.exit(1 if bad else 0)
PY
