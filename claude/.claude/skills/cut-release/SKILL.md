---
name: cut-release
description: Use when the user wants to cut/tag a release in a portal repo (core, qms, cga, lti, autodoc, fx, pbb, sales) - "cut a release", "/cut-release", "cut a patch/minor/major release", "tag vX.Y.Z", "release this". Resets the root repo to a clean base branch (discarding anything in the working tree without asking), then runs ./scripts/release cut <type>.
---

# Cut a release

Cut a build-once release with `./scripts/release cut <type>`.

The root project directory is **not** a workspace — real work happens in
`worktrees/`. So before releasing, the root is reset to a clean base branch
unconditionally: anything sitting in the root working tree is discarded without
asking. That is the point of this skill, not a side effect.

## `main` stays out of your checkout

Releases land on `main`, but **you never check out or pull `main` to cut one.**
`./scripts/release cut` fetches `origin main` itself, builds the release commit in its
own throwaway worktree anchored to `FETCH_HEAD`, and pushes fast-forward-only to `main`.
It never touches your working tree and it does not care which branch you are on - it only
requires a clean tree. So the root gets reset to the **base** branch, not to `main`:

```bash
BASE=develop; git show-ref -q --verify refs/remotes/origin/develop || BASE=main
```

`$BASE` is `develop` in the migrated repos (portal-core, portal-qms) and still `main`
elsewhere - where it resolves to `main`, checking it out is the pre-migration behaviour
and is fine. In a migrated repo, **do not `git switch main`**: it is the
release/production branch and has no business on a developer machine.

Note this skill cuts from `origin/main`, which in a migrated repo means the release train
is whatever has already been promoted `develop` → `main`. If work you expect in the
release is still sitting on `develop`, the promotion has not happened yet - say so and
stop; do not promote it yourself.

## Non-negotiables

1. **Run from the primary worktree root, never inside `worktrees/*`.**
2. **Discard root working-tree changes without asking.** No stash, no "are you
   sure", no listing-and-waiting. Report what was discarded *after* the fact.
3. **Never `git clean -x` (or `-X`).** Ignored files in these repos are local
   environment and in-flight work, not junk: `.env`, `.azure-kv.local`,
   `infra/traefik/ssl/*`, `infra/vector/.env.secrets`, `node_modules/`, and
   **`worktrees/` — which holds other people's feature worktrees**. `-x` would
   destroy all of it and none of it is recoverable. Plain `git clean -fd` only.
4. **Never force-push, never hand-create the tag.** `./scripts/release cut` owns
   the push and the GitHub Release; if it refuses, fix the cause and re-run it.
5. **Don't deploy.** Cutting ≠ shipping. Production is a separate, approval-gated
   workflow run — report it as the next step and stop.

## Steps

1. **Resolve the bump type.** `patch` | `minor` | `major` | explicit `vX.Y.Z`.
   Default to `patch` if the user didn't say. Anything else is an error — don't guess.

2. **Get to the primary worktree root** (in case the session is inside a worktree):

   ```bash
   cd "$(git worktree list --porcelain | head -1 | sed 's/^worktree //')" && pwd
   ```

3. **Record what's about to be thrown away** (for the report only — do not pause):

   ```bash
   git branch --show-current
   git status --porcelain
   ```

4. **Reset the root to a clean base branch at `origin/$BASE`:**

   ```bash
   git fetch origin --tags --force            # brings both origin/$BASE and origin/main up to date
   BASE=develop; git show-ref -q --verify refs/remotes/origin/develop || BASE=main
   git reset --hard                           # drop tracked modifications
   git clean -fd                              # drop untracked files (NOT -x: keeps .env, node_modules, worktrees/)
   git switch -C "$BASE" "origin/$BASE"       # -C resets in place, even if already checked out
   ```

   `release cut` fetches `origin main` again itself, so you do not need `main` locally  - 
   and in a migrated repo you must not have it checked out.

   Leaving `testing` behind is expected and safe — it's a local-only integration
   branch that is never pushed, and `/cleanup` recreates it fresh from `origin/$BASE`.

5. **Verify the tree is clean** before invoking the script — it hard-fails on a
   dirty tree, and a leftover file here would silently ride into the release commit:

   ```bash
   git status --porcelain            # must print nothing
   git log --oneline -1
   ```

6. **Cut it:**

   ```bash
   ./scripts/release cut <type>
   ```

   The script does the rest itself: checks `gh` auth and that you have **ADMIN**
   (main's branch protection and the `v*` tag ruleset only yield to admins),
   resolves the next version from the freshly-fetched tags, builds the release
   commit in its own throwaway worktree, regenerates the standalone service
   lockfiles, pushes fast-forward-only to `main`, and creates the GitHub Release
   with generated notes. The **last line of output is the finalized tag**.

7. **Report** the tag from that last line, plus the next step verbatim:
   *Actions → "Deploy to Production" → version `vX.Y.Z`* (gated on the `prod`
   environment approval). Also state which branch the root is now on (`$BASE`) and
   what step 3 found and discarded.

## When `release cut` fails

| Failure | Meaning | Do this |
|---|---|---|
| `requires admin on this repo` | You're not a release lead here | Stop. Use Actions → "Prepare Release" (PR + review), then `gh release create` — don't work around the protection |
| `working tree is dirty` | Step 4 didn't take, or something regenerated files | Re-run steps 4–5; never `--allow-dirty`-style workarounds |
| `tag vX.Y.Z already exists` | That version is already cut | Confirm the intended bump with the user; don't delete or move a published tag |
| `push to main was rejected` | `origin/main` moved mid-cut | Safe — **no tag was created**. Re-run from step 4 to cut from the new tip |
| `failed to regenerate service lockfiles` | npm registry auth missing | Fix GitHub Packages auth, then re-run. Do not skip it — this push bypasses pr-checks' lockfile guard |

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| `git clean -fdx` | Wipes `.env`, certs, and every worktree under `worktrees/` | `git clean -fd` — ignored files stay |
| Asking permission before discarding root changes | Wastes a turn on a decision already made | Discard, then report |
| Skipping the fetch in step 4 | Stale tags → wrong next version resolved | Always `git fetch origin --tags --force` first |
| `git switch main` to "get ready" in a migrated repo | Puts the release branch on a dev machine for no reason | Reset to `origin/$BASE`; the script fetches `main` itself |
| Creating the tag by hand | Skips notes generation and `release.yml` image re-tagging | Let the script do it |
| Deploying after cutting | Ships unapproved | Cut only; hand off the gated deploy workflow |
| Running inside `worktrees/*` | Releases from the wrong tree | `cd` to the primary root (step 2) |
