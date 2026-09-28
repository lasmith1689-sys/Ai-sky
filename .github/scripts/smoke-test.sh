#!/bin/bash
# Installs the Simulator build, launches it with demo places, walks through every screen via
# deep links, captures screenshots and fails if the app crashed.
#   smoke-test.sh <simulator-udid> <path/to/AiSky.app> [output-dir]
set -uo pipefail
UDID="$1"
APP="$2"
OUT="${3:-screenshots}"
mkdir -p "$OUT"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE" || true
xcrun simctl location "$UDID" set 41.8781,-87.6298 || true   # Chicago

xcrun simctl launch "$UDID" "$BUNDLE" -AiSkyDemoLibrary
sleep 30

shot() {
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$1.png" >/dev/null 2>&1 && echo "captured $1"
}
visit() {
  xcrun simctl openurl "$UDID" "$1"
  sleep "$2"
}

shot 01-forecast
visit "aisky://forecast/current?section=nextHour" 3 && shot 02-next-hour
visit "aisky://forecast/current?section=hourly" 3 && shot 03-hourly
visit "aisky://forecast/current?section=daily" 3 && shot 04-daily
visit "aisky://forecast/current?section=precipitation" 3 && shot 05-precipitation
visit "aisky://forecast/current?section=airQuality" 3 && shot 06-air-quality
visit "aisky://forecast/current?section=details" 3 && shot 07-details
visit "aisky://radar" 25 && shot 08-radar
visit "aisky://locations" 8 && shot 09-locations
visit "aisky://settings" 3 && shot 10-settings

if xcrun simctl spawn "$UDID" launchctl list | grep -q "UIKitApplication:$BUNDLE"; then
  echo "✅ Ai Sky is still running after visiting every screen"
else
  echo "❌ Ai Sky is not running — it probably crashed"
  find ~/Library/Logs/DiagnosticReports -name "AiSky*" -mmin -20 -print -exec head -120 {} \; 2>/dev/null
  exit 1
fi

echo "::group::App log (errors and faults)"
xcrun simctl spawn "$UDID" log show --last 5m --style compact \
  --predicate "process == \"AiSky\" AND (messageType == error OR messageType == fault)" 2>/dev/null | tail -n 60 || true
echo "::endgroup::"
