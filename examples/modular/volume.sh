#!/bin/sh
# Shows the speaker icon, and the volume for a moment after a click or scroll.
volume=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
case "$volume" in
  ''|*[!0-9]*) volume= ;;
esac
if [ "$SENDER" = action ] && [ -n "$volume" ]; then
  printf '{"text":"","temporary":{"fields":{"text":"%s%%"},"duration":1.5}}\n' "$volume"
else
  printf '{"text":""}\n'
fi
