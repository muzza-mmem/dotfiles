---
name: feature-worktree-workflow
description: Use when starting, integrating, shipping, or tearing down a feature/issue via the worktree + integration-branch flow — every unit of work is anchored to a GitHub issue, branched off main in a git worktree, tracked by a WIP draft PR, integrated on the `testing` branch, then shipped to main and cleaned up. Trigger on "start a feature", "work this issue", "new worktree", "integrate/merge into testing", "raise/ready the PR", "feature is merged, clean up".
---

# Feature worktree workflow

A four-phase loop for shipping a feature: **Start → Integrate → Ship → Teardown**.
Each phase has a hard guardrail. The phases are usually run across separate turns
(work happens between Start and Integrate), so re-read the relevant phase when you
re-enter the loop.

**Every unit of work is anchored to a GitHub issue.** The issue is the unit of work,
the branch, and (via the WIP draft PR) the thing being reviewed. No issue → no branch.

---

## Interaction contract (SET ONCE AT KICKOFF — THEN DO NOT RE-PROMPT)

**THIS IS THE MOST IMPORTANT RULE IN THIS SKILL. The user's overriding goal is to be
hands-off. Being asked "do you want to proceed?" mid-run, or coming back to a session
that is waiting on an approval it was told to skip, is a FAILURE of this workflow.**

Before doing ANY work (before brainstorming/spec, before Phase A actions), establish the
interaction contract **once**. It governs every optional prompt for the whole run. Once
set, **you MUST NOT ask the user to approve, confirm, or "proceed" at any stage the
contract says to skip** — not the spec, not the plan, not the implementation approach, not
Jira, not the milestone. The contract is captured a single time and honored to the end.

### Mode selection

**If the kickoff message contains the word `yolo` → YOLO MODE (fully autonomous to the
end of Phase B):**

- **Auto-approve the spec and the plan.** Still run brainstorming / writing-plans if the
  work benefits, but DO NOT wait for sign-off — produce them and proceed straight through.
- **Implementation:** use subagent-driven implementation **only when it is genuinely
  recommended** (two or more independent, well-scoped tasks — see Phase A). Otherwise go
  inline. **Never ask** which to use.
- **Every Phase A/B prompt is resolved by its hands-off default, silently:**
  - Jira → **Skip (GH-only)** (write the `Jira: none` marker; never create a ticket).
  - Milestone → **attach to an obvious in-flight epic only; never create a new milestone.**
  - Implementation approach → auto (rule above).
  - Phase B boot-verify → note whether it matters and hand the stack restart to the user;
    **do not ask.**
- **Zero follow-up questions** from kickoff until the natural end-of-Phase-B handoff.

**Otherwise → present a ONE-TIME form (`AskUserQuestion`) at kickoff**, then obey the
answers for the rest of the run:

1. *Which stages do you want to be involved in?* (multi-select: **Spec review**, **Plan
   review** — leaving one unchecked means hands-off / auto-approve that stage).
2. *Implementation approach?* (single-select: **Auto — subagent when recommended, else
   inline (no prompt)** [default] · **Always ask me** · **Prefer inline** · **Prefer
   subagent**).

For every stage the user did **not** opt into, apply the YOLO-mode default above
**silently** — no prompt at that stage, ever. **Only pause at a stage the user explicitly
opted into.** If the user opted out of everything, the run is effectively yolo.

### The only unconditional stops (these are safety roadblocks / handoffs, NOT approvals)

These always apply regardless of the contract — they are not "do you want to proceed"
prompts:

- **No issue exists** (Phase A Guardrail 1) — cannot fabricate a unit of work.
- **`testing` not checked out on MAIN_ROOT** (Phase A Guardrail 2).
- **Stack restart at the end of Phase B** — a handoff, not a question; the user owns the
  shared stack.
- **NEVER merge the PR yourself** (Phase C) — a handoff, always.

Everything else is governed by the contract. When in doubt about whether a prompt is
allowed: if the contract didn't opt into it and it isn't one of the four stops above,
**do not ask — apply the default and keep going.**

---

## Conventions & detection

- **MAIN_ROOT** = the primary working tree (root repo), not a linked worktree.
  Resolve it the same way the worktree script does:
  `git worktree list --porcelain | awk '/^worktree /{print $2; exit}'`
