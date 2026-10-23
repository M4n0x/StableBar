#!/bin/zsh

state="$CONFIG_DIR/.control-state"
case "$1" in
    level|enabled|mode|note)
        mkdir -p "$state"
        printf '%s' "$VALUE" > "$state/$1"
        ;;
esac

level=35
enabled=true
mode=balanced
note=""
[[ -f "$state/level" ]] && level="$(< "$state/level")"
[[ -f "$state/enabled" ]] && enabled="$(< "$state/enabled")"
[[ -f "$state/mode" ]] && mode="$(< "$state/mode")"
[[ -f "$state/note" ]] && note="$(< "$state/note")"

cat <<JSON
{
  "text": "$mode · $level%",
  "fields": {"enabled": "$enabled", "mode": "$mode", "note": $(osascript -l JavaScript -e 'function run(argv) { return JSON.stringify(argv[0]) }' "$note")},
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
