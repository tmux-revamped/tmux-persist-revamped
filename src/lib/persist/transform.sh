#!/usr/bin/env bash
#
# transform.sh: pure value transforms applied during restore and capture.
#
# - path rewrite makes a save host-portable: a directory recorded under one home
#   is replayed under the current home.
# - sensitive detection lets capture skip a pane running ssh, sudo, or a secret
#   tool so its scrollback is never written to disk.
# - the session keep test backs selective merge restore: load one project without
#   touching the rest.
#
# No tmux and no files here; the dispatcher supplies the values.

[[ -n "${_PERSIST_REVAMPED_TRANSFORM_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_TRANSFORM_LOADED=1

# transform_default_sensitive -> the built-in list of commands whose pane content
# is never captured. Glob entries are allowed.
transform_default_sensitive() {
  printf '%s' "ssh sudo su vault gpg pass op ssh-add openssl"
}

# transform_expand_path PATH HOME HOSTNAME -> PATH with a leading tilde, and any
# occurrence of $HOME or $HOSTNAME, replaced by the given values. A tmux option is
# stored verbatim, so a directory written as "~/state" reaches the plugin as four
# literal characters and names nothing. Expanding here lets the option be written
# the way a path is normally written, and lets one config give each host its own
# save directory.
transform_expand_path() {
  local path="${1}" home="${2}" host="${3:-}" tilde='~'
  case "${path}" in
    "${tilde}") path="${home}" ;;
    "${tilde}/"*) path="${home}/${path#"${tilde}/"}" ;;
  esac
  path="${path//\$HOME/${home}}"
  path="${path//\$HOSTNAME/${host}}"
  printf '%s' "${path}"
}

# transform_rewrite_path PATH OLD NEW -> PATH with a leading OLD replaced by NEW,
# only at a path boundary so "/home/old" never rewrites "/home/older". When OLD is
# empty, OLD equals NEW, or PATH does not start with OLD, PATH is returned as is.
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

# transform_shell_quote VALUE -> VALUE wrapped in single quotes, with any single
# quote inside it closed, escaped, and reopened. A restored directory is typed into
# a live shell, so a path holding a space, a quote, or a glob character reaches the
# shell as one word instead of several. The form is understood by every shell the
# strategy allows, including fish and csh, which do not accept a "--" separator.
transform_shell_quote() {
  local value="${1}"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

# transform_is_sensitive CMD LIST -> success when CMD matches a glob in LIST, so its
# scrollback must not be captured. An empty CMD never matches.
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

# transform_keep_session CANDIDATE FILTER -> success when a record for session
# CANDIDATE should be restored. An empty FILTER keeps every session; otherwise only
# the session that equals FILTER is kept. This is the selective merge gate.
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
