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
#
# Usage: install.sh [--dry-run]
#
# --dry-run prints every package, file, symlink, preference, login agent and
# service this would touch, and changes nothing. It exists because "read 200
# lines of bash and trust me" is not a reasonable thing to ask of someone about
# to let a script edit their keyboard configuration. Every mutation below sits
# behind the same flag, so the listing cannot drift from what the script does.
set -euo pipefail

DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --help|-h) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (try --help)" >&2; exit 1 ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HOME/.local/state/hyperspace"
MANIFEST="$STATE/manifest"
STAMP="$(date +%Y%m%d%H%M%S)"
(( DRY )) || { mkdir -p "$STATE"; touch "$MANIFEST"; }

log()   { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m warn\033[0m %s\n' "$*"; }
note()  { printf '      %s\n' "$*"; }
would() { printf '      \033[1;35mwould\033[0m %s\n' "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS only"; exit 1; }
command -v brew >/dev/null || { echo "Homebrew required: https://brew.sh"; exit 1; }

if (( DRY )); then
  printf '\033[1;35mDRY RUN\033[0m nothing below is executed. Repo: %s\n\n' "$REPO"
fi

# --- 0. Preflight -----------------------------------------------------------
# A macOS Caps Lock remap (System Settings -> Keyboard -> Modifier Keys)
# consumes the key before Karabiner ever sees it, so `from: caps_lock` never
# matches and EVERY binding silently does nothing - with a perfectly correct
# config on disk. Catch it here rather than letting it look like a broken setup.
log "Preflight"
if (( DRY )); then
  # --fix is the half that clears the remap, so the dry run only reports.
  "$REPO/bin/doctor" --caps-only || true
  would "clear a Caps Lock remap if one is set (backup: $STATE/modifiermapping.backup)"
else
  "$REPO/bin/doctor" --caps-only --fix || true
fi

# --- 1. Dependencies --------------------------------------------------------
# brew bundle is NOT fatal: the Brewfile carries one optional item (the Nerd
# Font), and a font cask fails outright if you already installed those fonts
# by hand. Required tools are verified individually below instead.
# Homebrew 6 refuses to load formulae or casks from a non-official tap until
# you trust it, because tapping one means running its maintainer's code. This
# repo needs two: nikitabobko/tap for AeroSpace and FelixKratz/formulae for
# borders. Without them the install dies on "Refusing to load cask ... from
# untrusted tap", which reads like a bug in hyperspace and is not.
#
# Not trusted automatically. Homebrew put that gate there on purpose, and a
# setup script quietly waving it through on your behalf is exactly the move
# this repo promises not to make. So: say what it is, and let you decide.
untrusted_taps() {
  local taps
  taps="$(grep -oE '^tap "[^"]+"' "$REPO/Brewfile" | sed 's/^tap "//;s/"$//')"
  [[ -z "$taps" ]] && return 0
  python3 - "$taps" <<'TRUST'
import json, subprocess, sys
want = [t.strip() for t in sys.argv[1].splitlines() if t.strip()]
try:
    out = subprocess.run(["brew", "trust", "--json", "v1"],
                         capture_output=True, text=True, timeout=30).stdout
    trusted = {t.lower() for t in json.loads(out or "{}").get("taps", [])}
except Exception:
    trusted = set()          # no store, or an older brew with no trust gate
for t in want:
    if t.lower() not in trusted:
        print(t)
TRUST
}

# An array, not a string. Passing the list as an unquoted `$(...)` relies on
# word splitting, which is what SC2046 objects to and is genuinely fragile: a
# tap name with a space would silently become two arguments. Built with a read
# loop rather than mapfile, which macOS's bash 3.2 does not have.
untrusted=()
while IFS= read -r t; do
  [[ -n "$t" ]] && untrusted+=("$t")
done < <(untrusted_taps)

if (( ${#untrusted[@]} )); then
  log "Third-party taps needing your trust"
  for t in "${untrusted[@]}"; do note "$t"; done
  note "Homebrew will not load a cask from these until they are trusted."
  note "Trusting a tap means agreeing to run code its maintainer publishes."
  if (( DRY )); then
    would "brew trust ${untrusted[*]}"
  elif [[ -t 0 ]]; then
    read -r -p "      trust them now? [y/N] " reply
    if [[ "$reply" =~ ^[Yy] ]]; then
      brew trust "${untrusted[@]}" || warn "brew trust failed"
    else
      echo "Not trusted, so the install cannot continue. To do it yourself:"
      echo "  brew trust ${untrusted[*]}"
      exit 1
    fi
  else
    echo "Not a terminal, so this cannot ask. Run:"
    echo "  brew trust ${untrusted[*]}"
    echo "then re-run install.sh."
    exit 1
  fi
fi

log "Dependencies from Brewfile"
if (( DRY )); then
  # --all, or brew lists only the formulae and silently hides every cask,
  # which is most of what this installs.
  while read -r line; do
    [[ -z "$line" ]] && continue
    # A tap is the only entry with a slash in it, and taps are added, not
    # installed. Saying "install" for one is a small lie in a listing whose
    # whole job is to be believed.
    if [[ "$line" == */* ]]; then
      would "brew tap $line"
    elif brew list "$line" >/dev/null 2>&1 || brew list --cask "$line" >/dev/null 2>&1; then
      note "already installed: $line"
    else
      would "brew install $line"
    fi
  done < <(brew bundle list --all --file="$REPO/Brewfile" 2>/dev/null || true)
  would "not remove or upgrade anything already installed"
else
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
fi

# --- 2. Link configs --------------------------------------------------------
# link <source in repo> <destination>
link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    local cur; cur="$(readlink "$dst")"
    if [[ "$cur" == "$src" ]]; then
      note "already linked: ${dst/#$HOME/\~}"
      # Record it even so. uninstall.sh deletes the whole state dir, so a link
      # that survives a teardown is unrecorded on the next install, and the
      # uninstall after that cannot see it. Found by `doctor --audit`: three of
      # seven links were listed.
      if (( ! DRY )) && ! grep -qxF "$(printf 'link\t%s' "$dst")" "$MANIFEST" 2>/dev/null; then
        printf 'link\t%s\n' "$dst" >> "$MANIFEST"
      fi
      return
    fi
    # Someone else's symlink (a dotfiles manager). Record it so we can put it back.
    if (( DRY )); then
      would "record and replace symlink ${dst/#$HOME/\~} (currently -> $cur)"
    else
      printf 'prior-symlink\t%s\t%s\n' "$dst" "$cur" >> "$MANIFEST"
      rm "$dst"
    fi
  elif [[ -e "$dst" ]]; then
    # Backups go to the state dir, NOT next to the original. SwiftBar runs
    # every file in its plugin directory, so a .bak left beside a plugin
    # becomes a second copy of that plugin in the menu bar.
    local bak
    bak="$STATE/backups/$(basename "$dst").bak.hyperspace.$STAMP"
    if (( DRY )); then
      would "back up existing ${dst/#$HOME/\~} -> ${bak/#$HOME/\~}"
    else
      mkdir -p "$STATE/backups"
      mv "$dst" "$bak"
      printf 'backup\t%s\t%s\n' "$dst" "$bak" >> "$MANIFEST"
      note "backed up existing ${dst/#$HOME/\~} -> $(basename "$bak")"
    fi
  fi
  if (( DRY )); then
    would "link ${dst/#$HOME/\~} -> ${src/#$REPO/<repo>}"
  else
    mkdir -p "$(dirname "$dst")"
    ln -sfn "$src" "$dst"
    printf 'link\t%s\n' "$dst" >> "$MANIFEST"
    log "linked ${dst/#$HOME/\~}"
  fi
}

# aerospace.toml is GENERATED from aerospace.base.toml plus whichever plugins
# are enabled, so it has to be built before it can be linked.
log "Building aerospace.toml from the base config + enabled plugins"
if (( DRY )); then
  would "write $REPO/config/aerospace/aerospace.toml (generated, gitignored)"
else
  "$REPO/bin/build-config"
fi

link "$REPO/config/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"
link "$REPO/config/swiftbar/aerospace.10s.sh" "$HOME/.config/swiftbar/aerospace.10s.sh"
link "$REPO/config/borders/bordersrc" "$HOME/.config/borders/bordersrc"

# Scripts the config and you both call by a stable path, so aerospace.toml
# never has to know where the repo lives.
link "$REPO/bin/cheatsheet-toggle" "$HOME/.local/bin/hyperspace-cheatsheet"
link "$REPO/bin/close-window" "$HOME/.local/bin/hyperspace-close"
link "$REPO/bin/doctor" "$HOME/.local/bin/hyperspace-doctor"
link "$REPO/bin/restart" "$HOME/.local/bin/hyperspace-restart"
link "$REPO/bin/menubar" "$HOME/.local/bin/hyperspace-menubar"
link "$REPO/bin/plugin" "$HOME/.local/bin/hyperspace-plugin"
link "$REPO/bin/plugin-ui" "$HOME/.local/bin/hyperspace-plugins"

# --- 3. Karabiner: merge one rule into whatever you already have ------------
log "Adding the Caps Lock -> Super rule to your existing karabiner.json"
if (( DRY )); then
  would "back up ~/.config/karabiner/karabiner.json beside itself (.bak.hyperspace.<stamp>)"
  would "insert ONE rule named 'Caps Lock -> Super' at the front of the active profile"
  would "leave every other rule you have exactly as it is"
else
  "$REPO/bin/karabiner-rule" install --rule "$REPO/config/karabiner/caps-to-super.json"
fi

# Karabiner watches this file, but a stale user server will READ it without
# APPLYING it - the log shows "Load ...karabiner.json..." with no
# "core_configuration is updated" after it, and core_service_daemon_client
# refusing to connect with "Permission denied". Every key remap silently does
# nothing until the agents are restarted. Kick them so the rule takes effect.
log "Restarting Karabiner agents so the rule actually applies"
if (( DRY )); then
  would "launchctl kickstart the Karabiner Core Service and Console User Server"
else
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
fi

# --- 4. Menu bar auto-hide --------------------------------------------------
# This is what actually lets windows use the full display height: with the menu
# bar auto-hidden macOS reports visibleFrame as the FULL screen, so AeroSpace
# tiles all of it. With the bar visible, macOS clamps windows out of that strip
# and no gap setting can reclaim it.
record_default() { # domain key
  if [[ -f "$MANIFEST" ]] && grep -q "^default $1 $2 " "$MANIFEST"; then return 0; fi
  local t v
  if v="$(defaults read "$1" "$2" 2>/dev/null)"; then
    if (( DRY )); then would "record current $1 $2 = $v, so uninstall can restore it"; return 0; fi
    t="$(defaults read-type "$1" "$2" 2>/dev/null | awk '{print $3}')"
    printf 'default %s %s %s %s\n' "$1" "$2" "${t:-string}" "$v" >> "$MANIFEST"
  else
    if (( DRY )); then would "record that $1 $2 is unset, so uninstall can unset it again"; return 0; fi
    printf 'default %s %s ABSENT ABSENT\n' "$1" "$2" >> "$MANIFEST"
  fi
}

set_default() { # domain key type value
  record_default "$1" "$2"
  if (( DRY )); then
    would "defaults write $1 $2 $3 $4"
  else
    defaults write "$1" "$2" "$3" "$4"
  fi
}

set_default NSGlobalDomain _HIHideMenuBar -bool true
(( DRY )) || killall cfprefsd 2>/dev/null || true
log "Menu bar set to auto-hide (windows reclaim the 30pt strip)"

# --- 5. SwiftBar plugin directory -------------------------------------------
set_default com.ameba.SwiftBar PluginDirectory -string "$HOME/.config/swiftbar"
log "SwiftBar plugin directory -> ~/.config/swiftbar"

# --- 6. Launch at login -----------------------------------------------------
# SwiftBar registers its login item through SMAppService, which only the app
# itself can call. A LaunchAgent that opens it at login does the same job with
# nothing resident. AeroSpace and borders handle their own.
log "Registering login agent for SwiftBar"
if (( DRY )); then
  would "write ~/Library/LaunchAgents/com.hyperspace.swiftbar.plist (RunAtLoad, no KeepAlive)"
  would "launchctl bootstrap that agent"
else
  "$REPO/bin/login-agent" install SwiftBar
fi

# --- 7. Start everything ----------------------------------------------------
# AeroSpace LAST and always restarted: it does not recompute screen geometry
# when the menu bar visibility changes, so it must start after step 4.
log "Starting services"
if (( DRY )); then
  would "brew services start FelixKratz/formulae/borders"
  would "open SwiftBar"
  would "restart AeroSpace (killall, then open)"
else
  brew services start FelixKratz/formulae/borders >/dev/null 2>&1 || warn "borders service failed to start"
  open -a SwiftBar 2>/dev/null || warn "SwiftBar failed to launch"
  killall AeroSpace 2>/dev/null || true
  sleep 2
  open -a AeroSpace 2>/dev/null || warn "AeroSpace failed to launch"
fi

if (( DRY )); then
  cat <<EOF

$(printf '\033[1;35mDRY RUN complete.\033[0m') Nothing was changed.

Never touched, in either mode: your shell config, any Homebrew package on
teardown, and any file not listed above. Run ./install.sh to apply, and
./uninstall.sh to put every listed change back.
EOF
  exit 0
fi

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
\`bin/login-agent uninstall SwiftBar\` first or it launches twice.

Homebrew packages are NOT removed by uninstall.sh, by design. See README.
EOF
