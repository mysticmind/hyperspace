#!/usr/bin/env bash
# Enabling this plugin installs nothing on its own. It checks for mpv, offers
# to fetch it if you are at a terminal, and says what the plugin talks to.
#
# mpv is deliberately NOT in the repo's Brewfile. That file is the core's
# dependency list and `./install.sh` acts on it, so putting mpv there would
# install a media player on every machine that runs hyperspace, including the
# ones that never turn this plugin on. The dictation plugin treats Handy the
# same way.
#
# It is never installed for you without asking. `plugin enable` from the menu
# bar or the panel passes --yes and has no terminal to prompt on, so in that
# case this only reports - and the menu bar item then shows the missing
# dependency itself, which is the one place that path can be told.
set -uo pipefail

if command -v mpv >/dev/null 2>&1; then
  echo "  mpv: $(command -v mpv)"
elif [[ -t 0 ]] && command -v brew >/dev/null 2>&1; then
  echo "  mpv is not installed, and the radio needs it to play anything."
  read -r -p "  run 'brew install mpv' now? [y/N] " answer
  case "$answer" in
    [Yy]*) brew install mpv ;;
    *) echo "  skipped - run 'brew install mpv' when you want sound." ;;
  esac
else
  echo "  WARNING: mpv is not installed, so nothing will play."
  echo "           brew install mpv"
fi

echo "  the globe and the menu bar reach two hosts, and only when you ask:"
echo "    api.radio-browser.info   the community station directory"
echo "    whichever station you tune, for the audio itself"
echo "  favourites and history stay on this machine, in"
echo "    ~/.local/state/hyperspace/worldradio/state.json"
