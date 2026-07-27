#!/usr/bin/env bash
#
# 60-tmux.sh — install tpm and all tmux plugins headlessly.
#
# tpm lives at ~/.config/tmux/plugins/tpm, which resolves inside the repo (that
# path is a stowed symlink) and is gitignored via /tmux/.config/tmux/plugins.
# install_plugins needs a tmux server with our config loaded, hence the
# start-server + source-file dance.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMUX_CONF="$HOME/.config/tmux/tmux.conf"
TPM_DIR="$HOME/.config/tmux/plugins/tpm"

have tmux || die "tmux not installed — run 00-apt.sh first"
[[ -e $TMUX_CONF ]] || die "$TMUX_CONF missing — run 50-stow.sh first"

if [[ $DRY_RUN == 1 ]]; then
	warn "would clone tpm to $TPM_DIR and install plugins"
	exit 0
fi

if [[ -d "$TPM_DIR/.git" ]]; then
	ok "tpm already cloned"
else
	log "cloning tpm"
	mkdir -p "$(dirname "$TPM_DIR")"
	git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

log "installing tmux plugins"
# TMUX_TMPDIR matches .zshrc, keeping the socket off /tmp.
export TMUX_TMPDIR="${TMUX_TMPDIR:-$HOME/.cache}"
mkdir -p "$TMUX_TMPDIR"
tmux start-server
tmux source-file "$TMUX_CONF"
"$TPM_DIR/bin/install_plugins"
tmux kill-server 2>/dev/null || true
ok "tmux plugins installed"
