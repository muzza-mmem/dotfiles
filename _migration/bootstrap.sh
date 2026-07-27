#!/usr/bin/env bash
#
# bootstrap.sh — rebuild this dev environment on a fresh Ubuntu 24.04 WSL box.
#
# Runs install/[0-9][0-9]-*.sh in filename order. Each module is idempotent and
# records a completion marker, so re-running skips finished work.
#
#   ./bootstrap.sh              # run everything still outstanding
#   ./bootstrap.sh 30           # run only the 30-* module
#   ./bootstrap.sh --force      # ignore completion markers, re-run everything
#   ./bootstrap.sh --list       # show modules and their status
#   ./bootstrap.sh --dry-run    # print what would run, mutate nothing
#
# Prerequisites (see README.md): git + gh installed, `gh auth login` done, and
# this repo cloned. Do not run as root.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/lib.sh
source "$SCRIPT_DIR/install/lib.sh"

FORCE=0
FILTER=''

usage() {
	sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'
	exit "${1:-0}"
}

while (($#)); do
	case "$1" in
	-h | --help) usage 0 ;;
	--force) FORCE=1 ;;
	--list) FILTER='__list__' ;;
	--dry-run) DRY_RUN=1 ;;
	[0-9][0-9]) FILTER="$1" ;;
	*) die "unknown argument: $1 (try --help)" ;;
	esac
	shift
done
export DRY_RUN

((EUID == 0)) && die "do not run as root — this writes into \$HOME"

mapfile -t MODULES < <(find "$SCRIPT_DIR/install" -maxdepth 1 -name '[0-9][0-9]-*.sh' -printf '%f\n' | sort)
((${#MODULES[@]} > 0)) || die "no install modules found in $SCRIPT_DIR/install"

if [[ $FILTER == __list__ ]]; then
	heading "Modules"
	for m in "${MODULES[@]}"; do
		if step_done "$m"; then
			ok "$m"
		else
			printf '  -- %s (pending)\n' "$m"
		fi
	done
	exit 0
fi

heading "Bootstrapping from $REPO_ROOT"
[[ $DRY_RUN == 1 ]] && warn "DRY_RUN: no changes will be made"

ran=0
for m in "${MODULES[@]}"; do
	if [[ -n $FILTER && ${m:0:2} != "$FILTER" ]]; then
		continue
	fi
	if ((FORCE == 0)) && step_done "$m"; then
		ok "$m (already done — --force to re-run)"
		continue
	fi
	heading "$m"
	if ! bash "$SCRIPT_DIR/install/$m"; then
		die "$m failed. Fix the cause, then re-run just this module:
    $0 ${m:0:2}"
	fi
	mark_step_done "$m"
	ran=$((ran + 1))
done

((ran == 0)) && ok "nothing to do"

heading "Verification"
cat <<'EOF'
  Expected to FAIL on a first run (see README.md "The first smoke test is
  expected to fail ~7 checks"):
    - fnm / node / npm      not on PATH until a new shell
    - docker checks         group change needs a new session
    - ~/.ssh/id_ed25519     restored by hand (MIGRATION.md section 2)
    - npmrc has a token     seeded blank from the template on purpose
  Re-run ./_migration/smoke-test.sh after `wsl --shutdown` + the follow-ups
  below; it should then be clean.
EOF
bash "$SCRIPT_DIR/smoke-test.sh" || warn "smoke test reported problems (see above)"

heading "Manual follow-ups"
cat <<'EOF'
  1. From Windows PowerShell: wsl --shutdown     (applies .wslconfig)
  2. Start a new shell/session               (applies docker group + zsh)
  3. Re-authenticate: gh auth login / claude / docker login / docker login ghcr.io
  4. Fill in ~/.npmrc and ~/.config/secrets  (seeded from templates/, tokens blank)
  5. Work through _migration/MIGRATION.md section 5 (Windows-side items)
EOF
