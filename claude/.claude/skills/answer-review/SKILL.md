---
name: answer-review
description: Use when an automated review bot has reviewed and autofixed a PR you implemented, and you need to work through its findings - "/answer-review", "answer the bot review", "respond to the review comments", "triage the autofixes", "did the bot get this right". Judges each finding and each applied fix, pushes back where the bot is wrong, applies counter-fixes, and replies in-thread with an explicit verdict per comment. HARD FAILS unless run in the session that implemented the PR.
---

# Answer Review

## Overview

An automated review bot reviews PRs and pushes fixes for what it finds. This skill
works through that review from the implementer's chair: judge every finding and every
applied fix, keep what is right, replace what is wrong, push back on what does not
hold, and reply in-thread so each comment carries an explicit verdict.

**Core principle:** the value here is judgement that only the implementer has. A
session that did not write the code can only read the bot's reasoning and nod along,
which produces exactly the "good catch, fixed!" theatre this skill exists to prevent.
That is why the gate below is a hard failure and not a warning.

Pairs with `review-pr`, which is the same exchange from the reviewer's side.

## Inputs

The PR may be given as a number, `#123`, or a URL. With no argument, resolve it from
the current branch with `gh pr view --json number` and say which PR you resolved.

## Workflow

### 1. The gate - hard fail, no fallback

Run this before anything else. **Both** conditions must hold, and you must state
out loud that you checked them.

**Condition A - branch.** The current checkout or worktree is on the PR's head
branch:

```bash
PR=<number>
gh pr view "$PR" --json number,title,state,isDraft,headRefName,url
git branch --show-current   # must equal headRefName
```

**Condition B - own context.** You can point to the implementation work in *this
session's conversation*: which files you wrote, which decisions you made, why. Not
"I can read the diff" - that is not the same thing and does not count.

If either fails, **stop**. Say which condition failed and this:

> This skill only works from the session that implemented the PR. Judging a review
> without that context means agreeing with whatever sounds plausible, which is worse
> than not answering at all. Re-run this from the implementing session, or review the
> findings yourself.

Offer no fallback, no degraded mode, and no "shall I proceed anyway". Do not read the
review to be helpful before failing - fail first.

**Condition C - clean tree.** Checked at the same time. The bot has pushed commits, so
the local branch must fast-forward onto them cleanly:

```bash
git fetch origin
git status --porcelain                     # must be empty
git rev-list --count "@{u}..HEAD"          # must be 0 (no unpushed local commits)
```

If the tree is dirty or the branch has diverged, stop and say so. Let the user decide
what to do with the local work first.

### 2. Sync onto the bot's fixes

```bash
git merge --ff-only "@{u}"
git log --oneline "HEAD@{1}..HEAD"    # the commits the bot pushed
```

You are now looking at the code as the bot left it. Everything downstream judges
*this* tree.

### 3. Collect the bot's threads

The bot signs every comment. Inline comments end with a footer reading
`_Posted by review-bot - an automated review, not a human's._`; the summary review body
ends with `_review-bot cannot approve or request changes; a human casts that vote._`.
Matching `review-bot` in the body catches both. Human reviewers are out of scope for
this skill - leave their comments alone entirely.

**Detect by body text, never by author.** The bot posts under a normal user account,
not a GitHub App, so `user.type == "Bot"` never matches. On PR#970 it posted under the
*same account as the implementer*, so an author-based filter would have swallowed the
whole thread. The footer is the only reliable signal.

```bash
ME=$(gh api user --jq .login)
gh api "repos/{owner}/{repo}/pulls/$PR/comments" --paginate > /tmp/ar-comments.json

# Unanswered top-level bot findings, in file order.
jq --arg me "$ME" '
  (map(select(.in_reply_to_id != null and .user.login == $me) | .in_reply_to_id)
   | unique) as $answered
  | map(select(
      .in_reply_to_id == null
      and (.body | test("review-bot"))
      and ((.id | IN($answered[])) | not)))
  | map({id, path, line, body})
' /tmp/ar-comments.json
```

