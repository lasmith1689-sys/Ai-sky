#!/bin/bash
# Installs the Simulator build, opens every screen (relaunching with debug launch arguments),
# captures screenshots and fails if the app crashes.
#   smoke-test.sh <simulator-udid> <path/to/AiSky.app> [output-dir]
set -uo pipefail
UDID="$1"
APP="$2"
OUT="${3:-screenshots}"
mkdir -p "$OUT"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
failures=0

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE" || true
xcrun simctl location "$UDID" set 41.8781,-87.6298 || true   # Chicago

# Text recognition, to tell a rendered screen from the plain launch screen (which only shows the
# status bar). Falls back to the PNG size check if it doesn't build.
OCR_BIN="$(mktemp -d)/ocr"
if ! xcrun swiftc -O -o "$OCR_BIN" "$(dirname "$0")/ocr.swift" >/dev/null 2>&1; then
  echo "::warning title=Smoke test::Couldn't build the OCR helper; loading checks use screenshot size only"
  OCR_BIN=""
fi

# rendered <png>: true when the screenshot shows more than the status bar.
rendered() {
  [ "$(stat -f%z "$1" 2>/dev/null || echo 0)" -gt 60000 ] || return 1
  [ -z "$OCR_BIN" ] && return 0
  local lines
  lines=$("$OCR_BIN" "$1" 2>/dev/null | grep -c "%  ")
  [ "${lines:-0}" -ge 4 ]
}

alive() {
  # Read the whole list first: `| grep -q` exits early, launchctl dies of SIGPIPE, and with
  # pipefail that reads as "not running" even when the app is.
  local services
  services=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null)
  [[ "$services" == *"UIKitApplication:$BUNDLE"* ]]
}

# capture <file> <screen> <seconds to wait> [extra launch arguments...]
capture() {
  local file="$1" screen="$2" wait="$3"
  shift 3
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -AiSkyDemoLibrary -AiSkyScreen "$screen" "$@" >/dev/null
  sleep "$wait"
  if alive; then
    # A slow runner can still be showing the plain launch screen; give it more time.
    for attempt in 1 2 3 4 5 6; do
      xcrun simctl io "$UDID" screenshot --type=png "$OUT/$file.png" >/dev/null 2>&1
      rendered "$OUT/$file.png" && break
      echo "… $file still loading (attempt $attempt)"
      sleep 5
    done
    echo "captured $file"
  else
    echo "❌ Ai Sky is not running on screen '$screen'"
    failures=$((failures + 1))
  fi
}

capture 01-forecast forecast 30
capture 02-next-hour nextHour 6
capture 03-hourly hourly 5
capture 04-daily daily 5
capture 05-precipitation precipitation 5
capture 06-air-quality airQuality 5
capture 07-details details 5
capture 08-radar radar 25
capture 09-locations locations 10
capture 10-settings settings 8
capture 11-rain-history rainHistory 25
capture 12-time-machine timeMachine 20
capture 13-radar-spot radarSpot 20
capture 14-day-detail dayDetail 8
capture 15-add-location addLocation 6
capture 16-forecast-large-text forecast 10 -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityM

# Every look, on sample weather (rain starting in a few minutes) so each look's rain states show.
# -AiSkyLook shows a look without saving it.
for look in liquid obsidian instrument editorial horizon chroma; do
  capture "$look-1-forecast" forecast 12 -AiSkyDemoWeather -AiSkyLook "$look"
  capture "$look-2-daily" daily 7 -AiSkyDemoWeather -AiSkyLook "$look"
  capture "$look-3-precipitation" precipitation 7 -AiSkyDemoWeather -AiSkyLook "$look"
  capture "$look-4-details" details 7 -AiSkyDemoWeather -AiSkyLook "$look"
  capture "$look-5-day-detail" dayDetail 8 -AiSkyDemoWeather -AiSkyLook "$look"
  capture "$look-6-places" locations 8 -AiSkyDemoWeather -AiSkyLook "$look"
  capture "$look-7-settings" settings 6 -AiSkyDemoWeather -AiSkyLook "$look"
  capture "$look-8-radar" radar 15 -AiSkyDemoWeather -AiSkyLook "$look"
done
capture editorial-9-large-text forecast 10 -AiSkyDemoWeather -AiSkyLook editorial -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityM
capture chroma-9-large-text forecast 10 -AiSkyDemoWeather -AiSkyLook chroma -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityM

# Liquid on each kind of sky (-AiSkyDemoSky sets the sample's current sky): light, clear glass on
# blue skies and clear nights, a dark sheen under the cards on gray skies.
for sky in clear partlyCloudy clear-night drizzle rain fog snow cloudy-night; do
  capture "liquid-sky-$sky" forecast 9 -AiSkyDemoWeather -AiSkyLook liquid -AiSkyDemoSky "$sky"
done

if [ "$failures" -gt 0 ]; then
  find ~/Library/Logs/DiagnosticReports -name "AiSky*" -mmin -20 -print -exec head -120 {} \; 2>/dev/null
  exit 1
fi
echo "✅ Ai Sky opened every screen without crashing"

# The debug build logs whether every bundled font resolved (a wrong PostScript name silently
# falls back to the system font).
fonts=$(xcrun simctl spawn "$UDID" log show --last 60m --style compact \
  --predicate 'subsystem == "com.lasmith1689.AiSky" AND category == "Fonts"' 2>/dev/null | grep -E "Look fonts" | tail -n 1)
if [[ "$fonts" == *"missing"* ]]; then
  echo "::error title=Fonts::${fonts##*Look fonts}"
  exit 1
elif [ -n "$fonts" ]; then
  echo "::notice title=Fonts::Look fonts${fonts##*Look fonts}"
else
  echo "::warning title=Fonts::No font check found in the app log"
fi

echo "::group::App log (errors and faults)"
xcrun simctl spawn "$UDID" log show --last 5m --style compact \
  --predicate "process == \"AiSky\" AND (messageType == error OR messageType == fault)" 2>/dev/null | tail -n 60 || true
echo "::endgroup::"
