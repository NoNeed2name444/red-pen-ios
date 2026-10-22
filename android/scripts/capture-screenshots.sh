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
adb shell am instrument -w -r com.stethoscore.app.test/androidx.test.runner.AndroidJUnitRunner | tee test-results/instrumentation.txt
grep -q 'OK (9 tests)' test-results/instrumentation.txt
adb pull /sdcard/Download/stethoscore-screenshots/. screenshots/
test "$(find screenshots -name '*.png' | wc -l)" -eq 12
