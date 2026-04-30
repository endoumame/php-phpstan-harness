#!/bin/bash
# UserPromptSubmit hook (Codex): block prompts containing API keys or tokens.
set -euo pipefail

input="$(cat)"
prompt="$(jq -r '.prompt // .user_prompt // empty' <<< "$input")"

if echo "$prompt" | grep -qiE '(sk-[a-zA-Z0-9]{20,}|xoxb-|ghp_|AKIA[A-Z0-9]{16})'; then
  echo '{"decision":"block","reason":"⚠️ API キーやトークンが含まれています。1Password などで管理してください。"}'
fi
