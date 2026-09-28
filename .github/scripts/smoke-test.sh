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

alive() {
  xcrun simctl spawn "$UDID" launchctl list | grep -q "UIKitApplication:$BUNDLE"
}

# capture <file> <screen> <seconds to wait>
capture() {
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -AiSkyDemoLibrary -AiSkyScreen "$2" >/dev/null
  sleep "$3"
  if alive; then
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$1.png" >/dev/null 2>&1 && echo "captured $1"
  else
    echo "❌ Ai Sky is not running on screen '$2'"
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
capture 10-settings settings 5
capture 11-rain-history rainHistory 25
capture 12-time-machine timeMachine 20
capture 13-radar-spot radarSpot 20

if [ "$failures" -gt 0 ]; then
  find ~/Library/Logs/DiagnosticReports -name "AiSky*" -mmin -20 -print -exec head -120 {} \; 2>/dev/null
  exit 1
fi
echo "✅ Ai Sky opened every screen without crashing"

echo "::group::App log (errors and faults)"
xcrun simctl spawn "$UDID" log show --last 5m --style compact \
  --predicate "process == \"AiSky\" AND (messageType == error OR messageType == fault)" 2>/dev/null | tail -n 60 || true
echo "::endgroup::"
