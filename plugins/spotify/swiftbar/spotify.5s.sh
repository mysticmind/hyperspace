#!/bin/bash
# <bitbar.title>Spotify Now Playing</bitbar.title>
# <bitbar.desc>Current track in the menu bar, with transport controls</bitbar.desc>
#
# Prints NOTHING when Spotify is not running, so the menu bar stays clean.
# The pgrep guard matters: `tell application "Spotify"` LAUNCHES Spotify, so
# without it this plugin would start the app every 5 seconds forever.
pgrep -x Spotify >/dev/null 2>&1 || exit 0

SELF="${BASH_SOURCE[0]}"
REAL="$(readlink "$SELF" 2>/dev/null || echo "$SELF")"
CTL="$(cd "$(dirname "$REAL")/.." && pwd)/spotify-ctl"

info="$(osascript 2>/dev/null <<'AS'
tell application "Spotify"
  set s to player state as text
  if s is "stopped" then return "stopped"
  return s & tab & (artist of current track as text) & tab & ¬
         (name of current track as text) & tab & (album of current track as text)
end tell
AS
)"

[[ -z "$info" || "$info" == "stopped" ]] && exit 0
IFS=$'\t' read -r state artist track album <<<"$info"

if [[ "$state" == "playing" ]]; then icon="▶"; else icon="⏸"; fi
# length= lets SwiftBar truncate long titles instead of shoving the menu bar around
echo "$icon $artist — $track | length=32"

echo "---"
echo "$track | length=45"
echo "$artist | length=45 color=#8a8a8a"
[[ -n "$album" ]] && echo "$album | length=45 color=#8a8a8a size=11"
echo "---"
if [[ "$state" == "playing" ]]; then
  echo "Pause | bash=$CTL param1=playpause terminal=false refresh=true"
else
  echo "Play | bash=$CTL param1=playpause terminal=false refresh=true"
fi
echo "Next | bash=$CTL param1=next terminal=false refresh=true"
echo "Previous | bash=$CTL param1=previous terminal=false refresh=true"
echo "---"
echo "Open Spotify | bash=$CTL param1=open terminal=false"
