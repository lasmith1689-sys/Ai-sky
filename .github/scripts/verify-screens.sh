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

# Radar with a forecast: the last frame is a forecast, labeled as one.
expect 17-radar-forecast "NEXRAD && HRRR forecast && Forecast . && Now && !unavailable"

# The radar renderer's geometry. The test pattern draws each tile's address ("z7 x32 y47") in the
# middle of the tile, so the labels read back must be upright (OCR can't read them otherwise), all
# at one zoom, west to east along each row, rows north to south, and around the map's center tile.
python3 - "$OCR" <<'PY' || failures=$((failures + 1))
import math, re, sys
text = open(sys.argv[1]).read()
match = re.search(r"===== 18-radar-tiles\.png =====\n(.*?)(?=\n=====|\Z)", text, re.S)
if not match:
    print("::error title=Screens::18-radar-tiles: no screenshot text")
    sys.exit(1)
rows = []
for line in match.group(1).splitlines():
    m = re.match(r"\s*(\d+)%\s+(.*)", line)
    if not m:
        continue
    labels = [tuple(map(int, t)) for t in re.findall(r"z\s*(\d+)[\s|]+x\s*(\d+)[\s|]+y\s*(\d+)", m.group(2), re.I)]
    if labels:
        rows.append((int(m.group(1)), labels))
labels = [label for _, row in rows for label in row]
problems = []
if len(labels) < 3 or len(rows) < 2:
    problems.append(f"read {len(labels)} tile labels in {len(rows)} rows (need 3 in 2 rows)")
zooms = {label[0] for label in labels}
if len(zooms) > 1:
    problems.append(f"mixed zooms {sorted(zooms)}")
for percent, row in rows:
    if len({label[2] for label in row}) != 1:
        problems.append(f"row at {percent}% mixes tile rows {row}")
    columns = [label[1] for label in row]
    if columns != sorted(set(columns)):
        problems.append(f"row at {percent}% isn't west to east: {row}")
tile_rows = [row[0][2] for _, row in sorted(rows)]
if tile_rows != sorted(set(tile_rows)):
    problems.append(f"rows aren't north to south: {tile_rows}")
def tile(lat, lon, z):
    n = 2 ** z
    r = math.radians(lat)
    return int((lon + 180) / 360 * n), int((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
if labels and len(zooms) == 1:
    z = labels[0][0]
    # The map opens on the selected place (Chicago in CI) or, without one, the middle of the U.S.
    centers = [tile(41.8781, -87.6298, z), tile(39.5, -98.35, z)]
    if not any(abs(l[1] - cx) <= 1 and abs(l[2] - cy) <= 1 for l in labels for cx, cy in centers):
        problems.append(f"no tile near the map's center {centers} at zoom {z}: {labels}")
if problems:
    print("::error title=Screens::18-radar-tiles: " + "; ".join(problems))
    sys.exit(1)
print(f"ok 18-radar-tiles ({len(labels)} tiles at zoom {labels[0][0]} in {len(rows)} rows)")
PY

if [ "$failures" -gt 0 ]; then
  echo "::error title=Screens::$failures screen(s) didn't show what they should"
  exit 1
fi
echo "✅ Every look's screens show what they should"
