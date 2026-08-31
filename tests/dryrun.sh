#!/usr/bin/env bash
# --dry-run must be inert.
#
# The listing is only worth reading if it is guaranteed not to also DO the
# things it lists. tests/properties.sh checks that every mutation in install.sh
# sits behind the flag by reading the source; this checks the same claim from
# the outside, by taking the machine's state before and after and diffing it.
#
# Safe to run anywhere, including on a machine with hyperspace installed: if
# the flag works, nothing happens, and if it does not, this is how you find out.
#
# Usage: tests/dryrun.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

snapshot() { # outfile
  {
    for pair in "NSGlobalDomain _HIHideMenuBar" "com.ameba.SwiftBar PluginDirectory"; do
      # shellcheck disable=SC2086
      printf '%s = %s\n' "$pair" "$(defaults read $pair 2>/dev/null || echo '<unset>')"
    done
    for f in "$HOME/.config/karabiner/karabiner.json" \
             "$HOME/.local/state/hyperspace/manifest" \
             "$REPO/config/aerospace/aerospace.toml"; do
      if [[ -f "$f" ]]; then
        printf '%s %s\n' "${f/#$HOME/\~}" "$(shasum -a 256 "$f" | awk '{print $1}')"
      else
        printf '%s <absent>\n' "${f/#$HOME/\~}"
      fi
    done
    ls -1 "$HOME/Library/LaunchAgents" 2>/dev/null | sort
    ls -1 "$HOME/.local/bin" 2>/dev/null | sort
    ls -1 "$HOME/.config/aerospace" "$HOME/.config/swiftbar" "$HOME/.config/borders" 2>/dev/null | sort
  } > "$1"
}

snapshot "$WORK/before"
./install.sh --dry-run > "$WORK/out" 2>&1
rc=$?
snapshot "$WORK/after"

fail=0

if (( rc != 0 )); then
  printf '  \033[1;31mFAIL\033[0m  --dry-run exited %d\n' "$rc"
  tail -20 "$WORK/out"
  fail=1
else
  printf '  \033[1;32mok\033[0m    --dry-run exits clean\n'
fi

if diff -u "$WORK/before" "$WORK/after" > "$WORK/diff"; then
  printf '  \033[1;32mok\033[0m    --dry-run changed nothing\n'
else
  printf '  \033[1;31mFAIL\033[0m  --dry-run CHANGED THE MACHINE:\n'
  sed 's/^/        /' "$WORK/diff"
  fail=1
fi

# It has to actually say something, or an install.sh that printed nothing at
# all would pass the inertness check trivially.
if grep -q "would" "$WORK/out"; then
  printf '  \033[1;32mok\033[0m    --dry-run reports what it would do (%d lines)\n' "$(grep -c would "$WORK/out")"
else
  printf '  \033[1;31mFAIL\033[0m  --dry-run listed nothing\n'
  fail=1
fi

exit $fail
