#!/bin/sh
# A mode event changes this widget's presence; the theme supplies presentation.
if [ -n "${INFO:-}" ] && [ "$INFO" != main ]; then
  printf '%s\n' '{"text":"Mode","hidden":false}'
else
  printf '%s\n' '{"text":"","hidden":true}'
fi
