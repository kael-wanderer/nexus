#!/bin/sh
# Counts main-thread stalls in a Nexus build while a person uses the bar.
#
#   scripts/stall-measure.sh [path/to/Nexus.app] [seconds]
#
# Launches the app with NEXUS_STALL_LOG=1 (through `open`, so macOS attributes its permissions to
# Nexus and not to the terminal), waits while you use the bar, then reads the stalls back from the
# system log. Nothing is written anywhere: copy the summary into docs/verification.md.
#
# What to do while it waits (the same every time, so two runs can be compared):
#   - music playing in Music or Spotify, the now-playing row on
#   - move the pointer on and off the bar 20 times
#   - open 5 window flyouts
#   - leave the player's timeline on screen for the last 30 seconds
set -eu

APP="${1:-build/Nexus.app}"
SECONDS_TO_WAIT="${2:-90}"

case "$SECONDS_TO_WAIT" in
  ''|*[!0-9]*) echo "seconds must be a whole number" >&2; exit 2 ;;
esac
if [ ! -d "$APP" ] || [ ! -x "$APP/Contents/MacOS/NexusApp" ]; then
  echo "No Nexus build at: $APP" >&2
  exit 2
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")

pkill -x NexusApp 2>/dev/null || true
sleep 1
START=$(date "+%Y-%m-%d %H:%M:%S")
open -n --env NEXUS_STALL_LOG=1 "$APP"

echo "Nexus $VERSION ($BUILD) is running with the stall monitor on."
echo "Use the bar for $SECONDS_TO_WAIT seconds: 20 hovers on and off, 5 flyouts, timeline visible at the end."
sleep "$SECONDS_TO_WAIT"

pkill -x NexusApp 2>/dev/null || true
# The log is written asynchronously; give the last lines a moment to land.
sleep 2

/usr/bin/log show \
  --predicate 'subsystem == "com.congbui.nexus" AND eventMessage CONTAINS "Main thread stalled"' \
  --start "$START" --style compact 2>/dev/null \
| awk -v version="$VERSION ($BUILD)" -v seconds="$SECONDS_TO_WAIT" '
    /Main thread stalled/ {
      for (i = 1; i <= NF; i++) if ($i == "stalled") ms = $(i + 1) + 0
      count++
      if (ms > max) max = ms
      if (ms >= 50) over50++
      if (ms >= 100) over100++
    }
    END {
      printf "\nNexus %s, %s s\n", version, seconds
      printf "  stalls of 32 ms or more: %d\n", count + 0
      printf "  of 50 ms or more:        %d\n", over50 + 0
      printf "  of 100 ms or more:       %d\n", over100 + 0
      printf "  longest:                 %d ms\n", max + 0
    }'
