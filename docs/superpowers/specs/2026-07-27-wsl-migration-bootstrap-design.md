# WSL Migration Bootstrap — Design

Date: 2026-07-27
Status: Approved

## Purpose

Make this repo the single artifact needed to rebuild a working dev machine on a
fresh WSL distro. Given only clone access to `muzza-mmem/dotfiles`, one script
must restore the dev environment (node, docker, claude, nvim, tmux, zsh), clone
the working repos, and apply WSL + docker performance tuning. A companion
checklist covers what a script cannot carry: keys, tokens, and unpushed work.

The current machine is Ubuntu 22.04; the target is **Ubuntu 24.04 LTS** on a
host with **32GB RAM**. This is a deliberate fresh start, not a port — the old
filesystem is discarded.

## Non-goals

- Reproducing the old machine byte-for-byte. Four deliberate improvements are
  folded in (see Deviations).
- Storing any secret in this repo, encrypted or otherwise.
- Restoring `.env` files. Every portal repo regenerates them from Azure Key
  Vault via `scripts/fetch-secrets`.
- Restoring tmux sessions or shell history.
- Automating Windows-side installs (Terminal, fonts, VS Code).

## Architecture

Three artifacts, all under a new top-level `_migration/` directory. That
directory is **not** a Stow package — the repo root otherwise contains only
Stow packages, and `_migration/` is named to make that obvious.

```
dotfiles/
├── _migration/
│   ├── README.md            prologue: bare WSL → bootstrap in 3 commands
│   ├── MIGRATION.md          pre-wipe checklist (run on the OLD box)
│   ├── bootstrap.sh          entrypoint
│   ├── repos.tsv             name → remote manifest
│   ├── install/
│   │   ├── lib.sh
│   │   ├── 00-apt.sh   10-shell.sh  20-node.sh   30-docker.sh
│   │   ├── 40-tools.sh 50-stow.sh   60-tmux.sh   70-nvim.sh
│   │   └── 80-repos.sh 90-wsl.sh
│   ├── templates/
│   │   ├── npmrc.example
│   │   └── secrets.example
│   └── wsl/
│       ├── wsl.conf          → /etc/wsl.conf
│       └── .wslconfig        → /mnt/c/Users/<user>/.wslconfig
├── CLAUDE.md                 + note that _migration/ is not stowable
└── bash/ bin/ claude/ git/ nvim/ tmux/ zsh/     ← Stow packages
```

### Bootstrap contract

`bootstrap.sh` is the only entrypoint. It:

- Resolves the repo root as the parent of its own directory, so Stow always
  runs from the right place regardless of the caller's cwd.
- Runs `install/*.sh` in filename order.
- Accepts an optional numeric prefix argument (`./bootstrap.sh 30`) to run one
  module alone, for debugging a failed step.
- Records completion per module in `~/.local/state/dotfiles-bootstrap/` so a
  re-run skips finished work. `--force` ignores the markers.
- Is idempotent as a whole: running it twice on a healthy box is a no-op that
  exits 0.
- Prints a smoke-test summary at the end (see Verification).

Each module is a standalone bash script sourcing `install/lib.sh`, with
`set -euo pipefail`. A module's only interface is "run me on a fresh box, or
run me again on a configured one." No module depends on another's variables —
only on the state earlier modules leave on disk.

`install/lib.sh` provides: `log`/`ok`/`warn`/`die` output helpers, `have <cmd>`
existence checks, `apt_install` (installs only missing packages), and the
step-marker read/write used by `bootstrap.sh`.

### Prologue (manual, unavoidable)

The repo needs authentication to clone, so `_migration/README.md` opens with
the three commands that must precede everything:

```sh
sudo apt update && sudo apt install -y git gh
gh auth login                      # device flow, browser on Windows
git clone https://github.com/muzza-mmem/dotfiles.git ~/dotfiles
~/dotfiles/_migration/bootstrap.sh
```

### Modules

