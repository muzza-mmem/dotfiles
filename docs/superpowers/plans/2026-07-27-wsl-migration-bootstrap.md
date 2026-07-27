# WSL Migration Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn this dotfiles repo into a one-shot machine rebuild: a `_migration/` directory holding `bootstrap.sh` plus numbered install modules that reconstruct the dev environment on a fresh Ubuntu 24.04 WSL distro, alongside a pre-wipe checklist for everything a script cannot carry.

**Architecture:** `_migration/bootstrap.sh` sources `install/lib.sh` for shared helpers, then runs `install/[0-9][0-9]-*.sh` in filename order, recording a completion marker per module so re-runs skip finished work. Each module is standalone, idempotent, and re-runnable alone via `./bootstrap.sh <NN>`. A separate always-run `smoke-test.sh` reports final state. Nothing in `_migration/` is a Stow package.

**Tech Stack:** bash (`set -euo pipefail`), GNU Stow 2.4, apt, fnm, Docker CE apt repo, tpm, lazy.nvim, Ubuntu 24.04 (noble).

## Global Constraints

- Target OS is **Ubuntu 24.04 LTS (noble)**. Package names must be the noble ones — notably the `t64` ABI renames: `libasound2t64`, `libatk1.0-0t64`, `libatk-bridge2.0-0t64`, `libcups2t64`.
- Target host has **32GB RAM**. `.wslconfig` uses `memory=20GB`, `swap=8GB`, and deliberately **omits** `autoMemoryReclaim` and `processors`.
- **No secret ever enters this repo**, encrypted or otherwise. Secrets are referenced only as `.example` templates and checklist items.
- Every module: `#!/usr/bin/env bash` + `set -euo pipefail`, sources `lib.sh`, and is safe to run twice.
- Never overwrite a user file. Move real files aside to `<file>.pre-stow` (configs) or `<file>.bak` (system files) first.
- `bootstrap.sh` refuses to run as root — it writes into `$HOME`.
- **Commit strategy: a single squashed commit in the final task.** No task before Task 11 commits anything.
- Verification is static (`bash -n`, `shellcheck -x`) plus real execution only where genuinely safe on the current machine. State plainly what remains unverified until the first real run.
- Match existing script style in `bin/.local/bin/` — `#!/usr/bin/env bash`, a `#`-comment header block explaining purpose and usage, then `set -euo pipefail`.
- `testing` branches are out of scope everywhere — throwaway.
- Do not touch the uncommitted working-tree changes in `bin/.local/bin/ss`. `tmux/.config/tmux/tmux.conf` is edited by Task 9 and already has unstaged changes; preserve them.

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `_migration/bootstrap.sh` | Entrypoint: arg parsing, module discovery/ordering, marker skip logic, final summary |
| `_migration/install/lib.sh` | Shared helpers only. Sourced, never executed. No side effects at source time. |
| `_migration/install/00-apt.sh` | apt refresh/upgrade + all apt-sourced packages |
| `_migration/install/10-shell.sh` | oh-my-zsh + login shell |
| `_migration/install/20-node.sh` | fnm + node 24 + npm globals |
| `_migration/install/30-docker.sh` | Docker CE repo, packages, daemon.json, group, service |
| `_migration/install/40-tools.sh` | lazygit binary + pipx packages |
| `_migration/install/50-stow.sh` | Conflict backup, `stow` all packages, seed secret templates |
| `_migration/install/60-tmux.sh` | tpm clone + headless plugin install |
| `_migration/install/70-nvim.sh` | Upstream Neovim to `/opt/nvim` + headless `Lazy! sync` |
| `_migration/install/80-repos.sh` | Clone from `repos.tsv`, non-fatal per-repo failures |
| `_migration/install/90-wsl.sh` | `/etc/wsl.conf` + Windows `.wslconfig` |
| `_migration/smoke-test.sh` | Always-run verification report. Never marked done. |
| `_migration/repos.tsv` | `name<TAB>remote` manifest |
| `_migration/templates/npmrc.example` | `@mmem` registry template, no token |
| `_migration/templates/secrets.example` | `~/.config/secrets` template, no values |
| `_migration/wsl/wsl.conf` | Source for `/etc/wsl.conf` |
| `_migration/wsl/.wslconfig` | Source for Windows `.wslconfig` |
| `_migration/README.md` | Prologue + module reference + troubleshooting |
| `_migration/MIGRATION.md` | Pre-wipe checklist |
| `git/.config/git/config` | New Stow package (moves `~/.gitconfig` to XDG) |
| `README.md` | Repo root README pointing at `_migration/` |

**Modified:**

| Path | Change |
|---|---|
| `zsh/.zshrc` | nvm→fnm, drop brew, de-duplicate PATH entries |
| `tmux/.config/tmux/tmux.conf:100-104` | tpm path `~/.tmux/plugins` → `~/.config/tmux/plugins` |
| `CLAUDE.md` | Note that `_migration/` is not a Stow package |
| `.gitignore` | Ignore `/git/.config/git/config`? **No** — see Task 9. Add nothing. |

---

### Task 1: Scaffolding — `lib.sh` and `bootstrap.sh`

The foundation every other task consumes. Nothing else works until this is right.

**Files:**
- Create: `_migration/install/lib.sh`
- Create: `_migration/bootstrap.sh`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: nothing.
- Produces, all sourced from `lib.sh` by every later module:
  - `REPO_ROOT` — absolute path to the dotfiles repo root
  - `MIGRATION_DIR` — absolute path to `_migration/`
  - `STATE_DIR` — marker directory, default `$HOME/.local/state/dotfiles-bootstrap`
  - `log <msg>` / `ok <msg>` / `warn <msg>` (stderr) / `die <msg>` (stderr, exit 1)
  - `have <cmd>` → exit 0 if on PATH
  - `apt_install <pkg>...` → installs only missing packages
  - `step_done <name>` → exit 0 if marker exists; `mark_step_done <name>`
  - `backup_file <path> [suffix]` → moves aside a real (non-symlink) file, default suffix `.pre-stow`
  - `win_home` → prints the Windows user profile path as a WSL path, e.g. `/mnt/c/Users/muzza.khan`; exit 1 if undeterminable
  - `DRY_RUN` — respected by callers; `1` means print, do not mutate

- [ ] **Step 1: Write `_migration/install/lib.sh`**

```bash
#!/usr/bin/env bash
#
# lib.sh — shared helpers for the bootstrap modules.
#
# This file is SOURCED, never executed. It must have no side effects at source
# time beyond defining variables and functions, so that sourcing it twice (or
# from a module run standalone) is harmless.
#
# shellcheck shell=bash

# _migration/install/lib.sh -> _migration -> repo root
MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$MIGRATION_DIR/.." && pwd)"
STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.local/state/dotfiles-bootstrap}"
DRY_RUN="${DRY_RUN:-0}"

if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'
	C_BLUE=$'\033[34m'
	C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'
	C_RED=$'\033[31m'
	C_BOLD=$'\033[1m'
else
	C_RESET='' C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_BOLD=''
fi

log() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok() { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf '%sFAIL%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
heading() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

have() { command -v "$1" >/dev/null 2>&1; }

# apt_install <pkg>... — install only the packages not already present.
apt_install() {
	local pkg missing=()
	for pkg in "$@"; do
		if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
			missing+=("$pkg")
		fi
	done
	if ((${#missing[@]} == 0)); then
		ok "apt: nothing to do (${#} packages already installed)"
		return 0
	fi
	log "apt: installing ${missing[*]}"
	if [[ $DRY_RUN == 1 ]]; then
		ok "apt: DRY_RUN, skipped"
		return 0
	fi
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
}

step_done() { [[ -f "$STATE_DIR/$1" ]]; }

mark_step_done() {
	[[ $DRY_RUN == 1 ]] && return 0
	mkdir -p "$STATE_DIR"
	: >"$STATE_DIR/$1"
}

# backup_file <path> [suffix] — move a real file/dir aside. Symlinks and
# missing paths are left alone (a symlink is assumed to be ours already).
backup_file() {
	local f="$1" suffix="${2:-.pre-stow}"
	[[ -e $f && ! -L $f ]] || return 0
	if [[ $DRY_RUN == 1 ]]; then
		warn "would back up $f -> ${f}${suffix}"
		return 0
	fi
	warn "backing up $f -> ${f}${suffix}"
	mv -- "$f" "${f}${suffix}"
}

# win_home — the Windows user profile as a WSL path. cmd.exe must be invoked
# from a Windows-visible cwd or it warns on stderr, hence the cd.
win_home() {
	local raw path
	raw=$(cd /mnt/c 2>/dev/null && cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n') || return 1
	[[ -n $raw ]] || return 1
	path=$(wslpath -u "$raw" 2>/dev/null) || return 1
	[[ -d $path ]] || return 1
	printf '%s\n' "$path"
}
```

- [ ] **Step 2: Write `_migration/bootstrap.sh`**

```bash
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
bash "$SCRIPT_DIR/smoke-test.sh" || warn "smoke test reported problems (see above)"

heading "Manual follow-ups"
cat <<'EOF'
  1. From Windows PowerShell: wsl --shutdown     (applies .wslconfig)
  2. Start a new shell/session               (applies docker group + zsh)
  3. Re-authenticate: gh auth login / claude / docker login / docker login ghcr.io
  4. Fill in ~/.npmrc and ~/.config/secrets  (seeded from templates/, tokens blank)
  5. Work through _migration/MIGRATION.md section 5 (Windows-side items)
EOF
```

- [ ] **Step 3: Make both executable and syntax-check**

```bash
cd ~/dotfiles
chmod +x _migration/bootstrap.sh
bash -n _migration/bootstrap.sh && bash -n _migration/install/lib.sh && echo "SYNTAX OK"
```
Expected: `SYNTAX OK`