Skipping threads you have already replied to makes the skill safely re-runnable after
a second bot pass. Also read the summary review body for context on what the bot
thought it was doing:

```bash
gh api "repos/{owner}/{repo}/pulls/$PR/reviews" \
  --jq '.[] | select(.body | test("review-bot")) | .body'
```

If there are no bot threads, say so in one line and stop. **Do not review the PR
yourself** - that is `/review-pr`, and it is a different job.

### 4. Read each finding's actual fix

Every bot comment declares its own fix status in the body:

| Marker | Meaning |
|---|---|
| `✅ Fixed in the pushed commit <sha>:` | It changed code. The SHA is cited in the comment. |
| `🚨 Not fixed:` | It declined, and is handing the decision back to you. |

For every `✅` finding, read the actual hunk before ruling on it:

```bash
git show <sha> -- <path>
```

The bot's prose description of its own fix is a **claim, not evidence**. A fix that
describes itself correctly can still be at the wrong layer, incomplete, or paper over
the symptom. Read the diff.

### 5. Judge - one verdict per finding

Invoke `superpowers:receiving-code-review` and hold to its posture. Three rules on top
of it, and they are hard constraints:

- **Never agree without naming the mechanism.** If your reply cannot state the specific
  line or control-flow path that makes the finding true, your verdict is not "accept" -
  it is "not decided yet". Go and read more code.
- **Agreement and pushback cost the same.** Do not accept because the bot sounds
  confident, and do not reject because you wrote the original. Both are failures of the
  same kind. Name whichever one you catch yourself doing.
- **Judge the finding and the fix separately.** "The defect is real but the fix is
  wrong" is one of the most common outcomes and needs saying explicitly.

The five verdicts:

**For `✅ Fixed` findings:**

1. **Accept** - the fix is right and stays. Reply names the mechanism that makes it
   right.
2. **Accept the finding, replace the fix** - the defect is real, the fix is wrong,
   incomplete, or at the wrong layer. Write your own on top. Reply says what was
   insufficient about theirs.
3. **Push back** - the finding does not hold, or the fix causes a worse problem than it
   solves. Revert the change (usually the hunk, not the whole commit). Reply gives the
   reasoning. This is a first-class outcome, not a last resort.

**For `🚨 Not fixed` findings:**

4. **Decide and fix** - make the call the bot handed back, implement it.
5. **Decide, no change** - the current behaviour is correct or is a deliberate
   deviation. Put the rationale in the reply *and* in the code where a future reader
   would need it.

**Defer** is available for findings that are real but genuinely outside this PR's
scope. It never fires on its own: propose it, and only file the GitHub issue if the
user says yes.

### 6. Show the triage table and STOP

Present the verdicts and wait for approval. Nothing is pushed and nothing is posted
before the user answers.

```
## Triage - PR#<n>, <k> findings

| # | File | Sev | Bot's claim | Bot fixed? | Verdict | Why | Code change |
|---|------|-----|-------------|-----------|---------|-----|-------------|
| 1 | ad.service.ts:442 | Minor | <one line> | ✅ | Replace fix | <one line> | yes |
| 2 | ...                                                                     |
```

Then ask, in one `AskUserQuestion` call:

1. **Proceed** (single, header `Proceed`) - "Act on these verdicts?" with options
   **Yes, all**, **Yes, but let me override some**, **No, stop**.
2. If any verdict is Defer, a second question confirming whether to file the issues.

If the user overrides a verdict, take the override, redo any code change it implies,
and re-show the table. This gate exists because pushing to a shared branch and posting
public replies are both outward-facing and awkward to retract - and the verdicts are
the part most worth correcting first.

Per the user's global rules, publish the triage table to the md-mcp viewer with
`/publish` rather than scrolling it past in the terminal, and keep the terminal reply
to a one-line pointer plus the question.

### 7. Apply the code changes

