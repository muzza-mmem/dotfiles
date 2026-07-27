#!/usr/bin/env bash
#
# 80-repos.sh — clone the working repos into ~/code from repos.tsv.
#
# A repo you have lost access to must not block the other eleven, so clone
# failures are collected and reported at the end rather than aborting.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MANIFEST="$MIGRATION_DIR/repos.tsv"
CODE_DIR="${CODE_DIR:-$HOME/code}"

[[ -f $MANIFEST ]] || die "manifest not found: $MANIFEST"
have git || die "git not installed — run 00-apt.sh first"

if have gh && ! gh auth status >/dev/null 2>&1; then
	warn "gh is not authenticated — private clones will fail. Run: gh auth login"
fi

mkdir -p "$CODE_DIR"

declare -a failed=()
cloned=0 skipped=0

while IFS=$'\t' read -r name remote; do
	[[ -z ${name// /} ]] && continue
	[[ $name == \#* ]] && continue
	if [[ -z ${remote:-} ]]; then
		warn "skipping malformed line (no tab-separated remote): $name"
		continue
	fi
	dest="$CODE_DIR/$name"
	if [[ -d $dest ]]; then
		ok "$name already present"
		skipped=$((skipped + 1))
		continue
	fi
	if [[ $DRY_RUN == 1 ]]; then
		warn "would clone $name from $remote"
		continue
	fi
	log "cloning $name"
	if git clone --quiet "$remote" "$dest"; then
		ok "$name"
		cloned=$((cloned + 1))
	else
		warn "FAILED to clone $name from $remote"
		failed+=("$name")
	fi
done <"$MANIFEST"

ok "repos: $cloned cloned, $skipped already present, ${#failed[@]} failed"
if ((${#failed[@]} > 0)); then
	warn "clone these by hand once access is sorted: ${failed[*]}"
fi
