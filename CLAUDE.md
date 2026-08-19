# dotfiles

Configuration files for local packages (vim, tmux, etc.), organized for use with GNU Stow.

## THIS REPO IS PUBLIC

`https://github.com/muzza-mmem/dotfiles` is a **public** GitHub repository.
Everything committed here is world-readable and permanently in the history —
a later deletion does not undo it. Combined with the "always commit and push
immediately" rule below, there is no review step to catch a mistake, so the
check has to happen **before** the write.

**Never commit any of the following:**

- Credentials of any kind — passwords, API tokens, npm `_authToken` values,
  OAuth tokens, `.credentials.json`, session cookies, connection strings.
- Private keys or certificates — `id_*`, `*.pem`, `*.key`, `*.p12`, anything
  matching `BEGIN ... PRIVATE KEY`.
- Real `.env` files, `secrets` files, or Key Vault / 1Password material.
- Internal infrastructure detail — private IP addresses, internal-only
  hostnames, VPN endpoints, database hosts, port mappings.
- Personal data — home addresses, phone numbers, colleagues' names or emails,
  customer or client data.

**Instead:** commit a `*.example` template with the value left blank (see
`_migration/templates/`), read the real value from `~/.config/secrets` or the
environment at runtime, and add the real path to `.gitignore`.

**Before every commit:** re-read the diff (`git diff --cached`) with the
question "would I be happy for a stranger to read this?". If a secret is ever
pushed, treat it as compromised — **rotate it first**, then worry about the
history.

Note the existing `.gitignore` uses an allowlist for `claude/.claude/*`:
everything Claude Code writes there is ignored by default and a new tracked
file needs an explicit `!` line. Keep that shape — do not loosen it to a
broad un-ignore.

## Git workflow

This repo has no review process — it is a single-author config repo, so the
normal branch/PR dance is overhead.

- **Always work directly on `master`.** Never create a feature branch or a
  worktree for a change here. (`master` is this repo's default and only
  branch — there is no `main`.)
- **Always commit changes**, without waiting to be asked. Don't leave edits
  sitting in the working tree.
- **Keep the message short** — a single subject line in the existing
  `<package>: <what changed>` style (e.g. `herdr: bind herdr-plus actions`).
  No body unless something is genuinely non-obvious.
- **No emojis** anywhere in commit messages.
- **Push to `origin master`** immediately after committing.

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

### Current contents

Inventory as of 2026-08-19 (99 tracked files). Stow packages:

| Package | Stows to | Contents |
|---|---|---|
| `bash/` | `~/.bashrc` | Bash rc; sources `~/.config/secrets` (untracked). |
| `bin/` | `~/.local/bin/` | Personal scripts: `ss` (ssh to a portal env), `ad-start`/`ad-stop`, `qms-start`/`qms-stop`, `dps`, `hp`, `herdr-even-panes`, `docker-cleanup`. |
| `claude/` | `~/.claude/` | Claude Code config: `CLAUDE.md`, `settings.json`, `keybindings.json`, `statusline-command.sh`, `hooks/`, and `skills/` (agent-ledger, answer-review, audit-fix, cleanup, fast-track, feature-worktree-workflow, jira-sync, myweek, pdf, pickup-work, publish, review-pr, seed-release-docs, ss). Allowlisted in `.gitignore` — see the public-repo section. |
| `git/` | `~/.config/git/config` | Git identity and the `gh` credential helper. |
| `herdr/` | `~/.config/herdr/` | herdr `config.toml` plus herdr-plus per-project TOMLs. |
| `nvim/` | `~/.config/nvim/` | NvChad-based config (`init.lua`, `lua/`); `lazy-lock.json` is gitignored. |
| `tmux/` | `~/.config/tmux/tmux.conf` | tmux config; `plugins/` (tpm) is gitignored. |
| `zsh/` | `~/.zshrc` | Oh My Zsh setup, plus the pre-omz backup. |

Non-package directories:

- `_migration/` — one-shot machine rebuild (see below).
- `_plugins/` — herdr plugins this repo ships (`even-panes`), linked from the working tree by `_migration/install/55-herdr-plugins.sh`; never stowed.
- `docs/superpowers/` — plans and specs from past work; reference only.

### `_`-prefixed directories are not Stow packages

Every top-level directory is a Stow package except the ones whose name starts
with an underscore: `_migration/` holds the one-shot machine rebuild
(`bootstrap.sh`, install modules, `MIGRATION.md`), and `_plugins/` holds the
herdr plugins linked into herdr from the working tree. Nothing in either belongs
under `~`, so never run `stow _migration` or `stow _plugins`. The leading
underscore is there to make that obvious at a glance.

## Adding configs for a new package

1. Create a directory named after the package (e.g. `tmux/`).
2. Inside it, create `.config/<package>/` and place config files there so they stow to `~/.config/<package>/` (e.g. `foo/.config/foo/config` → `~/.config/foo/config`).
3. From the repo root, run Stow to symlink it into place:

   ```
   stow <package>
   ```

   Use `stow -D <package>` to unlink, `stow -R <package>` to restow after changes.

Always run `stow` for any new package added so the symlinks are created.
