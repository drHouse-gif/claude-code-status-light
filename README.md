# Claude Code status light

Turn a Shelly RGBCCT bulb into an at-a-glance status light for a Claude Code
session. The bulb tells you, from across the room, whether the agent is working,
done, or stuck waiting on you.

| Colour | RGB | State | Fired by |
|---|---|---|---|
| red | `255,0,0` | working on your request | `UserPromptSubmit` |
| green | `0,255,0` | finished, ready for the next task | `Stop`, `SessionStart` |
| amber | `255,90,0` | blocked on you: permission prompt, question, or idle | `Notification` |

Amber is deliberately not yellow and not blue. Red and green cover the two
normal states, and amber is the one that means "come back to the terminal", so
it needs to be distinguishable from both in peripheral vision.

Brightness is pinned at 3%. This is an indicator, not room light.

## Why hooks

Claude Code cannot do this on its own initiative. Asking the agent to "change
the bulb when you start working" relies on it remembering to make a tool call
every single turn, and it will drift. Hooks are executed by the harness itself,
on lifecycle events, whether or not the model cooperates. That makes the light
a property of the session rather than a thing the agent has to remember.

The four events used here are the complete set needed to cover the three states:

- `UserPromptSubmit` fires the moment you hit enter, before the model runs.
- `Stop` fires when the main agent finishes its turn. It also fires on clear,
  resume and compact, which is correct: in all of those the agent is idle.
- `Notification` fires when the harness wants your attention, which covers both
  permission prompts and the idle-timeout nudge.
- `SessionStart` seeds the colour so a new session does not inherit a stale red
  from a session that was killed mid-turn.

## The device

Tested on a Shelly RGBCCT Bulb Gen3 (`S3BL-C010007AEU`, app `RGBCCTBulbG3`),
firmware `1.8.99-rgbcctbulbg3prod4`, on the local network with authentication
disabled.

The bulb exposes a single `rgbcct:0` component. Everything here is one call:

```
POST http://<bulb>/rpc
{"id":1,"method":"RGBCCT.Set","params":{"id":0,"on":true,"rgb":[255,0,0],"brightness":3}}
```

Read the current state back with `GET http://<bulb>/rpc/RGBCCT.GetStatus?id=0`.

Any Shelly Gen2+ RGB device works with a change of method name. For a
single-channel dimmer or relay there is no colour to set, so you would blink or
toggle instead.

## How it works

Two pieces, nothing else. No daemon, no polling, no cloud, no Home Assistant.

`claude-bulb.sh` maps a state name to one RPC call:

```bash
claude-bulb.sh busy      # red
claude-bulb.sh ready     # green
claude-bulb.sh waiting   # amber
claude-bulb.sh off
```

Four hook entries in `~/.claude/settings.json` call it with the right argument
on the right event. See `settings.example.json`.

Three details in the script matter more than they look:

1. **The curl is detached.** `( curl ... & )` in a subshell. A hook that blocks
   blocks your session, and a bulb that is unplugged or off-network would
   otherwise add its full timeout to every prompt you submit.
2. **Nothing is written to stdout.** Whatever a `UserPromptSubmit` hook prints
   on stdout is injected into the model's context. A chatty status script would
   quietly pollute every single turn.
3. **An unknown argument exits 0 without acting.** A hook that errors is noisy
   in the UI, so an unrecognised state is a silent no-op.

The hooks are declared `async: true` as well, so the harness does not wait on
them even if the script itself were slow.

## Install

```bash
git clone https://github.com/<you>/claude-code-status-light
cd claude-code-status-light
./install.sh
```

`install.sh` copies the script to `~/.claude/hooks/claude-bulb.sh` and merges
the four hook entries into `~/.claude/settings.json`, leaving anything already
in that file untouched. It backs the file up first and is idempotent, so
re-running it replaces its own entries rather than stacking duplicates.

Then point it at your bulb:

```bash
export CLAUDE_BULB_IP=10.0.0.42          # put this in your shell profile
~/.claude/hooks/claude-bulb.sh ready     # should go green
```

To merge the hooks by hand instead, copy them out of `settings.example.json`
and fix the absolute paths. Relative paths will not work: hooks run with the
project directory as their working directory, which varies per session.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_BULB_IP` | `192.168.1.50` | Bulb address. Set this. |
| `CLAUDE_BULB_BRIGHTNESS` | `3` | Percent. 3 is the device floor, see below. |

To change the colours, edit the three `rgb` triples in the `case` block.

## Verifying it actually fires

A hook that silently does nothing looks identical to a hook that is not
installed, and `Stop` and `UserPromptSubmit` fire outside the agent's own turn,
so neither can be proven from inside one. Two things make it checkable:

Validate the JSON shape per event. Exit 0 and a printed command means the
nesting is right:

```bash
jq -e '.hooks.Stop[] | .hooks[] | select(.type=="command") | .command' ~/.claude/settings.json
```

Then prove the transitions. Set the bulb to a colour no state uses, so the next
change is unambiguous, and log every call:

```bash
# baseline: blue, which no hook sets
curl -s -X POST "http://$CLAUDE_BULB_IP/rpc" -H 'Content-Type: application/json' \
  -d '{"id":1,"method":"RGBCCT.Set","params":{"id":0,"on":true,"rgb":[0,0,255],"brightness":3}}'

# temporarily add as the first line of claude-bulb.sh
echo "$(date +%H:%M:%S) called with: ${1:-<none>}" >> /tmp/claude-bulb-check.txt
```

End the turn and submit a new prompt. The log should show `ready` at the end of
the first turn and `busy` when the next prompt is submitted. Remove the log line
afterwards.

## Notes from building it

- **3% is the floor.** The bulb's `min_brightness_on_toggle` is 3, so lower
  values do not survive. Conveniently that is about right for an indicator.
- **Readbacks lie during the fade.** `transition_duration` defaults to 3
  seconds, so a `GetStatus` issued right after a `Set` returns a brightness
  somewhere mid-ramp. Wait about 1.5 seconds before trusting it. This looks
  exactly like something else fighting you for control of the bulb.
- **`source` in the status is the last writer**, not necessarily you:
  `HTTP_in` for these calls, `WS_in` if something like a Home Assistant
  integration is also connected. Useful for telling the two apart.
- **The settings watcher only watches directories that already had a settings
  file when the session started.** If `~/.claude/settings.json` existed, edits
  are picked up live and the hooks work immediately, with no restart. If you
  created the file for the first time mid-session, the session has to be
  restarted before the hooks load.
- **Hooks run detached from your shell profile.** They do not inherit an
  interactive shell's environment in every setup, so if `CLAUDE_BULB_IP` is not
  being seen, hardcode the address in the script rather than debugging the
  environment.

## Extending

More states are available if you want finer granularity. The harness exposes
roughly thirty hook events, including `SubagentStart` and `SubagentStop`,
`PostToolUse`, `PermissionDenied`, `PreCompact` and `SessionEnd`. The full
authoritative list is in the settings JSON schema. Some natural additions:

- `SessionEnd` to a warm white, so the bulb goes back to being useful as light.
- `PreCompact` to a distinct colour, since compaction can take a while.
- `SubagentStart` to a deeper red when a fan-out is in flight.