- **Integration branch** = `testing`. It is long-lived but **disposable** — never the
  thing you ship. The PR ships the feature onto `main` *alone*. **`testing` is
  local-only — NEVER push it to origin** (no `git push` on `testing`, ever). It exists
  purely as a local smoke env; origin only ever sees feature branches and `main`.
- **Branch name = the issue.** Format `<type>/<number>-<slug>`, where `<type>` reflects
  the issue kind (`feat` for feature/enhancement, `bug` for defect/fix, `chore` for
  maintenance/tooling — match the issue's labels/type), `<number>` is the issue number,
  and `<slug>` is a short kebab-case summary of the title.
  e.g. issue #42 "Add CSV export" → `feat/42-add-csv-export`;
  issue #57 "Export crashes on empty set" → `bug/57-export-crashes-on-empty-set`.
- **Worktree tooling**: if `./scripts/worktree` exists in the repo, prefer it (it
  provisions `.env`, submodules, shared Compose project). Otherwise fall back to raw
  `git worktree`.
- **Push every commit immediately.** There is no local-only commit in this flow — after
  every `git commit` **on a feature branch**, `git push` so origin and the draft PR always
  reflect HEAD. (The sole exception is `testing`, which is never pushed — see above.)
- **Always pull `main` from origin before merging it.** Whenever you merge `main` into
  anything (`testing` in Phase B, or refreshing for a rebase), update it from origin first
  (`git pull` on `main`, or `git fetch origin` + merge `origin/main`) — never merge a stale
  local `main`.
- **The issue/PR is the work log.** As work progresses, keep it current — post issue
  comments on meaningful checkpoints/decisions, or keep the PR description's task list
  ticked off. Don't go dark between Start and Ship.
- **Shared stack note**: in repos using the "one shared Docker stack" model (e.g.
  portal-qms pins `COMPOSE_PROJECT_NAME`), only ONE stack runs at a time across all
  worktrees. `./scripts/stop` the active one before `./scripts/start` elsewhere.

---

## Phase A — Start a feature

**GUARDRAIL 1 (roadblock — do not skip): a GitHub issue must exist.**
If the user did not provide an issue, **STOP and ask for it**, or **propose creating one**
and create it on their go-ahead (`gh issue create`). Do not start work without an issue.
Confirm it exists: `gh issue view <number>`.

Once you have the issue, **assign it to the user**:

```
gh issue edit <number> --add-assignee @me
```

**Assign the issue to its slice/epic milestone.** Milestones here represent a
multi-issue deliverable (a slice/epic — e.g. "PO-centric flows refactor",
"#175 decouple product↔supplier"), not a sprint or a release. So:

- If the issue belongs to an in-flight epic, attach it:
  `gh issue edit <number> --milestone "<epic title>"`
  (list options with `gh api repos/:owner/:repo/milestones --jq '.[].title'`).
- If the issue **starts a new epic** (it's the first of several related issues),
  propose creating a milestone and create it on the user's go-ahead — `gh` has no
  native create, use the API:
  `gh api repos/:owner/:repo/milestones -f title="<epic>" -f description="<scope>"`
  (add `-f due_on="<ISO-8601>"` only if there's a real target date).
  **Hands-off (yolo / opted-out): attach to an obvious in-flight epic only; never create
  a new milestone and never prompt — skip it.**
- If the issue is a genuine one-off (not part of any epic), **skip** — don't force
  a milestone. The `Closes #<number>` PR link advances the milestone bar on merge,
  so no other phase needs to touch it.

**GUARDRAIL 2 (roadblock — do not skip):** verify `testing` is checked out on MAIN_ROOT.

```
ROOT=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
git -C "$ROOT" symbolic-ref --short HEAD     # must print: testing
```

- If it prints `testing` → proceed.
- If it prints something else (e.g. `staging`, `main`) → **STOP and ask the user.**
  The normal expectation is that `testing` is checked out on the root repo. Likely
  resolutions to offer:
  - check out the existing `testing` branch on the root, or
  - if `testing` does not exist, create it from main: `git -C "$ROOT" checkout -b testing main` (or `origin/main`).
  Do not silently continue on the wrong branch.

Then create the feature branch **off main** in a worktree (name it from the issue —
see Conventions) and switch into it:

```
./scripts/worktree -b <type>/<number>-<slug> main        # preferred if present
# fallback:
git worktree add -b <type>/<number>-<slug> "$ROOT/worktrees/<type>-<number>-<slug>" main
```

Switch the agent into the worktree (EnterWorktree tool, or `cd` to the worktree path).
Then **push the branch and open the WIP draft PR immediately** — bootstrap with an empty
commit so the branch is one commit ahead of `main` and the PR has a diff to open against:

```
git commit --allow-empty -m "chore: scaffold #<number>"
git push -u origin <type>/<number>-<slug>
gh pr create --draft --base main \
  --title "WIP: <issue title>" \
  --body "Closes #<number>"     # auto-links + auto-closes the issue on merge
```

**Link Jira? Ask ONLY when the contract allows it (the mirror is optional).** GitHub is
the source of truth; the AII mirror is optional — some issues live in GitHub only.
**Hands-off (yolo / opted-out): do NOT ask — default to Skip (GH-only)**: invoke
`jira-sync` `skip <number>` to write the `Jira: none` marker, and move on. Otherwise ask
the user which of three to do, then act:

- **Create a new AII ticket** → invoke `jira-sync` `sync start <number>`
  (find-or-create, cross-link, move to **In Progress**).
- **Link an existing AII ticket** (the user supplies the key, e.g. `AII-456`) → invoke
  `jira-sync` `link <number> AII-456`, then move it to **In Progress**
  (`jira-sync` `status AII-456 In Progress`).
- **Skip linking (GitHub-only)** → invoke `jira-sync` `skip <number>` to record a
  durable `Jira: none` marker on the GH issue. No AII ticket is involved.

Record the choice **once, here.** The `Jira:` line in the GH issue body (`AII-xxx` or
`none`) is what Phases C/D read to decide whether to mirror — so they never re-prompt or
silently backfill a ticket. A Jira failure must not block the flow (it warns and
continues).

Now do the feature work here. Every commit gets pushed immediately (see Conventions),
so the draft PR tracks progress in real time.

**Choose the implementation approach — subagent-driven vs. inline.** First honor the
interaction contract: in **yolo / Auto** mode use subagents **only when recommended**
(criteria below) and otherwise go inline — **never ask**. Only ask when the user opted
into *Always ask me*; *Prefer inline* / *Prefer subagent* force that choice with no
prompt. Before writing code, assess whether this piece of work is a good fit for
subagent-driven implementation (the `superpowers:subagent-driven-development` skill, or
`superpowers:dispatching-parallel-agents` when the independent tasks can run concurrently).

- **If subagent-driven implementation is recommended, use it — do NOT ask.** Announce that
  you're doing so and proceed. It is recommended when the work decomposes into two or more
  **independent, well-scoped tasks** with no shared mutable state or tight sequential
  coupling — e.g. a written plan with parallelisable steps, changes spread across several
  modules/files that don't depend on each other, broad mechanical sweeps (rename/migrate
  across many sites), or fan-out research/implementation that one context would bloat.
- **Otherwise, ask the user** which approach they'd prefer (inline vs. subagent-driven)
  before starting. Not-clearly-recommended covers small single-file changes, tightly
  coupled logic that needs continuous shared context, or exploratory work needing tight
  local iteration — cases where subagents add coordination overhead without a real win.

Rule of thumb: **recommended → just do it; unclear → ask ONLY if the contract permits it.**
When in doubt about whether the decomposition is genuinely independent, treat it as
unclear: in *Always ask me* mode, ask; in yolo / Auto mode, **default to inline and
proceed — do not ask.**

> Branch off **main**, never off `testing` — this keeps the eventual PR diff clean.

---

## Phase B — Integrate (work complete, before testing)

Integration happens on MAIN_ROOT, not in the worktree.

1. Re-run the Phase A `testing` guardrail (`testing` checked out on MAIN_ROOT).
2. From MAIN_ROOT, **refresh `main` from origin first** (never merge a stale local `main`):
   `git fetch origin`, then `git merge origin/main` (into testing), then `git merge <branch>`
   (into testing).
3. Resolve any conflicts **here** — they're disposable on `testing`. (They do NOT carry
   to the feature→main PR; keep the feature rebased on main so the PR stays clean.)
4. Run static checks on MAIN_ROOT — type-check, lint, unit tests. **Then STOP and hand the
   stack restart to the user — do NOT run `qms-start` (or any `start`/`stop`/compose/recreate)
   yourself.** The user controls the single shared local stack and decides when it cycles.
   Report that `testing` is merged and static checks pass, and hand off. Booting is still the
   only way to catch Nest DI / module-graph boot crashes, so if a boot-verify matters for this
   change, **ask** — don't auto-boot. **Hands-off (yolo / opted-out): do NOT ask — just note
   in the handoff whether a boot-verify is worth it and let the user decide.** (The end-of-B
   handoff is the natural stopping point, not an approval prompt.) (For reference, the user's restart is
   `~/.local/bin/qms-start --no-watch --qms-only`: portal-qms stop→start without touching
   portal-core; drop `--qms-only` to also restart portal-core, `--no-watch` to live-tail logs.)

> **`testing` is a smoke env, not the merge gate.** It holds every in-flight feature at
> once, so a green `testing` does not prove the feature is green on `main` alone — another
> feature may be masking the issue. The PR's own CI (base = main) is the real gate.

---

## Phase C — Ship (all issue tasks done, tested OK)

1. Switch to the feature worktree.
2. **Rebase on latest `main` — mandatory, and the point where conflicts get caught
   (roadblock — do not skip).** `git fetch origin`, then `git rebase origin/main` on the
   feature branch — **always run it, even if you think `main` hasn't moved** (the old
   "rebase only if it has moved" is gone; run it unconditionally). Resolve any conflicts
   **right here**, before the PR is marked ready (step 4): this is the earliest clean point
   to surface them, and resolving now stops the PR's base-`main` CI — the real gate — from
   failing on a conflict later, and stops phantom conflicts leaking into the Phase D
   `main`→`testing` merge. Then force-push with lease: `git push --force-with-lease`.
   Do **not** proceed to `gh pr ready` until the rebase is clean and pushed.
