#!/bin/bash
# <bitbar.title>World Radio</bitbar.title>
# <bitbar.desc>What is on the radio, and everything you need to change it</bitbar.desc>
#
# All the state lives in the `radio` CLI next to this, so the menu bar, the
# globe panel and the keybindings read the same cache and write the same
# favourites - there is one implementation, and this is a view of it.
#
# Unlike the media plugin, this prints something even when nothing is playing:
# media reflects a player you started elsewhere, but this IS the player, so an
# item that vanishes when idle would leave nowhere to turn the radio on.
SELF="${BASH_SOURCE[0]}"
REAL="$(readlink "$SELF" 2>/dev/null || echo "$SELF")"
PLUGIN="$(cd "$(dirname "$REAL")/.." && pwd)"
CTL="$PLUGIN/radio"

# `radio status` never touches the network - it reads mpv's socket and the
# state file - so a menu bar refresh every 5 seconds costs nothing and asks
# the directory for nothing.
running=false playing=false paused=false buffering=false muted=false
volume=70 favorite=false title="" uuid="" name="" country="" cc="" homepage=""
mpv=""
while IFS=$'\t' read -r key value; do
  case "$key" in
    running) running="$value" ;;
    playing) playing="$value" ;;
    paused) paused="$value" ;;
    buffering) buffering="$value" ;;
    muted) muted="$value" ;;
    volume) volume="$value" ;;
    favorite) favorite="$value" ;;
    title) title="$value" ;;
    uuid) uuid="$value" ;;
    name) name="$value" ;;
    country) country="$value" ;;
    cc) cc="$value" ;;
    homepage) homepage="$value" ;;
    mpv) mpv="$value" ;;
  esac
done < <("$CTL" status --tsv 2>/dev/null)

# Some stations carry a country code and no country name. Falling back keeps
# the dropdown from showing a station from nowhere.
[[ -z "$country" ]] && country="$cc"

# A stray pipe would be read as SwiftBar's own parameter syntax, and station
# names come from a public directory that anyone can submit to.
clean() { printf '%s' "$1" | tr '|' '/' ; }

if [[ -z "$mpv" ]]; then
  # Enabling from the menu bar or the plugin panel passes --yes and discards
  # the install hook's output, so this is the only place the missing
  # dependency can actually reach someone who did not use the command line.
  echo "◎⚠ | color=#c88"
  echo "---"
  echo "mpv is not installed, so nothing can play | color=#c88"
  echo "The radio needs it to play a stream. | size=11 color=#8a8a8a"
  echo "---"
  echo "brew install mpv | font=Menlo size=12"
  echo "Copy that command | bash=$CTL param1=copy-install terminal=false refresh=true"
  echo "mpv.io | href=https://mpv.io"
  echo "---"
  echo "Everything else works: the globe, search and favourites | size=11 color=#8a8a8a"
  echo "Open the globe | bash=$PLUGIN/radio-panel terminal=false"
  exit 0
fi

if [[ "$playing" == true ]]; then
  icon="◉"
elif [[ "$buffering" == true ]]; then
  icon="◍"
elif [[ "$paused" == true ]]; then
  icon="◌"
else
  icon="◎"
fi

if [[ -n "$name" && "$running" == true ]]; then
  echo "$icon $(clean "$name") | length=26"
else
  echo "$icon | color=#8a8a8a"
fi

echo "---"

if [[ -n "$name" ]]; then
  echo "$(clean "$name")"
  [[ -n "$country" ]] && echo "$(clean "$country") | color=#8a8a8a size=11"
  # The song, when the stream sends one. Not truncated: the menu bar line above
  # has to keep a stable width, but this is where you come to read the title.
  [[ -n "$title" ]] && echo "$(clean "$title") | color=#8a8a8a size=11"
  [[ "$buffering" == true ]] && echo "buffering... | color=#8a8a8a size=11"
  echo "---"
fi

if [[ "$running" == true && "$playing" == true ]] || [[ "$paused" == true ]]; then
  if [[ "$paused" == true ]]; then
    echo "Play | bash=$CTL param1=toggle terminal=false refresh=true"
  else
    echo "Pause | bash=$CTL param1=toggle terminal=false refresh=true"
  fi
  echo "Stop | bash=$CTL param1=stop terminal=false refresh=true"
fi
echo "Tune somewhere new | bash=$CTL param1=random terminal=false refresh=true"

if [[ -n "$uuid" ]]; then
  if [[ "$favorite" == true ]]; then
    echo "♥ Remove from favourites | bash=$CTL param1=favorite param2=$uuid terminal=false refresh=true"
  else
    echo "♡ Add to favourites | bash=$CTL param1=favorite param2=$uuid terminal=false refresh=true"
  fi
fi

echo "---"
mutemark=""; [[ "$muted" == true ]] && mutemark=" (muted)"
echo "Volume $volume$mutemark | size=11 color=#8a8a8a"
echo "-- Louder | bash=$CTL param1=volume param2=+5 terminal=false refresh=true"
echo "-- Quieter | bash=$CTL param1=volume param2=-5 terminal=false refresh=true"
echo "-- Mute / unmute | bash=$CTL param1=mute terminal=false refresh=true"

# Favourites and recents come from the state file, so these submenus cost one
# read each and never a request.
list_into() { # which list: favorites | recent
  local which="$1" n=0
  local station_uuid station_name station_cc station_country
  while IFS=$'\t' read -r station_uuid station_name station_cc station_country; do
    [[ -z "$station_uuid" ]] && continue
    (( n++ )); (( n > 20 )) && break
    local where="$station_country"; [[ -z "$where" ]] && where="$station_cc"
    echo "-- $(clean "$station_name")  ·  $(clean "$where") | bash=$CTL param1=play param2=$station_uuid terminal=false refresh=true"
  done < <("$CTL" "$which" --tsv 2>/dev/null)
  (( n == 0 )) && echo "-- (none yet) | color=#8a8a8a"
}

echo "---"
echo "Favourites"
list_into favorites
echo "Recent"
list_into recent

echo "---"
echo "Open the globe | bash=$PLUGIN/radio-panel terminal=false"
echo "Super+Shift+R | size=11 color=#8a8a8a"
# An if, not `[[ ... ]] && echo`: as the last line of the script that idiom
# exits 1 whenever there is no homepage, and SwiftBar reads a non-zero exit as
# a broken plugin.
if [[ -n "$homepage" ]]; then
  echo "Station website | href=$homepage"
fi
