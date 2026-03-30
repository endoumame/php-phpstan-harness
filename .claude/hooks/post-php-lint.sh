#!/bin/bash
set -euo pipefail

input="$(cat)"
file="$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<< "$input")"

# Only process PHP files
case "$file" in
  *.php) ;;
  *) exit 0 ;;
esac

cd "$CLAUDE_PROJECT_DIR"

# Auto-fix with phpcbf (suppress errors — exit code 1 means fixes were applied)
vendor/bin/phpcbf --standard=phpcs.xml "$file" >/dev/null 2>&1 || true

# PHPCS: check for remaining violations
diag=""
phpcs_out="$(vendor/bin/phpcs --standard=phpcs.xml "$file" 2>&1 | head -20)" || true
if echo "$phpcs_out" | grep -qE '(ERROR|WARNING)'; then
  diag="$phpcs_out"
fi

# PHPStan: analyze the file
phpstan_out="$(vendor/bin/phpstan analyse --no-progress "$file" 2>&1 | head -20)" || true
if echo "$phpstan_out" | grep -qE '(Error|--.*Line)'; then
  diag="$diag"$'\n'"$phpstan_out"
fi

if [ -n "$diag" ]; then
  jq -Rn --arg msg "$diag" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }'
fi
