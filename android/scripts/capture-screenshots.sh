#!/usr/bin/env bash
set -euo pipefail
mkdir -p screenshots test-results
trap 'adb logcat -d > test-results/logcat.txt 2>&1 || true' EXIT
sdkmanager --version | tee test-results/sdkmanager-version.txt
grep -h "^target=" "$ANDROID_AVD_HOME/test.ini" | tee test-results/avd-target.txt
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
# What the run must show, read from the test itself: one result per @Test, one picture per shot("...") name.
test_source=app/src/androidTest/java/com/stethoscore/app/ScreenshotTest.kt
tests=$(grep -c '@Test' "$test_source")
shots=$(grep -o 'shot("[^"]*")' "$test_source" | sort -u | wc -l)
echo "expecting OK ($tests tests) and $shots pictures" | tee test-results/expected.txt
[ "$tests" -gt 0 ] && [ "$shots" -gt 0 ]
adb shell am instrument -w -r -e notClass com.stethoscore.app.TourTest com.stethoscore.app.test/androidx.test.runner.AndroidJUnitRunner | tee test-results/instrumentation.txt
# Pull first, so a failed run still uploads the pictures it took.
adb pull /sdcard/Download/stethoscore-screenshots/. screenshots/ || true
grep -qF "OK ($tests tests)" test-results/instrumentation.txt
test "$(find screenshots -name '*.png' | wc -l)" -eq "$shots"
