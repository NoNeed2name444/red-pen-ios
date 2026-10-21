#!/usr/bin/env bash
# The Ward preview's pictures, recordings and fit reports, for
# .github/workflows/ward-preview.yml. One simulator per call, each on a Mac
# of its own so the parts run side by side:
#
#   tools/ward_shots.sh phone  <udid> <app>        the main iPhone, into out/
#   tools/ward_shots.sh small  <udid> <app>        the same iPhone: the SE's
#                                                  size and large text, into out/
#   tools/ward_shots.sh device <udid> <app> <key>  another device, into out/devices/<key>/
#   tools/ward_shots.sh states <udid> <app>        the controls' states, into out/shots/states/
#
# phone: the recordings of the colour shift (the app's own light/dark
# switch, home stepping through its sections, the system's switch), then
# home, a study screen, New set, Settings, a sheet and each section in both
# modes.
# small: home and each section at the iPhone SE's size (375 x 647, the
# app's own frame inside this phone); and Dynamic Type at XXL (the largest
# standard size), AX1 (the first accessibility size) and AX5 (the largest).
# device: home and each section in both modes, and home at XXL and AX1
# (Pro Max, iPad).
# states: the states gallery (every Ward control at rest, held, disabled
# and chosen) in each section's hue, both modes.
#
# Home ("library") writes its fit report (HomeFit: the round card, its
# Start button, New set, the tiles, the bar at the bottom and whether any
# of home's words would break), filed under the picture's name in
# home-fit.txt (phone), home-fit-small.txt (small) or
# devices/<key>/home-fit.txt; the workflow fails on any FAULT line.
#
# Needs xcrun simctl, sips and python3 (macOS); BID may be set to skip
# reading the bundle identifier, which a dry run on Linux does with stand-in
# commands.
plan=$1; UDID=$2; APP=$3; KEY=${4:-}
BID=${BID:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")}
case "$plan" in
  phone) OUT=out; SHOTS=out/shots; LOG=out/shots.log; FIT=out/home-fit.txt ;;
  small) OUT=out; SHOTS=out/shots; LOG=out/shots-small.log; FIT=out/home-fit-small.txt ;;
  device) OUT="out/devices/$KEY"; SHOTS="$OUT"; LOG="$OUT/shots.log"; FIT="$OUT/home-fit.txt" ;;
  states) OUT=out; SHOTS=out/shots; LOG=out/shots-states.log; FIT=/dev/null ;;
  *) echo "usage: $0 phone|small|device|states <udid> <app> [key]" >&2; exit 64 ;;
esac
mkdir -p "$SHOTS"
SE=(-uiPreviewWidth 375 -uiPreviewHeight 647)
SECTIONS="anki book cases osce narrate home-ideas"

# Whether a picture is still the launch screen: flat above and below the
# logo. sips turns it into an uncompressed BMP to read.
BLANK="$OUT/.blank-$plan.py"
cat > "$BLANK" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read()
off, = struct.unpack_from("<I", d, 10)
w, h = struct.unpack_from("<ii", d, 18)
bpp, = struct.unpack_from("<H", d, 28)
step = bpp // 8; row = (w * step + 3) & ~3; up = h > 0; h = abs(h)
def spread(top, bottom):  # rows as a share of the picture, from its top
    vals = []
    for r in range(int(h * top), int(h * bottom), 7):
        y = h - 1 - r if up else r
        for x in range(w // 8, 7 * w // 8, 5):
            i = off + y * row + x * step
            vals.append(0.2126 * d[i + 2] + 0.7152 * d[i + 1] + 0.0722 * d[i])
    m = sum(vals) / len(vals)
    return (sum((v - m) ** 2 for v in vals) / len(vals)) ** 0.5
# the launch screen: one flat colour above and below its logo
print("blank" if spread(0.12, 0.38) < 3 and spread(0.7, 0.9) < 3 else "ok")
PY

# The Dynamic Type size for the next pictures, in simctl's words (empty:
# the default, large), and the name UIKit gives it.
SIZE=""
category() {
  case "$1" in
    extra-extra-large) echo UICTContentSizeCategoryXXL ;;
    extra-extra-extra-large) echo UICTContentSizeCategoryXXXL ;;
    accessibility-medium) echo UICTContentSizeCategoryAccessibilityM ;;
    accessibility-extra-extra-extra-large) echo UICTContentSizeCategoryAccessibilityXXXL ;;
    *) echo UICTContentSizeCategoryL ;;
  esac
}

