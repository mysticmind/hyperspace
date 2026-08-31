#!/usr/bin/env bash
# hyperspace - AeroSpace + Caps-Lock-as-Super + SwiftBar in the native menu bar.
#
# Design rules, learned the hard way from a setup that broke all of them:
#   1. Never touch ~/.zshrc or any shell config. This repo is not a dotfiles manager.
#   2. Never uninstall Homebrew packages on teardown. Not even ones we installed.
#   3. Back up anything real we displace, and record it, so uninstall can restore
#      exactly that instead of guessing.
#   4. Symlink individual FILES, not whole directories, so other tools' configs
#      in the same directory keep working.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HOME/.local/state/hyperspace"
MANIFEST="$STATE/manifest"
STAMP="$(date +%Y%m%d%H%M%S)"
mkdir -p "$STATE"; touch "$MANIFEST"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn\033[0m %s\n' "$*"; }
note() { printf '      %s\n' "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS only"; exit 1; }
command -v brew >/dev/null || { echo "Homebrew required: https://brew.sh"; exit 1; }
BREW_PREFIX="$(brew --prefix)"

# --- 0. Preflight -----------------------------------------------------------
# A macOS Caps Lock remap (System Settings -> Keyboard -> Modifier Keys)
# consumes the key before Karabiner ever sees it, so `from: caps_lock` never
# matches and EVERY binding silently does nothing - with a perfectly correct
# config on disk. Catch it here rather than letting it look like a broken setup.
log "Preflight"
"$REPO/bin/doctor" --caps-only --fix || true

# --- 1. Dependencies --------------------------------------------------------
# brew bundle is NOT fatal: the Brewfile carries one optional item (the Nerd
# Font), and a font cask fails outright if you already installed those fonts
# by hand. Required tools are verified individually below instead.
log "Installing dependencies from Brewfile"
brew bundle --file="$REPO/Brewfile" || warn "brew bundle reported failures - checking what actually matters"

missing=()
for c in aerospace karabiner-elements swiftbar; do
  brew list --cask "$c" >/dev/null 2>&1 || missing+=("cask $c")
done
brew list borders >/dev/null 2>&1 || missing+=("formula borders")
if (( ${#missing[@]} )); then
  printf 'Missing required package(s):\n'
  printf '  %s\n' "${missing[@]}"
  echo "Install them and re-run: brew bundle --file=$REPO/Brewfile"
  exit 1
fi
log "All required packages present"

# The Nerd Font is optional - the SwiftBar plugin names it, and falls back to
# the system font if it is absent. Do not fail the install over it.
if ! ls "$HOME/Library/Fonts"/JetBrainsMono*Nerd* >/dev/null 2>&1 \
   && ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
  warn "JetBrains Mono Nerd Font not found - menu bar pills use the system font"
fi

# --- 2. Link configs --------------------------------------------------------
# link <source in repo> <destination>
link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    local cur; cur="$(readlink "$dst")"
    [[ "$cur" == "$src" ]] && { note "already linked: ${dst/#$HOME/\~}"; return; }
    # Someone else's symlink (a dotfiles manager). Record it so we can put it back.
    printf 'prior-symlink\t%s\t%s\n' "$dst" "$cur" >> "$MANIFEST"
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    # Backups go to the state dir, NOT next to the original. SwiftBar runs
    # every file in its plugin directory, so a .bak left beside a plugin
    # becomes a second copy of that plugin in the menu bar.
    mkdir -p "$STATE/backups"
    local bak="$STATE/backups/$(basename "$dst").bak.hyperspace.$STAMP"
    mv "$dst" "$bak"
    printf 'backup\t%s\t%s\n' "$dst" "$bak" >> "$MANIFEST"
    note "backed up existing ${dst/#$HOME/\~} -> $(basename "$bak")"
  fi
  ln -sfn "$src" "$dst"
  printf 'link\t%s\n' "$dst" >> "$MANIFEST"
  log "linked ${dst/#$HOME/\~}"
}

# aerospace.toml is GENERATED from aerospace.base.toml plus whichever plugins
# are enabled, so it has to be built before it can be linked.
log "Building aerospace.toml from the base config + enabled plugins"
"$REPO/bin/build-config"

link "$REPO/config/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"
link "$REPO/config/swiftbar/aerospace.10s.sh" "$HOME/.config/swiftbar/aerospace.10s.sh"
link "$REPO/config/borders/bordersrc" "$HOME/.config/borders/bordersrc"

# Scripts the config and you both call by a stable path, so aerospace.toml
# never has to know where the repo lives.
link "$REPO/bin/cheatsheet-toggle" "$HOME/.local/bin/hyperspace-cheatsheet"
link "$REPO/bin/close-window" "$HOME/.local/bin/hyperspace-close"
link "$REPO/bin/doctor" "$HOME/.local/bin/hyperspace-doctor"
link "$REPO/bin/plugin" "$HOME/.local/bin/hyperspace-plugin"
link "$REPO/bin/plugin-ui" "$HOME/.local/bin/hyperspace-plugins"

# --- 3. Karabiner: merge one rule into whatever you already have ------------
log "Adding the Caps Lock -> Super rule to your existing karabiner.json"
"$REPO/bin/karabiner-rule" install --rule "$REPO/config/karabiner/caps-to-super.json"

# Karabiner watches this file, but a stale user server will READ it without
# APPLYING it - the log shows "Load ...karabiner.json..." with no
# "core_configuration is updated" after it, and core_service_daemon_client
# refusing to connect with "Permission denied". Every key remap silently does
# nothing until the agents are restarted. Kick them so the rule takes effect.
log "Restarting Karabiner agents so the rule actually applies"
for svc in Karabiner-Core-Service-rev2 Karabiner-Console-User-Server; do
  launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.$svc" 2>/dev/null || true
done
sleep 3
KLOG="$HOME/.local/share/karabiner/log/console_user_server.log"
if [[ -f "$KLOG" ]] && tail -30 "$KLOG" | grep -q "core_configuration is updated"; then
  log "Karabiner applied the config"
else
  warn "Karabiner may not have applied the config - check $KLOG"
  warn "and open Karabiner-Elements once to grant any pending permission."
fi

# --- 4. Menu bar auto-hide --------------------------------------------------
# This is what actually lets windows use the full display height: with the menu
# bar auto-hidden macOS reports visibleFrame as the FULL screen, so AeroSpace
# tiles all of it. With the bar visible, macOS clamps windows out of that strip
# and no gap setting can reclaim it.
record_default() { # domain key
  grep -q "^default $1 $2 " "$MANIFEST" && return 0
  local t v
  if v="$(defaults read "$1" "$2" 2>/dev/null)"; then
    t="$(defaults read-type "$1" "$2" 2>/dev/null | awk '{print $3}')"
    printf 'default %s %s %s %s\n' "$1" "$2" "${t:-string}" "$v" >> "$MANIFEST"
  else
    printf 'default %s %s ABSENT ABSENT\n' "$1" "$2" >> "$MANIFEST"
  fi
}
record_default NSGlobalDomain _HIHideMenuBar
defaults write NSGlobalDomain _HIHideMenuBar -bool true
killall cfprefsd 2>/dev/null || true
log "Menu bar set to auto-hide (windows reclaim the 30pt strip)"

# --- 5. SwiftBar plugin directory -------------------------------------------
record_default com.ameba.SwiftBar PluginDirectory
defaults write com.ameba.SwiftBar PluginDirectory -string "$HOME/.config/swiftbar"
log "SwiftBar plugin directory -> ~/.config/swiftbar"

# --- 6. Launch at login -----------------------------------------------------
# SwiftBar registers its login item through SMAppService, which only the app
# itself can call. A LaunchAgent that opens it at login does the same job with
# nothing resident. AeroSpace and borders handle their own.
log "Registering login agent for SwiftBar"
"$REPO/bin/login-agent" install SwiftBar

# --- 7. Start everything ----------------------------------------------------
# AeroSpace LAST and always restarted: it does not recompute screen geometry
# when the menu bar visibility changes, so it must start after step 4.
log "Starting services"
brew services start FelixKratz/formulae/borders >/dev/null 2>&1 || warn "borders service failed to start"
open -a SwiftBar 2>/dev/null || warn "SwiftBar failed to launch"
killall AeroSpace 2>/dev/null || true
sleep 2
open -a AeroSpace 2>/dev/null || warn "AeroSpace failed to launch"

cat <<EOF

$(printf '\033[1;32mDone.\033[0m') Super = Caps Lock (⌘⌃⌥). Super+Return opens a terminal.

Steps this script cannot do for you:
  - Grant Accessibility to AeroSpace and Karabiner when macOS asks.
  - Hide your terminal's title bar, if you want the traffic lights gone:
    Alacritty  ~/.config/alacritty/alacritty.toml   decorations = "Buttonless"
    Ghostty    ~/.config/ghostty/config             window-decoration = false
    Prefer the setting that keeps the native frame (Alacritty's Buttonless
    hides the buttons but keeps it). Dropping the frame outright, as
    Alacritty's decorations = "none" does, squares the window corners, and
    the focus ring is round, so it cuts across them.
    Your terminal config is yours; this repo does not touch it.
  - The full keybinding list is on Super+K, in the SwiftBar menu, and README.md.

Plugins:  hyperspace-plugin list | enable <name> | disable <name>

Everything starts at login: AeroSpace and borders on their own, SwiftBar via a
LaunchAgent. If you later tick "Launch at Login" inside SwiftBar, run
`bin/login-agent uninstall SwiftBar` first or it launches twice.

Homebrew packages are NOT removed by uninstall.sh, by design. See README.
EOF
