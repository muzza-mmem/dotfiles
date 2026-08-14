---
name: fast-track
description: Use when the user runs /fast-track (or says "fast-track this / fast track this issue") to kick off a fast-tracked unit of work. Resolves the GitHub issue — creating one from the described change if no issue link/number is supplied — then runs the feature-worktree-workflow in fast-track mode (Phase A → C → D, skipping the testing-integration Phase B).
---

# Fast-track

Entry point for shipping a small, self-contained, low-risk change fast. It does two
things and then gets out of the way:

1. **Resolve the issue** — every unit of work is anchored to a GitHub issue. If the
   user gave an issue link/number, use it. If they only described the change, **create
   the issue first** (invoking `/fast-track` with a description IS the go-ahead to create
   it — don't re-ask for permission to create).
2. **Hand off to `feature-worktree-workflow` fast-track mode** — run **A → C → D**,
   **skip Phase B** (no `testing` merge, no shared-stack restart). The PR's own CI
   against the repo's base branch is the gate.

**Base branch:** `$BASE` = `develop` if `origin/develop` exists, else `main` - resolve it
per `feature-worktree-workflow`'s Conventions and branch/PR against `origin/$BASE`.
**Never check out or pull `main` on a dev machine**; in a migrated repo it is the
release/production branch.

## When to use

- User types `/fast-track <issue link | issue number | description of the change>`.
- User says "fast track this", "fast-track #123", "quick-ship this fix".
- The change is small and low-risk (e.g. a read-path bug fix mirroring an existing
  reference impl). If it's large, risky, or touches many subsystems, use the full
  `feature-worktree-workflow` (with Phase B) instead — say so and switch.

## Step 1 — Resolve or create the issue

**If args contain an issue reference** (a `github.com/.../issues/N` URL or a bare `#N`):
verify it exists and use it — no creation.

```
gh issue view <number>
```

**Otherwise, create the issue from the described change.** Derive a concise,
descriptive title and put the user's description (plus any relevant context/acceptance
detail) in the body. Match the issue's kind with a label where the repo uses them
(`bug` / `enhancement` / `chore`).

```
gh issue create \
  --title "<concise title derived from the description>" \
  --body "<the described change, expanded into a clear problem/goal statement>" \
  --label "<bug|enhancement|chore>"     # only if the repo uses these labels
```

Report the created issue number/URL back to the user, then proceed straight into the
workflow — this is a fast track, not a checkpoint. (If the title or scope is genuinely
ambiguous from what the user wrote, ask one tight clarifying question before creating;
otherwise create.)

## Step 2 — Run feature-worktree-workflow, fast-track mode

**REQUIRED SUB-SKILL:** Use `feature-worktree-workflow` and follow its **Fast-track mode
(skip Phase B)** section. Do not reimplement its phases here — invoke it with the resolved
issue number.

Fast-track sequence:

| Phase | What | Reminder |
|-------|------|----------|
| A Start | assign issue @me, milestone if part of an epic, branch `<type>/<number>-<slug>` off **`origin/$BASE`** in a worktree, push, empty scaffold commit, open **WIP draft PR** → `$BASE` (check `baseRefName` - `gh` defaults to the repo default, still `main`) | issue must exist (Step 1 guarantees it); `testing` checked out on MAIN_ROOT |
| ~~B~~ | **SKIPPED** | no `testing` merge, no stack restart |
| C Ship | rebase on latest `origin/$BASE`, push, add release note via `append-release-note` **in this same PR**, `gh pr ready`, comment issue summary | |
| D Teardown | after the **user** merges: `git fetch`, merge `origin/$BASE` → testing, rm worktree + local + remote branch | only after user confirms merge; never check out or pull `main` |

## Guardrails (inherited — do not skip)

- **Honor the interaction contract (inherited from `feature-worktree-workflow`).** Set it
  ONCE at kickoff and never re-prompt. `yolo` in the message (or opting out of every form
  question) = fully hands-off; hands-off defaults apply (Jira skip / GH-only, milestone
  attach-only, implementation auto, no boot-verify prompt). Fast-track skips Phase B, so a
  yolo fast-track runs A → C silently and stops only at the Phase C `gh pr ready` handoff.
- **No issue → no work.** Step 1 must yield a real issue before Phase A.
- **Base is `origin/$BASE`, never `main`.** Branch off it, target the PR at it, rebase on
  it. Never check out or pull `main`.
- **NEVER merge the PR yourself.** "fast track" / "ship" means get the PR ready-for-review
  and hand off. Phase C ends at `gh pr ready`. Phase D only after the user confirms the merge.
- **Push every commit immediately** on the feature branch; **never push `testing`**.
- **Still write the release note** in the same PR (skip only for pure internal chores).

## Common mistakes

- Skipping issue creation because "it's a tiny fix" — no issue, no branch. Create it.
- Re-asking whether to create the issue after the user already invoked `/fast-track` with
  a description — the invocation is the go-ahead.
- Running Phase B anyway "just to be safe" — that's the full workflow, not fast-track. If
  the change warrants integration testing, it isn't a fast-track; switch skills and say so.
- Self-merging the PR when CI is green — never. Hand off.