- [ ] **Step 4: Install shellcheck and lint**

`shellcheck` is not currently installed on this box.

```bash
sudo apt-get install -y shellcheck
shellcheck -x _migration/bootstrap.sh _migration/install/lib.sh
```
Expected: no output (clean). `lib.sh` carries `# shellcheck shell=bash` because it has no shebang-driven shell. If SC2034 fires on `C_BOLD`/unused colours, that is expected — later modules use them; silence it with a `# shellcheck disable=SC2034` on the colour block rather than deleting the variables.

- [ ] **Step 5: Verify helpers behave, in an isolated state dir**

```bash
cd ~/dotfiles
DOTFILES_STATE_DIR=$(mktemp -d) bash -c '
  source _migration/install/lib.sh
  echo "REPO_ROOT=$REPO_ROOT"
  echo "MIGRATION_DIR=$MIGRATION_DIR"
  have git && echo "have git: yes"
  have definitely-not-a-real-command && echo "BUG: false positive" || echo "have bogus: no"
  step_done fake.sh && echo "BUG: marker exists" || echo "step_done fake: no"
  mark_step_done fake.sh
  step_done fake.sh && echo "step_done after mark: yes"
  echo "win_home=$(win_home || echo UNRESOLVED)"
'
```
Expected: `REPO_ROOT=/home/muzzakhan/dotfiles`, `MIGRATION_DIR=/home/muzzakhan/dotfiles/_migration`, `have git: yes`, `have bogus: no`, `step_done fake: no`, `step_done after mark: yes`, and `win_home=/mnt/c/Users/muzza.khan`. If `win_home` is `UNRESOLVED`, `cmd.exe` interop is unavailable — fix before Task 8 depends on it.

- [ ] **Step 6: Verify `bootstrap.sh` guards work**

`--list` must not fail even with zero modules present yet — but `MODULES` is empty until Task 2, so this step confirms the *error path* first, then re-run after Task 2 for the success path.

```bash
cd ~/dotfiles
./_migration/bootstrap.sh --help | head -5
./_migration/bootstrap.sh --list || echo "expected failure: no modules yet"
./_migration/bootstrap.sh --bogus-flag; echo "exit=$?"
```
Expected: help text prints; `--list` dies with `no install modules found`; `--bogus-flag` dies with `unknown argument` and a non-zero exit.

- [ ] **Step 7: Add the `_migration/` note to `CLAUDE.md`**

Insert after the `## Layout` section's closing paragraph (the one ending "does not support `XDG_CONFIG_HOME` / `~/.config`."):

```markdown
### `_migration/` is not a Stow package

Every other top-level directory is a Stow package. `_migration/` is the
exception: it holds the one-shot machine rebuild (`bootstrap.sh`, install
modules, `MIGRATION.md`). Never run `stow _migration`. The leading underscore
is there to make that obvious at a glance.
```

- [ ] **Step 8: No commit**

Per the Global Constraints, everything lands in one commit in Task 11. Leave the working tree dirty.

---

### Task 2: `00-apt.sh` and `10-shell.sh`

Base packages and the shell. Grouped because `10-shell.sh` is meaningless without `zsh` from `00-apt.sh`, and a reviewer would accept or reject them together.

**Files:**
- Create: `_migration/install/00-apt.sh`
- Create: `_migration/install/10-shell.sh`

**Interfaces:**
- Consumes: `lib.sh` (`apt_install`, `log`, `ok`, `warn`, `have`).
- Produces: `zsh`, `tmux`, `stow`, `git`, `gh`, `jq`, `curl`, `shellcheck`, `fzf`, `zoxide`, `pipx`, `ripgrep`, `fd` (symlinked from `fdfind`) on PATH; `~/.oh-my-zsh` present; login shell set to zsh. Task 4 (`50-stow.sh`) requires `stow`; Task 4 (`40-tools.sh`) requires `jq` and `pipx`; Task 6 requires `git`.

- [ ] **Step 1: Write `_migration/install/00-apt.sh`**

Package list derived from `apt-mark showmanual` on the old box, translated to noble names. The font/lib block is what headless Chromium (Puppeteer/Playwright) needs.

```bash
#!/usr/bin/env bash
#
# 00-apt.sh — refresh apt and install every apt-sourced package.
#
# The font and lib block at the end is what headless Chromium needs (Puppeteer
# / Playwright in the portal repos). Package names are Ubuntu 24.04 (noble):
# several ABI-renamed to *t64 vs 22.04.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "refreshing package lists"
[[ $DRY_RUN == 1 ]] || sudo apt-get update -qq

log "upgrading installed packages"
[[ $DRY_RUN == 1 ]] || sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log "core tooling"
apt_install \
	ca-certificates curl wget unzip gnupg build-essential \
	git gh \
	zsh tmux stow \
	jq htop tree nmap pandoc mkcert screen \
	ripgrep fd-find fzf zoxide pipx shellcheck

log "headless Chromium runtime (fonts + libs)"
apt_install \
	fonts-liberation fonts-freefont-ttf fonts-noto-color-emoji \
	fonts-ipafont-gothic fonts-wqy-zenhei fonts-unifont \
	xfonts-cyrillic xfonts-scalable xvfb \
	libnss3 libnss3-tools libnspr4 \
	libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
	libcups2t64 libdrm2 libgbm1 libasound2t64 \
	libpango-1.0-0 libcairo2 libglib2.0-0t64 \
	libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 \
	libxfixes3 libxrandr2 libxkbcommon0 libwayland-client0

# Debian/Ubuntu ship fd as `fdfind` to avoid a name clash. Everything (and
# nvim's telescope config) expects `fd`.
if have fdfind && ! have fd; then
	mkdir -p "$HOME/.local/bin"
	ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
	ok "linked fdfind -> ~/.local/bin/fd"
fi

ok "apt packages installed"
```

- [ ] **Step 2: Write `_migration/install/10-shell.sh`**

`KEEP_ZSHRC=yes` is essential — without it the oh-my-zsh installer writes its own `~/.zshrc`, which then collides with the one Stow wants to place in Task 4.

```bash
#!/usr/bin/env bash
#
# 10-shell.sh — oh-my-zsh + make zsh the login shell.
#
# KEEP_ZSHRC=yes matters: without it the installer writes its own ~/.zshrc,
# which then conflicts with the one 50-stow.sh symlinks in from the repo.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

have zsh || die "zsh not installed — run 00-apt.sh first"

if [[ -d "$HOME/.oh-my-zsh" ]]; then
	ok "oh-my-zsh already installed"
elif [[ $DRY_RUN == 1 ]]; then
	warn "would install oh-my-zsh"
else
	log "installing oh-my-zsh (unattended, keeping our .zshrc)"
	RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
		"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

zsh_path="$(command -v zsh)"
current_shell="$(getent passwd "$USER" | cut -d: -f7)"
if [[ $current_shell == "$zsh_path" ]]; then
	ok "login shell already $zsh_path"
elif [[ $DRY_RUN == 1 ]]; then
	warn "would set login shell to $zsh_path (currently $current_shell)"
else
	log "setting login shell to $zsh_path (was $current_shell)"
	sudo chsh -s "$zsh_path" "$USER"
	warn "login shell change applies on next new session"
fi
```

- [ ] **Step 3: Make executable and syntax-check**

```bash
cd ~/dotfiles
chmod +x _migration/install/00-apt.sh _migration/install/10-shell.sh
bash -n _migration/install/00-apt.sh && bash -n _migration/install/10-shell.sh && echo "SYNTAX OK"
shellcheck -x _migration/install/00-apt.sh _migration/install/10-shell.sh
```
Expected: `SYNTAX OK`, then no shellcheck output.

- [ ] **Step 4: Dry-run both, confirming no mutation**

```bash
cd ~/dotfiles
DRY_RUN=1 bash _migration/install/00-apt.sh
DRY_RUN=1 bash _migration/install/10-shell.sh
```
Expected: both exit 0. `00-apt.sh` prints `apt: installing …` naming packages absent on **this** 22.04 box (`fd-find`, `shellcheck`, and the `t64` names, which legitimately do not exist on jammy) then `apt: DRY_RUN, skipped`. `10-shell.sh` prints `oh-my-zsh already installed` and `login shell already /usr/bin/zsh`.

**Do not "fix" the `t64` packages appearing as missing.** They are noble-only; that is correct and expected on 22.04. This is precisely the class of thing that stays unverified until the real run.

- [ ] **Step 5: Confirm module discovery now works**

```bash
cd ~/dotfiles
./_migration/bootstrap.sh --list
```
Expected: both `00-apt.sh` and `10-shell.sh` listed as `(pending)`.

- [ ] **Step 6: No commit** — single squashed commit in Task 11.

---

### Task 3: `20-node.sh` and `30-docker.sh`

The two runtime installs. Grouped: both add third-party sources and neither is safe to execute on this box.

**Files:**
- Create: `_migration/install/20-node.sh`
- Create: `_migration/install/30-docker.sh`

**Interfaces:**
- Consumes: `lib.sh`; `curl`, `gnupg`, `ca-certificates` from `00-apt.sh`.
- Produces: `fnm` at `$HOME/.local/share/fnm/fnm`, node 24 as the fnm default, `npm` globals `@anthropic-ai/claude-code` + `confluence-cli` + `corepack`; `docker` + `docker compose` working, `$USER` in the `docker` group. Task 9's `.zshrc` rewrite hardcodes the fnm path `$HOME/.local/share/fnm` — keep them in step.

- [ ] **Step 1: Write `_migration/install/20-node.sh`**

