#!/bin/sh
# After Claude edits a Swift file, format it, so `make lint` never fails on style.
file=$(jq -r '.tool_input.file_path // empty')
case "$file" in
  *.swift) command -v swift >/dev/null && swift format --in-place "$file" 2>/dev/null ;;
esac
exit 0
