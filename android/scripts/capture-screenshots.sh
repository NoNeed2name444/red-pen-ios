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
set -euo pipefail
mkdir -p screenshots test-results
trap 'adb logcat -d > test-results/logcat.txt 2>&1 || true' EXIT
sdkmanager --version | tee test-results/sdkmanager-version.txt
grep -h "^target=" "${ANDROID_AVD_HOME:-$HOME/.android/avd}/test.ini" | tee test-results/avd-target.txt
grep -qx "target=android-37.0" test-results/avd-target.txt
adb wait-for-device
for attempt in $(seq 1 60); do
  if adb shell pm path android | grep -q 'package:'; then break; fi
  sleep 2
done
adb shell pm path android | grep -q 'package:'
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
# "tour": only the app tour (TourTest), every listed row in light and dark, into screenshots/tour/.
if [ "${1:-}" = tour ]; then
  mkdir -p screenshots/tour
  tour_source=app/src/androidTest/java/com/stethoscore/app/TourTest.kt
  tests=$(grep -c '@Test' "$tour_source")
  shots=$(grep -oE 'r[0-9]{3}-[a-z0-9-]+-(light|dark)' ../tools/tour_screens_android.txt | sort -u | wc -l)
  echo "expecting OK ($tests tests) and $shots tour pictures" | tee test-results/expected.txt
  [ "$tests" -gt 0 ] && [ "$shots" -gt 0 ]
  adb shell am instrument -w -r -e class com.stethoscore.app.TourTest com.stethoscore.app.test/androidx.test.runner.AndroidJUnitRunner | tee test-results/instrumentation.txt
  adb pull /sdcard/Download/stethoscore-tour/. screenshots/tour/ || true
  grep -qF "OK ($tests tests)" test-results/instrumentation.txt
  test "$(find screenshots/tour -name '*.png' | wc -l)" -eq "$shots"
  exit 0
fi
if [ "${1:-}" != matrix ]; then
# What the run must show, read from the test itself: one result per @Test, one picture per shot("...") name.
# (the ScreenshotTest class's own @Tests: WindowShots, below it in the file, is the window matrix's)
test_source=app/src/androidTest/java/com/stethoscore/app/ScreenshotTest.kt
tests=$(awk '/^class WindowShots/{exit} /@Test/{c++} END{print c+0}' "$test_source")
shots=$(grep -o 'shot("[^"]*")' "$test_source" | sort -u | wc -l)
echo "expecting OK ($tests tests) and $shots pictures" | tee test-results/expected.txt
[ "$tests" -gt 0 ] && [ "$shots" -gt 0 ]
adb shell am instrument -w -r -e class com.stethoscore.app.ScreenshotTest com.stethoscore.app.test/androidx.test.runner.AndroidJUnitRunner | tee test-results/instrumentation.txt
# Pull first, so a failed run still uploads the pictures it took.
adb pull /sdcard/Download/stethoscore-screenshots/. screenshots/ || true
grep -qF "OK ($tests tests)" test-results/instrumentation.txt
test "$(find screenshots -name '*.png' | wc -l)" -eq "$shots"
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
# One WindowShots run: every key screen at the posture and turn given, in [modes], and at [sizes] if any.
shots_pass() { # posture orient rotation modes sizes
  local posture=$1 orient=$2 rotation=$3 modes=$4 sizes=${5:-}
  rotate "$rotation"
  local n_modes n_sizes tall
  tall=$(natural_tall)
  echo "$posture $tall" >> test-results/natural-tall.txt
  n_modes=$(echo "$modes" | tr ',' '\n' | grep -c .)
  n_sizes=$( [ -n "$sizes" ] && echo "$sizes" | tr ',' '\n' | grep -c . || echo 1)
  expected=$((expected + window_tests * n_modes * n_sizes))
  passes=$((passes + 1))
  local log="test-results/window-$posture-$orient${sizes:+-sized}.txt"
  adb shell am instrument -w -r -e class com.stethoscore.app.WindowShots -e profile "$kind" -e posture "$posture" \
    -e orient "$orient" -e modes "$modes" ${sizes:+-e sizes "$sizes"} -e naturalTall "$tall" $runner | tee "$log"
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
    adb shell am instrument -w -r -e class com.stethoscore.app.FoldLayoutTest $runner | tee "test-results/fold-layout-$r.txt"
    grep -qF "OK ($tests tests)" "test-results/fold-layout-$r.txt"
  done
}
rotation_state() { # the device states to fold through, comma separated, or none
  local tests
  tests=$(grep -c '@Test' app/src/androidTest/java/com/stethoscore/app/RotationStateTest.kt)
  rotate 0
  adb shell am instrument -w -r -e class com.stethoscore.app.RotationStateTest ${1:+-e foldStates "$1"} $runner | tee test-results/rotation-state.txt
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
      if [ -n "$open" ]; then adb shell cmd device_state state "$open"; else adb emu unfold || true; fi
      orient_passes flat
      if [ "$kind" = fold ]; then
        if [ -n "$half" ]; then
          adb shell cmd device_state state "$half"
          # half open, upright: the book; turned, the fold lies across: the tabletop
          shots_pass book natural 0 light
          shots_pass tabletop left 1 light
          shots_pass tabletop right 3 light
        else echo "no half-open state on this image: book and tabletop proved by FoldLayoutTest only" | tee -a test-results/postures.txt; fi
      fi
      if [ -n "$closed" ]; then adb shell cmd device_state state "$closed"; else adb emu fold || true; fi
      orient_passes folded
      adb shell cmd device_state state reset || adb emu unfold || true
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
