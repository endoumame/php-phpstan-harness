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

mapfile -t direct < <(jq -r '
  [ .tool_input.file_path?, .tool_input.path?, .tool_input.target_file? ]
  | map(select(. != null and . != ""))
  | .[]
' <<< "$input" 2>/dev/null || true)
files+=("${direct[@]}")

# apply_patch: extract paths from the patch body in tool_input.input.
patch_body="$(jq -r '.tool_input.input // .tool_input.patch // empty' <<< "$input" 2>/dev/null || true)"
if [ -n "$patch_body" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] && files+=("$path")
  done < <(printf '%s\n' "$patch_body" | sed -nE 's/^\*\*\* (Update|Add|Move) File: (.+)$/\2/p')
fi

# De-duplicate and keep only PHP files outside vendor/.
declare -A seen=()
targets=()
for f in "${files[@]:-}"; do
  [ -z "$f" ] && continue
  case "$f" in
    *.php) ;;
    *) continue ;;
  esac
  case "$f" in
    vendor/*|*/vendor/*) continue ;;
  esac
  [ -n "${seen[$f]:-}" ] && continue
  seen[$f]=1
  [ -f "$f" ] || continue
  targets+=("$f")
done

[ "${#targets[@]}" -eq 0 ] && exit 0

diag=""
for file in "${targets[@]}"; do
  # Auto-fix with phpcbf (exit code 1 means fixes were applied — ignore).
  vendor/bin/phpcbf --standard=phpcs.xml "$file" >/dev/null 2>&1 || true

  phpcs_out="$(vendor/bin/phpcs --standard=phpcs.xml "$file" 2>&1 | head -20)" || true
  if echo "$phpcs_out" | grep -qE '(ERROR|WARNING)'; then
    diag="${diag:+$diag$'\n'}$phpcs_out"
  fi

  phpstan_out="$(vendor/bin/phpstan analyse --no-progress "$file" 2>&1 | tail -20)" || true
  if echo "$phpstan_out" | grep -qiE '(error|warning|--.*Line)'; then
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
