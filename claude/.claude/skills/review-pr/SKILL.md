---
name: review-pr
description: Use when the user runs /review-pr (or asks to review a specific GitHub pull request by number/URL) — checks the PR branch out into an isolated git worktree, reviews it with parallel agents, reports only the concerns grouped by severity, then offers a form to post inline comments and submit an approve/hold/reject review. For reviewing your own uncommitted working diff use /code-review instead.
---

# Review PR

## Overview

Review a GitHub pull request end-to-end: check its branch out into a throwaway
worktree, run a focused parallel review, and surface **only the concerns** —
grouped by severity, each one short and actionable. Then present a form so the
user picks which findings to post as inline comments and what verdict to submit.

**Core principle:** the user cares about problems, not a recap. No praise, no
change-summary, no restating what the PR does. Every line of the report is a
concern the user can act on.

## Inputs

The PR is given as an argument: a number (`123`), a `#123`, or a full URL. If no
argument is given, resolve the PR for the current branch with
`gh pr view --json number` and confirm before proceeding. If that fails, ask the
user which PR.

## Workflow

### 1. Check the PR out into a worktree

Never review in the user's working tree. Fetch the PR ref (works for forks too)
and add a worktree. Run from the repo root:

```bash
PR=<number>
# Fail fast if the PR is closed/merged/draft — surface it, ask before continuing.
gh pr view "$PR" --json number,title,state,isDraft,headRefName,baseRefName,url

git fetch origin "pull/$PR/head:review-pr-$PR" --force
git fetch origin "$(gh pr view "$PR" --json baseRefName -q .baseRefName)" --force
git worktree add --force "worktrees/review-pr-$PR" "review-pr-$PR"
```

All review work happens inside `worktrees/review-pr-$PR`. The diff to review is:

```bash
BASE=$(gh pr view "$PR" --json baseRefName -q .baseRefName)
git -C "worktrees/review-pr-$PR" diff "origin/$BASE...HEAD"
```

### 2. Review with parallel agents

Read the root `CLAUDE.md` (and any `CLAUDE.md` in touched directories) for
project rules. Then dispatch parallel agents over the worktree, each returning
`{finding, reason, file, line}`:

- **CLAUDE.md / standards adherence** — violations of documented project rules.
- **Bugs** — correctness defects in the changed lines (logic, null/undefined,
  error handling, race conditions, resource leaks, security). Shallow scan of
  the diff; read surrounding code only to confirm.
- **Historical context** — `git blame`/log and prior PRs on these files for
  regressions or ignored past review feedback.

**Verify before reporting.** For each candidate finding, confirm it against the
worktree code. Drop anything a linter/typechecker/CI would catch (imports,
formatting, type errors, test coverage), pre-existing issues on unmodified
lines, likely-intentional changes, and pedantic nitpicks a senior engineer
wouldn't raise. Keep only findings you are confident are real.

### 3. Report concerns, grouped by severity

Output **only** the concerns. If there are none, say so in one line and skip to
the form (verdict only). Use this format — keep each finding to its lines:

```
## Concerns

### Major
1. <one-line description> — `path:line`
   - Blocking: yes | no
   - Fix: <one-line recommended resolution>

### Minor
1. ...

### Nits
1. ...
```

Severity = impact: **Major** (bug / rule violation / real risk), **Minor**
(should fix, low risk), **Nit** (style/polish). `Blocking` is a separate
per-finding flag — a Major can be non-blocking, a Minor is rarely blocking.
No summary paragraph, no "what the PR does", no positives.

### 4. Present the form

Ask both questions in a single `AskUserQuestion` call:

1. **Inline comments** (multiSelect, header `Inline`): "Post which findings as
   inline comments on the PR?" — options **Major**, **Minor**, **Nits**,
   **Skip (post none)**. If Skip is chosen, post no comments regardless of other
   selections.
2. **Verdict** (single, header `Verdict`): "Submit what review verdict?" —
   options **Approve**, **Hold**, **Reject**, **No action**.

### 5. Act on the answers

Map the verdict to a GitHub review event, attach the selected findings as inline
comments, and submit **one** review via the API. `{owner}`/`{repo}` resolve from
the current repo.

| Verdict    | Event             |
|------------|-------------------|
| Approve    | `APPROVE`         |
| Reject     | `REQUEST_CHANGES` |
| Hold       | `COMMENT`         |
| No action  | *(see below)*     |

- **No action + Skip** → do nothing; just report that no review was posted.
- **No action + some severities selected** → submit a `COMMENT` review carrying
  the inline comments only.
- Otherwise submit the mapped event, with the selected comments attached.

Build the payload and post it:

```bash
# payload.json — comments only for selected severities; anchor each to a line
# that appears in the diff (RIGHT = new file; use LEFT/deleted lines sparingly).
cat > payload.json <<'JSON'
{
  "event": "COMMENT",
  "body": "Automated review — see inline comments.",
  "comments": [
    { "path": "src/foo.ts", "line": 42, "side": "RIGHT",
      "body": "**[Major]** <headline>. <one-line fix>." }
  ]
}
JSON
gh api --method POST "repos/{owner}/{repo}/pulls/$PR/reviews" --input payload.json
```

**Inline comment style — keep it simple:** one headline plus a one-line
actionable fix. Prefix with the severity tag (`**[Major]**`). No essays, no
restating the code. One comment per finding, anchored to `path:line` from the
report. Lines must exist in the diff or the API rejects them (422) — re-anchor
to the nearest changed line if needed.

### 6. Clean up

Always remove the worktree and temp branch when done (even if the review was
posted or the user chose No action):

```bash
git worktree remove --force "worktrees/review-pr-$PR"
git branch -D "review-pr-$PR"
```

## Quick Reference

| Step | Command |
|------|---------|
| Inspect PR | `gh pr view $PR --json number,title,state,isDraft,headRefName,baseRefName,url` |
| Fetch + worktree | `git fetch origin pull/$PR/head:review-pr-$PR --force && git worktree add --force worktrees/review-pr-$PR review-pr-$PR` |
| Diff | `git -C worktrees/review-pr-$PR diff origin/$BASE...HEAD` |
| Submit review | `gh api --method POST repos/{owner}/{repo}/pulls/$PR/reviews --input payload.json` |
| Clean up | `git worktree remove --force worktrees/review-pr-$PR && git branch -D review-pr-$PR` |

## Common Mistakes

- **Reviewing in the working tree.** Always use the worktree — the user's
  checkout must stay untouched.
- **Padding the report.** No summary, no praise, no restating the change. Only
  concerns. Zero concerns = one line saying so.
- **Posting nitpick noise inline.** Only post the severities the user selected;
  respect Skip.
- **Approving your own PR / wrong event.** GitHub rejects `APPROVE` on your own
  PR — if that happens, fall back to `COMMENT` and tell the user.
- **Leaving the worktree behind.** Clean up on every path, including errors.
