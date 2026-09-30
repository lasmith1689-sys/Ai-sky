#!/bin/bash
# Checks the OCR text of each look's screenshots for what that screen must show, so a look that
# renders blank, falls back to an error, or loses its tab bar fails CI.
#   verify-screens.sh ocr.txt
set -uo pipefail
OCR="${1:-ocr.txt}"
[ -f "$OCR" ] || { echo "::warning title=Screens::No OCR text to check"; exit 0; }
failures=0

# section <capture name>: the OCR lines printed for that screenshot.
section() {
  awk -v name="===== $1.png =====" '$0 == name {p = 1; next} /^===== / {p = 0} p' "$OCR"
}

# expect <capture name> <spec>: every " && "-separated extended regex must match (case-insensitive);
# a leading "!" means it must not.
expect() {
  local name="$1" rest="$2" term problems="" text
  text=$(section "$name")
  if [ -z "$text" ]; then
    echo "::error title=Screens::$name: no screenshot text"
    failures=$((failures + 1))
    return
  fi
  while [ -n "$rest" ]; do
    term="${rest%% && *}"
    if [ "$term" = "$rest" ]; then rest=""; else rest="${rest#* && }"; fi
    if [ "${term:0:1}" = "!" ]; then
      grep -Eiq -- "${term:1}" <<<"$text" && problems+="[shows '${term:1}'] "
    else
      grep -Eiq -- "$term" <<<"$text" || problems+="[no '$term'] "
    fi
  done
  if [ -n "$problems" ]; then
    echo "::error title=Screens::$name: $problems"
    failures=$((failures + 1))
  else
    echo "ok $name"
  fi
}

tabs="Radar && Places && Settings"
expect 10-settings "Settings && Look && Instrument && Units"
expect instrument-1-forecast "$tabs && Forecast && NEXT HOUR && FEELS && WIND && HUMID && !load weather"
expect liquid-1-forecast "Forecast && $tabs && Feels && Now && !load weather"
expect obsidian-1-forecast "$tabs && Forecast && NEXT HOUR && HOURLY && FEELS && !load weather"
expect editorial-1-forecast "$tabs && Forecast && THE NEXT HOUR && Feels like && !load weather"
expect horizon-1-forecast "$tabs && Timeline && HOURS && Feels && !load weather"
expect chroma-1-forecast "$tabs && Forecast && FEELS && !load weather"

# Every look shows the old screen's features: the week in a sentence, My Location, the yesterday
# comparison when it's dry, and the rate line and resolution while it's raining.
for look in liquid obsidian instrument editorial horizon chroma; do
  expect "$look-2-daily" "temperatures"
done
for look in obsidian instrument editorial horizon chroma; do
  expect "$look-10-dry" "My Location && yesterday"
  expect "$look-11-raining" "Now: && rain && (by minute|15-minute)"
done
expect liquid-sky-clear "My Location && yesterday"
expect liquid-sky-rain "Now: && Minute by minute"

# The widget gallery shows every family.
for look in instrument editorial liquid; do
  for mode in "" "-tinted"; do
    expect "widgets-$look-1$mode" "Conditions && Next Hour && Air Quality && Lock Screen && Chicago"
    expect "widgets-$look-2$mode" "Conditions . large && Rainfall . medium && Chicago"
    expect "widgets-$look-3$mode" "My Places . large && Rainfall . small && Work && Denver"
  done
done

# Liquid on each sky shows that sky's condition in the hero.
expect liquid-sky-clear "Clear && Feels && Now && !load weather"
expect liquid-sky-partlyCloudy "Partly Cloudy && Feels && Now && !load weather"
expect liquid-sky-clear-night "Clear && Feels && Now && !load weather"
expect liquid-sky-drizzle "Drizzle && Feels && Now && !load weather"
expect liquid-sky-rain "Rain && Feels && Now && !load weather"
expect liquid-sky-fog "Fog && Feels && Now && !load weather"
expect liquid-sky-snow "Snow && Feels && Now && !load weather"
expect liquid-sky-cloudy-night "Cloudy && Feels && Now && !load weather"

for look in liquid obsidian instrument editorial horizon chroma; do
  # Horizon's daily section opens with the next hour and the week sentence, so its Time Machine
  # link sits below the fold; the ten days are checked instead.
  if [ "$look" = horizon ]; then
    expect "$look-2-daily" "The Week && Today && Tomorrow"
  else
    expect "$look-2-daily" "Time Machine"
  fi
  expect "$look-3-precipitation" "Past 24 hrs && Rainfall"
  expect "$look-4-details" "Humidity && Wind && UV"
  expect "$look-5-day-detail" "Temperature && Done"
  expect "$look-6-places" "Places && Saved Places && Work"
  expect "$look-7-settings" "Settings && Look && Obsidian && Editorial && Horizon"
  expect "$look-8-radar" "(NEXRAD|RainViewer) && Now"
done

if [ "$failures" -gt 0 ]; then
  echo "::error title=Screens::$failures screen(s) didn't show what they should"
  exit 1
fi
echo "✅ Every look's screens show what they should"
