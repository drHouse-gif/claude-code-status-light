#!/usr/bin/env bash
# Claude Code status light on a Shelly RGBCCT bulb.
#
#   busy     red     - working on your request
#   ready    green   - finished, waiting for the next task
#   waiting  amber   - blocked on you (permission prompt / question / idle)
#   off      turn the bulb off
#
# Usage: claude-bulb.sh <busy|ready|waiting|off>
#
# Set CLAUDE_BULB_IP to your bulb's address. Brightness defaults to 3%, which
# is also the device's min_brightness_on_toggle, i.e. the lowest it will go.
# It is an indicator, not room light.

BULB="${CLAUDE_BULB_IP:-192.168.1.50}"
BRIGHTNESS="${CLAUDE_BULB_BRIGHTNESS:-3}"

case "$1" in
  busy)    params="\"on\":true,\"rgb\":[255,0,0],\"brightness\":$BRIGHTNESS"   ;;
  ready)   params="\"on\":true,\"rgb\":[0,255,0],\"brightness\":$BRIGHTNESS"   ;;
  waiting) params="\"on\":true,\"rgb\":[255,90,0],\"brightness\":$BRIGHTNESS"  ;;
  off)     params="\"on\":false"                                              ;;
  *)       exit 0                                                             ;;
esac

# Detached so an unreachable bulb can never stall the hook, and silent because
# anything on stdout of a UserPromptSubmit hook is injected into the model's
# context.
( curl -s -m 2 -X POST "http://$BULB/rpc" \
    -H 'Content-Type: application/json' \
    -d "{\"id\":1,\"method\":\"RGBCCT.Set\",\"params\":{\"id\":0,$params}}" \
    >/dev/null 2>&1 & ) >/dev/null 2>&1

exit 0
