#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_AISESSION_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_AISESSION_LOADED=1

aisession_tools() {
  printf '%s' "claude codex opencode copilot crush gemini qwen amp aider"
}

aisession_runtime() {
  case "${1}" in
    node | bun | deno | python | python3 | python3.* | Python) return 0 ;;
    *) return 1 ;;
  esac
}

aisession_script_name() {
  local rest="${1#* }" word
  local -a words
  [[ "${rest}" != "${1}" ]] || return 0
  read -ra words <<< "${rest}"
  for word in "${words[@]}"; do
    [[ "${word}" == -* ]] && continue
    printf '%s' "${word##*/}"
    return 0
  done
}

aisession_tool() {
  local name="${1}" tool
  aisession_runtime "${name}" && name="$(aisession_script_name "${2:-}")"
  for tool in $(aisession_tools); do
    if [[ "${name}" == "${tool}" ]]; then
      printf '%s' "${tool}"
      return 0
    fi
  done
  return 1
}

aisession_claude_dir() {
  printf '%s/sessions' "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
}

aisession_claude_id() {
  local file content re='"sessionId"[[:space:]]*:[[:space:]]*"([0-9A-Za-z-]+)"'
  file="$(aisession_claude_dir)/${1}.json"
  [[ -n "${1}" && -f "${file}" ]] || return 0
  content="$(cat "${file}" 2>/dev/null)"
  [[ "${content}" =~ ${re} ]] && printf '%s' "${BASH_REMATCH[1]}"
  return 0
}

aisession_id() {
  case "${1}" in
    claude) aisession_claude_id "${2:-}" ;;
  esac
  return 0
}

aisession_resume_by_id() {
  case "${1}" in
    claude) printf 'claude --resume %s' "${2}" ;;
    codex) printf 'codex resume %s' "${2}" ;;
    opencode) printf 'opencode --session %s' "${2}" ;;
    copilot) printf 'copilot --resume=%s' "${2}" ;;
    crush) printf 'crush --session %s' "${2}" ;;
    *) aisession_resume_latest "${1}" ;;
  esac
}

aisession_resume_latest() {
  case "${1}" in
    claude | opencode | copilot | crush | qwen) printf '%s --continue' "${1}" ;;
    codex) printf 'codex resume --last' ;;
    gemini) printf 'gemini --resume latest' ;;
    amp) printf 'amp last' ;;
    aider) printf 'aider --restore-chat-history' ;;
    *) printf '%s' "${1}" ;;
  esac
}

aisession_command() {
  local tool="${1}" id="${2:-}"
  if [[ -n "${id}" && "${id}" =~ ^[0-9A-Za-z-]+$ ]]; then
    aisession_resume_by_id "${tool}" "${id}"
  else
    aisession_resume_latest "${tool}"
  fi
}

export -f aisession_tools
export -f aisession_runtime
export -f aisession_script_name
export -f aisession_tool
export -f aisession_claude_dir
export -f aisession_claude_id
export -f aisession_id
export -f aisession_resume_by_id
export -f aisession_resume_latest
export -f aisession_command
