---
name: audit-fix
description: Use when remediating an npm-audit / Dependabot / dependency-security advisory in a portal repo (portal-core/-cga/-lti/-qms/-autodoc). The fix runs in a git worktree with its OWN real node_modules + lockfiles (never a shared/symlinked node_modules), so package-lock changes are genuine, committed with the fix, and CI-safe. The PR starts as a WIP draft and the agent marks it ready-for-review once all Verify gates pass (the human still owns the merge). Prefer this over feature-worktree-workflow for any dependency/lockfile change. Triggers - "fix this audit advisory", "remediate GHSA-… / CVE-…", "bump <pkg> for the security milestone", "npm audit fix for an issue", "verify the audit fix cleared".
---

# Audit-fix workflow

Isolated, repeatable, verifiable npm-audit remediation. Phases:
**Orient → Isolate → Remediate → Verify → Ship → Teardown** (Verify is
re-runnable and can be run standalone on the current worktree). Phases usually
span turns — re-read the phase you're entering.

**Why this is not `feature-worktree-workflow`:** that flow shares/symlinks
`node_modules` across worktrees, so `package-lock.json` edits don't land cleanly
in the PR and CI's `npm ci` fails with sync errors. Audit fixes edit lockfiles,
so this flow gives the worktree its OWN real dependency state — a clean
`npm install`, never a symlink.

## Setup & conventions

- **SKILL_DIR** = the folder holding this file (`~/.claude/skills/audit-fix/`).
  Helper: `"$SKILL_DIR/audit-helpers.sh"`; friction log: `"$SKILL_DIR/friction-log.md"`.
- **MAIN_ROOT** = the repo's primary working tree:
  `git -C <repo> worktree list --porcelain | awk '/^worktree /{print $2; exit}'`.
- **Helper** (`audit-helpers.sh <cmd> <dir> …`) does ONLY the error-prone
  mechanics: `baseline`, `diff`, `check-pkg`, `override`. Everything else
  (worktree, install, commit, push, PR, teardown) is the steps below, run directly.
- **Branch name starts with the issue id**: `<num>-<slug>` (e.g.
  `575-bump-next-postcss`) — portal-core CLAUDE.md requires the id first.
- **Push only via `./scripts/safe-push`** (never bare `git push`). safe-push
  forwards args to `git push`, so the FIRST push sets upstream explicitly:
  `./scripts/safe-push -u origin HEAD:<branch>`.
- **One advisory per issue/PR** — scoped, so sibling audit PRs don't collide on
  the lockfile.

---

## Phase 0 · Orient

**GUARDRAIL: a GitHub issue must exist.** No issue → STOP and ask, or propose
creating one (`gh issue create`) and create it on the go-ahead. Confirm:
`gh issue view <num>`.

1. **Read the friction log** — `cat "$SKILL_DIR/friction-log.md"`. It is the
   accumulated hard-won knowledge; the "Known traps" summary tells you what to
   avoid before you hit it.
2. **Identify the remediation target(s)** from the issue: the exact package(s)
   and/or advisory id (GHSA-… / CVE-…) named, and the intended strategy —
   parent bump vs transitive override. Write them down; Phase 3 confirms exactly
   these cleared.
3. **Issue admin:** `./scripts/update-issue-status <num> "In Progress"` (if it
   fails on a missing `read:project` scope, note it and carry on — known token
   limitation), then `gh issue edit <num> --add-assignee @me`.

## Phase 1 · Isolate

**GUARDRAIL: never reuse or symlink `node_modules`. A clean `npm install` in the
worktree, always.**

```bash
ROOT=$(git -C <repo> worktree list --porcelain | awk '/^worktree /{print $2; exit}')
git -C "$ROOT" fetch origin
git -C "$ROOT" worktree add --no-track -b <num>-<slug> "$ROOT/worktrees/<num>-<slug>" origin/main
cd "$ROOT/worktrees/<num>-<slug>"
npm install                                   # OWN real node_modules — the whole point
bash "$SKILL_DIR/audit-helpers.sh" baseline .
```

Then bootstrap the draft PR (issue → worktree → draft PR → implement order):

```bash
git commit --allow-empty -m "chore: scaffold #<num> audit fix"
./scripts/safe-push -u origin HEAD:<num>-<slug>          # -u sets upstream (friction log #6)
gh pr create --draft --base main \
  --title "<concise title> (#<num>)" \
  --body "Closes #<num>

Automated npm-audit remediation. Target: <package/advisory>."
```

## Phase 2 · Remediate

Apply the fix; keep lock churn minimal and scoped.

