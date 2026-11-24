#!/usr/bin/env bash
# Install the status light: copy the script into ~/.claude/hooks and merge the
# four hooks into ~/.claude/settings.json, preserving everything already there.
# Re-running replaces only this project's hook entries.
set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT="$HOOKS_DIR/claude-bulb.sh"

mkdir -p "$HOOKS_DIR"
install -m 755 "$(dirname "$0")/claude-bulb.sh" "$SCRIPT"
echo "installed $SCRIPT"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak"

SCRIPT="$SCRIPT" python3 - "$SETTINGS" <<'PY'
import collections, json, os, sys

path = sys.argv[1]
script = os.environ["SCRIPT"]

with open(path) as f:
    cfg = json.load(f, object_pairs_hook=collections.OrderedDict)

mapping = {
    "SessionStart":     "ready",    # session open, nothing running yet
    "UserPromptSubmit": "busy",     # red: working
    "Stop":             "ready",    # green: done
    "Notification":     "waiting",  # amber: blocked on you
}

hooks = cfg.setdefault("hooks", collections.OrderedDict())
for event, state in mapping.items():
    entries = hooks.setdefault(event, [])
    # Drop any previous entry of ours so re-installing stays idempotent.
    for group in entries:
        group["hooks"] = [h for h in group.get("hooks", [])
                          if "claude-bulb.sh" not in str(h.get("command", ""))]
    entries[:] = [g for g in entries if g.get("hooks")]
    entries.append(collections.OrderedDict([
        ("hooks", [collections.OrderedDict([
            ("type", "command"),
            ("command", f"{script} {state}"),
            ("async", True),
            ("timeout", 5),
        ])]),
    ]))

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY

python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS"
echo "merged hooks into $SETTINGS (backup at $SETTINGS.bak)"
echo
echo "Set your bulb's address, then test:"
echo "  export CLAUDE_BULB_IP=10.0.0.42"
echo "  $SCRIPT ready"
