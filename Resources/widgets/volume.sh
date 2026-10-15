#!/bin/bash
set -e
source "$STABLEBAR_SCRIPTS/environment.sh"
IFS=, read -r volume muted < <(osascript -e 'set v to get volume settings' -e 'return (output volume of v as text) & "," & (output muted of v as text)')
case "$volume" in
  [6-9][0-9]|100) icon=speaker.wave.3.fill ;;
  [3-5][0-9]) icon=speaker.wave.2.fill ;;
  [1-9]|[1-2][0-9]) icon=speaker.wave.1.fill ;;
  *) icon=speaker.slash.fill ;;
esac
[ "$muted" = true ] && icon=speaker.slash.fill
jq -cn --arg icon "$icon" --arg tooltip "Volume $volume% · muted: $muted" '{text:"",icon:$icon,tooltip:$tooltip}'
