#!/usr/bin/env bash
# Back to a normal Mac.
#
# What this does NOT do, deliberately: it does not uninstall a single Homebrew
# package. A teardown script that removes your window manager because it also
# installed it is a trap. The removal commands are printed at the end instead,
# so you run them only if you mean to.
set -uo pipefail

STATE="$HOME/.local/state/hyperspace"
MANIFEST="$STATE/manifest"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# --- 1. Stop the stack ------------------------------------------------------
log "Stopping services"
brew services stop FelixKratz/formulae/borders >/dev/null 2>&1 || true
# Quitting AeroSpace hands every window it was managing back to macOS.
osascript -e 'quit app "AeroSpace"' 2>/dev/null || killall AeroSpace 2>/dev/null || true
osascript -e 'quit app "SwiftBar"' 2>/dev/null || killall SwiftBar 2>/dev/null || true

# --- 1a. Plugins ------------------------------------------------------------
# Disable every enabled plugin first: that runs their uninstall.sh hooks and
# unlinks any menu bar plugins they added.
if [[ -f "$HOME/.local/state/hyperspace/enabled-plugins" ]]; then
  while read -r pl; do
    [[ -n "$pl" ]] && "$REPO/bin/plugin" disable "$pl" >/dev/null 2>&1 || true
  done < "$HOME/.local/state/hyperspace/enabled-plugins"
  log "Disabled all plugins"
fi

# Scripts we linked into ~/.local/bin, only when they still point at this repo.
#
# Globbed rather than listed. A hardcoded list rots every time a command is
# added: hyperspace-plugins, hyperspace-restart and hyperspace-menubar were all
# added after the list was written and none of them were being removed, which
# made uninstall quietly incomplete. The `$REPO/*` test is what keeps this safe:
# a same-named link of yours pointing elsewhere is left alone.
for f in "$HOME/.local/bin"/hyperspace-*; do
  [[ -L "$f" ]] || continue
  t="$(readlink "$f" 2>/dev/null || true)"
  case "$t" in "$REPO"/*) rm -f "$f"; log "removed ${f/#$HOME/\~}" ;; esac
done

# --- 1b. Login agents -------------------------------------------------------
# Ice is no longer part of hyperspace, but older installs registered an agent
# for it. Keep it in the uninstall list so those get cleaned up too.
"$REPO/bin/login-agent" uninstall SwiftBar Ice 2>/dev/null || true

# --- 2. Unlink configs, restore what we displaced ---------------------------
# Only paths the manifest records as OURS are touched.
if [[ -f "$MANIFEST" ]]; then
  while IFS=$'\t' read -r kind dst _; do
    [[ "$kind" == "link" ]] || continue
    if [[ -L "$dst" ]]; then
      target="$(readlink "$dst")"
      case "$target" in
        "$REPO"/*) rm "$dst"; log "unlinked ${dst/#$HOME/\~}" ;;
        *) log "left alone (not ours): ${dst/#$HOME/\~}" ;;
      esac
    fi
  done < "$MANIFEST"

  # A symlink we displaced comes back before a plain backup does.
  while IFS=$'\t' read -r kind dst prior; do
    [[ "$kind" == "prior-symlink" ]] || continue
    [[ -e "$dst" ]] && continue
    ln -sfn "$prior" "$dst"; log "relinked ${dst/#$HOME/\~} -> $prior"
  done < "$MANIFEST"

  while IFS=$'\t' read -r kind dst bak; do
    [[ "$kind" == "backup" ]] || continue
    # never clobber something recreated since
    [[ -e "$dst" || ! -e "$bak" ]] && continue
    mv "$bak" "$dst"; log "restored ${dst/#$HOME/\~}"
  done < "$MANIFEST"
fi

# --- 3. Karabiner: pull out just our rule -----------------------------------
"$REPO/bin/karabiner-rule" uninstall 2>/dev/null || true

# --- 4. Restore recorded defaults -------------------------------------------
if [[ -f "$MANIFEST" ]]; then
  grep '^default ' "$MANIFEST" 2>/dev/null | while read -r _ domain key type value; do
    if [[ "$type" == "ABSENT" ]]; then
      defaults delete "$domain" "$key" 2>/dev/null || true
      log "unset $domain $key (was unset before hyperspace)"
    else
      case "$type" in
        boolean) defaults write "$domain" "$key" -bool "$value" ;;
        integer) defaults write "$domain" "$key" -int "$value" ;;
        float)   defaults write "$domain" "$key" -float "$value" ;;
        *)       defaults write "$domain" "$key" -string "$value" ;;
      esac
      log "restored $domain $key = $value"
    fi
  done
fi
killall cfprefsd 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

rm -rf "$STATE"

cat <<'EOF'

Done. Left in place on purpose:

  - Every Homebrew package. Remove them yourself if you want them gone:
      brew services stop FelixKratz/formulae/borders
      brew uninstall borders
      brew uninstall --cask aerospace swiftbar
      # karabiner-elements is deliberately NOT in that list - you probably
      # had it before, and other rules of yours may depend on it.

  - The repo itself. Delete the directory when you are done with it.

  - Accessibility / Input Monitoring entries in System Settings -> Privacy.
    macOS lets no script remove those. They are inert once the apps are gone.

  - "Launch at Login" for SwiftBar, if you enabled it. Turn it off in the app,
    or in System Settings -> General -> Login Items.

  - /Applications/Ice.app, if an older hyperspace installed it. It is no longer
    part of this setup: `rm -rf /Applications/Ice.app` if you want it gone.

The menu bar returns on the next login if it has not already.
EOF
