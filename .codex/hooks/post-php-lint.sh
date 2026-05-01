#!/bin/bash
# PostToolUse hook (Codex): run phpcbf/phpcs/phpstan on edited PHP files.
set -euo pipefail

input="$(cat)"

project_dir="$(jq -r '.cwd // empty' <<< "$input")"
if [ -z "$project_dir" ]; then
  project_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
cd "$project_dir"

# Collect candidate file paths from common tool_input shapes.
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

# apply_patch: extract paths from the patch body in tool_input.input.
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
  done < <(printf '%s\n' "$patch_body" | sed -nE 's/^\*\*\* (Update|Add|Move) File: (.+)$/\2/p')
fi

# De-duplicate and keep only PHP files outside vendor/.
targets=()
has_target() {
  local needle="$1"
  local existing
  for existing in "${targets[@]:-}"; do
    [ "$existing" = "$needle" ] && return 0
  done
  return 1
}

for f in "${files[@]:-}"; do
  [ -z "$f" ] && continue
  case "$f" in
    *.php) ;;
    *) continue ;;
  esac
  case "$f" in
    vendor/*|*/vendor/*) continue ;;
  esac
  [ -f "$f" ] || continue
  has_target "$f" && continue
  targets+=("$f")
done

[ "${#targets[@]}" -eq 0 ] && exit 0

diag=""
for file in "${targets[@]}"; do
  # Auto-fix with phpcbf (exit code 1 means fixes were applied — ignore).
  vendor/bin/phpcbf --standard=phpcs.xml "$file" >/dev/null 2>&1 || true

  if phpcs_out="$(vendor/bin/phpcs --standard=phpcs.xml "$file" 2>&1)"; then
    phpcs_rc=0
  else
    phpcs_rc=$?
  fi
  if [ "$phpcs_rc" -ne 0 ]; then
    diag="${diag:+$diag$'\n'}$phpcs_out"
  fi

  if phpstan_out="$(vendor/bin/phpstan analyse --no-progress "$file" 2>&1)"; then
    phpstan_rc=0
  else
    phpstan_rc=$?
  fi
  if [ "$phpstan_rc" -ne 0 ]; then
    diag="${diag:+$diag$'\n'}$phpstan_out"
  fi
done

if [ -n "$diag" ]; then
  jq -Rn --arg msg "$diag" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }'
fi