prepare() {
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl status_bar "$UDID" override --time "9:41" --batteryLevel 100 --batteryState charged \
    >> "$LOG" 2>&1 || true
  # an iPad without a modem has no bars to set
  xcrun simctl status_bar "$UDID" override --cellularMode active --cellularBars 4 --wifiBars 3 \
    >> "$LOG" 2>&1 || true
  xcrun simctl install "$UDID" "$APP"
  # a first launch on a fresh simulator brings a system banner over the
  # top of the screen for a few seconds; let it come and go before
  # anything is recorded
  xcrun simctl launch "$UDID" "$BID" -uiPreviewScreen library >> "$LOG" 2>&1
  sleep 12
}

wait_push_back() {  # app data directory, picture name
  local data="$1" name="$2" check
  for check in $(seq 30); do
    if [ -n "$data" ] && grep -Fxq 'push and back: done' "$data/Documents/home-fit.txt" 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "FAULT $name: push and back did not finish; no screenshot taken" >> "$LOG"
  return 1
}

shoot() {  # appearance, screen, picture name (may hold a folder), extra launch arguments
  local look="$1" screen="$2" name="$3" try size data
  local push=()
  shift 3
  [ "$screen" = library ] && push=(-uiPreviewPushBack)
  mkdir -p "$(dirname "$SHOTS/$name.png")"
  size=${SIZE:-large}
  xcrun simctl ui "$UDID" appearance "$look"
  xcrun simctl ui "$UDID" content_size "$size" >> "$LOG" 2>&1 || echo "content size failed: $size" >> "$LOG"
  for try in 1 2 3; do
    xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
    if [ "$screen" = library ]; then
      data=$(xcrun simctl get_app_container "$UDID" "$BID" data 2>/dev/null) || true
      # Only this launch's completed report can release its screenshot.
      if [ -n "$data" ]; then rm -f "$data/Documents/home-fit.txt"; fi
    fi
    # the size as a launch argument too, which UIKit reads before the
    # first frame
    xcrun simctl launch "$UDID" "$BID" -uiPreviewScreen "$screen" "${push[@]}" \
      -UIPreferredContentSizeCategoryName "$(category "$size")" "$@" >> "$LOG" 2>&1 \
      || echo "launch failed: $name" >> "$LOG"
    sleep $((10 + 6 * try))
    if [ "$screen" = library ]; then wait_push_back "$data" "$name" || return 1; fi
    xcrun simctl io "$UDID" screenshot --type=png --mask=alpha "$SHOTS/$name.png" >> "$LOG" 2>&1 \
      || echo "shot failed: $name" >> "$LOG"
    pgrep -f "RedPen.app/RedPen" >/dev/null || echo "not running after: $name" >> "$LOG"
    sips -s format bmp "$SHOTS/$name.png" --out "$OUT/.shot-$plan.bmp" >/dev/null 2>&1 || break
    [ "$(python3 "$BLANK" "$OUT/.shot-$plan.bmp")" = ok ] && break
    echo "still the launch screen, try $try: $name" >> "$LOG"
    # a slow first frame (AX5 on the SE's size takes about half a minute on a
    # busy Mac) is waited for where it stands: relaunching threw the nearly
    # ready app away and began the same slow launch again, three times over,
    # so no screen and no fit report ever came
    for _ in $(seq 8); do
      sleep 5
      xcrun simctl io "$UDID" screenshot --type=png --mask=alpha "$SHOTS/$name.png" >> "$LOG" 2>&1 || true
      sips -s format bmp "$SHOTS/$name.png" --out "$OUT/.shot-$plan.bmp" >/dev/null 2>&1 || break 2
      [ "$(python3 "$BLANK" "$OUT/.shot-$plan.bmp")" = ok ] && break 2
    done
  done
}

