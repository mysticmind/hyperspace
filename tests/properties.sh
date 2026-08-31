#!/usr/bin/env bash
# The security properties, as tests.
#
# Every claim the README makes about what hyperspace will not do is checked
# here, so they stay true instead of merely being true on the day they were
# written. A property nobody tests is a property that quietly stops holding.
#
# Runs anywhere: no macOS, no Homebrew, no install required. That is deliberate,
# so CI on any runner can enforce it.
#
# Usage: tests/properties.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

pass=0 fail=0
ok()  { printf '  \033[1;32mok\033[0m    %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); }

# Tracked files only. An untracked scratch file is not what anyone installs.
files() { git ls-files; }

# Skip this file when scanning: it necessarily contains the patterns it bans.
scan() { git ls-files | grep -v '^tests/properties.sh$'; }

echo "Security properties"

# 1. Never asks for root. A tiling window manager has no business with sudo,
#    and a user who is asked for a password has no way to know what for.
if scan | xargs grep -nE '(^|[^a-zA-Z_-])(sudo|doas)( |$)' 2>/dev/null | grep -v '^\s*#' | grep -q .; then
  bad "found sudo/doas"
  scan | xargs grep -nE '(^|[^a-zA-Z_-])(sudo|doas)( |$)' 2>/dev/null | sed 's/^/        /'
else
  ok "no sudo, no doas, nothing asks for a password"
fi

# 2. Never touches the network at runtime. Homebrew does, in install.sh, and
#    that is the user's own package manager acting on a Brewfile they can read.
#    Nothing else may fetch anything.
if scan | grep -vE '^(README\.md|Brewfile|SECURITY\.md)$' \
   | xargs grep -nE '(^|[;&|(`$ ])(curl|wget|nc|ncat|telnet|scp|sftp|rsync)( |$)' 2>/dev/null | grep -q .; then
  bad "found a network client"
  scan | grep -vE '^(README\.md|Brewfile|SECURITY\.md)$' \
    | xargs grep -nE '(^|[;&|(`$ ])(curl|wget|nc|ncat|telnet|scp|sftp|rsync)( |$)' 2>/dev/null | sed 's/^/        /'
else
  ok "no curl, wget, nc or any other fetcher outside the docs"
fi

# 3. Nothing is piped into a shell, and nothing is eval'd. This is the pattern
#    that turns any compromised download into arbitrary code, and there is no
#    download here to compromise. Keep it that way.
# Prose is excluded, as in check 2: SECURITY.md documents this ban and would
# otherwise trip it. Markdown is not executed, so describing the pattern there
# is not the same as containing it.
code() { scan | grep -vE '\.md$'; }
if code | xargs grep -nE 'curl[^|]*\| *(ba)?sh|\beval\b|python[0-9.]* -c .*exec\(' 2>/dev/null | grep -q .; then
  bad "found eval or a pipe-to-shell"
  code | xargs grep -nE 'curl[^|]*\| *(ba)?sh|\beval\b|python[0-9.]* -c .*exec\(' 2>/dev/null | sed 's/^/        /'
else
  ok "no eval, nothing piped into a shell"
fi

# 4. Design rule 1: never touch shell config. The repo is not a dotfiles
#    manager and must never write to a file that runs on every login shell.
if scan | grep -vE '^(README\.md|install\.sh|SECURITY\.md)$' \
   | xargs grep -nE '(>|>>|tee|sed -i).*\.(zshrc|bashrc|bash_profile|zprofile|profile)' 2>/dev/null | grep -q .; then
  bad "something writes to a shell config"
else
  ok "nothing writes to .zshrc, .bashrc or any shell profile"
fi

# 5. Design rule 2: teardown removes no Homebrew package. uninstall.sh may
#    print the commands, never run them.
# Heredoc bodies are stripped first. uninstall.sh PRINTS the brew commands for
# the user to run themselves, and a check that cannot tell printing from doing
# would fail on the very design rule it is meant to protect.
strip_heredocs() { # file
  awk '
    heredoc != "" { if ($0 == heredoc) heredoc = ""; next }
    match($0, /<<-?['"'"'"]?[A-Za-z_][A-Za-z_0-9]*['"'"'"]?/) {
      d = substr($0, RSTART, RLENGTH)
      sub(/^<<-?/, "", d); gsub(/['"'"'"]/, "", d)
      heredoc = d; next
    }
    { print FILENAME ":" NR ":" $0 }
  ' "$1"
}
if strip_heredocs uninstall.sh | grep -E '^[^#]*brew (uninstall|remove|rm)' | grep -q .; then
  bad "uninstall.sh RUNS a brew uninstall (printing them is fine, running is not)"
  strip_heredocs uninstall.sh | grep -E '^[^#]*brew (uninstall|remove|rm)' | sed 's/^/        /'
else
  ok "uninstall.sh removes no Homebrew package (it only prints the commands)"
fi

# 6. Every mutation in install.sh is behind the dry-run flag. This is what
#    makes --dry-run trustworthy rather than decorative: if a write is added
#    without a guard, the listing silently stops matching what runs.
unguarded=0
while IFS=: read -r lineno text; do
  # Mutating verbs, outside comments.
  case "$text" in \#*|*'|| true'*) continue ;; esac
  unguarded=$((unguarded+1))
  printf '        install.sh:%s %s\n' "$lineno" "${text# }"
done < <(awk '
  /^\s*#/            { next }
  /DRY/              { next }
  /^\s*(defaults write|ln -sfn|launchctl (bootstrap|kickstart)|brew (bundle|services)|killall|open -a)/ {
    print NR ":" $0
  }' install.sh)
if (( unguarded )); then
  bad "install.sh has $unguarded mutation(s) not visibly guarded by DRY"
else
  ok "every mutation in install.sh sits behind the dry-run guard"
fi

# 7. LaunchAgents may launch, never persist. KeepAlive would make it a daemon,
#    which is the thing this repo promises not to install.
# The plist KEY, not the word. bin/login-agent's own comment says "no
# KeepAlive", and matching prose rather than the key would fail on a file that
# is documenting the very property being checked.
if scan | xargs grep -n '<key>KeepAlive</key>' 2>/dev/null | grep -q .; then
  bad "a LaunchAgent sets KeepAlive, which makes it a daemon"
  scan | xargs grep -n '<key>KeepAlive</key>' 2>/dev/null | sed 's/^/        /'
else
  ok "no LaunchAgent sets KeepAlive, so nothing stays resident"
fi

echo
printf 'properties: %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
