#!/usr/bin/env bash
#
# 00-apt.sh — refresh apt and install every apt-sourced package.
#
# The font and lib block at the end is what headless Chromium needs (Puppeteer
# / Playwright in the portal repos). Package names are Ubuntu 24.04 (noble):
# several ABI-renamed to *t64 vs 22.04.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "refreshing package lists"
[[ $DRY_RUN == 1 ]] || sudo apt-get update -qq

log "upgrading installed packages"
[[ $DRY_RUN == 1 ]] || sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log "core tooling"
apt_install \
	ca-certificates curl wget unzip gnupg build-essential \
	git gh \
	zsh tmux stow \
	jq htop tree nmap netcat-openbsd pandoc mkcert screen \
	ripgrep fd-find fzf zoxide pipx shellcheck

log "headless Chromium runtime (fonts + libs)"
apt_install \
	fonts-liberation fonts-freefont-ttf fonts-noto-color-emoji \
	fonts-ipafont-gothic fonts-wqy-zenhei fonts-unifont \
	xfonts-cyrillic xfonts-scalable xvfb \
	libnss3 libnss3-tools libnspr4 \
	libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
	libcups2t64 libdrm2 libgbm1 libasound2t64 \
	libpango-1.0-0 libcairo2 libglib2.0-0t64 \
	libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 \
	libxfixes3 libxrandr2 libxkbcommon0 libwayland-client0

# Debian/Ubuntu ship fd as `fdfind` to avoid a name clash. Everything (and
# nvim's telescope config) expects `fd`.
if have fdfind && ! have fd; then
	mkdir -p "$HOME/.local/bin"
	ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
	ok "linked fdfind -> ~/.local/bin/fd"
fi

ok "apt packages installed"
