#!/bin/bash
# AeroSpace workspaces for SwiftBar.
# The 10s interval is only a fallback — aerospace.toml pushes an instant
# refresh via `open -g "swiftbar://refreshplugin?name=aerospace"` on every
# workspace change, so this is never the thing you actually see.
#
# <bitbar.title>AeroSpace Workspaces</bitbar.title>
# <bitbar.author>babu</bitbar.author>
# <bitbar.desc>Focused workspace + switcher for AeroSpace</bitbar.desc>

AS=/opt/homebrew/bin/aerospace
[ -x "$AS" ] || { echo "⚠︎ aerospace"; exit 0; }

# SwiftBar runs this through a symlink in ~/.config/swiftbar, so resolve back
# to the repo rather than assuming a clone path. ~/.local/bin is not
# necessarily on SwiftBar's PATH, so call bin/plugin directly.
SELF="${BASH_SOURCE[0]}"
REAL="$(readlink "$SELF" 2>/dev/null || echo "$SELF")"
REPO="$(cd "$(dirname "$REAL")/../.." && pwd)"

focused=$("$AS" list-workspaces --focused 2>/dev/null)
if [ -z "$focused" ]; then
  echo "○ | color=#8a8a8a"
  echo "---"
  echo "AeroSpace is not running"
  echo "Start AeroSpace | bash=/usr/bin/open param1=-a param2=AeroSpace terminal=false refresh=true"
  exit 0
fi

# Workspaces that actually hold windows, plus the focused one even if empty.
occupied=$("$AS" list-workspaces --monitor all --empty no 2>/dev/null)
shown=$(printf '%s\n%s\n' "$occupied" "$focused" | grep -v '^$' | sort -n -u)

title=""
for ws in $shown; do
  if [ "$ws" = "$focused" ]; then
    title="$title [$ws]"
  else
    title="$title $ws"
  fi
done
echo "${title# } | font=JetBrainsMonoNF-Regular size=13"

echo "---"
echo "Workspaces | size=11 color=#8a8a8a"
for ws in $shown; do
  n=$("$AS" list-windows --workspace "$ws" 2>/dev/null | grep -c .)
  mark=" "; [ "$ws" = "$focused" ] && mark="●"
  echo "$mark  $ws — $n window(s) | bash=$AS param1=workspace param2=$ws terminal=false refresh=true"
done

echo "---"
echo "Windows here | size=11 color=#8a8a8a"
"$AS" list-windows --workspace "$focused" --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null |
while IFS='|' read -r wid app title; do
  wid=$(echo "$wid" | tr -d ' ')
  app=$(echo "$app" | sed 's/^ *//;s/ *$//')
  # strip any stray pipe from the title so SwiftBar's own param parsing
  # never sees one it did not put there
  title=$(echo "$title" | tr '|' '/' | cut -c1-45)
  [ -n "$wid" ] && echo "  $app — $title | bash=$AS param1=focus param2=--window-id param3=$wid terminal=false refresh=true length=50"
done

# A disabled plugin takes its keybindings out of the cheatsheet with it, so
# without this there is nothing left anywhere pointing at how to switch one
# back on — the CLI works, but you have to already know it exists.
echo "---"
echo "Plugins | size=11 color=#8a8a8a"
STATE="$HOME/.local/state/hyperspace/enabled-plugins"
for d in "$REPO"/plugins/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  if grep -qx "$name" "$STATE" 2>/dev/null; then
    echo "  ● $name — on | bash=$REPO/bin/plugin param1=disable param2=$name terminal=false refresh=true"
  else
    echo "  ○ $name — off | bash=$REPO/bin/plugin param1=enable param2=$name terminal=false refresh=true"
  fi
done

echo "---"
echo "Cheatsheet (Super = Caps Lock)"
echo "-- Super+Return — terminal | font=Menlo size=12"
echo "-- Super+Shift+Return — browser | font=Menlo size=12"
echo "-- Super+Space — Raycast | font=Menlo size=12"
echo "-- Super+W — close window | font=Menlo size=12"
echo "-- Super+←↓↑→ / hjkl — focus | font=Menlo size=12"
echo "-- Super+Shift+←↓↑→ — move window | font=Menlo size=12"
echo "-- Super+1..9 — workspace | font=Menlo size=12"
echo "-- Super+Shift+1..9 — send window there | font=Menlo size=12"
echo "-- Super+Tab / Shift+Tab — next/prev ws | font=Menlo size=12"
echo "-- Super+B — back and forth | font=Menlo size=12"
echo "-- Alt+Tab — cycle windows in workspace | font=Menlo size=12"
echo "-- Super+T — float / tile | font=Menlo size=12"
echo "-- Super+E — flip split orientation | font=Menlo size=12"
echo "-- Super+A — accordion / tiles | font=Menlo size=12"
echo "-- Super+F — fullscreen | font=Menlo size=12"
echo "-- Super+- / Super+= — resize | font=Menlo size=12"
echo "-- Super+R — resize mode | font=Menlo size=12"
echo "-- Super+Esc — lock screen | font=Menlo size=12"
echo "-- Super+Shift+; — service mode | font=Menlo size=12"

echo "---"
echo "Reload AeroSpace config | bash=$AS param1=reload-config terminal=false refresh=true"
echo "Refresh | refresh=true"
