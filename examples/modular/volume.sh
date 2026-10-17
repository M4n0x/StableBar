#!/bin/sh
# Shows the speaker icon, and the volume for a moment after a click, a scroll or any other change.
# On volumeChange, INFO holds the volume, so nothing needs to ask osascript.
if [ "$SENDER" = volumeChange ]; then
  volume=$INFO
else
  volume=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
fi
case "$volume" in
  ''|*[!0-9]*) volume= ;;
esac
if [ -n "$volume" ] && { [ "$SENDER" = action ] || [ "$SENDER" = volumeChange ]; }; then
  printf '{"text":"","temporary":{"fields":{"text":"%s%%"},"duration":1.5}}\n' "$volume"
else
  printf '{"text":""}\n'
fi