```bash
#!/usr/bin/env bash
#
# 20-node.sh — fnm + node 24 + global npm packages.
#
# fnm replaces nvm deliberately: sourcing nvm.sh costs 300-600ms on every shell
# start, fnm is a static binary doing the same job in ~10ms and still honours
# .nvmrc. --skip-shell because 50-stow.sh brings our own .zshrc with the
# `fnm env --use-on-cd` line already in it.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FNM_INSTALL_DIR="$HOME/.local/share/fnm"
NODE_MAJOR=24
NPM_GLOBALS=(@anthropic-ai/claude-code confluence-cli corepack)

if [[ -x "$FNM_INSTALL_DIR/fnm" ]]; then
	ok "fnm already installed at $FNM_INSTALL_DIR"
elif [[ $DRY_RUN == 1 ]]; then
	warn "would install fnm to $FNM_INSTALL_DIR"
else
	log "installing fnm"
	curl -fsSL https://fnm.vercel.app/install |
		bash -s -- --install-dir "$FNM_INSTALL_DIR" --skip-shell
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
```

- [ ] **Step 2: Write `_migration/install/30-docker.sh`**

```bash
#!/usr/bin/env bash
#
# 30-docker.sh — Docker CE from Docker's own apt repo, plus the two settings
# that stop the WSL VHD ballooning: log rotation and builder GC.
#
# Native engine in WSL, not Docker Desktop — faster I/O, no licence question,
# and fully scriptable from inside WSL. Requires systemd, which /etc/wsl.conf
# enables (see 90-wsl.sh).
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KEYRING=/etc/apt/keyrings/docker.gpg
SOURCE_LIST=/etc/apt/sources.list.d/docker.list
DAEMON_JSON=/etc/docker/daemon.json

if [[ $DRY_RUN == 1 ]]; then
	warn "would add Docker apt repo, install docker-ce, write $DAEMON_JSON,"
	warn "enable the service, and add $USER to the docker group"
	exit 0
fi

if have docker; then
	ok "docker already installed ($(docker --version))"
else
	log "adding Docker apt repository"
	sudo install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
		sudo gpg --batch --yes --dearmor -o "$KEYRING"
	sudo chmod a+r "$KEYRING"
	printf 'deb [arch=%s signed-by=%s] https://download.docker.com/linux/ubuntu %s stable\n' \
		"$(dpkg --print-architecture)" "$KEYRING" \
		"$(. /etc/os-release && echo "$VERSION_CODENAME")" |
		sudo tee "$SOURCE_LIST" >/dev/null
	sudo apt-get update -qq
	apt_install docker-ce docker-ce-cli containerd.io \
		docker-buildx-plugin docker-compose-plugin
fi

log "writing $DAEMON_JSON"
sudo mkdir -p /etc/docker
if [[ -f $DAEMON_JSON ]] && ! grep -q 'defaultKeepStorage' "$DAEMON_JSON"; then
	sudo cp -a "$DAEMON_JSON" "${DAEMON_JSON}.bak"
	warn "backed up existing daemon.json -> ${DAEMON_JSON}.bak"
fi
sudo tee "$DAEMON_JSON" >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "10GB"
    }
  }
}
EOF

log "enabling docker service"
sudo systemctl enable --now docker
sudo systemctl restart docker

if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
	ok "$USER already in the docker group"
else
	log "adding $USER to the docker group"
	sudo usermod -aG docker "$USER"
	warn "group change applies on next new session (or: wsl --shutdown)"
fi
```

- [ ] **Step 3: Make executable, syntax-check, lint**

```bash
cd ~/dotfiles
chmod +x _migration/install/20-node.sh _migration/install/30-docker.sh
bash -n _migration/install/20-node.sh && bash -n _migration/install/30-docker.sh && echo "SYNTAX OK"
shellcheck -x _migration/install/20-node.sh _migration/install/30-docker.sh
```
Expected: `SYNTAX OK`, no shellcheck output.

- [ ] **Step 4: Dry-run both**

```bash
cd ~/dotfiles
DRY_RUN=1 bash _migration/install/20-node.sh
DRY_RUN=1 bash _migration/install/30-docker.sh
```
Expected: both exit 0 having mutated nothing. `20-node.sh` prints `would install fnm to /home/muzzakhan/.local/share/fnm` (fnm is genuinely absent here) then the node/globals line. `30-docker.sh` prints its four `would …` lines.

- [ ] **Step 5: Verify the fnm install URL is live** (cheap, catches a dead upstream before the real run)

```bash
curl -fsSI https://fnm.vercel.app/install | head -1
curl -fsSI https://download.docker.com/linux/ubuntu/gpg | head -1
```
Expected: both `HTTP/2 200`. A 404 here means the plan's URL needs updating now, not on the fresh box.

- [ ] **Step 6: No commit.**

**Unverified until the real run:** whether `fnm install 24` resolves, whether Docker's noble repo has all five packages, and whether `systemctl enable --now docker` works before `wsl.conf` sets `systemd=true`. That last one is an ordering risk — on a fresh distro systemd is already on by default in recent WSL, but if `30-docker.sh` fails with "System has not been booted with systemd", the fix is to run `90-wsl.sh`, `wsl --shutdown`, then re-run `./bootstrap.sh 30`. Document that in Task 10's troubleshooting section.

---

### Task 4: `40-tools.sh`, `50-stow.sh`, and the secret templates

**Files:**
- Create: `_migration/install/40-tools.sh`
- Create: `_migration/install/50-stow.sh`
- Create: `_migration/templates/npmrc.example`
- Create: `_migration/templates/secrets.example`

**Interfaces:**
- Consumes: `lib.sh` (`backup_file`); `jq`, `pipx`, `stow`, `curl` from `00-apt.sh`.
- Produces: `lazygit` at `/usr/local/bin/lazygit`; pipx apps `sqlit-tui`, `sshtunnel`; all Stow packages symlinked into `$HOME`; `~/.npmrc` and `~/.config/secrets` seeded from templates with blank values, mode 600.

- [ ] **Step 1: Write `_migration/templates/npmrc.example`**

```
# Copy to ~/.npmrc and fill in the token, then: chmod 600 ~/.npmrc
#
# The @mmem scope resolves from GitHub Packages, which needs a classic PAT with
# read:packages. Generate a FRESH one on the new machine — do not carry the old
# token across. See _migration/MIGRATION.md section 3.
@mmem:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=
```

- [ ] **Step 2: Write `_migration/templates/secrets.example`**

```sh
# Copy to ~/.config/secrets and fill in, then: chmod 600 ~/.config/secrets
#
# Sourced by ~/.zshrc on every shell start, so keep it to plain `export` lines
# and nothing slow. Never commit the real file.
#
# export SOME_TOKEN=
```

- [ ] **Step 3: Write `_migration/install/40-tools.sh`**

Note: lazygit publishes `.tar.gz` archives for Linux, not `.deb`. Extract the binary.

```bash
#!/usr/bin/env bash
#
# 40-tools.sh — the handful of tools that are not in apt.
#
# lazygit ships tarballs (not .deb) for Linux, so we pull the release archive
# and install the single binary. pipx apps come from PyPI.
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
	local tag ver tmp
	tag=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name)
	[[ -n $tag && $tag != null ]] || die "could not resolve the latest lazygit release"
	ver="${tag#v}"
	tmp=$(mktemp -d)
	log "installing lazygit $ver"
	curl -fsSL -o "$tmp/lazygit.tar.gz" \
		"https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${ver}_Linux_x86_64.tar.gz"
	tar -xzf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit
	sudo install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
	rm -rf "$tmp"
	ok "lazygit $(lazygit --version 2>/dev/null | head -1)"
}

install_pipx_apps() {
	if [[ $DRY_RUN == 1 ]]; then
		warn "would pipx install: ${PIPX_APPS[*]}"
		return 0
	fi
	have pipx || die "pipx not installed — run 00-apt.sh first"
	pipx ensurepath >/dev/null 2>&1 || true
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
```

- [ ] **Step 4: Write `_migration/install/50-stow.sh`**

The conflict sweep is the important part: `stow` aborts on an existing real file, and a fresh Ubuntu ships a real `~/.bashrc`, so this would fail immediately without it.

```bash
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
```

- [ ] **Step 5: Make executable, syntax-check, lint**

```bash
cd ~/dotfiles
chmod +x _migration/install/40-tools.sh _migration/install/50-stow.sh
bash -n _migration/install/40-tools.sh && bash -n _migration/install/50-stow.sh && echo "SYNTAX OK"
shellcheck -x _migration/install/40-tools.sh _migration/install/50-stow.sh
```
Expected: `SYNTAX OK`, no shellcheck output.

- [ ] **Step 6: Dry-run `40-tools.sh` — safe, mutates nothing**

```bash
cd ~/dotfiles
DRY_RUN=1 bash _migration/install/40-tools.sh
```
Expected: `lazygit already installed (…0.61.1…)` (the Homebrew one, still present on this box) and `would pipx install: sqlit-tui sshtunnel`.

- [ ] **Step 7: Verify the lazygit release URL pattern resolves**

The archive filename casing (`Linux_x86_64`) is easy to get wrong and only fails on the real run. Check it now.

```bash
tag=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name)
ver="${tag#v}"
echo "tag=$tag ver=$ver"
curl -fsSIL -o /dev/null -w '%{http_code}\n' \
  "https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${ver}_Linux_x86_64.tar.gz"
```
Expected: `200`. If `404`, list the real asset names with
`curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r '.assets[].name'`
and correct the filename in `40-tools.sh`.

- [ ] **Step 8: Dry-run `50-stow.sh` — this one is a genuine test**

The `git` package does not exist until Task 9, so expect a clean, informative failure first:

```bash
cd ~/dotfiles
DRY_RUN=1 bash _migration/install/50-stow.sh; echo "exit=$?"
```
Expected: dies with `missing Stow package: /home/muzzakhan/dotfiles/git` and a non-zero exit. That proves the guard works. Re-run this step after Task 9 and expect: no `would back up` lines for already-symlinked configs, a `would back up /home/muzzakhan/.gitconfig` line, `stow --no` output showing zero conflicts, and both `seed_template` calls reporting the real files already exist.

