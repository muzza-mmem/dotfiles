# dotfiles

Configuration files for local packages (vim, tmux, etc.), organized for use with GNU Stow.

## Layout

Each top-level directory is a Stow "package" mirroring the structure that should appear under `~` (or `~/.config`). For example:

```
dotfiles/
├── vim/
│   └── .vimrc
├── tmux/
│   └── .tmux.conf
└── nvim/
    └── .config/
        └── nvim/
            └── init.lua
```

## Adding configs for a new package

1. Create a directory named after the package (e.g. `tmux/`).
2. Place config files inside it mirroring their destination path relative to `~` (e.g. `tmux/.tmux.conf` → `~/.tmux.conf`, or `foo/.config/foo/config` → `~/.config/foo/config`).
3. From the repo root, run Stow to symlink it into place:

   ```
   stow <package>
   ```

   Use `stow -D <package>` to unlink, `stow -R <package>` to restow after changes.

Always run `stow` for any new package added so the symlinks are created.
