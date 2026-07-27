#!/usr/bin/env bash
#
# 10-shell.sh — oh-my-zsh + make zsh the login shell.
#
# KEEP_ZSHRC=yes matters: without it the installer writes its own ~/.zshrc,
# which then conflicts with the one 50-stow.sh symlinks in from the repo.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

have zsh || die "zsh not installed — run 00-apt.sh first"

if [[ -d "$HOME/.oh-my-zsh" ]]; then
	ok "oh-my-zsh already installed"
elif [[ $DRY_RUN == 1 ]]; then
	warn "would install oh-my-zsh"
else
	log "installing oh-my-zsh (unattended, keeping our .zshrc)"
	RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
		"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

zsh_path="$(command -v zsh)"
current_shell="$(getent passwd "$USER" | cut -d: -f7)"
if [[ $current_shell == "$zsh_path" ]]; then
	ok "login shell already $zsh_path"
elif [[ $DRY_RUN == 1 ]]; then
	warn "would set login shell to $zsh_path (currently $current_shell)"
else
	log "setting login shell to $zsh_path (was $current_shell)"
	sudo chsh -s "$zsh_path" "$USER"
	warn "login shell change applies on next new session"
fi