- [ ] **Step 9: No commit.**

---

### Task 5: `60-tmux.sh` and `70-nvim.sh`

Both depend on Task 4 having stowed their configs.

**Files:**
- Create: `_migration/install/60-tmux.sh`
- Create: `_migration/install/70-nvim.sh`

**Interfaces:**
- Consumes: `lib.sh`; `~/.config/tmux/tmux.conf` and `~/.config/nvim/` symlinks from `50-stow.sh`; `git`, `curl`, `tar` from `00-apt.sh`.
- Produces: tpm at `~/.config/tmux/plugins/tpm` with all plugins installed; `nvim` at `/usr/local/bin/nvim` → `/opt/nvim/bin/nvim`, plugins synced. Task 9 updates `tmux.conf` to use this same tpm path — they must agree.

- [ ] **Step 1: Write `_migration/install/60-tmux.sh`**

```bash
#!/usr/bin/env bash
#
# 60-tmux.sh — install tpm and all tmux plugins headlessly.
#
# tpm lives at ~/.config/tmux/plugins/tpm, which resolves inside the repo (that
# path is a stowed symlink) and is gitignored via /tmux/.config/tmux/plugins.
# install_plugins needs a tmux server with our config loaded, hence the
# start-server + source-file dance.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMUX_CONF="$HOME/.config/tmux/tmux.conf"
TPM_DIR="$HOME/.config/tmux/plugins/tpm"

have tmux || die "tmux not installed — run 00-apt.sh first"
[[ -e $TMUX_CONF ]] || die "$TMUX_CONF missing — run 50-stow.sh first"

if [[ $DRY_RUN == 1 ]]; then
	warn "would clone tpm to $TPM_DIR and install plugins"
	exit 0
fi

if [[ -d "$TPM_DIR/.git" ]]; then
	ok "tpm already cloned"
else
	log "cloning tpm"
	mkdir -p "$(dirname "$TPM_DIR")"
	git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

log "installing tmux plugins"
# TMUX_TMPDIR matches .zshrc, keeping the socket off /tmp.
export TMUX_TMPDIR="${TMUX_TMPDIR:-$HOME/.cache}"
mkdir -p "$TMUX_TMPDIR"
tmux start-server
tmux source-file "$TMUX_CONF"
"$TPM_DIR/bin/install_plugins"
tmux kill-server 2>/dev/null || true
ok "tmux plugins installed"
```

- [ ] **Step 2: Write `_migration/install/70-nvim.sh`**

Ubuntu 24.04's apt Neovim is 0.10, too old for this NvChad config — hence the upstream tarball. The asset name changed at 0.10.4 (`nvim-linux64` → `nvim-linux-x86_64`), so try the new name first and fall back.

```bash
#!/usr/bin/env bash
#
# 70-nvim.sh — Neovim from the upstream tarball, then sync plugins.
#
# Deliberately NOT from apt: noble ships 0.10, too old for this NvChad config.
# The release asset was renamed at 0.10.4 (nvim-linux64 -> nvim-linux-x86_64),
# so try the current name and fall back to the old one.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NVIM_TAG="${NVIM_TAG:-stable}"
NVIM_PREFIX=/opt/nvim
BASE="https://github.com/neovim/neovim/releases/download/${NVIM_TAG}"

if [[ $DRY_RUN == 1 ]]; then
	warn "would install Neovim ($NVIM_TAG) to $NVIM_PREFIX and run Lazy! sync"
	exit 0
fi

[[ -d "$HOME/.config/nvim" ]] || die "~/.config/nvim missing — run 50-stow.sh first"

if [[ -x "$NVIM_PREFIX/bin/nvim" ]]; then
	ok "Neovim already installed ($("$NVIM_PREFIX/bin/nvim" --version | head -1))"
else
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	log "downloading Neovim $NVIM_TAG"
	if ! curl -fsSL -o "$tmp/nvim.tar.gz" "$BASE/nvim-linux-x86_64.tar.gz"; then
		warn "nvim-linux-x86_64.tar.gz not found, trying nvim-linux64.tar.gz"
		curl -fsSL -o "$tmp/nvim.tar.gz" "$BASE/nvim-linux64.tar.gz" ||
			die "could not download a Neovim tarball for tag $NVIM_TAG"
	fi
	log "installing to $NVIM_PREFIX"
	sudo rm -rf "$NVIM_PREFIX"
	sudo mkdir -p "$NVIM_PREFIX"
	sudo tar -xzf "$tmp/nvim.tar.gz" -C "$NVIM_PREFIX" --strip-components=1
	sudo ln -sfn "$NVIM_PREFIX/bin/nvim" /usr/local/bin/nvim
	ok "installed $(/usr/local/bin/nvim --version | head -1)"
fi

log "syncing plugins (first launch would otherwise do this interactively)"
nvim --headless "+Lazy! sync" +qa 2>&1 | tail -20 || true
ok "nvim plugins synced"
```

- [ ] **Step 3: Make executable, syntax-check, lint**

```bash
cd ~/dotfiles
chmod +x _migration/install/60-tmux.sh _migration/install/70-nvim.sh
bash -n _migration/install/60-tmux.sh && bash -n _migration/install/70-nvim.sh && echo "SYNTAX OK"
shellcheck -x _migration/install/60-tmux.sh _migration/install/70-nvim.sh
```
Expected: `SYNTAX OK`, no shellcheck output.

- [ ] **Step 4: Dry-run both**

```bash
cd ~/dotfiles
DRY_RUN=1 bash _migration/install/60-tmux.sh
DRY_RUN=1 bash _migration/install/70-nvim.sh
```
Expected: `would clone tpm to …` and `would install Neovim (stable) …`, both exit 0.

- [ ] **Step 5: Verify the Neovim asset name is current**

```bash
for a in nvim-linux-x86_64.tar.gz nvim-linux64.tar.gz; do
  printf '%-26s %s\n' "$a" \
    "$(curl -fsSIL -o /dev/null -w '%{http_code}' https://github.com/neovim/neovim/releases/download/stable/$a)"
done
```
Expected: at least one `200`. If both are `404`, list real assets with
`curl -fsSL https://api.github.com/repos/neovim/neovim/releases/tags/stable | jq -r '.assets[].name'`
and fix `70-nvim.sh`.

- [ ] **Step 6: No commit.**

**Unverified until the real run:** whether `install_plugins` completes headlessly under tmux 3.4, and whether `Lazy! sync` resolves every plugin without a Neovim version complaint. Both are recoverable by hand (`tmux` then `prefix + I`; `nvim` then `:Lazy sync`), which Task 10 documents.

---

### Task 6: `80-repos.sh` and `repos.tsv`

**Files:**
- Create: `_migration/install/80-repos.sh`
- Create: `_migration/repos.tsv`

**Interfaces:**
- Consumes: `lib.sh`; `git` and `gh` (authenticated) from the prologue.
- Produces: `~/code/<name>` for each manifest line. Failures are warnings, never fatal.

- [ ] **Step 1: Write `_migration/repos.tsv`**

Tab-separated. `~/code/audit-tools` and `~/code/plan-agent` are deliberately absent — they have no remote and cannot be cloned. They appear in `MIGRATION.md` instead.

```
# name<TAB>remote — cloned into ~/code by _migration/install/80-repos.sh
# Add a line here and re-run: ./bootstrap.sh 80
AutoDoc	https://github.com/MMEM/AutoDoc.git
ai-coding-standards	https://github.com/MMEM/ai-coding-standards.git
portal-autodoc	https://github.com/MMEM/portal-autodoc.git
portal-cga	https://github.com/MMEM/portal-cga.git
portal-core	https://github.com/MMEM/portal-core.git
portal-fx	https://github.com/MMEM/portal-fx.git
portal-keycloak	https://github.com/MMEM/portal-keycloak.git
portal-lti	https://github.com/MMEM/portal-lti.git
portal-openobserve	https://github.com/MMEM/portal-openobserve.git
portal-pbb	https://github.com/MMEM/portal-pbb.git
portal-qms	https://github.com/MMEM/portal-qms.git
portal-sales	https://github.com/MMEM/portal-sales.git
```

**Important:** the separator must be a literal tab. Verify with `grep -P '\t' _migration/repos.tsv | wc -l` → `12`.

- [ ] **Step 2: Write `_migration/install/80-repos.sh`**

```bash
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
```

Note the deliberate absence of `die` on failure — the module still exits 0 so `bootstrap.sh` continues.

- [ ] **Step 3: Make executable, syntax-check, lint, verify tabs**

```bash
cd ~/dotfiles
chmod +x _migration/install/80-repos.sh
bash -n _migration/install/80-repos.sh && echo "SYNTAX OK"
shellcheck -x _migration/install/80-repos.sh
grep -cP '\t' _migration/repos.tsv
```
Expected: `SYNTAX OK`, no shellcheck output, and `12`.

- [ ] **Step 4: Run it for real — this box is a genuine test case**

All twelve repos already exist in `~/code`, so a real (non-dry) run must be a complete no-op. This exercises the parser, the manifest, and the skip path for free.

```bash
cd ~/dotfiles
bash _migration/install/80-repos.sh
```
Expected: twelve `ok <name> already present` lines, then `repos: 0 cloned, 12 already present, 0 failed`. Any `would clone` or `FAILED` line means a name in `repos.tsv` does not match the directory on disk — fix the manifest.

- [ ] **Step 5: Verify the failure path is non-fatal**

```bash
cd ~/dotfiles
tmp=$(mktemp -d)
printf 'nope\thttps://github.com/MMEM/definitely-not-a-repo.git\n' > "$tmp/repos.tsv"
CODE_DIR="$tmp/code" bash -c '
  source _migration/install/lib.sh
  MIGRATION_DIR='"$tmp"' bash _migration/install/80-repos.sh
'; echo "exit=$?"
rm -rf "$tmp"
```
Expected: a `FAILED to clone nope` warning, the summary line reporting `1 failed`, and **`exit=0`**. A non-zero exit here is a bug — it would abort `bootstrap.sh` over one dead repo.