3. **Add this release to the notes — in *this* PR, not a follow-up.** Run the
   `append-release-note` skill to add this issue to `docs/releases/<YYYY-MM-DD>.md`,
   **including the current issue even though it is still open**: it closes when
   this PR merges, so document it as shipped now (a "premature" close). In this repo
   every closed issue is a release recorded into that day's report; committing the
   report on this branch means the release note ships in the same PR — we never open
   a second PR just to add release notes. Skip only when the change genuinely
   warrants no note (pure internal tooling/chore).
4. **Mark the draft PR ready** (the PR already exists from Phase A): `gh pr ready <number-or-url>`.
   Drop the `WIP:` prefix from the title and make sure the description reflects the final scope.
5. **Comment on the issue with a summary** of what was done:
   `gh issue comment <number> --body "<summary of changes, decisions, anything notable>"`.
6. **Sync Jira (mirror), unless GH-only:** if the GH issue body has a `Jira: none` line,
   skip this step. Otherwise invoke `jira-sync` — `sync review <number>` — to move the
   AII ticket to **Code Review / Testing** and comment the PR URL on it. Warns and
   continues on failure.
7. The PR's CI against `main` is the authoritative gate — not the `testing` result.

**GUARDRAIL (roadblock — do not skip): rebase clean on `origin/main` BEFORE `gh pr ready`.**
The mandatory `git rebase origin/main` in step 2 is where conflicts are caught early. The PR
must not be marked ready while the branch is behind `main` or has unresolved conflicts —
resolve them on the feature branch here, not at merge time.

