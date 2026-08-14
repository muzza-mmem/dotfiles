# Global working rules

## `develop` is the base branch - never touch `main` on this machine

**IMPORTANT:** Repos are migrating to a `develop` / `main` split: **`develop` is the base
branch for all development**, and **`main` is release/production only**. `portal-core` and
`portal-qms` have migrated; the rest follow gradually, so **detect the base per repo rather
than assuming either name**:

```bash
git fetch origin --prune
BASE=develop; git show-ref -q --verify refs/remotes/origin/develop || BASE=main
```

Then use `origin/$BASE` as the branch point, the PR base, the rebase target, and the thing
merged into `testing`. Always work from the **freshly fetched remote-tracking ref**, not a
local copy - that is what keeps the base current.

**Never check out or pull `main` on a developer machine.** No `git checkout main`, no
`git switch main`, no `git pull` on `main`, no `git merge origin/main` into a feature branch
or `testing`. If a step appears to need `main`, it needs `origin/$BASE` instead. Work reaches
`main` through the release flow, never through a local checkout.

**The one exception is cutting a release**, which is a repo-script operation, not something
you do by hand: `./scripts/release cut <type>` fetches `origin main` itself, builds the
release commit in its own throwaway worktree, and pushes fast-forward-only. It never touches
your checkout and does not care which branch you are on, so cutting a release still requires
no local `main`. Do not promote `develop` to `main` by hand.

This split is being rolled out repo by repo, so the detection above is temporary scaffolding.
Once every repo has `develop` it resolves to a constant and nothing else has to change.

## Never use em dashes

**IMPORTANT:** In all written output - documentation, code comments, commit
messages, PR descriptions, issue text, and any draft message intended for a
third party - **never use a long dash**: no em dash (U+2014) and no en dash
(U+2013). Always use the plain ASCII hyphen-minus (U+002D, the `-` key),
surrounded by spaces when it is acting as a separator.

This applies to text I will read as well as text that leaves the machine. If a
sentence feels like it needs an em dash, either use a spaced hyphen or rewrite
it with a comma, colon, or full stop.

## Always distinguish issue numbers from PR numbers

**IMPORTANT:** GitHub issues and pull requests share one numbering space, so a bare
`#123` is ambiguous. Always qualify which one is meant:

- an issue is **`I#<number>`** - e.g. `I#883`
- a pull request is **`PR#<number>`** - e.g. `PR#890`

Never write a bare `#<number>` when referring to one specifically. This applies to
text I will read - chat replies, summaries, status tables - and to text written into
a file or sent anywhere: commit messages, PR titles and descriptions, issue and PR
comments, QA plans, Jira tickets, and docs.

**One exception, because these strings are load-bearing.** Where a `#<number>` is
parsed by a tool rather than read by a person, keep it bare and exactly as the tool
expects. Most importantly, GitHub's auto-link keywords: write `Closes #883` in a PR
body verbatim, or the issue will not auto-close on merge. When a PR title needs the
issue in brackets at the end, use `(I#883)`.

Quoting is not rewriting: if a file, ticket, or log already says `#883`, quote it
verbatim and let the surrounding sentence supply the `I#` / `PR#` qualifier.

## Publish anything I have to read to make a decision

**IMPORTANT:** Long-form output meant for me to review belongs in the md-mcp viewer,
not scrolling past in the terminal. Whenever a response is a substantial chunk of
prose or tables that I have to read through before deciding something, run the
`publish` skill (`/publish`) on it as part of producing it - don't wait to be asked.

Publish by default for things like:

- review findings, audit results, code-review or PR-review output
- explanations, analyses, investigations, root-cause write-ups
- plans, proposals, option comparisons, trade-off write-ups
- status summaries, weekly recaps, migration or release reports
- anything long enough that I would have to scroll back to take it in

Keep the terminal reply to a short pointer: one or two lines of headline plus the
page title, with the detail living in the viewer. Publish the content verbatim -
the viewer copy is the full version, not a second draft.

Skip publishing only when I explicitly say not to, or for short conversational
replies, direct answers to a direct question, and routine progress narration.
When in doubt, publish.

## Tests are a separate, explicitly-consented phase (TDD)

- **Never write or modify tests as part of implementation work.** Producing or
  changing test files is its own task and requires my **explicit consent each time**.
  Do not bundle test creation/edits into a feature, fix, or refactor change.
- **Use TDD:** when a unit of work (e.g. a slice/feature) is being built, write the
  tests **first** as a distinct, consented step, confirm they fail for the right
  reason, and only **then** do the implementation as a **separate** step.
- If implementation work would benefit from new or changed tests, **stop and ask**
  before touching any test file.

### How to apply TDD when symbols don't exist yet

Write the failing test directly against the API you intend to build. If a symbol
doesn't exist yet, add only the **minimal scaffolding** the test needs to run and fail
on **behaviour** (an assertion failure), not on a compile/import error - but no real
logic. Confirm it's red for the right reason, then implement as a **separate** step to
turn it green. There is **no separate "skeleton-only" phase** - the test and whatever
stub it needs to execute are written together, with consent, in one step.

Heavier test layers (integration against a real DB, e2e) are their own later explicit
phases - don't fold them into the unit cycle above.

### Minimal, high-value tests - precedence over the superpowers TDD skill

The superpowers `test-driven-development` skill is rigid and pushes broad coverage with
red-green-refactor on every unit. **These rules take precedence over it:** write the
**minimum** tests that capture the most valuable behaviour, never expand coverage just
because the skill encourages it, and never add or tweak tests during implementation.
A test, once written, **specs how the code must behave** - implement to the test; do
**not** reshape the test just to get CI green.
