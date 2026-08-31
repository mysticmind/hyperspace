#!/usr/bin/env bash
# Design rule 3, as a test: install then uninstall must leave the machine as it
# was found.
#
# This is the repo's central promise and the one a stranger has least ability to
# check by reading. So: snapshot everything install.sh is capable of touching,
# install, uninstall, snapshot again, diff.
#
# It deliberately snapshots MORE than install.sh writes. A test that only checks
# the files we know about cannot catch the bug worth catching, which is the
# write nobody remembered to record in the manifest.
#
# Destructive by nature: it really installs. Refuses to run unless
# HYPERSPACE_TEST_I_MEAN_IT=1, so it cannot be triggered by accident on a
# machine someone is using. CI sets it; you probably should not, unless the
# machine is disposable.
#
# Usage: HYPERSPACE_TEST_I_MEAN_IT=1 tests/reversible.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

if [[ "${HYPERSPACE_TEST_I_MEAN_IT:-0}" != "1" ]]; then
  cat >&2 <<'EOF'
tests/reversible.sh really installs hyperspace and then uninstalls it.

It will change your Karabiner config, your menu bar setting, your SwiftBar
plugin directory and your login items, and put them all back. If any of that
would ruin your day, do not run it here.

  HYPERSPACE_TEST_I_MEAN_IT=1 tests/reversible.sh
EOF
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Everything install.sh could plausibly reach. Directory listings rather than
# just the files we expect, so a stray file counts as a difference.
snapshot() { # outfile
  {
    echo "--- defaults ---"
    for pair in "NSGlobalDomain _HIHideMenuBar" "com.ameba.SwiftBar PluginDirectory"; do
      # shellcheck disable=SC2086
      printf '%s = %s\n' "$pair" "$(defaults read $pair 2>/dev/null || echo '<unset>')"
    done

    echo "--- karabiner.json ---"
    if [[ -f "$HOME/.config/karabiner/karabiner.json" ]]; then
      # Compared by MEANING, not bytes. karabiner-rule rewrites the file with
      # its own indentation, so a correct uninstall restores the same config in
      # a different layout. Hashing the raw bytes fails that, which is a test
      # calling a working teardown broken. Sorted keys, fixed indent.
      python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True, indent=2))' \
        "$HOME/.config/karabiner/karabiner.json"
    else
      echo "<absent>"
    fi

    echo "--- launch agents ---"
    ls -1 "$HOME/Library/LaunchAgents" 2>/dev/null | sort || true

    echo "--- ~/.local/bin ---"
    ls -1 "$HOME/.local/bin" 2>/dev/null | sort || true

    echo "--- config dirs ---"
    for d in aerospace swiftbar borders karabiner; do
      echo "[$d]"
      ls -1 "$HOME/.config/$d" 2>/dev/null | sort || true
    done

    echo "--- hyperspace state ---"
    [[ -d "$HOME/.local/state/hyperspace" ]] && echo "present" || echo "absent"
  } > "$1"
}

# A machine that has never launched Karabiner-Elements has no karabiner.json,
# and `karabiner-rule install` refuses to invent one. install.sh runs set -e,
# so that stops the whole install - which is why this test could not run on a
# fresh runner. Seed a minimal config, exactly as launching the app once would,
# and the merge-and-restore path becomes testable rather than skipped.
#
# Seeded BEFORE the snapshot on purpose: it then counts as part of the machine's
# original state, so uninstall has to hand it back byte for byte.
KCFG="$HOME/.config/karabiner/karabiner.json"
if [[ ! -f "$KCFG" ]]; then
  echo "==> seeding a minimal karabiner.json (none present)"
  mkdir -p "$(dirname "$KCFG")"
  cat > "$KCFG" <<'KARABINER'
{
    "profiles": [
        {
            "complex_modifications": { "rules": [] },
            "name": "Default profile",
            "selected": true,
            "virtual_hid_keyboard": { "keyboard_type_v2": "ansi" }
        }
    ]
}
KARABINER
fi

echo "==> snapshot before"
snapshot "$WORK/before"

echo "==> install"
if ! ./install.sh > "$WORK/install.log" 2>&1; then
  echo "install failed:" >&2
  tail -30 "$WORK/install.log" >&2
  exit 1
fi

echo "==> uninstall"
if ! ./uninstall.sh > "$WORK/uninstall.log" 2>&1; then
  echo "uninstall failed:" >&2
  tail -30 "$WORK/uninstall.log" >&2
  exit 1
fi

echo "==> snapshot after"
snapshot "$WORK/after"

if diff -u "$WORK/before" "$WORK/after" > "$WORK/diff"; then
  echo
  echo "PASS: the machine is as it was found."
  exit 0
fi

echo
echo "FAIL: uninstall did not restore the machine."
echo "  - lines are the before state, + lines what was left behind:"
echo
cat "$WORK/diff"
exit 1
