#!/bin/bash
set -euo pipefail

input="$(cat)"
file="$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<< "$input")"

# Only process PHP files
case "$file" in
  *.php) ;;
  *) exit 0 ;;
esac

# Skip vendor files
case "$file" in
  vendor/*|*/vendor/*) exit 0 ;;
esac

[ -f "$file" ] || exit 0

# Check for @phpstan-ignore or phpcs:ignore annotations
found=""
details=""

if matches="$(grep -n '@phpstan-ignore' "$file" 2>/dev/null)"; then
  found="@phpstan-ignore"
  details="$matches"
fi

if matches="$(grep -n 'phpcs:ignore' "$file" 2>/dev/null)"; then
  if [ -n "$found" ]; then
    found="$found and phpcs:ignore"
  else
    found="phpcs:ignore"
  fi
  details="${details:+$details
}$matches"
fi

if [ -n "$found" ]; then
  msg="[POLICY VIOLATION] ${found} annotation(s) detected in ${file}:
${details}

This project PROHIBITS the use of @phpstan-ignore and phpcs:ignore annotations.
You MUST:
1. Remove the ${found} annotation(s) you just wrote
2. Fix the underlying code issue that the annotation was suppressing
3. If the warning is unavoidable due to framework constraints, leave the warning as-is (do NOT suppress it)
Do NOT add @phpstan-ignore or phpcs:ignore to project source code."

  jq -Rn --arg msg "$msg" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }'
fi
