#!/usr/bin/env bash
#
# 55-herdr-plugins.sh — install the herdr plugins that config.toml already
# binds keys to, and link the ones this repo ships itself.
#
# herdr/.config/herdr/config.toml declares two `plugin_action` bindings for
# cloudmanic.herdr-plus, and this repo tracks that plugin's project templates
# under herdr/.config/herdr/plugins/config/cloudmanic.herdr-plus/. But the
# plugin itself is a cloned-and-compiled Go program under
# ~/.config/herdr/plugins/github/, which is deliberately NOT tracked here. So
# on a fresh box the keybindings exist, the templates exist, and
# `herdr plugin list` says "No plugins installed" — the bindings just do
# nothing, with no error to point at.
#
# Runs after 50-stow.sh: config.toml and the plugin config dir must be linked
# in first, and 50-stow.sh is what forces ~/.config/herdr/plugins to be a real
# directory. Installing before that would leave herdr writing the 9MB clone
# into a folded symlink, i.e. straight into this repo's working tree.
#
# This repo also ships its own plugins under _plugins/ (currently even-panes,
# which keeps a tab's panes equally sized). Those are never published, so they
# are linked from the working tree rather than installed from GitHub.
#
# `herdr plugin install` builds the plugin with `sh scripts/build.sh`, which
# needs go on PATH. 40-tools.sh installs the toolchain to ~/.local/go but its
# PATH export does not survive into this process, so it is re-established here.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# plugin_id<space>source — the id is what `herdr plugin list` reports and what
# config.toml's plugin_action commands are namespaced under.
PLUGINS=(
	"cloudmanic.herdr-plus cloudmanic/herdr-plus"
)

if [[ $DRY_RUN == 1 ]]; then
	warn "would install herdr plugins: ${PLUGINS[*]}"
	warn "would link local herdr plugins from $REPO_ROOT/_plugins/"
	exit 0
fi

export PATH="$HOME/.local/go/bin:$PATH"
have herdr || die "herdr not on PATH — run 40-tools.sh first"
have go || warn "go not on PATH — herdr will fall back to an upstream prebuilt binary"

installed=$(herdr plugin list 2>/dev/null || true)
for entry in "${PLUGINS[@]}"; do
	read -r id source <<<"$entry"
	if grep -q "$id" <<<"$installed"; then
		ok "herdr plugin already installed: $id"
		continue
	fi
	# --yes is required: the install prints a manifest preview and prompts, and
	# stdin is not a terminal here.
	log "installing herdr plugin $source"
	herdr plugin install "$source" --yes >/dev/null ||
		warn "could not install $source — retry by hand: herdr plugin install $source"
done

# Local plugins live in _plugins/ and are never published, so they are linked
# straight out of the working tree - `herdr plugin link` records that absolute
# path, which is why this must run against the repo the machine will keep using.
for manifest in "$REPO_ROOT"/_plugins/*/herdr-plugin.toml; do
	[[ -e $manifest ]] || continue
	dir=$(dirname "$manifest")
	id=$(sed -n 's/^id = "\(.*\)"/\1/p' "$manifest" | head -1)
	if [[ -n $id ]] && grep -q "$id" <<<"$installed"; then
		ok "herdr plugin already linked: $id"
		continue
	fi
	log "linking herdr plugin $dir"
	herdr plugin link "$dir" >/dev/null ||
		warn "could not link $dir - retry by hand: herdr plugin link $dir"
done

herdr plugin list 2>/dev/null | grep -q 'plugin installed' ||
	warn "no herdr plugins installed — the plugin_action keybindings in config.toml will do nothing"

ok "herdr plugins done"
