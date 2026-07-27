#!/usr/bin/env bash
#
# 50-stow.sh — symlink every Stow package into $HOME, then seed the two
# secret-bearing files from templates.
#
# A fresh Ubuntu ships real ~/.bashrc and ~/.profile files, and `stow` aborts
# rather than clobber them. So every target a package would own is checked
# first and moved to <file>.pre-stow if it is a real file. Symlinks are left
# alone — they are assumed to be ours already.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PACKAGES=(bash bin claude git nvim tmux zsh)

have stow || die "stow not installed — run 00-apt.sh first"

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

mkdir -p "$HOME/.local/bin" "$HOME/.config"

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
