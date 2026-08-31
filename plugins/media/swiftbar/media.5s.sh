#!/bin/bash
# <bitbar.title>Now Playing</bitbar.title>
# <bitbar.desc>Current track in the menu bar, with transport controls</bitbar.desc>
#
# All the player discovery lives in media-ctl, so this and the keybindings act
# on the same player and there is one list to maintain, not two. Prints
# NOTHING when no supported player has a track, so the menu bar stays clean.
SELF="${BASH_SOURCE[0]}"
REAL="$(readlink "$SELF" 2>/dev/null || echo "$SELF")"
CTL="$(cd "$(dirname "$REAL")/.." && pwd)/media-ctl"

info="$("$CTL" status 2>/dev/null)"
[[ -z "$info" ]] && exit 0
IFS=$'\t' read -r app state artist track album <<<"$info"

if [[ "$state" == "playing" ]]; then icon="▶"; else icon="⏸"; fi
# length= lets SwiftBar truncate long titles instead of shoving the menu bar around
if [[ -n "$artist" ]]; then
  echo "$icon $artist - $track | length=32"
else
  echo "$icon $track | length=32"
fi

echo "---"
# NOT truncated, unlike the menu bar line above: the menu bar has to keep a
# stable width, but the dropdown is where you go to read the full title, so
# capping it here defeated the point. A long title widens the menu instead.
echo "$track"
[[ -n "$artist" ]] && echo "$artist | color=#8a8a8a"
[[ -n "$album" ]] && echo "$album | color=#8a8a8a size=11"
echo "---"
if [[ "$state" == "playing" ]]; then
  echo "Pause | bash=$CTL param1=playpause terminal=false refresh=true"
else
  echo "Play | bash=$CTL param1=playpause terminal=false refresh=true"
fi
echo "Next | bash=$CTL param1=next terminal=false refresh=true"
echo "Previous | bash=$CTL param1=previous terminal=false refresh=true"
echo "---"
echo "Open $app | bash=$CTL param1=open terminal=false"
