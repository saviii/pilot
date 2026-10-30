#!/bin/sh
# Before Claude finishes a turn that changed Swift or the project, run `make verify`.
# A failure sends Claude back to fix it (exit 2). Skipped in cloud sessions (no Xcode).
input=$(cat)
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && exit 0
command -v xcodebuild >/dev/null || exit 0
cd "$CLAUDE_PROJECT_DIR" || exit 0

# Only when something that verify checks has changed since the last commit.
git status --porcelain -- '*.swift' project.yml PilotKit .swift-format | grep -q . || exit 0

# Second stop in a row after a failure: let it through rather than loop forever.
if [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ]; then
  exit 0
fi

if ! out=$(make verify 2>&1); then
  printf 'make verify failed. Fix it before finishing:\n\n%s\n' "$(printf '%s' "$out" | grep -v IDERunDestination | tail -40)" >&2
  exit 2
fi
exit 0
