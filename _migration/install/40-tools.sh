#!/usr/bin/env bash
#
# 40-tools.sh — the handful of tools that are not in apt.
#
# lazygit ships tarballs (not .deb) for Linux, so we pull the release archive
# and install the single binary. The release tag is resolved dynamically via
# the GitHub API + jq, the same pattern 20-node.sh uses for fnm. pipx apps
# come from PyPI.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PIPX_APPS=(sqlit-tui sshtunnel)

install_lazygit() {
	if have lazygit; then
		ok "lazygit already installed ($(lazygit --version 2>/dev/null | head -1))"
		return 0
	fi
	if [[ $DRY_RUN == 1 ]]; then
		warn "would install lazygit to /usr/local/bin"
		return 0
	fi
	local tag ver tmp url
	log "resolving latest lazygit release tag"
	tag=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name)
	[[ -n $tag && $tag != null ]] || die "could not resolve the latest lazygit release"
	ver="${tag#v}"
	ok "latest lazygit release: $tag"

	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	url="https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${ver}_Linux_x86_64.tar.gz"

	log "downloading $url"
	curl -fsSL -o "$tmp/lazygit.tar.gz" "$url" || die "failed to download lazygit release asset: $url"

	log "installing lazygit $ver"
	tar -xzf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit || die "failed to extract lazygit release asset"
	[[ -f "$tmp/lazygit" ]] || die "lazygit binary missing from release asset"
	sudo install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit

	rm -rf "$tmp"
	trap - EXIT
	ok "lazygit $(lazygit --version 2>/dev/null | head -1)"
}

install_pipx_apps() {
	if [[ $DRY_RUN == 1 ]]; then
		warn "would pipx install: ${PIPX_APPS[*]}"
		return 0
	fi
	have pipx || die "pipx not installed — run 00-apt.sh first"
	# `pipx ensurepath` appends an export line to ~/.zshrc — which by now is a
	# symlink into this repo, so it would re-add the exact duplicate PATH line
	# this migration removed from zsh/.zshrc. Skip it when ~/.local/bin is
	# already on PATH (zsh/.zshrc and Ubuntu's ~/.profile both put it there).
	case ":$PATH:" in
	*":$HOME/.local/bin:"*) ok "pipx: ~/.local/bin already on PATH" ;;
	*) pipx ensurepath >/dev/null 2>&1 || true ;;
	esac
	local installed app
	installed=$(pipx list --short 2>/dev/null || true)
	for app in "${PIPX_APPS[@]}"; do
		if grep -q "^${app} " <<<"$installed"; then
			ok "pipx app present: $app"
		else
			log "pipx install $app"
			pipx install "$app"
		fi
	done
}

install_lazygit
install_pipx_apps
