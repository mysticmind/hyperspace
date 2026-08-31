#!/usr/bin/env bash
# Silence first: a radio that keeps playing after you disabled the plugin that
# owns it has no controls left, and mpv is running headless with no window to
# close.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$HERE/radio" stop >/dev/null 2>&1 || true
echo "  radio stopped"

# Favourites are yours and are left alone, the same way the dictation plugin
# leaves Handy's own setting: deleting them would be a guess about whether this
# is a disable or a goodbye, and re-enabling is one command away.
echo "  favourites and history left in ~/.local/state/hyperspace/worldradio/"
echo "  remove them with: rm -rf ~/.local/state/hyperspace/worldradio"
