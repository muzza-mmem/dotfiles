# Pre-wipe migration checklist

Run through this on the **OLD** machine, before the WSL distro is deleted.
Ordered by consequence: section 1 is unrecoverable, section 6 is convenience.

`testing` branches are out of scope everywhere — they are throwaway.

## 1. Code at risk (unrecoverable once the distro is gone)

**Do not skip straight to a name — this section drifts the moment you do more
work.** The sweep below is the source of truth; any branch names mentioned
elsewhere in this section are illustrative only and will go stale.

- [ ] **Run this sweep first.** It finds every branch that would be lost, and
      separates the two risk classes because they need different handling:
      branches with **no upstream at all** (never pushed anywhere) vs.
      branches that are **ahead of their upstream** by N commits (partially
      pushed — the remote copy is behind).

      ```sh
      for d in ~/code/*/; do
        git -C "$d" for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads |
        while read -r b u; do
          [ "$b" = testing ] && continue
          if [ -z "$u" ]; then echo "$(basename "$d")  $b  [NO UPSTREAM - never pushed]"
          else n=$(git -C "$d" rev-list --count "$u..$b" 2>/dev/null)
               [ "$n" != 0 ] && echo "$(basename "$d")  $b  [AHEAD $n - partially pushed]"
          fi
        done
      done
      ```

      As of 2026-07-27 this reported (verify with the sweep — this list WILL
      be stale):

      ```
      portal-core  feat/availability-banner  [AHEAD 3 - partially pushed]
      portal-core  feat/domain-shell-header  [NO UPSTREAM - never pushed]
      portal-core  pr-562                    [NO UPSTREAM - never pushed]
      portal-core  review-pr-740             [NO UPSTREAM - never pushed]
      ```

- [ ] **Push every branch the sweep reported.** Do not enumerate names by
      hand — fill in what the sweep just printed:

      ```sh
      cd ~/code/<repo>
      git push -u origin <branch>   # once per branch the sweep listed
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

- [ ] **Repos with no remote at all cannot be cloned and are not in
      `repos.tsv`.** Discover them rather than trusting a memorized list —
      any repo could lose its remote or gain one since this was last checked:

      ```sh
      for d in ~/code/*/; do
        git -C "$d" remote get-url origin >/dev/null 2>&1 || echo "$(basename "$d")  [NO REMOTE]"
      done
      ```

      As of 2026-07-27 this reported `audit-tools` and `plan-agent` (verify
      with the command above — this list WILL be stale). Create a repo and
      push, or tarball them out to Windows — otherwise they are gone:

      ```sh
      tar -czf /mnt/c/Users/muzza.khan/wsl-migration/no-remote-repos.tar.gz \
        -C ~/code audit-tools plan-agent   # substitute today's sweep result
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
      PowerShell to apply. **Verify it actually landed in the profile you log
      in as** — `%USERPROFILE%` is unreliable under the WSL interop token (see
      the `WIN_HOME` note below), and a `.wslconfig` written to the wrong
      profile silently does nothing. If `90-wsl.sh` could not reliably resolve
      your profile, it printed candidates and refused to guess; re-run it with
      `WIN_HOME=/mnt/c/Users/<your-account> ./bootstrap.sh 90` to target the
      right one, then confirm the file exists at
      `C:\Users\<your-account>\.wslconfig`.
- [ ] Re-trust the mkcert root CA in Windows if the CA key was **not** carried
      over: `mkcert -install`

## 6. Low priority

- [ ] **Confirm the nonprod Key Vault service-principal credentials are in
      1Password.** It is the one secret Key Vault cannot supply
      (chicken-and-egg), so `scripts/fetch-secrets` cannot run without it. If
      it is not in 1Password, capture it before the wipe. Run the discovery
      command rather than trusting a memorized repo list — which repos have
      this file can change:

      ```sh
      grep -l . ~/code/*/.azure-kv.local 2>/dev/null
      ```

      As of 2026-07-27 this reported `portal-core`, `portal-cga`, and
      `portal-qms` (verify with the command above — this list WILL be stale).

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
