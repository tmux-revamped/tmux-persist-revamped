#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_BOOT_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_BOOT_LOADED=1

boot_label_valid() {
	local label="${1:-}"
	[[ "${label}" =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]] && return 0
	return 1
}

boot_agent_path() {
	local os="${1}" home="${2}" label="${3}"
	case "${os}" in
	Darwin) printf '%s/Library/LaunchAgents/%s.plist' "${home}" "${label}" ;;
	*) printf '%s/.config/systemd/user/%s.service' "${home}" "${label}" ;;
	esac
}

boot_plist() {
	local label="${1}" bin="${2}" args="${3}" arg
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
	printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
	printf '%s\n' '<plist version="1.0">'
	printf '%s\n' '<dict>'
	printf '  <key>Label</key>\n  <string>%s</string>\n' "${label}"
	printf '%s\n' '  <key>ProgramArguments</key>'
	printf '%s\n' '  <array>'
	printf '    <string>%s</string>\n' "${bin}"
	for arg in ${args}; do
		printf '    <string>%s</string>\n' "${arg}"
	done
	printf '%s\n' '  </array>'
	printf '%s\n' '  <key>RunAtLoad</key>'
	printf '%s\n' '  <true/>'
	printf '%s\n' '</dict>'
	printf '%s\n' '</plist>'
}

boot_unit() {
	local bin="${1}" args="${2}"
	printf '%s\n' '[Unit]'
	printf '%s\n' 'Description=tmux server'
	printf '%s\n' ''
	printf '%s\n' '[Service]'
	printf '%s\n' 'Type=forking'
	printf 'ExecStart=%s %s\n' "${bin}" "${args}"
	printf 'ExecStop=%s kill-server\n' "${bin}"
	printf '%s\n' 'KillMode=none'
	printf '%s\n' 'RemainAfterExit=yes'
	printf '%s\n' ''
	printf '%s\n' '[Install]'
	printf '%s\n' 'WantedBy=default.target'
}

export -f boot_label_valid
export -f boot_agent_path
export -f boot_plist
export -f boot_unit
