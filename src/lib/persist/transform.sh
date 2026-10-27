#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_TRANSFORM_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_TRANSFORM_LOADED=1

transform_default_sensitive() {
  printf '%s' "ssh sudo su vault gpg pass op ssh-add openssl"
}

transform_expand_path() {
  local path="${1}" home="${2}" host="${3:-}" tilde='~'
  case "${path}" in
    "${tilde}") path="${home}" ;;
    "${tilde}/"*) path="${home}/${path#"${tilde}/"}" ;;
  esac
  path=${path//"\$HOME"/"${home}"}
  path=${path//"\$HOSTNAME"/"${host}"}
  printf '%s' "${path}"
}

transform_rewrite_path() {
  local path="${1}" old="${2}" new="${3}"
  if [[ -z "${old}" || "${old}" == "${new}" ]]; then
    printf '%s' "${path}"
    return 0
  fi
  if [[ "${path}" == "${old}" ]]; then
    printf '%s' "${new}"
    return 0
  fi
  if [[ "${path}" == "${old}/"* ]]; then
    printf '%s%s' "${new}" "${path#"${old}"}"
    return 0
  fi
  printf '%s' "${path}"
  return 0
}

transform_shell_quote() {
  local rest="${1}" out=""
  while [[ "${rest}" == *\'* ]]; do
    out="${out}${rest%%\'*}'\\''"
    rest="${rest#*\'}"
  done
  printf "'%s%s'" "${out}" "${rest}"
}

transform_is_sensitive() {
  local cmd="${1}" list="${2}" entry
  local -a entries
  [[ -z "${cmd}" ]] && return 1
  read -ra entries <<< "${list}"
  for entry in "${entries[@]}"; do
    # shellcheck disable=SC2053
    [[ "${cmd}" == ${entry} ]] && return 0
  done
  return 1
}

transform_keep_session() {
  local candidate="${1}" filter="${2:-}"
  [[ -z "${filter}" || "${candidate}" == "${filter}" ]] && return 0
  return 1
}

export -f transform_default_sensitive
export -f transform_rewrite_path
export -f transform_expand_path
export -f transform_shell_quote
export -f transform_is_sensitive
export -f transform_keep_session
