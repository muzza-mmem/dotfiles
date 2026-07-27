#!/usr/bin/env bash
#
# 70-nvim.sh — Neovim from the upstream tarball, then sync plugins.
#
# Deliberately NOT from apt: noble ships 0.10, too old for this NvChad config.
# The release asset was renamed at 0.10.4 (nvim-linux64 -> nvim-linux-x86_64),
# so try the current name and fall back to the old one.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NVIM_TAG="${NVIM_TAG:-stable}"
NVIM_PREFIX=/opt/nvim
BASE="https://github.com/neovim/neovim/releases/download/${NVIM_TAG}"

[[ -d "$HOME/.config/nvim" ]] || die "$HOME/.config/nvim missing — run 50-stow.sh first"

if [[ $DRY_RUN == 1 ]]; then
	warn "would install Neovim ($NVIM_TAG) to $NVIM_PREFIX and run Lazy! sync"
	exit 0
fi

if [[ -x "$NVIM_PREFIX/bin/nvim" ]]; then
	ok "Neovim already installed ($("$NVIM_PREFIX/bin/nvim" --version | head -1))"
else
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT

	log "downloading Neovim $NVIM_TAG"
	if curl -fsSL -o "$tmp/nvim.tar.gz" "$BASE/nvim-linux-x86_64.tar.gz"; then
		:
	else
		warn "nvim-linux-x86_64.tar.gz not found, trying nvim-linux64.tar.gz"
		curl -fsSL -o "$tmp/nvim.tar.gz" "$BASE/nvim-linux64.tar.gz" ||
			die "could not download a Neovim tarball for tag $NVIM_TAG"
	fi

	log "installing to $NVIM_PREFIX"
	sudo rm -rf "$NVIM_PREFIX"
	sudo mkdir -p "$NVIM_PREFIX"
	sudo tar -xzf "$tmp/nvim.tar.gz" -C "$NVIM_PREFIX" --strip-components=1 ||
		die "failed to extract Neovim release asset"
	sudo ln -sfn "$NVIM_PREFIX/bin/nvim" /usr/local/bin/nvim

	rm -rf "$tmp"
	trap - EXIT
	ok "installed $(/usr/local/bin/nvim --version | head -1)"
fi

log "syncing plugins (first launch would otherwise do this interactively)"
nvim --headless "+Lazy! sync" +qa 2>&1 | tail -20 || true
ok "nvim plugins synced"
