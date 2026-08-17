---
name: agent-ledger
description: Use when several agents work the same repo at once and need to see who is doing what - "what are the other agents working on", "is anyone on this issue", "who owns that branch", "stack this PR on top of X", "can I raise my PR yet", "show the ledger". Reads and writes a shared per-repo ledger of in-flight work, declares dependencies between branches, and gates a PR from going ready until the branch it is stacked on has merged.
---

# Agent ledger

A shared record of what every agent is doing in this repo: which issue it claimed,
which branch and worktree it is in, its PR, what it is touching, and what it is
waiting on. It exists so concurrent agents do not claim the same issue, do not
collide in the same files unknowingly, and can **stack** work rather than serialise it.

**Everything goes through the `ledger` script.** Never Read/Edit the JSON directly -
concurrent agents writing at once is the normal case here, and hand-editing loses an
entry silently.

```
~/.claude/skills/agent-ledger/ledger <command> [flags]
```

The ledger lives at `~/.claude/ledger/<owner>__<repo>.json`, one per repo, on this
machine only. It is created on first write - there is nothing to set up.

---

## Commands

| Command | Purpose |
|---|---|
| `ledger list [--json]` | Everything in flight. The default read. |
| `ledger show --issue N` | One entry in full. |
| `ledger claim --issue N --branch B [...]` | Register work. Phase A. |
| `ledger update --issue N [...]` | Change status/PR/note; refreshes the heartbeat. |
| `ledger blockers --issue N` | **The PR gate.** Exit 0 = clear, 1 = blocked, 2 = parent abandoned. |
| `ledger overlaps --touches a,b` | Who else is in these paths. Exit 1 = someone is. |
| `ledger release --issue N` | Drop the entry. Phase D. |
| `ledger reconcile` | Force a liveness pass now. |
| `ledger path` | Print the ledger file path. |

Statuses run `claimed` → `wip` → `waiting` → `ready`. `stale` is derived from the
heartbeat (24h default), never set by hand.

`--no-reconcile` skips the liveness pass - use it when offline or when `gh` is failing.

---

## When to read it

**Read the ledger before you commit to any unit of work.** Concretely:

- **`pickup-work` runs `ledger list` before recommending anything.** An issue with a
  live entry is not pickable, even when GitHub still shows it unassigned - that closes
  the window between an agent claiming work and `gh issue edit --add-assignee` landing.
- **Before claiming**, if you know roughly which paths the work touches, check
  `ledger overlaps --touches <paths>`. An overlap is not a stop sign; it is the moment
  to decide between stacking, sequencing, or accepting a likely conflict.
- **When the user asks "what's running"** - `ledger list` is the answer.

Reconciliation runs automatically on read (at most once a minute): entries whose PR
merged or closed, or whose branch no longer exists locally or on origin, are dropped
and the removal is reported. A crashed agent's claim therefore self-heals; you never
need to prune by hand.

## When to write it

Writes are owned by `feature-worktree-workflow`:

| Phase | Call |
|---|---|
| A, right after the worktree + draft PR exist | `ledger claim --issue N --branch B --pr P --touches ...` |
| During work, at meaningful checkpoints | `ledger update --issue N --status wip --note "..."` |
| C, blocked at the gate | `ledger update --issue N --status waiting` |
| C, cleared and going ready | `ledger update --issue N --status ready` |
| D, teardown | `ledger release --issue N` |

Keep `--note` short and about *state*, not narrative: "waiting on I#883 forms refactor",
"rebased, CI green". The issue and PR remain the real work log.

`claim` refuses an issue another agent already holds (exit 1) and names the holder.
That is a genuine conflict - resolve it by stacking or by picking different work, not
by reaching for `--force`. `--force` is for taking over work you know is abandoned.

---

## Stacking a PR on unmerged work

Use this when your work genuinely needs commits that are still sitting on another
agent's branch. If it does not, branch off `origin/$BASE` as normal - stacking has a
real cost and should not be the default.

### 1. Branch off the parent, target the parent