**GUARDRAIL (roadblock — do not skip): NEVER merge the PR yourself.** Merging is the
user's explicit step, always. Do not run `gh pr merge` (or merge via the UI/API) even
when CI is green and the user says "ship" — "ship" means get the PR ready-for-review and
hand off. Stop here and tell the user the PR is ready for them to merge. Only proceed to
Phase D once the user confirms they have merged it (or explicitly tells you to merge this
one time).

---

## Phase D — Teardown (PR merged by the user)

**GUARDRAIL:** you cannot remove the worktree you are standing in. `cd` back to MAIN_ROOT first.

```
ROOT=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
cd "$ROOT"
git checkout main && git pull           # refresh main
./scripts/worktree rm <branch>          # or: git worktree remove --force <path>
git branch -d <branch>                  # worktree rm leaves the local branch — delete it
git push origin --delete <branch>       # also delete the merged feature branch on origin
git checkout testing && git merge main  # bring the merged feature into testing (local-only, never pushed)
```

The `Closes #<number>` in the PR body closes the issue automatically on merge — confirm
it closed (`gh issue view <number>`); close it manually if the link didn't resolve.

**Sync Jira (mirror), unless GH-only:** if the GH issue body has a `Jira: none` line,
skip this step. Otherwise invoke `jira-sync` — `sync uat <number>` — to move the AII
ticket to **Ready for UAT** (the flow never sets it to Done; that's a manual step after
UAT). Warns and continues on failure.

