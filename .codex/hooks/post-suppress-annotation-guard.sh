#!/bin/bash
# PostToolUse hook (Codex): forbid @phpstan-ignore and phpcs:ignore in source.
set -euo pipefail

input="$(cat)"

project_dir="$(jq -r '.cwd // empty' <<< "$input")"
if [ -z "$project_dir" ]; then
  project_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
cd "$project_dir"

files=()

mapfile -t direct < <(jq -r '
  [ .tool_input.file_path?, .tool_input.path?, .tool_input.target_file? ]
  | map(select(. != null and . != ""))
  | .[]
' <<< "$input" 2>/dev/null || true)
files+=("${direct[@]}")

patch_body="$(jq -r '.tool_input.input // .tool_input.patch // empty' <<< "$input" 2>/dev/null || true)"
if [ -n "$patch_body" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] && files+=("$path")
  done < <(printf '%s\n' "$patch_body" | sed -nE 's/^\*\*\* (Update|Add|Move) File: (.+)$/\2/p')
fi

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

aggregated=""
for file in "${targets[@]}"; do
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
    aggregated="${aggregated:+$aggregated$'\n\n'}$msg"
  fi
done

if [ -n "$aggregated" ]; then
  jq -Rn --arg msg "$aggregated" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }'
fi