Only for verdicts 2, 3, 4. Make the changes, then:

```bash
./scripts/pr-checks          # must pass completely, not mostly
git add -A && git commit -m "<type>(<scope>): <what changed> (I#<issue>)"
./scripts/safe-push
```

**Never `git push`.** Always `./scripts/safe-push`. If pr-checks fails, fix it and run
again - do not push and do not reply until it is green.

Record the resulting SHA. Replies cite it.

### 8. Reply in-thread, one per finding

```bash
BODY=$(cat <<'MSG'
<verdict line>

<reasoning, and the SHA if code changed>
MSG
)
jq -n --arg body "$BODY" '{body: $body}' \
  | gh api --method POST "repos/{owner}/{repo}/pulls/$PR/comments/<comment-id>/replies" --input -
```

Open each reply with its verdict so the thread is skimmable, then give the reasoning.
Cite the SHA whenever code moved. Worked examples, all from PR#970:

- **Accept:** *"Keeping your fix. Verified the mechanism: `pc.isActive = true` in the
  query means a deactivated PC never reaches the map, so the controller nulls its
  fields."*
- **Replace:** *"Fixed in 618a50d7. `searchProfitCentres` now returns
  `{ profitCentres, totalMatched }` and the panel renders the count - your version
  logged the truncation server-side, where an admin never sees it."*
- **Push back / no change:** *"Recorded as a deviation in 618a50d7 rather than
  migrated, because the prescribed fix doesn't hold up here. portal-core has no global
  exception filter, so [reason]."*

Then one summary comment on the PR:

```bash
gh pr comment "$PR" --body "Answered <k> findings: <a> accepted, <b> fix replaced, <c> pushed back, <d> deferred. Changes in <sha>."
```

### 9. Report

Short terminal summary: the tally, the SHA, and anything the user should look at. If
any finding was deferred, name the issue numbers as `I#<n>`.

## Scope - what this skill does not do

- **Does not resolve threads.** Marking a conversation resolved is the reviewer's call,
  not the author's.
- **Does not approve, merge, or mark the PR ready.** `feature-worktree-workflow` owns
  the PR lifecycle.
- **Does not review the PR.** It answers a review that already exists.
- **Does not touch human reviewers' comments.** Bot threads only.
- **Creates no worktree of its own.** It runs in the implementer's existing worktree,
  because that is the entire premise.

## Quick Reference

| Step | Command |
|------|---------|
| Gate: branch | `gh pr view $PR --json headRefName` vs `git branch --show-current` |
| Gate: clean | `git status --porcelain` empty and `git rev-list --count @{u}..HEAD` = 0 |
| Sync | `git fetch origin && git merge --ff-only @{u}` |
| Bot threads | `gh api repos/{owner}/{repo}/pulls/$PR/comments --paginate` + the jq above |
| A fix's diff | `git show <sha> -- <path>` |
| Checks | `./scripts/pr-checks` |
| Push | `./scripts/safe-push` (never `git push`) |
| Reply | `gh api --method POST repos/{owner}/{repo}/pulls/$PR/comments/<id>/replies --input -` |

## Common Mistakes

- **Running it from a session that did not implement the PR.** The gate is the skill.
  Failing it is the correct outcome, not an obstacle to route around.
- **Accepting a fix from its description.** Read the hunk. The bot's summary of its own
  change is a claim.
- **Replying "good catch, fixed" with no mechanism.** If you cannot name the line that
  makes it true, you have not decided yet.
- **Reflexively defending your own code.** The mirror image of the same failure.
- **Judging the finding and the fix as one thing.** "Real defect, wrong fix" is common
  and needs saying.
- **Posting or pushing before the step 6 gate.** Both are hard to retract.
- **Replying before pr-checks is green.** The reply cites a SHA that must actually be
  good.
- **Using `git push`.** Always `./scripts/safe-push`.
- **Reviewing the PR when no bot review exists.** Stop and say so instead.