- [ ] **Step 6: No commit.**

---

### Task 7: `90-wsl.sh` and the WSL config files

**Files:**
- Create: `_migration/wsl/wsl.conf`
- Create: `_migration/wsl/.wslconfig`
- Create: `_migration/install/90-wsl.sh`

**Interfaces:**
- Consumes: `lib.sh` (`win_home`, `backup_file`).
- Produces: `/etc/wsl.conf` and `<win_home>/.wslconfig`. Neither takes effect until `wsl --shutdown`.

- [ ] **Step 1: Write `_migration/wsl/wsl.conf`**

```ini
# → /etc/wsl.conf  (installed by _migration/install/90-wsl.sh)
#
# Takes effect after `wsl --shutdown` from Windows.

[boot]
systemd = true

[user]
default = muzzakhan

[automount]
# metadata is what makes chmod/chown actually stick under /mnt/c.
options = "metadata,umask=22,fmask=11"

[interop]
# Windows PATH stays appended — `explorer.exe .`, `cmd.exe`, and wslpath-based
# tooling all depend on it. It does cost some shell-startup time.
appendWindowsPath = true
```

- [ ] **Step 2: Write `_migration/wsl/.wslconfig`**

Sized for a 32GB host. The comments are load-bearing — they explain the two omissions.

```ini
# → C:\Users\<you>\.wslconfig  (installed by _migration/install/90-wsl.sh)
#
# Applies to ALL WSL2 distros. Takes effect after `wsl --shutdown`.
# Tuned for a 32GB host.

[wsl2]
# Default is 50% of host RAM = 16GB, which is tight for the portal container
# stack plus a Next build. 20GB leaves Windows 12GB.
memory=20GB

# OOM insurance; cheap on NVMe.
swap=8GB

# Survives corporate VPN DNS, which otherwise breaks resolution in the distro.
dnsTunneling=true

# Chromium runs headless under xvfb here, so WSLg is dead weight.
guiApplications=false

# The VHD otherwise only ever grows — this lets freed space be reclaimed.
sparseVhd=true

# --- Deliberate omissions ------------------------------------------------
#
# processors: omitted on purpose. Defaults to all logical cores, which is what
#   we want, and hardcoding it would be wrong on a machine with a different
#   core count.
#
# autoMemoryReclaim: deliberately NOT set. It hands "free" pages back to
#   Windows, but that includes the page cache holding node_modules and docker
#   layers. Worth the trade on a 16GB box; on 32GB it buys back RAM we do not
#   need at the cost of rebuild latency.
#
# networkingMode=mirrored: left commented out. It is the best option for
#   host<->container networking, but still has rough edges with published
#   ports. Enable deliberately, later, not during a rebuild.
# networkingMode=mirrored
```

- [ ] **Step 3: Write `_migration/install/90-wsl.sh`**

```bash
#!/usr/bin/env bash
#
# 90-wsl.sh — install /etc/wsl.conf and the Windows-side .wslconfig.
#
# Neither file takes effect until `wsl --shutdown` runs from Windows. This
# script prints that instruction rather than attempting it: the shutdown would
# kill the script (and the rest of the bootstrap) mid-run.
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SRC_WSL_CONF="$MIGRATION_DIR/wsl/wsl.conf"
SRC_WSLCONFIG="$MIGRATION_DIR/wsl/.wslconfig"

[[ -f $SRC_WSL_CONF ]] || die "missing $SRC_WSL_CONF"
[[ -f $SRC_WSLCONFIG ]] || die "missing $SRC_WSLCONFIG"

# --- /etc/wsl.conf -------------------------------------------------------
if [[ $DRY_RUN == 1 ]]; then
	warn "would write /etc/wsl.conf from $SRC_WSL_CONF"
else
	if [[ -f /etc/wsl.conf ]] && ! cmp -s "$SRC_WSL_CONF" /etc/wsl.conf; then
		log "backing up /etc/wsl.conf -> /etc/wsl.conf.bak"
		sudo cp -a /etc/wsl.conf /etc/wsl.conf.bak
	fi
	log "writing /etc/wsl.conf"
	sudo install -m 0644 "$SRC_WSL_CONF" /etc/wsl.conf
	ok "/etc/wsl.conf installed"
fi

# --- Windows .wslconfig --------------------------------------------------
if ! wh="$(win_home)"; then
	warn "could not resolve the Windows user profile (cmd.exe interop unavailable)."
	warn "Copy this file to C:\\Users\\<you>\\.wslconfig by hand:"
	warn "  $SRC_WSLCONFIG"
else
	dest="$wh/.wslconfig"
	if [[ $DRY_RUN == 1 ]]; then
		warn "would write $dest from $SRC_WSLCONFIG"
	else
		if [[ -f $dest ]] && ! cmp -s "$SRC_WSLCONFIG" "$dest"; then
			log "backing up $dest -> ${dest}.bak"
			cp -a "$dest" "${dest}.bak"
		fi
		log "writing $dest"
		install -m 0644 "$SRC_WSLCONFIG" "$dest"
		ok ".wslconfig installed to $dest"
	fi
fi

warn "NEITHER file is active yet. From Windows PowerShell, run:  wsl --shutdown"
```

- [ ] **Step 4: Make executable, syntax-check, lint**

```bash
cd ~/dotfiles
chmod +x _migration/install/90-wsl.sh
bash -n _migration/install/90-wsl.sh && echo "SYNTAX OK"
shellcheck -x _migration/install/90-wsl.sh
```
Expected: `SYNTAX OK`, no shellcheck output.

- [ ] **Step 5: Dry-run — verifies `win_home` resolves without writing anything**

```bash
cd ~/dotfiles
DRY_RUN=1 bash _migration/install/90-wsl.sh
```
Expected: `would write /etc/wsl.conf …`, `would write /mnt/c/Users/muzza.khan/.wslconfig …`, and the `wsl --shutdown` warning. If the second line is the "could not resolve" fallback instead, `cmd.exe` interop is broken — that is a real finding to report, not something to paper over.

- [ ] **Step 6: Confirm the current `/etc/wsl.conf` would be preserved**

This box has a real `/etc/wsl.conf` with `systemd=true` and the default user. Confirm the new one is a superset before anything overwrites it on the real run.

```bash
diff <(cat /etc/wsl.conf) _migration/wsl/wsl.conf || true
```
Expected: the new file adds `[automount]` and `[interop]` blocks and comments; it must not *drop* `systemd = true` or `default = muzzakhan`. Confirm both are present in the new file.

- [ ] **Step 7: No commit.**

---

### Task 8: `smoke-test.sh`

The final report. Runnable standalone, never marked done, and safe on this box — which makes it the one script that can be meaningfully executed end-to-end right now.

**Files:**
- Create: `_migration/smoke-test.sh`

**Interfaces:**
- Consumes: `lib.sh`.
- Produces: a pass/fail report. Exits 1 if any check fails, so `bootstrap.sh` can warn.

- [ ] **Step 1: Write `_migration/smoke-test.sh`**

```bash
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
	v=$("$cmd" --version 2>&1 | head -1)
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
for c in zsh tmux nvim git gh stow fnm node npm docker lazygit fzf zoxide rg fd jq pipx; do
	check_version "$c"
done

heading "Stowed config"
for p in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.config/nvim" "$HOME/.config/tmux" \
	"$HOME/.config/git/config" "$HOME/.claude/settings.json" "$HOME/.local/bin/ss"; do
	check "symlink into repo: ${p/#$HOME/~}" is_symlink_into_repo "$p"
done

heading "Docker"
check "docker daemon reachable" docker info
check "docker group membership" bash -c 'id -nG "$USER" | tr " " "\n" | grep -qx docker'
check "hello-world runs" docker run --rm hello-world

heading "Neovim plugins"
check "Lazy! check exits clean" nvim --headless "+Lazy! check" +qa

heading "Repos"
manifest="$MIGRATION_DIR/repos.tsv"
if [[ -f $manifest ]]; then
	while IFS=$'\t' read -r name _; do
		[[ -z ${name// /} || $name == \#* ]] && continue
		check "~/code/$name" test -d "$HOME/code/$name"
	done <"$manifest"
else
	warn "FAIL: $manifest missing"
	fail=$((fail + 1))
fi

heading "Secrets (presence only — contents never checked)"
for f in "$HOME/.ssh/id_ed25519" "$HOME/.config/secrets" "$HOME/.npmrc"; do
	check "exists: ${f/#$HOME/~}" test -s "$f"
done
check "npmrc has a token" bash -c 'grep -qE "_authToken=.+" "$HOME/.npmrc"'
check "gh authenticated" gh auth status

heading "Result"
if ((fail == 0)); then
	ok "all $pass checks passed"
	exit 0
fi
warn "$fail of $((pass + fail)) checks failed"
exit 1
```

- [ ] **Step 2: Make executable, syntax-check, lint**

```bash
cd ~/dotfiles
chmod +x _migration/smoke-test.sh
bash -n _migration/smoke-test.sh && echo "SYNTAX OK"
shellcheck -x _migration/smoke-test.sh
```
Expected: `SYNTAX OK`, no shellcheck output.

- [ ] **Step 3: Run it for real on this box**

Safe — every check is read-only except `docker run --rm hello-world`.

```bash
cd ~/dotfiles
./_migration/smoke-test.sh; echo "exit=$?"
```
Expected on **this** machine: most checks pass; `fnm` fails (not installed here — nvm is), `~/.config/git/config` fails (created in Task 9), and `exit=1`. That is the correct result, and it proves the failure accounting works. Everything else — the symlink checks, docker, repos, nvim — should pass. Investigate anything else that fails.

