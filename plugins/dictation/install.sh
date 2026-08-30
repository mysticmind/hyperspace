#!/usr/bin/env bash
# Handy is in TOGGLE mode (push_to_talk = false). That is deliberate: Handy has
# one global mode, not one per binding, so it cannot offer hold and toggle at
# the same time. Toggle mode plus a Karabiner rule that sends the chord on BOTH
# key-down and key-up gives us push-to-talk on top, and both behaviours coexist.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STATE="$HOME/.local/state/hyperspace/karabiner-dictation.json"

# Handy must be in toggle mode or the emulation double-fires.
HANDY="$HOME/Library/Application Support/com.pais.handy/settings_store.json"
if [[ -f "$HANDY" ]]; then
  python3 - "$HANDY" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
if d["settings"].get("push_to_talk") is not False:
    d["settings"]["push_to_talk"] = False
    p.write_text(json.dumps(d, indent=2))
    print("  handy: push_to_talk -> false (toggle mode; PTT is emulated)")
else:
    print("  handy: already in toggle mode")
b = d["settings"]["bindings"]["transcribe"]["current_binding"]
if b != "fn+f19":
    print(f"  WARNING: Handy's transcribe binding is '{b}', these rules send fn+f19.")
    print("           Set it to fn+F19 in Handy > Settings > Bindings.")
PY
else
  echo "  WARNING: Handy settings not found — is handy.computer installed?"
fi

"$REPO/bin/karabiner-rule" install --rule "$HERE/karabiner-rules.json" --state "$STATE"

# Karabiner reads the file without applying it if the user server is stale.
for svc in Karabiner-Core-Service-rev2 Karabiner-Console-User-Server; do
  launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.$svc" 2>/dev/null || true
done
