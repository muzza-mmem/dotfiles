#!/usr/bin/env bash
#
# 20-node.sh — fnm + node 24 + global npm packages.
#
# fnm replaces nvm deliberately: sourcing nvm.sh costs 300-600ms on every shell
# start, fnm is a static binary doing the same job in ~10ms and still honours
# .nvmrc.
#
# fnm is installed from its GitHub release asset, not the vercel.app install
# script: that domain fails TLS verification on networks with corporate TLS
# interception, and a bare `curl | bash` is worth avoiding anyway. The release
# tag is resolved dynamically via the GitHub API + jq, the same pattern
# 40-tools.sh uses for lazygit.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FNM_INSTALL_DIR="$HOME/.local/share/fnm"
FNM_REPO="Schniz/fnm"
NODE_MAJOR=24
NPM_GLOBALS=(@anthropic-ai/claude-code confluence-cli corepack)

if [[ -x "$FNM_INSTALL_DIR/fnm" ]]; then
	ok "fnm already installed at $FNM_INSTALL_DIR"
elif [[ $DRY_RUN == 1 ]]; then
	warn "would install fnm to $FNM_INSTALL_DIR"
else
	log "resolving latest fnm release tag"
	fnm_tag=$(curl -fsSL "https://api.github.com/repos/$FNM_REPO/releases/latest" | jq -r '.tag_name')
	[[ -n $fnm_tag && $fnm_tag != null ]] || die "could not resolve latest fnm release tag"
	ok "latest fnm release: $fnm_tag"

	fnm_tmp="$(mktemp -d)"
	trap 'rm -rf "$fnm_tmp"' EXIT
	fnm_zip="$fnm_tmp/fnm-linux.zip"
	fnm_url="https://github.com/$FNM_REPO/releases/download/$fnm_tag/fnm-linux.zip"

	log "downloading $fnm_url"
	curl -fsSL -o "$fnm_zip" "$fnm_url" || die "failed to download fnm release asset: $fnm_url"

	log "installing fnm to $FNM_INSTALL_DIR"
	mkdir -p "$FNM_INSTALL_DIR"
	unzip -oq "$fnm_zip" -d "$fnm_tmp" || die "failed to unzip fnm release asset"
	[[ -f "$fnm_tmp/fnm" ]] || die "fnm binary missing from release asset"
	install -m 0755 "$fnm_tmp/fnm" "$FNM_INSTALL_DIR/fnm"

	rm -rf "$fnm_tmp"
	trap - EXIT
	ok "fnm $fnm_tag installed at $FNM_INSTALL_DIR"
fi

if [[ $DRY_RUN == 1 ]]; then
	warn "would install node $NODE_MAJOR and npm globals: ${NPM_GLOBALS[*]}"
	exit 0
fi

export PATH="$FNM_INSTALL_DIR:$PATH"
have fnm || die "fnm not on PATH after install"
eval "$(fnm env --shell bash)"

if fnm list | grep -qE "v${NODE_MAJOR}\."; then
	ok "node $NODE_MAJOR already installed"
else
	log "installing node $NODE_MAJOR"
	fnm install "$NODE_MAJOR"
fi
fnm default "$NODE_MAJOR"
fnm use "$NODE_MAJOR"
ok "node $(node -v), npm $(npm -v)"

for pkg in "${NPM_GLOBALS[@]}"; do
	if npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then
		ok "npm global present: $pkg"
	else
		log "npm install -g $pkg"
		npm install -g "$pkg"
	fi
done
