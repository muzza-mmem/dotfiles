#!/usr/bin/env bash
#
# 90-wsl.sh — install /etc/wsl.conf and the Windows-side .wslconfig.
#
# Neither file takes effect until `wsl --shutdown` runs from Windows. This
# script prints that instruction rather than attempting it: the shutdown would
# kill the script (and the rest of the bootstrap) mid-run.
#
# The Windows profile is resolved via win_home() in lib.sh. %USERPROFILE% is
# unreliable when WSL interop runs under a non-interactive token (seen as
# %USERNAME%=SYSTEM) — in that case win_home() refuses to guess. Set WIN_HOME
# to override, e.g.: WIN_HOME=/mnt/c/Users/<you> ./bootstrap.sh 90
#
# The [user] default in wsl/wsl.conf is validated against this distro's accounts
# first: installing a wsl.conf that names a nonexistent user locks you out of
# the distro after the shutdown, so that case dies loudly instead.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SRC_WSL_CONF="$MIGRATION_DIR/wsl/wsl.conf"
SRC_WSLCONFIG="$MIGRATION_DIR/wsl/.wslconfig"

[[ -f $SRC_WSL_CONF ]] || die "missing $SRC_WSL_CONF"
[[ -f $SRC_WSLCONFIG ]] || die "missing $SRC_WSLCONFIG"

# --- validate [user] default --------------------------------------------
#
# wsl.conf names the account WSL logs in as. If that account does not exist on
# THIS distro, the next `wsl --shutdown` leaves a distro that cannot open a
# session at all — recovery needs `wsl -u root` from Windows. So the name is
# checked against the local passwd database before the file is installed.
wsl_conf_default_user() {
	awk '
		/^[[:space:]]*\[/ { in_user = ($0 ~ /^[[:space:]]*\[user\]/); next }
		in_user && /^[[:space:]]*default[[:space:]]*=/ {
			sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*(#.*)?$/, "")
			print
		}
	' "$SRC_WSL_CONF" | tail -1
}

conf_user="$(wsl_conf_default_user)"
if [[ -z $conf_user ]]; then
	ok "wsl.conf sets no [user] default — WSL will pick the first account"
elif id -u -- "$conf_user" >/dev/null 2>&1; then
	ok "wsl.conf [user] default '$conf_user' exists on this distro"
else
	die "wsl.conf would set [user] default = '$conf_user', which does not exist
on this distro. Installing it and running \`wsl --shutdown\` would lock you out
of the distro (recovery: \`wsl -u root -d <distro>\` from Windows).

Fix: edit $SRC_WSL_CONF and set

    [user]
    default = ${USER:-$(id -un)}

then re-run: ./bootstrap.sh 90"
fi

# --- /etc/wsl.conf -------------------------------------------------------
if [[ $DRY_RUN == 1 ]]; then
	warn "would write /etc/wsl.conf from $SRC_WSL_CONF"
else
	if [[ -f /etc/wsl.conf ]] && sudo cmp -s "$SRC_WSL_CONF" /etc/wsl.conf; then
		ok "/etc/wsl.conf already up to date"
	else
		if [[ -f /etc/wsl.conf ]]; then
			log "backing up /etc/wsl.conf -> /etc/wsl.conf.bak"
			sudo cp -a /etc/wsl.conf /etc/wsl.conf.bak
		fi
		log "writing /etc/wsl.conf"
		sudo install -m 0644 "$SRC_WSL_CONF" /etc/wsl.conf
		ok "/etc/wsl.conf installed"
	fi
fi

# --- Windows .wslconfig --------------------------------------------------
if ! wh="$(win_home)"; then
	warn "could not reliably resolve the Windows user profile."
	warn "Either cmd.exe interop is unavailable, or it reported an untrusted"
	warn "identity (%USERNAME% empty or SYSTEM) — common when WSL interop"
	warn "runs under a non-interactive token; %USERPROFILE% then points at"
	warn "the wrong account."
	warn "Candidate profiles under /mnt/c/Users:"
	found_candidate=0
	if [[ -d /mnt/c/Users ]]; then
		for cand in /mnt/c/Users/*/; do
			cand="${cand%/}"
			name="$(basename "$cand")"
			case "$name" in
			Public | Default | "Default User" | "All Users" | desktop.ini) continue ;;
			esac
			[[ -d $cand ]] || continue
			warn "  $cand"
			found_candidate=1
		done
	fi
	((found_candidate)) || warn "  (none found)"
	warn "Copy this file to <your-profile>\\.wslconfig by hand:"
	warn "  $SRC_WSLCONFIG"
	warn "Or re-run with the override once you know the right account:"
	warn "  WIN_HOME=/mnt/c/Users/<your-account> ./bootstrap.sh 90"
else
	dest="$wh/.wslconfig"
	if [[ $DRY_RUN == 1 ]]; then
		warn "would write $dest from $SRC_WSLCONFIG"
	else
		if [[ -f $dest ]] && cmp -s "$SRC_WSLCONFIG" "$dest"; then
			ok "$dest already up to date"
		else
			if [[ -f $dest ]]; then
				log "backing up $dest -> ${dest}.bak"
				cp -a "$dest" "${dest}.bak"
			fi
			log "writing $dest"
			install -m 0644 "$SRC_WSLCONFIG" "$dest"
			ok ".wslconfig installed to $dest"
		fi
	fi
	log "Windows .wslconfig destination: $dest"
fi

warn "NEITHER file is active yet. From Windows PowerShell, run:  wsl --shutdown"
