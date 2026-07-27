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

**Re-running `60-tmux.sh` from inside a tmux session drops the session**
Plugin install runs a bare `tmux kill-server`, which kills every session on
the default socket, not just a temporary one. Harmless on a fresh box, but if
you re-run `./bootstrap.sh 60` later, do it from a plain shell outside tmux —
not from inside a tmux session.

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
inside the distro. Also confirm it landed in the right Windows profile: see
the `WIN_HOME` entry above.
