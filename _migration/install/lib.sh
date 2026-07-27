#!/usr/bin/env bash
#
# lib.sh — shared helpers for the bootstrap modules.
#
# This file is SOURCED, never executed. It must have no side effects at source
# time beyond defining variables and functions, so that sourcing it twice (or
# from a module run standalone) is harmless.
#
# shellcheck shell=bash

# _migration/install/lib.sh -> _migration -> repo root
MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # consumed by bootstrap.sh and later modules
REPO_ROOT="$(cd "$MIGRATION_DIR/.." && pwd)"
STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.local/state/dotfiles-bootstrap}"
DRY_RUN="${DRY_RUN:-0}"

# shellcheck disable=SC2034
if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'
	C_BLUE=$'\033[34m'
	C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'
	C_RED=$'\033[31m'
	C_BOLD=$'\033[1m'
else
	C_RESET='' C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_BOLD=''
fi

log() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok() { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf '%sFAIL%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
heading() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

have() { command -v "$1" >/dev/null 2>&1; }

# apt_install <pkg>... — install only the packages not already present.
apt_install() {
	local pkg missing=()
	for pkg in "$@"; do
		if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
			missing+=("$pkg")
		fi
	done
	if ((${#missing[@]} == 0)); then
		ok "apt: nothing to do (${#} packages already installed)"
		return 0
	fi
	log "apt: installing ${missing[*]}"
	if [[ $DRY_RUN == 1 ]]; then
		ok "apt: DRY_RUN, skipped"
		return 0
	fi
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
}

step_done() { [[ -f "$STATE_DIR/$1" ]]; }

mark_step_done() {
	[[ $DRY_RUN == 1 ]] && return 0
	mkdir -p "$STATE_DIR"
	: >"$STATE_DIR/$1"
}

# backup_file <path> [suffix] — move a real file/dir aside. Symlinks and
# missing paths are left alone (a symlink is assumed to be ours already).
backup_file() {
	local f="$1" suffix="${2:-.pre-stow}"
	[[ -e $f && ! -L $f ]] || return 0
	if [[ $DRY_RUN == 1 ]]; then
		warn "would back up $f -> ${f}${suffix}"
		return 0
	fi
	warn "backing up $f -> ${f}${suffix}"
	mv -- "$f" "${f}${suffix}"
}

# win_home — the Windows user profile as a WSL path. cmd.exe must be invoked
# from a Windows-visible cwd or it warns on stderr, hence the cd.
#
# $WIN_HOME, if set to an existing directory, is used verbatim and takes
# precedence over interop detection.
#
# Otherwise this also queries %USERNAME%. When WSL interop runs under a
# non-interactive token, %USERPROFILE% resolves to some other account (seen
# in the wild: an elevated admin profile) while %USERNAME% comes back empty
# or as SYSTEM. That combination makes the interop answer UNTRUSTED, so it is
# rejected here rather than handed to the caller as a confident result.
win_home() {
	local raw user path

	if [[ -n ${WIN_HOME:-} && -d ${WIN_HOME} ]]; then
		printf '%s\n' "$WIN_HOME"
		return 0
	fi

	raw=$(cd /mnt/c 2>/dev/null && cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n') || return 1
	[[ -n $raw ]] || return 1
	user=$(cd /mnt/c 2>/dev/null && cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n')
	if [[ -z $user || ${user,,} == system ]]; then
		return 1
	fi
	path=$(wslpath -u "$raw" 2>/dev/null) || return 1
	[[ -d $path ]] || return 1
	printf '%s\n' "$path"
}
