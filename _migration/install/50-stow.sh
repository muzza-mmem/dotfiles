#!/usr/bin/env bash
#
# 50-stow.sh — symlink every Stow package into $HOME, then seed the two
# secret-bearing files from templates.
#
# A fresh Ubuntu ships real ~/.bashrc and ~/.profile files, and `stow` aborts
# rather than clobber them. So every target a package would own is checked
# first and moved to <file>.pre-stow if it is a real file. Symlinks are left
# alone — they are assumed to be ours already — and so is anything that
# resolves back inside this repo (see backup_file in lib.sh).
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PACKAGES=(bash bin claude git nvim tmux zsh)

# Directories that must exist as REAL directories before stow runs.
#
# `stow` folds a package: when the target directory does not already exist it
# creates ONE symlink to the package directory inside this repo instead of
# linking each file. Everything the tool then writes into that directory lands
# in the git working tree. For ~/.claude that means Claude Code's live OAuth
# credential (.credentials.json), session transcripts, and caches ending up in
# a repo with a remote. Pre-creating the directory forces per-file symlinks.
#
# Per package: bash and zsh drop files straight into $HOME (nothing to fold);
# bin owns ~/.local/bin, where pipx and the fdfind shim install binaries;
# claude is the dangerous one above; git's dir is where `git config --global`
# writes; nvim's is where lazy.nvim writes lazy-lock.json; tmux's plugins dir
# is where tpm clones whole plugin git repos.
REAL_DIRS=(
	"$HOME/.config"
	"$HOME/.local/bin"
	"$HOME/.claude"
	"$HOME/.claude/hooks"
	"$HOME/.claude/skills"
	"$HOME/.config/git"
	"$HOME/.config/nvim"
	"$HOME/.config/tmux"
	"$HOME/.config/tmux/plugins"
)

have stow || die "stow not installed — run 00-apt.sh first"

# ensure_real_dir <dir> — create it, first undoing any fold left by an earlier
# run. Removing a folded symlink loses nothing: the real files live in the repo
# and `stow --restow` links them back individually.
ensure_real_dir() {
	local d="$1" resolved
	if [[ -L $d ]]; then
		resolved=$(readlink -f -- "$d" 2>/dev/null) || resolved=''
		if [[ -n $resolved && $resolved == "$REPO_ROOT"/* ]]; then
			if [[ $DRY_RUN == 1 ]]; then
				warn "would unfold $d (symlink -> $resolved)"
			else
				warn "unfolding $d (was a folded symlink into the repo)"
				rm -- "$d"
			fi
		fi
	fi
	if [[ $DRY_RUN == 1 ]]; then
		[[ -d $d ]] || warn "would create $d"
		return 0
	fi
	mkdir -p -- "$d"
}

log "pre-creating target directories (stops stow folding them into the repo)"
for d in "${REAL_DIRS[@]}"; do
	ensure_real_dir "$d"
done

backup_conflicts() {
	local pkg="$1" rel target
	while IFS= read -r rel; do
		target="$HOME/${rel#./}"
		backup_file "$target"
	done < <(cd "$REPO_ROOT/$pkg" && find . \( -type f -o -type l \) -printf '%P\n')
}

log "checking for conflicting real files"
for pkg in "${PACKAGES[@]}"; do
	[[ -d "$REPO_ROOT/$pkg" ]] || die "missing Stow package: $REPO_ROOT/$pkg"
	backup_conflicts "$pkg"
done

# ~/.gitconfig is not inside any package (we moved to ~/.config/git/config) but
# it takes precedence over the XDG path, so a leftover would silently win.
backup_file "$HOME/.gitconfig"

log "stowing: ${PACKAGES[*]}"
if [[ $DRY_RUN == 1 ]]; then
	stow --dir "$REPO_ROOT" --target "$HOME" --no --verbose=1 --restow "${PACKAGES[@]}" 2>&1 |
		sed 's/^/  /'
	warn "DRY_RUN: nothing stowed"
else
	stow --dir "$REPO_ROOT" --target "$HOME" --restow "${PACKAGES[@]}"
	ok "stowed ${#PACKAGES[@]} packages"
fi

# Seed secret-bearing files, but never overwrite a real one.
seed_template() {
	local template="$MIGRATION_DIR/templates/$1" dest="$2"
	[[ -f $template ]] || die "missing template: $template"
	if [[ -e $dest ]]; then
		ok "$dest already exists — left untouched"
		return 0
	fi
	if [[ $DRY_RUN == 1 ]]; then
		warn "would seed $dest from $1"
		return 0
	fi
	mkdir -p "$(dirname "$dest")"
	install -m 600 "$template" "$dest"
	warn "seeded $dest from template — YOU MUST FILL IN THE TOKEN"
}

seed_template npmrc.example "$HOME/.npmrc"
seed_template secrets.example "$HOME/.config/secrets"