wait_up() {  # file
  local check
  for check in $(seq 10); do
    xcrun simctl io "$UDID" screenshot --type=png --mask=alpha "$OUT/.wait-$plan.png" >> "$LOG" 2>&1
    sips -s format bmp "$OUT/.wait-$plan.png" --out "$OUT/.wait-$plan.bmp" >/dev/null 2>&1
    if [ "$(python3 "$BLANK" "$OUT/.wait-$plan.bmp")" = ok ]; then
      rm -f "$OUT/.wait-$plan.png" "$OUT/.wait-$plan.bmp"
      return 0
    fi
    echo "still the launch screen before recording, check $check: $1" >> "$LOG"
    sleep 3
  done
  echo "FAULT $1: the app's screen never came up; recorded anyway" >> "$LOG"
  rm -f "$OUT/.wait-$plan.png" "$OUT/.wait-$plan.bmp"
  return 0
}

fit() {  # the name the report is filed under: home's fit, as the app wrote it
  local data
  data=$(xcrun simctl get_app_container "$UDID" "$BID" data 2>/dev/null) || true
  # the app writes its report 6 s after the screen is up (HomeFitProbe)
  for _ in $(seq 8); do
    [ -f "$data/Documents/home-fit.txt" ] && break
    sleep 2
  done
  {
    echo "== $1"
    cat "$data/Documents/home-fit.txt" 2>/dev/null || echo "FAULT no fit report was written"
  } >> "$FIT"
  if [ -n "$data" ]; then rm -f "$data/Documents/home-fit.txt"; fi
}