| Module | Responsibility |
|---|---|
| `00-apt.sh` | `apt update`/`upgrade`, then base packages: `git gh zsh tmux stow jq htop tree nmap pandoc mkcert ripgrep fd-find fzf zoxide pipx unzip build-essential` (`git`/`gh` are already present from the prologue; listed so the module stands alone) plus the font/lib set headless Chromium needs (`fonts-liberation fonts-noto-color-emoji libnss3 libatk-bridge2.0-0 libgbm1 libasound2t64 xvfb …`) |
| `10-shell.sh` | oh-my-zsh unattended install (`--keep-zshrc`, so Stow's `.zshrc` survives), then `chsh -s $(which zsh)` |
| `20-node.sh` | `fnm` via its install script, `fnm install 24 && fnm default 24`, then npm globals: `@anthropic-ai/claude-code`, `confluence-cli`, `corepack` |
| `30-docker.sh` | Docker's apt repo + `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`, `usermod -aG docker`, `/etc/docker/daemon.json` (log rotation + builder GC), `systemctl enable --now docker` |
| `40-tools.sh` | `lazygit` (latest .deb from GitHub releases), `pipx install sqlit-tui sshtunnel`, `pipx ensurepath` |
| `50-stow.sh` | Backs up any conflicting real file to `<file>.pre-stow`, then `stow bash bin claude git nvim tmux zsh` from the repo root. Copies `templates/*.example` to their destinations only if the real file is absent. |
| `60-tmux.sh` | Clone `tpm` into `~/.config/tmux/plugins/tpm`, headless plugin install |
| `70-nvim.sh` | Install upstream Neovim tarball to `/opt/nvim`, symlink into `/usr/local/bin`, then headless `Lazy! sync` so first launch is instant |
| `80-repos.sh` | Read `repos.tsv`, clone each into `~/code`, skipping any that already exist |
| `90-wsl.sh` | Write `/etc/wsl.conf` and `/mnt/c/Users/<user>/.wslconfig` from `wsl/`, backing up existing files. Prints the required `wsl --shutdown`. |

Ordering constraints that matter: `50-stow` must precede `60-tmux` and
`70-nvim` (both need the stowed config present), and `00-apt` must precede
everything.

### `repos.tsv`

Tab-separated `name<TAB>remote`, one per line, comments with `#`. Twelve repos
with GitHub remotes:

```
AutoDoc              https://github.com/MMEM/AutoDoc.git
ai-coding-standards  https://github.com/MMEM/ai-coding-standards.git
portal-autodoc       https://github.com/MMEM/portal-autodoc.git
portal-cga           https://github.com/MMEM/portal-cga.git
portal-core          https://github.com/MMEM/portal-core.git
portal-fx            https://github.com/MMEM/portal-fx.git
portal-keycloak      https://github.com/MMEM/portal-keycloak.git
portal-lti           https://github.com/MMEM/portal-lti.git
portal-openobserve   https://github.com/MMEM/portal-openobserve.git
portal-pbb           https://github.com/MMEM/portal-pbb.git
portal-qms           https://github.com/MMEM/portal-qms.git
portal-sales         https://github.com/MMEM/portal-sales.git
```

`~/code/audit-tools` and `~/code/plan-agent` are excluded: they have no remote
and therefore cannot be cloned. They appear in `MIGRATION.md` instead.

## Deviations from the current setup

Four intentional changes, each approved:

1. **Homebrew removed.** It existed for `fzf`, `lazygit`, `pipx`, `zoxide`.
   On 24.04 `fzf`, `zoxide`, and `pipx` are in apt and `lazygit` ships a .deb.
   Saves ~500MB and one `brew shellenv` eval per shell start.
2. **`nvm` → `fnm`.** Sourcing `nvm.sh` costs 300–600ms on every shell start;
   `fnm` is a static binary doing the same job in ~10ms, and still honours
   `.nvmrc`.
3. **Neovim from upstream tarball, not apt.** 24.04's apt Neovim is 0.10,
   which is too old for the NvChad config. This is the one package deliberately
   not installed from apt.
4. **`~/.gitconfig` → `git/.config/git/config`** as a new Stow package, per
   `CLAUDE.md`'s XDG preference. Contents unchanged and secret-free (name,
   email, `gh` credential helper, `insteadOf` rewrite).

`lazy-lock.json` stays gitignored, so nvim plugin versions are resolved fresh
at bootstrap time. This is a knowingly accepted reproducibility gap.

## `.zshrc` cleanup

Applied as part of this work, since the file is being edited for `fnm` anyway:

- Remove the `brew shellenv` eval (Homebrew is gone).
- Replace the `nvm` block with `eval "$(fnm env --use-on-cd)"`.
- Remove the duplicate `~/.local/bin` PATH export (currently added twice).
- Remove the stale `~/.tmux/plugins/...` PATH entry, keeping only the
  `~/.config/tmux/plugins/...` one.

## Performance tuning

### `.wslconfig`

Currently absent, so the machine runs on defaults. On a 32GB host the default
memory cap is 16GB, which is tight for the portal container stack plus a Next
build.

```ini
[wsl2]
memory=20GB            # up from the 16GB default; leaves Windows 12GB
swap=8GB               # OOM insurance
dnsTunneling=true      # survives corporate VPN DNS
guiApplications=false  # Chromium runs headless under xvfb; WSLg unused
sparseVhd=true         # VHD otherwise only ever grows

# processors: omitted — defaults to all logical cores.
# autoMemoryReclaim: deliberately unset. It returns "free" pages to Windows,
#   but that includes the page cache holding node_modules and docker layers.
#   Worth it at 16GB; at 32GB it trades rebuild latency for RAM not needed.
# networkingMode=mirrored: commented out. Best option for host↔container
#   networking, but still has rough edges with published ports. Enable later,
#   deliberately, not on day one.
```