> **Squash-merge drift (watch for this):** if the PR was squash- or rebase-merged, `main`
> gets a NEW commit SHA that never matches the feature commits already sitting in `testing`
> from Phase B. Merging `main` into `testing` then stacks the squashed commit on top of the
> originals → duplicated history and recurring phantom conflicts (a wall of
> `Merge branch '…' into testing` is the symptom). When that cruft accumulates, **reset the
> integration branch instead of merging**:
> `git checkout testing && git reset --hard origin/main` (do **not** push — `testing` is
> never pushed to origin). `testing` is disposable — recreating it from `main` is always safe.

---

## Fast-track mode (skip Phase B)

For small, self-contained, low-risk changes — e.g. read-path bug fixes that mirror an
existing reference impl — the `testing` integration env adds no value: the PR's own CI
against `main` is the real gate, and `testing` only masks per-feature issues by stacking
all in-flight work. When the user says **"fast track"** an issue, run **A → C → D** and
**skip Phase B entirely** — no `testing` merge, no shared-stack restart.

Everything else is unchanged: still anchor to a GitHub issue, branch off `main`, push
every commit, open the WIP draft PR, add the release note in the *same* PR, and **never
merge the PR yourself** — Phase C still ends at `gh pr ready` + handoff.

---

## Quick reference

| Phase | Where | Action | Guardrail |
|-------|-------|--------|-----------|
| A Start | MAIN_ROOT → worktree | assign issue @me; attach slice/epic milestone (create if it starts a new epic, skip if one-off); branch `<type>/<number>-<slug>` off **main**; push; empty commit; open WIP draft PR → main; **ask: create / link existing / skip Jira** (create+link → **In Progress**; skip → `jira-sync` `skip` writes `Jira: none`) | **issue must exist** (else roadblock); `testing` checked out on root (else roadblock) |
| B Integrate | MAIN_ROOT (`testing`) | merge main, then feature; run static checks; **hand the restart to the user** (don't auto-boot) | `testing` ≠ merge gate; one shared stack; never restart without consent |
| C Ship | feature worktree | **rebase on `origin/main` (mandatory — `git fetch` + `git rebase origin/main`, resolve conflicts HERE, `push --force-with-lease`)**, add release note (`append-release-note`, same PR), `gh pr ready`, comment issue summary; **`jira-sync` `sync review` → Code Review / Testing** (skip if `Jira: none`) | **rebase clean on main BEFORE `gh pr ready`** (conflicts caught here, not at merge); PR CI is the real gate; release note ships in the same PR |
| D Teardown | MAIN_ROOT | pull main, rm worktree + local branch + **remote branch** (`git push origin --delete`), merge→testing; **`jira-sync` `sync uat` → Ready for UAT** (skip if `Jira: none`) | can't rm cwd worktree; watch squash drift; confirm issue closed |

**Cross-cutting:** **set the interaction contract ONCE at kickoff and never re-prompt — `yolo` (or opt-out of everything) = fully hands-off to end of Phase B; else a one-time form gates spec / plan / implementation involvement; hands-off defaults: Jira skip, milestone attach-only, implementation auto, no boot-verify prompt** · one issue per unit of work · **choose implementation approach in Phase A: subagent-driven if recommended (independent, well-scoped tasks) → just do it; unclear → ask only if the contract permits** · push every commit immediately (feature branches only — **never push `testing`**) · always pull `main` from origin before merging it · keep the issue/PR as a live work log · **the Jira mirror is optional — Phase A always asks create / link existing / skip; a `Jira: none` marker means GH-only, so Phases C/D skip all Jira steps** · "fast track" = skip Phase B (see Fast-track mode).