# Stops a recordVideo started in the background. simctl can hang while it
# finishes the file (ward-r15's phone job waited 80 minutes on one), so it
# gets 20 s, then is killed and the gap is logged; the frames check then
# reports the missing or short video instead of the job timing out.
stop_rec() {  # pid, file
  kill -INT "$1" 2>/dev/null || true
  for _ in $(seq 40); do
    if ! kill -0 "$1" 2>/dev/null; then wait "$1" || true; return 0; fi
    sleep 0.5
  done
  echo "FAULT recording $2 did not stop in 20 s; killed" >> "$LOG"
  kill -KILL "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

record() {  # screen, file, seconds to wait, seconds to record
  xcrun simctl ui "$UDID" appearance light
  xcrun simctl ui "$UDID" content_size large >> "$LOG" 2>&1 || true
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BID" -uiPreviewScreen "$1" >> "$LOG" 2>&1
  sleep "$3"
  wait_up "$2"
  xcrun simctl io "$UDID" recordVideo --codec=h264 --mask=black "$OUT/$2" &
  local rec=$!
  sleep "$4"
  stop_rec $rec "$2"
  # the pictures after a switch start from the device's own mode: the
  # app turns Always night sky off on any other preview screen
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
}

system_switch() {  # home while the system turns dark and back
  xcrun simctl ui "$UDID" appearance light
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BID" -uiPreviewScreen library >> "$LOG" 2>&1
  sleep 9
  wait_up mode-switch.mp4
  xcrun simctl io "$UDID" recordVideo --codec=h264 --mask=black "$OUT/mode-switch.mp4" &
  local rec=$!
  sleep 3
  for look in dark light dark light; do
    xcrun simctl ui "$UDID" appearance "$look"
    sleep 2.5
  done
  stop_rec $rec mode-switch.mp4
}

crashes() {
  for report in ~/Library/Logs/DiagnosticReports/RedPen*.ips; do
    [ -f "$report" ] && cp "$report" "$OUT/" && echo "crash report: $(basename "$report")" >> "$LOG"
  done
}

prepare
if [ "$plan" = phone ]; then
  # the app's own switch first (Always night sky turning the window dark
  # and back every 2.5 s), then home stepping along its dock
  record mode-switch mode-switch-app.mp4 6 11
  record mode-switch-quiz mode-switch-quiz.mp4 6 11
  record section-switch section-switch.mp4 5 13
  for look in light dark; do
    for screen in library quiz quiz-checked new settings sheet; do
      shoot "$look" "$screen" "$screen-$look"
      if [ "$screen" = library ]; then fit "library-$look"; fi
    done
    # each section in its hue: Cards, Textbook, Cases, OSCE, Audio and
    # Ideas (Questions is the quiz above)
    for screen in $SECTIONS; do
      shoot "$look" "$screen" "section-$screen-$look"
    done
  done
  system_switch
elif [ "$plan" = states ]; then
  for look in light dark; do
    for section in questions cards textbook cases osce audio ideas; do
      shoot "$look" states "states/$section-$look" -uiPreviewSection "$section"
    done
  done
elif [ "$plan" = small ]; then
  for look in light dark; do
    # the iPhone SE: 375 points wide, 647 under its status bar
    shoot "$look" library "library-se-$look" "${SE[@]}"
    fit "library-se-$look"
    for screen in $SECTIONS; do
      shoot "$look" "$screen" "se/section-$screen-$look" "${SE[@]}"
    done
    shoot "$look" quiz "se/quiz-$look" "${SE[@]}"
  done
  # Dynamic Type: home and every section at XXL, home at the SE's size
  # too, and home and a study screen at AX1
  SIZE=extra-extra-large
  for screen in library quiz $SECTIONS; do
    shoot light "$screen" "type/xxl-$screen-light"
    if [ "$screen" = library ]; then fit "xxl-library-light"; fi
  done
  shoot dark library "type/xxl-library-dark"
  fit "xxl-library-dark"
  shoot light library "type/xxl-library-se-light" "${SE[@]}"
  fit "xxl-library-se-light"
  SIZE=accessibility-medium
  shoot light library "type/ax1-library-light"
  fit "ax1-library-light"
  shoot dark library "type/ax1-library-dark"
  fit "ax1-library-dark"
  shoot light quiz "type/ax1-quiz-light"
  # AX5, the largest: home (on the SE's frame too), the sections list and
  # New set, where words broke and a row ran off the sheet (15 Oct)
  SIZE=accessibility-extra-extra-extra-large
  shoot light library "type/ax5-library-light"
  fit "ax5-library-light"
  shoot light library "type/ax5-library-se-light" "${SE[@]}"
  fit "ax5-library-se-light"
  shoot light sections "type/ax5-sections-light"
  shoot light new "type/ax5-new-light"
  SIZE=""
  xcrun simctl ui "$UDID" content_size large >> "$LOG" 2>&1 || true
else
  for look in light dark; do
    shoot "$look" library "library-$look"
    fit "$KEY library-$look"
    for screen in quiz $SECTIONS; do
      shoot "$look" "$screen" "section-$screen-$look"
    done
  done
  SIZE=extra-extra-large
  for look in light dark; do
    shoot "$look" library "xxl-library-$look"
    fit "$KEY xxl-library-$look"
  done
  SIZE=accessibility-medium
  shoot light library "ax1-library-light"
  fit "$KEY ax1-library-light"
  SIZE=""
  xcrun simctl ui "$UDID" content_size large >> "$LOG" 2>&1 || true
  xcrun simctl shutdown "$UDID" >> "$LOG" 2>&1 || true
fi
crashes
rm -f "$BLANK" "$OUT/.shot-$plan.bmp"
exit 0
