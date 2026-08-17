---
name: pickup-work
description: Use when the user wants to find and start the next piece of work - "pick up work", "what should I work on", "grab an issue", "next issue", "find me something to do". Reviews open GitHub issues plus the shared agent ledger, surfaces the unassigned + unclaimed + unblocked ones, recommends one, and waits for go-ahead before any work starts.
---

# Pick up work

Survey open GitHub issues **and what other agents already have in flight**, recommend
one unassigned, unclaimed, unblocked issue to work on next, and **stop for the user's
go-ahead** before starting anything.

This skill only *selects* the work. Once the user approves an issue, hand off to
the **feature-worktree-workflow** skill (Phase A) to actually start it.

## The rule

**Never start work from this skill.** Its output is a recommendation + a question.
You present the full picture, name your pick, and wait. The user either says "go"
(→ feature-worktree-workflow) or names a different issue.

## Steps

1. **Fetch all open issues** with the data needed to judge assignment and blockedness:

   ```
   gh issue list --state open --limit 100 \
     --json number,title,labels,assignees,milestone
   ```

2. **Read the shared agent ledger** - what other agents already have in flight:

   ```
   ~/.claude/skills/agent-ledger/ledger list --json
   ```

   GitHub assignment lags a claim by a minute or two, so the ledger is the *authoritative*
   answer to "is anyone already on this?". See the `agent-ledger` skill for the full
   protocol. If the script is missing or errors, say so in one line and carry on with
   GitHub data alone - a missing ledger degrades the review, it does not block it.

3. **Classify each issue:**
   - **In flight** - a live ledger entry for that issue number. Exclude from candidates,
     **even when GitHub shows it unassigned**. Show who holds it, their branch/PR and status.
   - **Assigned** — `assignees` is non-empty. Exclude from candidates (someone owns it).
   - **Blocked** — any of:
     - a label like `blocked`, `on-hold`, `wontfix`, `needs-info`, `discussion`
     - the title/body says it depends on, is blocked by, or waits for another issue/slice
       (check the body with `gh issue view <n>` for anything that looks dependent)
     - it references an unmerged dependency or an undecided question (TBD/DEC)
   - **Pickable** - unassigned AND unclaimed AND not blocked.

4. **For the top candidate(s), read the body** (`gh issue view <number>`) to confirm
   it's genuinely actionable — scope is clear, dependencies are merged, no open
   question gating it. An issue that *looks* simple from its title but says "blocked
   on X" in the body is NOT pickable.

5. **Check your top pick for overlap with in-flight work.** From the body, judge which
   paths it likely touches and compare against the `touches` of live ledger entries
   (`ledger overlaps --touches <paths>` does this for you). Overlap does **not** make an
   issue unpickable - it changes the advice:
   - **Needs the other branch's commits** → recommend stacking, and name the parent
     branch so Phase A can branch off it (`--stacked-on`).
   - **Same area, independent change** → recommend it as normal, but say which in-flight
     work it sits near so the user can sequence it if they'd rather.

6. **Present the review** (see format below): the full open list with status, then
   your recommended pick and *why*, then the question.

7. **STOP and wait.** Do not branch, assign, claim a ledger entry, or create a worktree
   until the user responds. **`pickup-work` never writes to the ledger** - claiming
   happens in Phase A of `feature-worktree-workflow`, after go-ahead.

## Output format

```
## Open issues (N)

| #  | Title                          | Status                              |
|----|--------------------------------|-------------------------------------|
| 38 | Nav item loses active state…   | ✅ pickable                         |
| 37 | User selector typeahead        | ✅ pickable - near I#883 (forms)    |
| 35 | Compliance upload + indexing   | 🔒 blocked (needs FTS)              |
| 12 | Foo                            | 👤 assigned (@someone)              |
| 883| CSV export                     | 🤖 in flight - wt-883@dev, PR#921 wip |

## Recommendation

**I#38 - Nav item loses active state on sub-pages.** Unassigned, unclaimed, no blockers,
scope is self-contained (a frontend active-state fix), and it's a quick win.

Want me to start I#38, or would you rather pick another? (I'll start it via the
feature-worktree-workflow once you confirm.)
```

When the pick overlaps in-flight work, add one line to the recommendation rather than a
new section:

```
**I#37 - User selector typeahead.** Unassigned, unclaimed, unblocked. It touches
`src/forms`, where I#883 (wt-883@dev, PR#921, wip) is also working - it doesn't need
I#883's commits, so I'd branch off `develop` as normal and let the Phase C rebase sort
out any conflict. Say the word if you'd rather stack it on `feat/883-csv-export`.
```

## Choosing the recommendation

When several issues are pickable, prefer, in order:
1. **Bugs** over enhancements (`bug` label) — defects usually matter more.
2. **Smaller, self-contained scope** — quicker to ship, less integration risk.
3. **Milestone / higher-priority labels** if present.

State the reason for your pick in one line — the user is deciding whether to trust it.

## Common mistakes

- **Recommending an assigned issue.** Always exclude non-empty `assignees`.
- **Skipping the ledger.** GitHub assignment lags a claim, so an issue can look free on
  GitHub while another agent is three commits into it. Always run `ledger list` first.
- **Claiming the issue here.** This skill reads the ledger; it never writes to it.
- **Treating an overlap as a blocker.** Overlap changes the advice, not the pickability.
- **Trusting the title.** A title can look trivial while the body says "blocked on #29".
  Read the body of your top pick before recommending it.
- **Starting work.** This skill ends at a question. Starting a branch/worktree is the
  next skill's job, after go-ahead.
- **Listing only candidates.** The user asked for a review of *all* open issues — show
  the full list with status, not just the pickable ones.
