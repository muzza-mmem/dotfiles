#!/usr/bin/env bash
#
# smoke-test.sh — report on the state of a bootstrapped machine.
#
# Run by bootstrap.sh at the end, and safe to run standalone at any time:
#
#   ./_migration/smoke-test.sh
#
# Exits non-zero if any check fails, so the caller can flag it. Checks are
# independent — one failure never stops the rest.
#
set -uo pipefail # NOT -e: every check must run
# shellcheck source=install/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install/lib.sh"

pass=0 fail=0

check() { # check <label> <command...>
	local label="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		ok "$label"
		pass=$((pass + 1))
	else
		warn "FAIL: $label"
		fail=$((fail + 1))
	fi
}

check_version() { # check_version <cmd>
	local cmd="$1" v
	if ! have "$cmd"; then
		warn "FAIL: $cmd not on PATH"
		fail=$((fail + 1))
		return
	fi
	# first_line strips leading WARNING/NOTICE chatter before taking line 1 —
	# `az --version` opens with "WARNING: You have N update(s) available",
	# which would otherwise be reported as the version string.
	first_line() { grep -vE '^(WARNING|NOTICE|DEPRECAT)' | grep -m1 . || true; }
	# `go` has no --version/-V flag at all; it is a `version` subcommand. Try
	# that too rather than reporting "(version unavailable)" for a healthy tool.
	if v=$("$cmd" --version 2>&1); then
		v=$(printf '%s\n' "$v" | first_line)
	elif v=$("$cmd" -V 2>&1); then
		v=$(printf '%s\n' "$v" | first_line)
	elif v=$("$cmd" version 2>&1); then
		v=$(printf '%s\n' "$v" | first_line)
	else
		v="(version unavailable)"
	fi
	[[ -n $v ]] || v="(version unavailable)"
	ok "$(printf '%-10s %s' "$cmd" "$v")"
	pass=$((pass + 1))
}

is_symlink_into_repo() { # is_symlink_into_repo <path>
	local p="$1" target
	[[ -L $p ]] || return 1
	target=$(readlink -f "$p") || return 1
	[[ $target == "$REPO_ROOT"/* ]]
}

heading "Commands on PATH"
for c in zsh tmux nvim git gh stow fnm node npm codex docker az lazygit herdr go fzf zoxide rg fd jq pipx; do
	check_version "$c"
done

heading "Stowed config"
# Config DIRECTORIES are deliberately real directories, not folded Stow
# symlinks (see REAL_DIRS in install/50-stow.sh), so the per-directory probe
# targets a file the package owns inside it. That is the stronger assertion
# anyway: it fails both when nothing is linked and when stow folded the parent.
for p in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.config/nvim/init.lua" \
	"$HOME/.config/tmux/tmux.conf" "$HOME/.config/herdr/config.toml" \
	"$HOME/.config/git/config" "$HOME/.claude/settings.json" "$HOME/.local/bin/ss"; do
	check "symlink into repo: ${p/#$HOME/\~}" is_symlink_into_repo "$p"
done

heading "Docker"
check "docker daemon reachable" docker info
check "docker group membership" bash -c 'id -nG "$USER" | tr " " "\n" | grep -qx docker'
check "hello-world runs" docker run --rm hello-world

heading "Neovim plugins"
check "Lazy! check exits clean" nvim --headless "+Lazy! check" +qa

heading "Claude Code plugins"
# settings.json declares superpowers as enabled; this catches the case where the
# flag is set but the marketplace checkout was never installed (see 45-*.sh).
check "superpowers plugin installed" \
	bash -c 'claude plugin list 2>/dev/null | grep -q superpowers'

heading "Repos"
manifest="$MIGRATION_DIR/repos.tsv"
if [[ -f $manifest ]]; then
	while IFS=$'\t' read -r name _; do
		[[ -z ${name// /} || $name == \#* ]] && continue
		# shellcheck disable=SC2088 # literal ~ is the intended display label, not path expansion
		check "~/code/$name" test -d "$HOME/code/$name"
	done <"$manifest"
else
	warn "FAIL: $manifest missing"
	fail=$((fail + 1))
fi

heading "Secrets (presence only — contents never checked)"
for f in "$HOME/.ssh/id_ed25519" "$HOME/.config/secrets" "$HOME/.npmrc"; do
	check "exists: ${f/#$HOME/\~}" test -s "$f"
done
check "npmrc has a token" bash -c 'grep -qE "_authToken=.+" "$HOME/.npmrc"'
# ~/.npmrc holds `_authToken=${NODE_AUTH_TOKEN}`, so the check above passes on a
# placeholder that expands to nothing if secrets was never filled in — which
# reads as configured but 401s on the first @mmem install. Resolve it for real.
check "npm resolves the @mmem scope" bash -c '
	source "$HOME/.config/secrets" 2>/dev/null
	[[ -n ${NODE_AUTH_TOKEN:-} ]] || exit 1
	NODE_AUTH_TOKEN="$NODE_AUTH_TOKEN" npm view @mmem/portal-ui version >/dev/null 2>&1'
check "gh authenticated" gh auth status

heading "Result"
if ((fail == 0)); then
	ok "all $pass checks passed"
	exit 0
fi
warn "$fail of $((pass + fail)) checks failed"
exit 1