```bash
git fetch origin --prune
./scripts/worktree -b feat/884-export-ui feat/883-csv-export     # parent, not origin/$BASE
git commit --allow-empty -m "chore: scaffold #884"
git push -u origin feat/884-export-ui
gh pr create --draft --base feat/883-csv-export \
  --title "WIP: Export UI" --body "Closes #884"
ledger claim --issue 884 --branch feat/884-export-ui --pr 922 \
  --stacked-on feat/883-csv-export \
  --touches services/portal-core/src/forms
```

The PR targets the **parent branch**, so its diff shows only your work rather than the
parent's changes replayed. `claim` records the parent's tip SHA automatically in
`stacked_at` (pass `--stacked-at` yourself if the parent ref is not resolvable locally).

**Say so in the PR body**, so a human reader is not confused by the unusual base:

```
Closes #884

Stacked on PR#921 (feat/883-csv-export). Base moves to `develop` once PR#921 merges.
```

### 2. If the parent moves while you are stacked

Rebase onto it as normal, then refresh the marker:

```bash
git rebase feat/883-csv-export
git push --force-with-lease
ledger update --issue 884 --stacked-at "$(git rev-parse feat/883-csv-export)"
```

### 3. The gate - before `gh pr ready`

```bash
ledger blockers --issue 884
```

- **Exit 0** - the parent has merged or released. Un-stack (below), then go ready.
- **Exit 1** - still blocked. `ledger update --issue 884 --status waiting --note "on PR#921"`,
  tell the user plainly which PR you are waiting on, and **stop**. Do not poll, do not
  mark ready against the parent branch, and never merge the parent yourself to unblock
  yourself.
- **Exit 2** - the parent was closed without merging. You are not blocked, you are
  orphaned: re-target the PR at `$BASE` and rebase off `origin/$BASE`, keeping whatever
  parent commits you actually still need.

### 4. Un-stacking once the parent merges

```bash
STACKED_AT=$(ledger show --issue 884 --json | jq -r .stacked_at)
gh pr edit 922 --base "$BASE"
git fetch origin --prune
git rebase --onto "origin/$BASE" "$STACKED_AT"
git push --force-with-lease
ledger update --issue 884 --status ready --stacked-on '' --stacked-at ''
gh pr ready 922
```

**Rebase onto the recorded SHA, not the branch name.** Origin deletes the parent branch
when its PR merges, which is exactly the moment you need this to work - a branch name
there fails precisely when you use it.

---

## Rules

- **The script is the only writer.** No Read/Edit of the JSON, ever.
- **Never merge someone else's PR to unblock yourself.** Merging is always the user's
  step, in this skill as in `feature-worktree-workflow`.
- **A blocked agent reports and stops.** No polling loops, no sleeping. If the user
  wants unattended resumption they will wire a `/loop`.
- **Overlaps are advisory.** They warn; they never block a claim. The agent (or the
  user) decides what to do about them.
- **One ledger per repo, this machine only.** An agent on another machine or in the
  cloud cannot see it - do not assume the ledger is the whole picture when the user is
  running cloud sessions.
- **`ledger release` at teardown**, but do not panic if it is missed - reconciliation
  drops the entry once the branch or PR is gone.

## Common mistakes

- **Claiming before the branch exists.** Claim in Phase A *after* the worktree and draft
  PR are up, so `--branch` and `--pr` are real. Reconcile drops an entry whose branch
  does not exist.
- **Stacking when you only overlap.** Touching the same directory is not a dependency.
  Stack only when you need the parent's commits; otherwise branch off `origin/$BASE` and
  let the rebase in Phase C handle the conflict.
- **Marking ready while stacked.** `ledger blockers` must run before `gh pr ready`. A PR
  merged into a parent branch does not reach `$BASE`.
- **Rebasing `--onto` a branch name after the parent merged.** Use `stacked_at`.
- **Treating a stale entry as dead.** Stale means "no heartbeat in 24h", not "abandoned".
  Check the branch and PR before taking work over with `--force`.
