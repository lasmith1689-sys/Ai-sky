#!/bin/bash
# Turns compiler and test errors in a build log into GitHub annotations, so failures are readable
# from the run summary without downloading logs.
#   annotate-errors.sh <log> [title]
# GitHub shows at most 10 error annotations per step, so the first 9 unique errors get their own
# annotation (with file and line) and up to 40 more are folded into a 10th. Then the last 60 lines
# of the log are printed.
set -uo pipefail
LOG="$1"
TITLE="${2:-Build}"
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
[ -f "$LOG" ] || { echo "::error::$TITLE log $LOG is missing"; exit 0; }

escape() { local s="$1"; s="${s//'%'/%25}"; s="${s//$'\r'/%0D}"; s="${s//$'\n'/%0A}"; printf '%s' "$s"; }

count=0
rest=""
while IFS= read -r line; do
  if [[ "$line" =~ ^(/[^:]+):([0-9]+):([0-9]+:)?\ error:\ (.*)$ ]]; then
    file="${BASH_REMATCH[1]}"
    rel="${file#"$ROOT"/}"
    if [ "$count" -lt 9 ]; then
      echo "::error file=$rel,line=${BASH_REMATCH[2]},title=$TITLE::$(escape "${BASH_REMATCH[4]}")"
    else
      rest+="$rel:${BASH_REMATCH[2]}: ${BASH_REMATCH[4]}"$'\n'
    fi
  else
    if [ "$count" -lt 9 ]; then
      echo "::error title=$TITLE::$(escape "$line")"
    else
      rest+="$line"$'\n'
    fi
  fi
  count=$((count + 1))
  [ "$count" -ge 50 ] && break
done < <(grep -E "error:|\*\* (BUILD|ARCHIVE|TEST) FAILED|Fatal error|failed \(" "$LOG" | grep -v "^warning:" | awk '!seen[$0]++')

if [ -n "$rest" ]; then
  echo "::error title=$TITLE (more)::$(escape "$rest")"
fi

echo "::group::Last 60 lines of $LOG"
tail -n 60 "$LOG"
echo "::endgroup::"
