#!/bin/bash
set -e
source "$STABLEBAR_SCRIPTS/environment.sh"
battery=$(pmset -g batt)
percentage=$(echo "$battery" | sed -nE 's/.*[[:space:]]([0-9]+)%.*/\1/p')
if [ -z "$percentage" ]; then
  echo '{"text":"","hidden":true}'
  exit
fi
case "$percentage" in
  9[0-9]|100) icon=battery.100percent ;;
  [6-8][0-9]) icon=battery.75percent ;;
  [3-5][0-9]) icon=battery.50percent ;;
  [1-2][0-9]) icon=battery.25percent ;;
  *) icon=battery.0percent ;;
esac
[[ "$battery" == *"AC Power"* ]] && icon=bolt.batteryblock
jq -cn --arg text "$percentage%" --arg icon "$icon" --arg tooltip "$battery" '{text:$text,icon:$icon,tooltip:$tooltip}'
