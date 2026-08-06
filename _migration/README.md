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

### The first smoke test is expected to fail ~10 checks

`bootstrap.sh` runs `smoke-test.sh` in the same session that just did the
install, so several checks cannot pass yet. **A perfect first run still reports
roughly ten failures.** They are:

| Check | Why it fails on a first run |
|---|---|
| `fnm`, `node`, `npm`, `codex` not on PATH | `20-node.sh` exported them in its own process; the smoke test is a separate one. A new shell picks them up. |
| `go` not on PATH | Installed to `~/.local/go`; `zsh/.zshrc` is what puts `~/.local/go/bin` on PATH, so it needs a new shell. |
| `superpowers plugin installed` | The probe shells out to `claude`, which is not on PATH yet for the same reason as `node`. |
| `docker daemon reachable`, `hello-world runs` | The `docker` group change only applies to a new session (and systemd needs `/etc/wsl.conf` applied). |
| `exists: ~/.ssh/id_ed25519` | Keys are carried by hand — MIGRATION.md section 2. |
| `npmrc has a token` | `~/.npmrc` was seeded from a template with the token deliberately blank. |

After `wsl --shutdown` from Windows, reopening the distro, and doing the
re-auth / secrets follow-ups `bootstrap.sh` prints, run `./_migration/smoke-test.sh`
again — that run should come back clean. Nothing in the checks is relaxed to
make the first run look tidy.

## Modules

| Module | Does |
|---|---|
| `00-apt.sh` | apt upgrade + all apt packages (incl. headless-Chromium libs) |
| `10-shell.sh` | oh-my-zsh, zsh as login shell |
| `20-node.sh` | fnm, node 24, npm globals (claude, codex, confluence-cli) |
| `30-docker.sh` | Docker CE, `daemon.json`, docker group |
| `35-azure.sh` | Azure CLI from Microsoft's apt repo |
| `40-tools.sh` | lazygit, zoxide, herdr, Go toolchain, pipx apps |
| `45-claude-plugins.sh` | Claude Code marketplace + the `superpowers` plugin |
| `50-stow.sh` | Stow every package, seed secret templates |
| `60-tmux.sh` | tpm + plugins |
| `70-nvim.sh` | Neovim from upstream tarball, `Lazy! sync` |
| `80-repos.sh` | Clone `repos.tsv` into `~/code` |
| `90-wsl.sh` | `/etc/wsl.conf` + Windows `.wslconfig` |

Order matters in three places: `00-apt.sh` precedes everything, `20-node.sh`
must precede `45-claude-plugins.sh` (which needs the `claude` CLI), and
`50-stow.sh` must precede `60-tmux.sh` and `70-nvim.sh` (both need their stowed
config).

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

**`90-wsl.sh` reports it cannot reliably resolve the Windows profile**
Both `cmd.exe` and `powershell.exe` can report `%USERPROFILE%` for an
unrelated elevated/admin account (`%USERNAME%=SYSTEM`) rather than the
interactive user, because the WSL interop token isn't the interactive user's.
When that happens the module refuses to guess and prints the candidate
profiles it found. Re-run it targeting your real profile explicitly:

```sh
WIN_HOME=/mnt/c/Users/<your-account> ./bootstrap.sh 90
```

**`60-tmux.sh` finishes but plugins are missing**
Install interactively: start `tmux`, then `prefix + I` (capital i).

**`60-tmux.sh` fails with `no server running on .../default`**
Fixed on 2026-08-06. The module used a bare `tmux start-server`, which leaves a
server with no sessions — and `exit-empty` (a server option, default `on`) makes
it exit the instant it starts, so the next command finds nothing. It now opens a
detached `tpm-install` session instead, and kills only that session rather than
running a bare `kill-server`, so re-running it from inside tmux no longer drops
your own sessions.

**`70-nvim.sh` download 404s**
The release asset name changed. List real names with
`curl -fsSL https://api.github.com/repos/neovim/neovim/releases/tags/stable | jq -r '.assets[].name'`
and update the URL in the module.

**`90-wsl.sh` dies on the `[user] default` in wsl.conf**
`wsl/wsl.conf` names the account WSL logs in as, and it is committed with a
literal username. If the fresh distro's first user is named something else the
module refuses to install the file — installing it would leave a distro that
cannot open a session after `wsl --shutdown` (recovery: `wsl -u root -d
<distro>` from Windows). Edit the `default =` line in `_migration/wsl/wsl.conf`
to your username and re-run `./bootstrap.sh 90`.

**`35-azure.sh` fails resolving the repo for this Ubuntu codename**
Microsoft publishes `packages.microsoft.com/repos/azure-cli` per codename and
sometimes lags a new Ubuntu release. The module detects that and falls back to
the `jammy` build, which runs fine (azure-cli is pure Python). If both fail,
apt sources are unreachable — check the network, not the module.

**`45-claude-plugins.sh` cannot install the plugin**
It only warns, never aborts, because the plugin is not load-bearing for the
rebuild. Finish the bootstrap, start a new shell so `claude` is on PATH, then
either re-run `./bootstrap.sh 45` or do it interactively: start `claude` and
run `/plugin`. `settings.json` already has `superpowers` in `enabledPlugins`,
so nothing else needs changing once it is installed.

**`go` is missing after a rebuild**
`40-tools.sh` installs it to `~/.local/go`, and `zsh/.zshrc` is what puts
`~/.local/go/bin` on PATH — so it only appears in a new zsh session, not in the
bash process that ran the bootstrap.

**Stow refuses to link a file**
A real file is in the way. `50-stow.sh` moves conflicts to `<file>.pre-stow`
automatically, but if it reports a conflict it could not resolve, move the file
aside by hand and re-run `./bootstrap.sh 50`.

**`50-stow.sh` prints `BUG in find_stowed_path? Absolute/relative mismatch`**
Harmless noise, not a failure — stow still exits 0 and links everything. The
cause is the `~/windir -> /mnt/c/Users/<you>` convenience symlink (MIGRATION.md
section 6): stow walks `$HOME`, follows it out to a path outside the stow dir,
and complains. noble ships the same stow 2.3.1 as the old box, so the behaviour
carries over. It cannot happen on a first run, because `~/windir` is created
*after* the bootstrap — only on later re-runs of module 50. To silence it,
`mv ~/windir` aside for the duration of the re-run.

**`--dry-run` shows `.claude/skills` being linked as one whole-directory symlink**
An artefact of the dry run, not what actually happens. `ensure_real_dir` does
not create the `REAL_DIRS` when `DRY_RUN=1`, so stow still sees them as absent
and reports the fold it *would* do if they were. On a real run the directories
are created first and stow links per-file. Do not "fix" this by reading the
dry-run output as the outcome — check with `smoke-test.sh` after a real run.

**`.wslconfig` changes did nothing**
It only applies after `wsl --shutdown` from Windows PowerShell — not from
inside the distro. Also confirm it landed in the right Windows profile: see
the `WIN_HOME` entry above.
