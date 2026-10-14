#!/usr/bin/env bash
set -euo pipefail
mkdir -p screenshots test-results
trap 'adb logcat -d > test-results/logcat.txt 2>&1 || true' EXIT
adb wait-for-device
for attempt in $(seq 1 60); do
  if adb shell pm path android | grep -q 'package:'; then break; fi
  sleep 2
done
adb shell pm path android | grep -q 'package:'
adb shell getprop ro.build.version.release | tee test-results/android-release.txt
adb shell getprop ro.build.version.sdk | tee test-results/android-sdk.txt
grep -qx '37' test-results/android-sdk.txt
adb shell settings put system font_scale 1.0
adb shell input keyevent 82
adb install -r -t built-apks/outputs/apk/debug/app-debug.apk
adb install -r -t built-apks/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w -r com.stethoscore.app.test/androidx.test.runner.AndroidJUnitRunner | tee test-results/instrumentation.txt
grep -q 'OK (8 tests)' test-results/instrumentation.txt
adb pull /sdcard/Download/stethoscore-screenshots/. screenshots/
test "$(find screenshots -name '*.png' | wc -l)" -eq 10