- [ ] **Step 4: Confirm the all-pass path is reachable**

Verify the exit-0 branch is not dead code:

```bash
cd ~/dotfiles
bash -c 'source _migration/install/lib.sh; pass=3; fail=0; ((fail==0)) && { ok "all $pass checks passed"; exit 0; }'; echo "exit=$?"
```
Expected: `all 3 checks passed` and `exit=0`.

- [ ] **Step 5: No commit.**

---

### Task 9: Config edits — `git` package, `.zshrc` cleanup, tmux tpm path

The only task that touches existing tracked files. Grouped because all three are the "deviations" the spec approved, and a reviewer would judge them together.

**Files:**
- Create: `git/.config/git/config`
- Modify: `zsh/.zshrc`
- Modify: `tmux/.config/tmux/tmux.conf:100-104`

**Interfaces:**
- Consumes: the fnm install dir `$HOME/.local/share/fnm` from Task 3, and the tpm dir `$HOME/.config/tmux/plugins/tpm` from Task 5. Both paths must match exactly.
- Produces: the `git` Stow package that `50-stow.sh` lists in `PACKAGES`, and the `~/.config/git/config` path `smoke-test.sh` checks.

- [ ] **Step 1: Create the `git` Stow package**

Content is the current `~/.gitconfig` verbatim — it holds no secrets (`gh` supplies credentials at runtime). Write to `git/.config/git/config`:

```ini
[user]
	name = Muzza Khan
	email = muzza.khan@mmem.com.au
[credential "https://github.com"]
	helper =
	helper = !/usr/bin/gh auth git-credential
[credential "https://gist.github.com"]
	helper =
	helper = !/usr/bin/gh auth git-credential
[url "https://github.com/"]
	insteadOf = git@github.com:
```

