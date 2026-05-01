#!/bin/bash
# PreToolUse hook (Codex): block edits to protected config files.
# Protected files should not be modified to work around linter/formatter issues.
set -euo pipefail

input="$(cat)"

files=()

while IFS= read -r path; do
  [ -n "$path" ] && files+=("$path")
done < <(
  jq -r '
    [ .tool_input.file_path?, .tool_input.path?, .tool_input.target_file? ]
    | map(select(. != null and . != ""))
    | .[]
  ' <<< "$input" 2>/dev/null || true
)

patch_body="$(jq -r '
  def patch_from_command:
    (
      .tool_input.command?
      // (.tool_input.arguments? | strings | fromjson? | .command?)
      // empty
    )
    | if type == "array" then .[1] // empty
      elif type == "string" then .
      else empty
      end;

  patch_from_command // .tool_input.input // .tool_input.patch // empty
' <<< "$input" 2>/dev/null || true)"
if [ -n "$patch_body" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] && files+=("$path")
  done < <(printf '%s\n' "$patch_body" | sed -nE 's/^\*\*\* (Update|Add|Move|Delete) File: (.+)$/\2/p')
fi

PROTECTED="phpstan.neon phpcs.xml phpunit.xml composer.lock .env"

for FILE in "${files[@]:-}"; do
  [ -z "$FILE" ] && continue
  for p in $PROTECTED; do
    case "$FILE" in
      *"$p"*)
        echo "BLOCKED: $FILE is a protected config file. Fix the code, not the linter/formatter config." >&2
        exit 2
        ;;
    esac
  done
done
