---
name: pickup-work
description: Use when the user wants to find and start the next piece of work — "pick up work", "what should I work on", "grab an issue", "next issue", "find me something to do". Reviews open GitHub issues, surfaces the unassigned + unblocked ones, recommends one, and waits for go-ahead before any work starts.
---

# Pick up work

Survey open GitHub issues, recommend one unassigned, unblocked issue to work on
next, and **stop for the user's go-ahead** before starting anything.

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

2. **Classify each issue:**
   - **Assigned** — `assignees` is non-empty. Exclude from candidates (someone owns it).
   - **Blocked** — any of:
     - a label like `blocked`, `on-hold`, `wontfix`, `needs-info`, `discussion`
     - the title/body says it depends on, is blocked by, or waits for another issue/slice
       (check the body with `gh issue view <n>` for anything that looks dependent)
     - it references an unmerged dependency or an undecided question (TBD/DEC)
   - **Pickable** — unassigned AND not blocked.

3. **For the top candidate(s), read the body** (`gh issue view <number>`) to confirm
   it's genuinely actionable — scope is clear, dependencies are merged, no open
   question gating it. An issue that *looks* simple from its title but says "blocked
   on X" in the body is NOT pickable.

4. **Present the review** (see format below): the full open list with status, then
   your recommended pick and *why*, then the question.

5. **STOP and wait.** Do not branch, assign, or create a worktree until the user
   responds.

## Output format

```
## Open issues (N)

| #  | Title                          | Status                    |
|----|--------------------------------|---------------------------|
| 38 | Nav item loses active state…   | ✅ pickable               |
| 37 | User selector typeahead        | ✅ pickable               |
| 35 | Compliance upload + indexing   | 🔒 blocked (needs FTS)    |
| 12 | Foo                            | 👤 assigned (@someone)    |

## Recommendation

**#38 — Nav item loses active state on sub-pages.** Unassigned, no blockers, scope
is self-contained (a frontend active-state fix), and it's a quick win.

Want me to start #38, or would you rather pick another? (I'll start it via the
feature-worktree-workflow once you confirm.)
```

## Choosing the recommendation

When several issues are pickable, prefer, in order:
1. **Bugs** over enhancements (`bug` label) — defects usually matter more.
2. **Smaller, self-contained scope** — quicker to ship, less integration risk.
3. **Milestone / higher-priority labels** if present.

State the reason for your pick in one line — the user is deciding whether to trust it.

## Common mistakes

- **Recommending an assigned issue.** Always exclude non-empty `assignees`.
- **Trusting the title.** A title can look trivial while the body says "blocked on #29".
  Read the body of your top pick before recommending it.
- **Starting work.** This skill ends at a question. Starting a branch/worktree is the
  next skill's job, after go-ahead.
- **Listing only candidates.** The user asked for a review of *all* open issues — show
  the full list with status, not just the pickable ones.
