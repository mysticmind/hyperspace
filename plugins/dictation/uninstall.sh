#!/usr/bin/env bash
# Removes only our rules. Handy's push_to_talk is left as it is — flipping it
# back would be a guess about what you want, and it is one toggle in Handy.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
"$REPO/bin/karabiner-rule" uninstall --rule "$HERE/karabiner-rules.json" \
  --state "$HOME/.local/state/hyperspace/karabiner-dictation.json"
for svc in Karabiner-Core-Service-rev2 Karabiner-Console-User-Server; do
  launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.$svc" 2>/dev/null || true
done
echo "  Handy's push_to_talk setting left unchanged — flip it in Handy if you want hold-only again."
