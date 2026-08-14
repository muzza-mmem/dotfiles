---
name: cleanup
description: Use when the user wants to tidy up git branches and worktrees to get back to a clean base branch - "clean up my branches", "/cleanup", "delete merged branches", "prune worktrees", "clean main". Deletes only the user's OWN branches that are already merged, on both local and origin, and removes stale worktrees. Never touches unmerged work, protected branches, or other people's branches.
---

# Cleanup

Get back to a clean base branch by deleting **only branches that are BOTH mine AND
already merged**, on local and origin, plus any stale worktrees. Everything else
is left alone.

## The base branch

**`$BASE` = `develop` if `origin/develop` exists, else `main`.** Repos are migrating to a
`develop`/`main` split (`develop` = integration base, `main` = release/production), so
detect it instead of assuming:

```
git fetch origin --prune
BASE=develop; git show-ref -q --verify refs/remotes/origin/develop || BASE=main
```

Everything below that compares against "merged" means merged into `origin/$BASE`.
**Never check out or pull `main`** - in a migrated repo it is the release branch, and
this skill has no reason to touch it.

## The rules

1. **Delete only branches that are mine AND merged.** Both conditions, always.
   Mine-but-unmerged, merged-but-someone-else's, and unmerged-and-not-mine all stay.
2. **Never delete protected branches:** `main`, `develop`, `testing` (the integration
   branch), the currently checked-out branch, or `release/*`. (Exception: the final reset
   step intentionally recreates `testing` fresh from `origin/$BASE` - see step 9. It is
   still protected from the general merged-branch deletion pass in steps 5–7.)
3. **`git branch --merged` is not enough** — it MISSES squash-merged PRs, because
   their commits are not ancestors of the base. You MUST cross-check merged PRs via `gh`.
4. **Confirm before deleting remote branches.** Deleting an origin branch is
   outward-facing and hard to reverse on a shared repo. Show the exact list and get
   a go-ahead. Local `-d` deletes are safe (git refuses unless truly merged) — no confirm needed.
5. **Use `git branch -d`, never `-D`.** `-d` is the safety net: it refuses to delete
   anything not fully merged. If `-d` refuses, that branch is NOT merged — leave it.

## Steps

1. **Sync remote state and resolve the base** so "gone" and merged data are accurate:
   ```
   git fetch origin --prune
   BASE=develop; git show-ref -q --verify refs/remotes/origin/develop || BASE=main
   ```

2. **Identify who "I" am** (branch ownership = the branch's PR author):
   ```
   gh api user --jq '.login'      # e.g. muzza-mmem
   git config user.email
   ```

3. **Build the merged set** — the UNION of two sources (squash merges only appear in the second):
   ```
   git branch --merged "origin/$BASE"            # local, merge-commit style
   git branch -r --merged "origin/$BASE"         # remote, merge-commit style
   gh pr list --state merged --limit 200 --json number,headRefName,author,mergedAt,baseRefName
   ```
   A branch counts as merged if it's in `--merged "origin/$BASE"` OR its name matches a
   merged PR's `headRefName`. Compare against the remote-tracking ref, never a local
   `main`/`develop`, which may be stale or absent. Do **not** filter the PR list by
   `baseRefName`: branches merged into `main` before the develop migration are still
   merged, and the ancestor check above covers everything merged since.

4. **Build the ownership map:**
   ```
   gh pr list --state merged --limit 200 --json headRefName,author   # author.login == my login → mine
   gh pr list --state open   --limit 200 --json headRefName,author   # open PR → NEVER delete
   ```
   For a branch with no PR at all, check the tip author (`git log -1 --format='%ae' <branch>`)
   against your email; if still unsure, treat it as NOT mine and keep it.

5. **Classify every branch** (local and origin) into: delete (mine ∧ merged ∧ not protected ∧ no open PR)
   vs keep. Present a table of both, with the reason for each keep.

6. **Delete local** merged branches:
   ```
   git branch -d <branch>
   ```

7. **Confirm, then delete remote** merged branches (skip any GitHub already auto-deleted):
   ```
   git push origin --delete <branch>
   ```

8. **Clean worktrees.** For each worktree other than the primary: if its branch is
   merged + mine + has no uncommitted changes, remove it; then prune dangling entries:
   ```
   git worktree list
   git worktree remove <path>        # only if clean + merged; add --force only if user confirms
   git worktree prune
   ```

9. **Reset to a fresh `testing` branch off `origin/$BASE`.** Do this LAST, once all
   branch/worktree cleanup above is done:
   ```
   # a. Get out of any worktree — operate from the primary repo root
   git rev-parse --show-toplevel            # confirm where you are
   cd "$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"   # primary worktree root
   ```
   ```
   # b. Discard everything in the working tree (intentional — no work should live here)
   git reset --hard
   ```
   ```
   # c. Refresh the base ref, then recreate testing from it, in place
   git fetch origin --prune
   git switch -C testing "origin/$BASE"     # -C resets testing even while it's checked out
   ```
   Branching off a remote-tracking ref sets `testing`'s upstream to `origin/$BASE`
   automatically, so no extra `--set-upstream-to` is needed.
   `-C` recreates the branch **without ever checking out another branch first**, which is
   what keeps this off `main`. Do not "get out of the way" by switching to `main` - that
   is exactly the forbidden operation on a dev machine.

   Note: this step deliberately blows away the local `testing` branch and any
   uncommitted changes in the primary worktree — anyone with in-progress work there
   loses it. That is intended.

10. **Verify and report** the final clean state:
   ```
   git branch -vv && git branch -r && git worktree list
   ```
   List what was deleted and what was kept (with reasons), and confirm you are on a
   fresh `testing` branch tracking `origin/$BASE`.

## Common mistakes

| Mistake | Consequence | Fix |
|--------|-------------|-----|
| Trusting only `git branch --merged` | Squash-merged branches look unmerged and linger | Cross-check `gh pr list --state merged` by `headRefName` |
| Treating all local branches as "mine" | Deleting a teammate's checked-out branch | Ownership = PR author login, not local presence |
| Using `git branch -D` | Silently nukes unmerged work | Always `-d`; if it refuses, keep the branch |
| Deleting a branch with an open PR | Kills in-flight review | Exclude any branch in `gh pr list --state open` |
| Deleting `testing` / `develop` / `release/*` | Breaks the integration/release flow | Hard-code them as protected |
| Checking out `main` to free up `testing` | Pulls the release branch onto a dev machine | `git switch -C testing "origin/$BASE"` resets it in place |
| Measuring "merged" against `main` in a migrated repo | Branches merged into `develop` look unmerged and linger | Compare against `origin/$BASE` |
| Force-removing a dirty worktree | Loses uncommitted changes | Only remove clean worktrees; `--force` only with explicit confirm |
