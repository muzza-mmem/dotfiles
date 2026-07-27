# dotfiles

Configuration files for local packages (vim, tmux, etc.), organized for use with GNU Stow.

## Layout

Each top-level directory is a Stow "package" mirroring the structure that should appear under `~`. **Always prefer `~/.config/<package>/` as the destination** — do not place config files directly under `~` (e.g. `tmux/.tmux.conf` → `~/.tmux.conf`). Use the tmux package as the canonical example:

```
dotfiles/
└── tmux/
    └── .config/
        └── tmux/
            └── tmux.conf
```

This stows to `~/.config/tmux/tmux.conf`. Only fall back to placing a file directly under `~` if the tool genuinely does not support `XDG_CONFIG_HOME` / `~/.config`.

### `_migration/` is not a Stow package

Every other top-level directory is a Stow package. `_migration/` is the
exception: it holds the one-shot machine rebuild (`bootstrap.sh`, install
modules, `MIGRATION.md`). Never run `stow _migration`. The leading underscore
is there to make that obvious at a glance.

## Adding configs for a new package

1. Create a directory named after the package (e.g. `tmux/`).
2. Inside it, create `.config/<package>/` and place config files there so they stow to `~/.config/<package>/` (e.g. `foo/.config/foo/config` → `~/.config/foo/config`).
3. From the repo root, run Stow to symlink it into place:

   ```
   stow <package>
   ```

   Use `stow -D <package>` to unlink, `stow -R <package>` to restow after changes.

Always run `stow` for any new package added so the symlinks are created.