Requires one `wsl --shutdown` from Windows to take effect. `90-wsl.sh` prints
this rather than attempting it, since the shutdown would kill the script.

### `/etc/wsl.conf`

Keeps the current `[boot] systemd=true` and `[user] default=muzzakhan`, adding:

```ini
[automount]
options = "metadata,umask=22,fmask=11"   # so chmod works under /mnt/c
```

### `/etc/docker/daemon.json`

The two settings that keep the VHD from ballooning:

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "builder": { "gc": { "enabled": true, "defaultKeepStorage": "10GB" } }
}
```

## `MIGRATION.md` — pre-wipe checklist

Checkbox list, run on the old box, ordered by consequence. `testing` branches
are explicitly out of scope in every repo — they are throwaway.

**1. Code at risk**
- `portal-core`: three local-only branches with no upstream —
  `feat/domain-shell-header`, `pr-562`, `review-pr-740`. Push with `-u` or
  consciously discard.
- `AutoDoc`: one dirty file. Commit, stash-and-push, or discard.
- `git stash list` across every repo in `~/code`.
- Leftover `git worktree list` entries from the feature-worktree workflow.
- `~/code/audit-tools` and `~/code/plan-agent` have **no remote at all**.
  Create a repo or tarball them out, or they are lost.

**2. Copy out to a Windows staging directory**
- `~/.ssh/id_ed25519` + `.pub` (+ `known_hosts`).
- `~/.config/secrets`.
- `~/.local/share/mkcert/rootCA-key.pem` — high consequence. Without it every
  locally-trusted cert breaks and a new CA must be re-trusted in Windows.

**3. Rotate rather than carry**
`~/.docker/config.json` holds a GitHub PAT and two Docker Hub tokens as plain
base64 — not encryption. `~/.npmrc` holds the `@mmem` registry PAT. Rotate
both; re-auth on the new box via `docker login` and a fresh npm token.

**4. Re-authenticate on the new box** (nothing to copy)
`gh auth login`, `claude` login, `docker login ghcr.io`, `docker login`, npm
token into `~/.npmrc` (from `templates/npmrc.example`), `~/.config/secrets`
(from `templates/secrets.example`).

**5. Windows side**
- Windows Terminal `settings.json` + the Nerd Font that tmux/nvim glyphs need.
- `C:\Windows\System32\drivers\etc\hosts` entries for local portal domains.
- Place the new `.wslconfig` (written by `90-wsl.sh`) and `wsl --shutdown`.

**6. Low priority**
- Confirm the **nonprod** Key Vault service-principal credentials from
  `.azure-kv.local` (present in `portal-core`, `portal-cga`, `portal-qms`) are
  in 1Password. If not, capture them before the wipe — `scripts/fetch-secrets`
  cannot run without them, and they are the one secret Key Vault cannot supply.
- While checking: `portal-core/.azure-kv.local` has the **prod** SP secret
  populated, contrary to that file's own instruction to leave prod blank on a
  dev machine. Do not carry it over.
- `docker volume ls` — decide whether any database volume is worth preserving.
- Recreate the `~/windir → /mnt/c/Users/muzza.khan` symlink.

`.env` files are deliberately absent from this list: every portal repo
regenerates them from Key Vault.

## Error handling

- Every module runs `set -euo pipefail`; a failure aborts `bootstrap.sh` with
  the failing module named and the re-run command printed.
- A failed module writes no completion marker, so a re-run retries exactly it.
- `50-stow.sh` never overwrites: real files that would conflict move to
  `<file>.pre-stow` first, and the paths are reported.
- `90-wsl.sh` backs up any existing `wsl.conf`/`.wslconfig` before writing.
- Steps needing root use `sudo` explicitly per command; `bootstrap.sh` refuses
  to run as root, since it writes into `$HOME`.
- `80-repos.sh` treats a failed clone as a warning, not a fatal error, and
  reports the failures together at the end — one inaccessible repo should not
  block the rest of the setup.

## Verification

No automated tests. `bootstrap.sh` ends with a smoke-test summary reporting
pass/fail per line, which is also the checklist a human walks:

- `zsh`, `tmux`, `nvim`, `git`, `gh`, `stow`, `fnm`, `node`, `docker`,
  `lazygit`, `fzf`, `zoxide` all resolve on PATH, with versions.
- `docker run --rm hello-world` succeeds (proves group membership and daemon).
- `~/.zshrc`, `~/.config/nvim`, `~/.config/tmux`, `~/.config/git/config`, and
  `~/.local/bin/ss` are symlinks pointing into `~/dotfiles`.
- `nvim --headless "+Lazy! check" +qa` exits clean.
- `~/code` contains all twelve cloned repos.
- Reminders printed, not checked: `wsl --shutdown` for `.wslconfig`, a fresh
  login for docker group membership, and the section-4 re-auth items.

The honest limitation: full verification requires a real fresh WSL distro. The
modules are written to be individually re-runnable precisely because the first
real run is where problems will surface.
