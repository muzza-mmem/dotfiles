#!/usr/bin/env bash
#
# 45-claude-plugins.sh — install the Claude Code plugins that settings.json
# already declares as enabled.
#
# claude/.claude/settings.json carries `enabledPlugins: superpowers@...`, and
# the global CLAUDE.md leans on that plugin's skills by name. But the plugin
# itself lives under ~/.claude/plugins/, which is deliberately NOT tracked in
# this repo (it is a git cache of a marketplace checkout). So on a fresh box the
# flag says enabled and nothing is there — the failure is silent, and shows up
# as skills that simply never trigger.
#
# Runs after 20-node.sh, which is what installs the `claude` CLI. That module's
# PATH export does not survive into this process, so fnm's env is re-established
# here the same way.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MARKETPLACE_REPO=anthropics/claude-plugins-official
MARKETPLACE_NAME=claude-plugins-official
# User-scope plugins only — these apply everywhere. claude-md-management is
# project-scope in ~/code/ai-coding-standards and is left to that repo to declare.
PLUGINS=(superpowers)

if [[ $DRY_RUN == 1 ]]; then
	warn "would add marketplace $MARKETPLACE_REPO and install: ${PLUGINS[*]}"
	exit 0
fi

export PATH="$HOME/.local/share/fnm:$PATH"
if have fnm; then
	eval "$(fnm env --shell bash)"
fi
have claude || die "claude not on PATH — run 20-node.sh first"

# `marketplace add` is idempotent in effect but errors if the marketplace is
# already known, so an existing entry is not a failure.
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
	ok "marketplace already added: $MARKETPLACE_NAME"
else
	log "adding marketplace $MARKETPLACE_REPO"
	claude plugin marketplace add "$MARKETPLACE_REPO" --scope user ||
		warn "could not add the marketplace — install the plugins by hand with /plugin"
fi

installed=$(claude plugin list 2>/dev/null || true)
for p in "${PLUGINS[@]}"; do
	if grep -q "$p" <<<"$installed"; then
		ok "plugin already installed: $p"
		continue
	fi
	log "installing plugin $p"
	claude plugin install "${p}@${MARKETPLACE_NAME}" --scope user ||
		warn "could not install $p — do it interactively: claude, then /plugin"
done

ok "claude plugins done"