Two things to be careful about: keep the leading **tabs** (git's own formatting), and keep the empty `helper =` lines — they reset any system-level helper, and dropping them changes behaviour.

- [ ] **Step 2: Verify the git package parses**

```bash
cd ~/dotfiles
git config --file git/.config/git/config --list
```
Expected: seven entries, matching `git config --global --list` on this box (order may differ).

- [ ] **Step 3: Edit `zsh/.zshrc` — replace the nvm block**

Find:

```sh
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
```

Replace with:

```sh
# fnm (node version manager) — replaces nvm. Sourcing nvm.sh cost 300-600ms on
# every shell start; fnm is a static binary doing the same job in ~10ms and
# still honours .nvmrc. --use-on-cd switches version on directory change.
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd --shell zsh)"
```

- [ ] **Step 4: Edit `zsh/.zshrc` — remove the Homebrew eval**

Delete this line entirely (Homebrew is no longer installed):

```sh
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
```

- [ ] **Step 5: Edit `zsh/.zshrc` — de-duplicate the tmux plugin PATH**

Find both lines:

```sh
# ~/.tmux/plugins
export PATH=$HOME/.tmux/plugins/t-smart-tmux-session-manager/bin:$PATH
# ~/.config/tmux/plugins
export PATH=$HOME/.config/tmux/plugins/t-smart-tmux-session-manager/bin:$PATH
```

Replace both with just:

```sh
# t-smart-tmux-session-manager (installed by tpm under ~/.config/tmux/plugins)
export PATH="$HOME/.config/tmux/plugins/t-smart-tmux-session-manager/bin:$PATH"
```

- [ ] **Step 6: Edit `zsh/.zshrc` — de-duplicate `~/.local/bin`**

`~/.local/bin` is currently added twice, once with a hardcoded home. Delete the pipx-generated block:

```sh
# Created by `pipx` on 2026-05-27 00:30:42
export PATH="$PATH:/home/muzzakhan/.local/bin"
```

Keep the existing final block unchanged:

```sh
# User scripts (dotfiles bin package)
export PATH="$HOME/.local/bin:$PATH"
```

- [ ] **Step 7: Fix the tpm path in `tmux/.config/tmux/tmux.conf`**

The config auto-installs tpm to `~/.tmux/plugins/tpm` while the actual plugins live in `~/.config/tmux/plugins/` — the same stale path as the duplicated `.zshrc` entry. `60-tmux.sh` uses the `~/.config` path, so these must agree.

Find (around lines 100-104):

```tmux
# Auto-install TPM if missing, then init
if "test ! -d ~/.tmux/plugins/tpm" \
   "run 'git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm && ~/.tmux/plugins/tpm/bin/install_plugins'"

run '~/.tmux/plugins/tpm/tpm'
```

Replace with:

```tmux
# Auto-install TPM if missing, then init.
# Path must match _migration/install/60-tmux.sh.
if "test ! -d ~/.config/tmux/plugins/tpm" \
   "run 'git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm && ~/.config/tmux/plugins/tpm/bin/install_plugins'"

run '~/.config/tmux/plugins/tpm/tpm'
```

**Do not disturb the other unstaged changes already in this file.** Change only these five lines.

- [ ] **Step 8: Verify the edited `.zshrc` is valid and free of the removed lines**

```bash
cd ~/dotfiles
zsh -n zsh/.zshrc && echo "ZSH SYNTAX OK"
echo "--- should print nothing: ---"
grep -nE 'NVM_DIR|linuxbrew|\.tmux/plugins|/home/muzzakhan/\.local/bin' zsh/.zshrc
echo "--- should print 1: ---"
grep -c 'export PATH="\$HOME/.local/bin:\$PATH"' zsh/.zshrc
echo "--- should print the fnm line: ---"
grep -n 'fnm env' zsh/.zshrc
```
Expected: `ZSH SYNTAX OK`, no output from the first grep, `1` from the count, and the `fnm env --use-on-cd --shell zsh` line.

- [ ] **Step 9: Verify the tmux config still loads**

```bash
cd ~/dotfiles
grep -n 'plugins/tpm' tmux/.config/tmux/tmux.conf
TMUX_TMPDIR=$HOME/.cache tmux -f tmux/.config/tmux/tmux.conf new-session -d -s smoketest 2>&1 | head
TMUX_TMPDIR=$HOME/.cache tmux kill-session -t smoketest 2>/dev/null || true
```
Expected: all three `plugins/tpm` hits under `~/.config/tmux/`, and the session starts and dies without config errors. Harmless "plugin not found" style output is acceptable here; a syntax error is not.

- [ ] **Step 10: Re-run the Task 4 Step 8 dry-run, now that `git/` exists**

```bash
cd ~/dotfiles
DRY_RUN=1 bash _migration/install/50-stow.sh; echo "exit=$?"
```
Expected: `exit=0`, a `would back up /home/muzzakhan/.gitconfig` line, `stow --no` reporting no conflicts, and both seed calls reporting the real files already exist.

- [ ] **Step 11: Warn about this shell session**

Do **not** re-source `~/.zshrc` in an interactive session on this box — `fnm` is not installed here, so `eval "$(fnm env …)"` will error and the nvm-managed node will drop off PATH. The edit is correct for the *new* box. Leave the current session alone.

- [ ] **Step 12: No commit.**

---

### Task 10: `MIGRATION.md` and `_migration/README.md`

**Files:**
- Create: `_migration/MIGRATION.md`
- Create: `_migration/README.md`

**Interfaces:**
- Consumes: nothing. Documentation only.
- Produces: the checklist `bootstrap.sh`'s closing message points at.

- [ ] **Step 1: Write `_migration/MIGRATION.md`**

```markdown
# Pre-wipe migration checklist

Run through this on the **OLD** machine, before the WSL distro is deleted.
Ordered by consequence: section 1 is unrecoverable, section 6 is convenience.

`testing` branches are out of scope everywhere — they are throwaway.

## 1. Code at risk (unrecoverable once the distro is gone)

- [ ] `portal-core` — three local-only branches with no upstream. Push or
      consciously discard each:

      ```sh
      cd ~/code/portal-core
      for b in feat/domain-shell-header pr-562 review-pr-740; do
        git push -u origin "$b"
      done
      ```

- [ ] `AutoDoc` — one dirty file. Commit, or stash and push the stash, or
      accept losing it: `cd ~/code/AutoDoc && git status`
- [ ] Stashes everywhere. Anything listed here dies with the distro:

      ```sh
      for d in ~/code/*/; do
        s=$(git -C "$d" stash list 2>/dev/null) || continue
        [ -n "$s" ] && printf '\n%s\n%s\n' "$(basename "$d")" "$s"
      done
      ```

- [ ] Leftover worktrees from the feature-worktree workflow:

      ```sh
      for d in ~/code/*/; do git -C "$d" worktree list 2>/dev/null | tail -n +2; done
      ```

- [ ] Any other unpushed commits:

      ```sh
      for d in ~/code/*/; do
        git -C "$d" for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads |
        while read -r b u; do
          [ "$b" = testing ] && continue
          if [ -z "$u" ]; then echo "$(basename "$d")  $b  [no upstream]"
          else n=$(git -C "$d" rev-list --count "$u..$b" 2>/dev/null)
               [ "$n" != 0 ] && echo "$(basename "$d")  $b  [ahead $n]"
          fi
        done
      done
      ```

- [ ] **`~/code/audit-tools` and `~/code/plan-agent` have no remote at all.**
      They are not in `repos.tsv` and cannot be cloned. Create a repo and push,
      or tarball them out to Windows — otherwise they are gone:

      ```sh
      tar -czf /mnt/c/Users/muzza.khan/wsl-migration/no-remote-repos.tar.gz \
        -C ~/code audit-tools plan-agent
      ```

## 2. Copy out to a Windows staging directory

Stage at `C:\Users\muzza.khan\wsl-migration\` (`mkdir -p /mnt/c/Users/muzza.khan/wsl-migration`).
Delete the staging directory once the new box is verified.

- [ ] `~/.ssh/id_ed25519` and `id_ed25519.pub` (and `known_hosts` for convenience)
- [ ] `~/.config/secrets`
- [ ] **`~/.local/share/mkcert/rootCA-key.pem` + `rootCA.pem`** — highest
      consequence item in this section. Without the CA key, every
      locally-trusted certificate breaks and a new CA has to be generated and
      re-trusted in Windows.

      ```sh
      mkdir -p /mnt/c/Users/muzza.khan/wsl-migration
      cp -a ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub ~/.ssh/known_hosts \
            ~/.config/secrets \
            "$(mkcert -CAROOT)"/rootCA*.pem \
            /mnt/c/Users/muzza.khan/wsl-migration/
      ```

- [ ] After restoring on the new box: `chmod 600 ~/.ssh/id_ed25519` and
      `chmod 600 ~/.config/secrets`.

## 3. Rotate rather than carry

These hold live credentials in a form that is *not* encrypted. The rebuild is a
free opportunity to rotate rather than copy.

- [ ] `~/.docker/config.json` — holds a GitHub PAT (ghcr.io) and two Docker Hub
      tokens as **plain base64**, which is encoding, not encryption. Revoke and
      re-issue, then `docker login` fresh on the new box.
- [ ] `~/.npmrc` — holds the `@mmem` GitHub Packages PAT. Revoke, issue a new
      classic PAT with `read:packages`, and put it in the `~/.npmrc` that
      `50-stow.sh` seeds from `templates/npmrc.example`.

## 4. Re-authenticate on the new box (nothing to copy)

- [ ] `gh auth login` — needed *before* cloning this repo, so it happens in the
      prologue anyway
- [ ] `claude` — log in on first run
- [ ] `docker login` and `docker login ghcr.io` (with the rotated tokens)
- [ ] Add the new npm token to `~/.npmrc`
- [ ] Fill in `~/.config/secrets`

## 5. Windows side (outside WSL entirely)

- [ ] Windows Terminal `settings.json` — back up the profile, and note which
      **Nerd Font** is set. tmux and Neovim glyphs render as tofu without it.
      Path: `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json`
- [ ] `C:\Windows\System32\drivers\etc\hosts` — any local portal domain entries
- [ ] `.wslconfig` — `90-wsl.sh` writes it, then run `wsl --shutdown` from
      PowerShell to apply
- [ ] Re-trust the mkcert root CA in Windows if the CA key was **not** carried
      over: `mkcert -install`

## 6. Low priority

- [ ] **Confirm the nonprod Key Vault service-principal credentials are in
      1Password.** `.azure-kv.local` exists in `portal-core`, `portal-cga`, and
      `portal-qms`. It is the one secret Key Vault cannot supply
      (chicken-and-egg), so `scripts/fetch-secrets` cannot run without it. If
      it is not in 1Password, capture it before the wipe:

      ```sh
      grep -l . ~/code/*/.azure-kv.local 2>/dev/null
      ```

- [ ] While checking: `portal-core/.azure-kv.local` has the **prod** SP secret
      populated, contrary to that file's own instruction to leave prod blank on
      a dev machine. Do not carry it over to the new box.
- [ ] `docker volume ls` — decide whether any database volume is worth
      preserving (`docker run --rm -v <vol>:/v -v /mnt/c/...:/out alpine tar -czf /out/<vol>.tgz -C /v .`)
- [ ] Recreate the `~/windir` convenience symlink:
      `ln -s /mnt/c/Users/muzza.khan ~/windir`
- [ ] `~/.zsh_history`, if the history is worth keeping

## Deliberately NOT migrated

- **`.env` files.** Every portal repo regenerates them from Azure Key Vault via
  `./scripts/fetch-secrets`. Only `.azure-kv.local` (section 6) matters.
- **tmux sessions.** New sessions are fine.
- **`~/.claude.json`.** 82KB of per-project history and MCP state; Claude Code
  rebuilds it after a fresh login.
- **`~/.nvm`.** Replaced by fnm.
- **Homebrew.** Its four packages now come from apt or a release tarball.
```

- [ ] **Step 2: Write `_migration/README.md`**

```markdown
# One-shot machine rebuild

Rebuilds this dev environment on a fresh Ubuntu 24.04 WSL distro: node, docker,
claude, nvim, tmux, zsh, the working repos, and WSL/docker performance tuning.

Before wiping the old machine, work through **[MIGRATION.md](MIGRATION.md)** —
keys, tokens, and unpushed work that no script can carry.

## Prologue (on the fresh distro)

This repo needs authentication to clone, so three commands come first:

```sh
sudo apt update && sudo apt install -y git gh
gh auth login                                             # device flow, browser on Windows
git clone https://github.com/muzza-mmem/dotfiles.git ~/dotfiles
~/dotfiles/_migration/bootstrap.sh
```

Then follow the manual steps `bootstrap.sh` prints at the end — the important
one is `wsl --shutdown` from Windows PowerShell, which applies `.wslconfig` and
also picks up the docker group change.

## Usage

```sh
./bootstrap.sh            # run everything outstanding
./bootstrap.sh --list     # show modules and status
./bootstrap.sh 30         # re-run just the 30-* module
./bootstrap.sh --force    # ignore completion markers
./bootstrap.sh --dry-run  # print what would happen, change nothing
./smoke-test.sh           # verification report, safe any time
```

Every module is idempotent — re-running the whole thing on a healthy box is a
no-op. Completion markers live in `~/.local/state/dotfiles-bootstrap/`; delete
one to force that module to re-run.

## Modules

| Module | Does |
|---|---|
| `00-apt.sh` | apt upgrade + all apt packages (incl. headless-Chromium libs) |
| `10-shell.sh` | oh-my-zsh, zsh as login shell |
| `20-node.sh` | fnm, node 24, npm globals |
| `30-docker.sh` | Docker CE, `daemon.json`, docker group |
| `40-tools.sh` | lazygit, pipx apps |
| `50-stow.sh` | Stow every package, seed secret templates |
| `60-tmux.sh` | tpm + plugins |
| `70-nvim.sh` | Neovim from upstream tarball, `Lazy! sync` |
| `80-repos.sh` | Clone `repos.tsv` into `~/code` |
| `90-wsl.sh` | `/etc/wsl.conf` + Windows `.wslconfig` |

Order matters in two places: `00-apt.sh` precedes everything, and `50-stow.sh`
must precede `60-tmux.sh` and `70-nvim.sh` (both need their stowed config).

## Adding a repo

Append a `name<TAB>remote` line to `repos.tsv`, then `./bootstrap.sh 80`.
Repos with no remote cannot be cloned — see MIGRATION.md section 1.

## Troubleshooting

**`30-docker.sh` fails with "System has not been booted with systemd"**
`/etc/wsl.conf` has not been applied yet. Run `./bootstrap.sh 90`, then
`wsl --shutdown` from Windows, reopen the distro, and `./bootstrap.sh 30`.

**`docker info` fails but docker is installed**
The group change needs a new session: `wsl --shutdown` from Windows, or
`newgrp docker` for the current shell only.

**`60-tmux.sh` finishes but plugins are missing**
Install interactively: start `tmux`, then `prefix + I` (capital i).

**`70-nvim.sh` download 404s**
The release asset name changed. List real names with
`curl -fsSL https://api.github.com/repos/neovim/neovim/releases/tags/stable | jq -r '.assets[].name'`
and update the URL in the module.

**Stow refuses to link a file**
A real file is in the way. `50-stow.sh` moves conflicts to `<file>.pre-stow`
automatically, but if it reports a conflict it could not resolve, move the file
aside by hand and re-run `./bootstrap.sh 50`.

**`.wslconfig` changes did nothing**
It only applies after `wsl --shutdown` from Windows PowerShell — not from
inside the distro.
```

- [ ] **Step 3: Verify every referenced path and command actually exists**

Documentation drift is the failure mode here. Check the claims:

```bash
cd ~/dotfiles
echo "--- files referenced by README/MIGRATION must exist ---"
for f in _migration/bootstrap.sh _migration/smoke-test.sh _migration/repos.tsv \
         _migration/MIGRATION.md _migration/templates/npmrc.example \
         _migration/wsl/wsl.conf _migration/wsl/.wslconfig; do
  [ -e "$f" ] && echo "ok   $f" || echo "MISSING $f"
done
echo "--- every module named in README must exist ---"
grep -oE '`[0-9]{2}-[a-z]+\.sh`' _migration/README.md | tr -d '`' | sort -u |
  while read -r m; do
    [ -f "_migration/install/$m" ] && echo "ok   $m" || echo "MISSING $m"
  done
echo "--- mkcert CAROOT claim ---"
mkcert -CAROOT
ls "$(mkcert -CAROOT)" 2>/dev/null || echo "NOTE: no mkcert CA on this box yet"
```
Expected: every line `ok`, and `mkcert -CAROOT` prints a path. If the CAROOT directory is empty or missing, correct MIGRATION.md section 2 to say the CA has not been created yet rather than telling you to copy a file that does not exist.

- [ ] **Step 4: Verify the MIGRATION.md diagnostic snippets run**

These are the commands you will rely on under time pressure. Run them now.

```bash
cd ~/dotfiles
# stash sweep
for d in ~/code/*/; do s=$(git -C "$d" stash list 2>/dev/null) || continue; [ -n "$s" ] && printf '\n%s\n%s\n' "$(basename "$d")" "$s"; done; echo "stash sweep ok"
# worktree sweep
for d in ~/code/*/; do git -C "$d" worktree list 2>/dev/null | tail -n +2; done; echo "worktree sweep ok"
# unpushed sweep, testing excluded
for d in ~/code/*/; do git -C "$d" for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads | while read -r b u; do [ "$b" = testing ] && continue; if [ -z "$u" ]; then echo "$(basename "$d")  $b  [no upstream]"; else n=$(git -C "$d" rev-list --count "$u..$b" 2>/dev/null); [ "$n" != 0 ] && echo "$(basename "$d")  $b  [ahead $n]"; fi; done; done; echo "unpushed sweep ok"
# azure-kv sweep
grep -l . ~/code/*/.azure-kv.local 2>/dev/null; echo "kv sweep ok"
```
Expected: all four print their `ok` line. The unpushed sweep must list exactly the three `portal-core` branches and **no `testing` branch**. The kv sweep must list `portal-core`, `portal-cga`, `portal-qms`.

- [ ] **Step 5: No commit.**

---

### Task 11: Root README, final review, single commit

**Files:**
- Create: `README.md`
- Verify: everything

**Interfaces:**
- Consumes: all prior tasks.
- Produces: one commit containing the whole feature.

- [ ] **Step 1: Write the root `README.md`**

```markdown
# dotfiles

Configuration for local packages (zsh, tmux, nvim, claude, …), organised for
GNU Stow, plus a one-shot rebuild for a fresh WSL machine.

## Rebuilding a machine

See **[`_migration/README.md`](_migration/README.md)**. On a fresh Ubuntu 24.04
WSL distro:

```sh
sudo apt update && sudo apt install -y git gh
gh auth login
git clone https://github.com/muzza-mmem/dotfiles.git ~/dotfiles
~/dotfiles/_migration/bootstrap.sh
```

Before wiping an old machine, work through
[`_migration/MIGRATION.md`](_migration/MIGRATION.md).

## Layout

Every top-level directory except `_migration/` is a Stow package mirroring the
structure that should appear under `~`:

```
dotfiles/
└── tmux/
    └── .config/
        └── tmux/
            └── tmux.conf      → ~/.config/tmux/tmux.conf
```

| Package | Stows to |
|---|---|
| `bash` | `~/.bashrc` |
| `bin` | `~/.local/bin/` helper scripts |
| `claude` | `~/.claude/` settings, hooks, skills |
| `git` | `~/.config/git/config` |
| `nvim` | `~/.config/nvim/` (NvChad) |
| `tmux` | `~/.config/tmux/` |
| `zsh` | `~/.zshrc` |

`stow <package>` to link, `stow -D <package>` to unlink, `stow -R <package>` to
restow after changes. `_migration/install/50-stow.sh` does all of them at once.

See [CLAUDE.md](CLAUDE.md) for conventions when adding a package.
```

- [ ] **Step 2: Full static sweep over every script**

```bash
cd ~/dotfiles
for f in _migration/bootstrap.sh _migration/smoke-test.sh _migration/install/*.sh; do
  bash -n "$f" || echo "SYNTAX FAIL: $f"
done
echo "--- syntax done ---"
shellcheck -x _migration/bootstrap.sh _migration/smoke-test.sh _migration/install/*.sh
echo "--- shellcheck exit=$? ---"
zsh -n zsh/.zshrc && echo "zshrc ok"
```
Expected: no `SYNTAX FAIL`, shellcheck clean with `exit=0`, `zshrc ok`.

- [ ] **Step 3: Confirm executability and no stray secrets**

```bash
cd ~/dotfiles
echo "--- must all be executable ---"
find _migration -name '*.sh' ! -perm -u+x -print | sed 's/^/NOT EXECUTABLE: /'
echo "--- must find nothing: token-shaped strings ---"
grep -rInE '(ghp_|dckr_pat_|gho_|github_pat_|-----BEGIN)' _migration/ git/ zsh/ || echo "clean"
echo "--- templates must have empty values ---"
grep -nE '_authToken=' _migration/templates/npmrc.example
```
Expected: no output from the first two checks (or `clean`), and `_authToken=` with **nothing** after the `=`.

- [ ] **Step 4: Full dry-run of the whole bootstrap**

```bash
cd ~/dotfiles
./_migration/bootstrap.sh --list
DOTFILES_STATE_DIR=$(mktemp -d) ./_migration/bootstrap.sh --dry-run; echo "exit=$?"
```
Expected: `--list` shows all ten modules. The dry-run walks every module in order and exits 0. It ends by running `smoke-test.sh`, which will report failures on this box (`fnm`, `~/.config/git/config` — the latter now only because the package is not stowed here yet) — that is expected and does not fail the dry-run.

Use a throwaway `DOTFILES_STATE_DIR` so this does not leave markers that make a real future run skip modules.

- [ ] **Step 5: Self-review the diff before committing**

```bash
cd ~/dotfiles
git status --short
git diff --stat
git diff zsh/.zshrc tmux/.config/tmux/tmux.conf
```
Check specifically:
- `bin/.local/bin/ss` still shows its **pre-existing** unstaged changes, unmodified by this work.
- `tmux/.config/tmux/tmux.conf` shows both its pre-existing changes and only the five-line tpm path fix.
- No file under `_migration/` contains a real credential.

- [ ] **Step 6: Commit everything as one squashed commit**

```bash
cd ~/dotfiles
git add _migration/ git/ README.md CLAUDE.md zsh/.zshrc tmux/.config/tmux/tmux.conf
git status --short
git commit -m "$(cat <<'EOF'
Add _migration: one-shot rebuild for a fresh WSL machine

bootstrap.sh runs install/[0-9][0-9]-*.sh in order, each module idempotent
and individually re-runnable, with completion markers so re-runs skip
finished work. smoke-test.sh reports final state and is safe to run any time.

MIGRATION.md is the pre-wipe checklist for what no script can carry: SSH key,
the mkcert root CA, ~/.config/secrets, and unpushed work. Tokens in
~/.docker/config.json and ~/.npmrc are flagged for rotation rather than copy.

Targets Ubuntu 24.04 on a 32GB host. .wslconfig raises the memory cap to 20GB
and enables sparseVhd, but deliberately omits autoMemoryReclaim, which would
drop the page cache holding node_modules and docker layers.

Four deliberate changes from the old setup: Homebrew dropped (its four
packages come from apt or a release tarball), nvm replaced with fnm (~10ms vs
300-600ms per shell start), Neovim from the upstream tarball since noble ships
0.10, and ~/.gitconfig moved to the XDG path as a new git package. Also
de-duplicates PATH entries in .zshrc and fixes the stale ~/.tmux/plugins tpm
path in tmux.conf to match ~/.config/tmux/plugins.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git log --oneline -1
```

**Do not stage `bin/.local/bin/ss`** — its changes predate this work and belong in their own commit.

- [ ] **Step 7: Report what remains unverified**

State plainly, without hedging, that the following are untested and can only be confirmed on a real fresh distro:

1. Every noble-only package name (the `t64` renames) — they do not exist on 22.04.
2. `fnm install 24` resolving, and the fnm install script's `--install-dir`/`--skip-shell` flags.
3. Docker's noble apt repo carrying all five packages, and `systemctl enable --now docker` succeeding before `wsl.conf` is applied.
4. `stow` linking cleanly over a genuinely fresh Ubuntu home (real `.bashrc`/`.profile` in place).
5. tpm's headless `install_plugins` under tmux 3.4, and `Lazy! sync` on a cold Neovim.
6. `.wslconfig` actually taking effect, which needs a Windows-side `wsl --shutdown`.

Recovery for each is in `_migration/README.md`'s troubleshooting section, and
any single module can be re-run with `./bootstrap.sh <NN>`.

---

## Self-Review

**Spec coverage** — every spec section maps to a task:

| Spec section | Task |
|---|---|
| `_migration/` layout, not a Stow package | 1 (+ CLAUDE.md note) |
| Bootstrap contract (arg parsing, markers, idempotency, root guard) | 1 |
| `lib.sh` helper set | 1 |
| Prologue (git/gh/auth/clone) | 10 (README) |
| `00-apt` … `90-wsl` modules | 2, 3, 4, 5, 6, 7 |
| Module ordering constraints | 2–7, documented in 10 |
| `repos.tsv`, audit-tools/plan-agent excluded | 6 |
| Deviation 1: Homebrew removed | 2 (apt sources fzf/zoxide/pipx), 4 (lazygit) |
| Deviation 2: nvm → fnm | 3, 9 |
| Deviation 3: Neovim upstream tarball | 5 |
| Deviation 4: gitconfig → XDG Stow package | 9 |
| `.zshrc` cleanup (4 edits) | 9 |
| `.wslconfig` + `/etc/wsl.conf` | 7 |
| `daemon.json` | 3 |
| `MIGRATION.md` sections 1–6 | 10 |
| Templates, no secrets in repo | 4 (+ 11 Step 3 grep) |
| Error handling (backup, non-fatal clones, root guard) | 1, 4, 6 |
| Verification / smoke test | 8 |

Two spec details corrected in this plan, both flagged inline: lazygit ships
tarballs rather than `.deb`, and `tmux.conf`'s stale tpm path needed fixing to
match `60-tmux.sh` (the spec did not mention it).

**Placeholder scan** — no TBD/TODO, no "add error handling", no "similar to
Task N". Every code step has complete, runnable content.

**Type/name consistency** — checked across tasks: `REPO_ROOT`, `MIGRATION_DIR`,
`STATE_DIR`, `DRY_RUN`, `log`/`ok`/`warn`/`die`/`heading`, `have`,
`apt_install`, `step_done`/`mark_step_done`, `backup_file`, `win_home` are
defined once in Task 1 and used with those exact names throughout. The fnm
install dir `$HOME/.local/share/fnm` matches between Task 3 and Task 9's
`.zshrc` edit. The tpm path `$HOME/.config/tmux/plugins/tpm` matches between
Task 5, Task 9's `tmux.conf` edit, and `.gitignore`'s existing
`/tmux/.config/tmux/plugins`. The `PACKAGES` array in Task 4 lists `git`, which
Task 9 creates — hence Task 4 Step 8's expected failure and its re-run in Task
9 Step 10.
```
