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
