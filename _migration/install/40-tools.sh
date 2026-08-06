#!/usr/bin/env bash
#
# 40-tools.sh — the handful of tools that are not in apt.
#
# lazygit and zoxide ship tarballs for Linux, so we pull the release archive
# and install the single binary. The release tag is resolved dynamically via
# the GitHub API + jq, the same pattern 20-node.sh uses for fnm. pipx apps
# come from PyPI.
#
# zoxide also publishes a .deb, but apt's zoxide is stale and mixing a
# hand-fetched .deb into apt's database is worse than dropping the static musl
# binary next to lazygit. The `zoxide init zsh` line in zsh/.zshrc is currently
# commented out, so a missing binary would not break shell startup — but `z`
# and `zi` silently vanish, which is exactly the kind of thing an ad-hoc install
# gets wrong on a rebuild. It belongs in the bootstrap.
#
# herdr has no tarball worth unpacking by hand: its installer picks the right
# release asset and installs to ~/.local/bin, so we shell out to it.
#
# Go goes to ~/.local/go from the upstream tarball, not apt: noble's golang-go
# trails several major versions. zsh/.zshrc puts ~/.local/go/bin on PATH and
# `herdr plugin install` only COMPILES a cloned plugin (herdr-plus) when go is
# on PATH — without it you silently get an upstream prebuilt binary instead.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PIPX_APPS=(sqlit-tui sshtunnel)
GO_INSTALL_DIR="$HOME/.local/go"

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

install_zoxide() {
	if have zoxide; then
		ok "zoxide already installed ($(zoxide --version 2>/dev/null | head -1))"
		return 0
	fi
	if [[ $DRY_RUN == 1 ]]; then
		warn "would install zoxide to /usr/local/bin"
		return 0
	fi
	local tag ver tmp url
	log "resolving latest zoxide release tag"
	tag=$(curl -fsSL https://api.github.com/repos/ajeetdsouza/zoxide/releases/latest | jq -r .tag_name)
	[[ -n $tag && $tag != null ]] || die "could not resolve the latest zoxide release"
	ver="${tag#v}"
	ok "latest zoxide release: $tag"

	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	url="https://github.com/ajeetdsouza/zoxide/releases/download/${tag}/zoxide-${ver}-x86_64-unknown-linux-musl.tar.gz"

	log "downloading $url"
	curl -fsSL -o "$tmp/zoxide.tar.gz" "$url" || die "failed to download zoxide release asset: $url"

	log "installing zoxide $ver"
	tar -xzf "$tmp/zoxide.tar.gz" -C "$tmp" zoxide || die "failed to extract zoxide release asset"
	[[ -f "$tmp/zoxide" ]] || die "zoxide binary missing from release asset"
	sudo install -m 0755 "$tmp/zoxide" /usr/local/bin/zoxide

	rm -rf "$tmp"
	trap - EXIT
	ok "zoxide $(zoxide --version 2>/dev/null | head -1)"
}

install_herdr() {
	if have herdr; then
		ok "herdr already installed ($(herdr --version 2>/dev/null | head -1))"
		return 0
	fi
	if [[ $DRY_RUN == 1 ]]; then
		warn "would install herdr to ~/.local/bin"
		return 0
	fi
	# herdr's own installer resolves the latest release and drops the single
	# static binary in ~/.local/bin — no sudo, no apt entry, and it is the
	# only supported install path on Linux besides brew/nix/cargo.
	log "installing herdr"
	curl -fsSL https://herdr.dev/install.sh | sh || die "herdr installer failed"
	have herdr || die "herdr not on PATH after install (~/.local/bin)"
	ok "herdr $(herdr --version 2>/dev/null | head -1)"
}

install_go() {
	if [[ -x "$GO_INSTALL_DIR/bin/go" ]]; then
		ok "go already installed ($("$GO_INSTALL_DIR/bin/go" version 2>/dev/null))"
		return 0
	fi
	if [[ $DRY_RUN == 1 ]]; then
		warn "would install the Go toolchain to $GO_INSTALL_DIR"
		return 0
	fi
	local ver tmp url
	# go.dev/VERSION?m=text returns the release name on the first line, e.g.
	# "go1.26.5", followed by a build timestamp we do not want.
	log "resolving the latest Go release"
	ver=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)
	[[ $ver == go[0-9]* ]] || die "could not resolve the latest Go release (got: '$ver')"
	ok "latest Go release: $ver"

	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	url="https://go.dev/dl/${ver}.linux-amd64.tar.gz"

	log "downloading $url"
	curl -fsSL -o "$tmp/go.tar.gz" "$url" || die "failed to download the Go tarball: $url"

	# The tarball's top-level directory is "go", so extract to ~/.local and let
	# it land as ~/.local/go. A stale tree must go first: Go's tarball is not
	# self-cleaning and leftovers from an older release break the build cache.
	log "installing Go to $GO_INSTALL_DIR"
	rm -rf "$GO_INSTALL_DIR"
	mkdir -p "$(dirname "$GO_INSTALL_DIR")"
	tar -xzf "$tmp/go.tar.gz" -C "$(dirname "$GO_INSTALL_DIR")" ||
		die "failed to extract the Go tarball"
	[[ -x "$GO_INSTALL_DIR/bin/go" ]] || die "go binary missing after extraction"

	rm -rf "$tmp"
	trap - EXIT
	ok "$("$GO_INSTALL_DIR/bin/go" version)"
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
	# Parse plain `pipx list`, not `pipx list --short`: --short only exists from
	# pipx 1.1 and the old `|| true` turned an "unrecognized arguments" error
	# into an empty string, which made every app look absent and re-ran the
	# install on every pass. The full output carries `package <name> <version>`
	# lines on every version that matters.
	local installed app
	installed=$(pipx list 2>/dev/null || true)
	for app in "${PIPX_APPS[@]}"; do
		if grep -qE "(^|[[:space:]])package ${app} " <<<"$installed"; then
			ok "pipx app present: $app"
		else
			log "pipx install $app"
			pipx install "$app"
		fi
	done
}

install_lazygit
install_zoxide
install_herdr
install_go
install_pipx_apps