- **Parent bump:** edit the dep in `package.json`, `npm install`.
- **Transitively-pinned dep** (a parent bump won't clear it — friction log #2):
  add the root `overrides` entry to `package.json`, then re-resolve just that
  node (a plain `npm install` is a NO-OP against an existing lockfile — #1):
  ```bash
  bash "$SKILL_DIR/audit-helpers.sh" override . node_modules/<parent>/node_modules/<dep>
  ```
- **Standalone service locks** (friction log #8): if you changed a service that
  ships its own Docker `npm ci` lock, regenerate it — root `overrides` do NOT
  propagate there. Check the repo's list in `./scripts/generate-lockfiles`
  (portal-core: `portal-core`, `lti-backend`, `portal-migration-runner`):
  ```bash
  ./scripts/generate-lockfiles <service>
  ```
- **Breaking changes:** fix them. For a Next frontend build, build workspace
  packages first (friction log #5): `npm run build:packages`.
- Commit and push each step: `./scripts/safe-push`.

## Phase 3 · Verify  (repeatable; also runnable standalone)

Ships only when ALL FOUR hold:

1. **Target cleared** — for every Phase-0 target:
   `bash "$SKILL_DIR/audit-helpers.sh" check-pkg . <target>` exits 0.
2. **No regression** — `bash "$SKILL_DIR/audit-helpers.sh" diff .` shows current
   total ≤ baseline (no NEW advisories introduced).
3. **CI-safe** — `./scripts/pr-checks` exits 0. If a standalone-lock service's
   `package.json` changed, its lock was regenerated and re-checked; if a target
   could live in a standalone service lock, audit that service independently too.
4. **Scoped diff** — `git diff --numstat -- package-lock.json` is small and
   confined to the target subtree (surgical override, NOT a full re-resolve; #1).

Loop Phase 2 ↔ 3 until green. Expect `pr-checks` to run up to 3× (this check,
safe-push's own run, the pre-push hook — #7); harmless, just slow.

## Phase 4 · Ship

1. Finalise the PR body: baseline→current counts, current severity, target(s)
   cleared.
2. **Post the QA test plan as a comment on the ISSUE** (not the PR — CLAUDE.md
   step 13): `gh issue comment <num> --body "<test plan>"`.
3. `./scripts/update-issue-status <num> "Needs Review"`.
4. **Mark the PR READY as soon as it's done: `gh pr ready <num>`.** All four Verify
   gates have passed, so an audit-fix PR flips out of draft the moment Ship completes
   — do NOT leave it a draft. **Never `gh pr merge`, though — the human still owns the
   merge.** Report the PR URL and hand off.
   (Audit-fix only: this is the one workflow where the agent readies its own PR,
   because Verify is an objective, fully-automated bar. Other workflows leave PRs draft.)

## Phase 5 · Teardown  (after the human merges, or on explicit request)

**GUARDRAIL: you can't remove the worktree you're standing in — `cd "$ROOT"` first.**

```bash
cd "$ROOT"
git checkout main && git pull
git worktree remove worktrees/<num>-<slug>       # add --force only if uncommitted & intended
git branch -D <num>-<slug>
git push origin --delete <num>-<slug>            # delete the merged remote branch
```

Confirm the issue closed via the `Closes #<num>` link (`gh issue view <num>`);
close manually if it didn't resolve. Drop the baseline state file
(`~/.cache/audit-fix/<repo>--<branch>.baseline.json`).

## Learn from each run — update the friction log

When you hit a NEW trap (or the log proves wrong), append a dated entry to
`"$SKILL_DIR/friction-log.md"` under "Detailed log" — symptom → root cause → fix
— and add/update its one-liner in the "Known traps (read first)" summary at the
top. Tag repo-specific quirks with the repo name. This is how each fix makes the
next one easier.

## Quick reference

| Phase | Where | Action | Guardrail |
|-------|-------|--------|-----------|
| 0 Orient | MAIN_ROOT | read friction log; identify target(s)+strategy from issue; status In Progress; assign @me | **issue must exist** |
| 1 Isolate | MAIN_ROOT → worktree | worktree `--no-track` off origin/main; **clean `npm install`**; baseline; empty commit; `safe-push -u`; draft PR (`Closes #`) | **never symlink node_modules**; first push sets upstream |
| 2 Remediate | worktree | parent bump OR override + `override` helper; regenerate standalone locks; fix breakage; push each step | plain `npm install` won't apply a new override |
| 3 Verify | worktree | target cleared + no regression + pr-checks green + scoped lock diff | all four hold before Ship |
| 4 Ship | worktree | finalise PR body; QA plan on the ISSUE; status Needs Review; **`gh pr ready`** | ready it once done; never merge (human owns merge) |
| 5 Teardown | MAIN_ROOT | rm worktree + local + remote branch; refresh main; confirm issue closed | can't rm cwd worktree |

**Cross-cutting:** own real node_modules per worktree · one advisory per PR ·
push only via `safe-push` (first push `-u`) · PR starts draft, readied at Ship (`gh pr ready`), never merged by the agent · append new traps
to the friction log.
