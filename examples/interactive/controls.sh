#!/bin/zsh

state="$CONFIG_DIR/.control-state"
case "$1" in
    level|enabled|mode)
        mkdir -p "$state"
        printf '%s' "$VALUE" > "$state/$1"
        ;;
esac

level=35
enabled=true
mode=balanced
[[ -f "$state/level" ]] && level="$(< "$state/level")"
[[ -f "$state/enabled" ]] && enabled="$(< "$state/enabled")"
[[ -f "$state/mode" ]] && mode="$(< "$state/mode")"

cat <<JSON
{
  "text": "$mode · $level%",
  "fields": {"enabled": "$enabled", "mode": "$mode"},
  "values": {"level": $level},
  "lists": {
    "apps": [
      {"name": "Finder", "command": "open -a Finder"},
      {"name": "Calendar", "command": "open -a Calendar"},
      {"name": "Activity Monitor", "command": "open -a 'Activity Monitor'"},
      {"name": "Terminal", "command": "open -a Terminal"}
    ]
  }
}
JSON
