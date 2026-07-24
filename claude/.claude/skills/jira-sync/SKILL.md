---
name: jira-sync
description: Use to mirror a GitHub-issue's dev lifecycle onto the Jira AII board ("AI Initiatives", board 489) and to make adhoc Jira edits. GitHub stays the source of truth; the AII ticket is a status mirror, cross-linked to the GH issue and assigned to you. Invoked automatically by feature-worktree-workflow at Phase A/C/D, and directly for adhoc work. Triggers — "create a story/bug in AII", "make a jira ticket for this", "link GH #123 to AII-456", "move AII-456 to <status>", "update AII-456 description", "show my AII tickets", "skip Jira for this issue / track it in GitHub only", or any "sync jira" step from the feature workflow.
---

# Jira Sync (AII board)

Mirror a GitHub issue's lifecycle onto the Jira **AII** board and serve adhoc Jira
edits. **GitHub is primary** — the GH issue is the unit of work; the AII ticket is a
mirror whose status is driven by the GH lifecycle. All Jira work goes through the
connected **Atlassian MCP** tools (no scripts, no tokens).

## Constants (use these verbatim)

| Thing | Value |
|---|---|
| `cloudId` | `933ff754-55b2-407d-a906-242eae0b78b7` (or pass `mmelectrical.atlassian.net`) |
| `projectKey` | `AII` |
| Board | 489 · `https://mmelectrical.atlassian.net/jira/software/projects/AII/boards/489` |
| Assignee (`assignee_account_id`) | `712020:9e1ddbc5-33e0-44ed-b104-753d72974654` (Muzza Khan) |
| Issue types | `Story`, `Bug`, `Task` (pass as `issueTypeName`) |
| Sprint field | `customfield_10022` — set to the **numeric** active-sprint id (e.g. `6353`), resolved at runtime (never hardcode the id) |

**AII statuses:** `New → To Do → In Analysis → In Progress → Code Review / Testing → Ready for UAT → Done`

**Status mapping (GH lifecycle → AII):**

| GH event | AII status |
|---|---|
| Start feature (Phase A) | In Progress |
| PR ready (`gh pr ready`, Phase C) | Code Review / Testing |
| PR merged + teardown (Phase D) | Ready for UAT |
| UAT passes | Done *(manual only — the automated flow never sets Done)* |

## Cross-linking model

- **GH side:** a single line `Jira: AII-123` appended to the GH issue body. This is
  the durable, greppable link used to rediscover the ticket in later phases/sessions.
  Read it with `gh issue view <#> --json body -q .body`.
- **GH-only sentinel:** the line `Jira: none` marks an issue deliberately tracked in
  **GitHub only** — no AII mirror. It occupies the same marker slot, so any operation
  that reads the `Jira:` line treats `none` as "do not mirror": skip the op, never
  backfill a ticket, never re-prompt. Written by the `skip` op.
- **Jira side:** a `GitHub: <issue-url>` line at the **top of the ticket description**
  (the MCP has no create-remote-link verb, so the description is the back-link).
- **Repo label:** every ticket gets a Jira label = the GH repo name (`portal-core`,
  `portal-cga`, `portal-lti`, `portal-qms`, …) so board cards can be filtered by repo.

## Golden rules

1. **Never hardcode transition IDs.** Team-managed workflows differ per issue. Always
   call `getTransitionsForJiraIssue` and match the target **status name**, then use
   that transition's `id` in `transitionJiraIssue`.
2. **Idempotent.** Before creating, resolve the marker — if the GH issue already has
   `Jira: AII-xxx`, reuse it (never create a duplicate). Before transitioning, check
   the current status — if already there, skip.
3. **Never block the GH flow.** In a workflow phase, any Jira/MCP failure prints
   `⚠ Jira sync skipped: <reason>` and continues. Jira is a mirror, not a gate.
4. **Always assign to Muzza — and verify it stuck.** Pass `assignee_account_id` on
   `createJiraIssue`, then check the returned `assignee`. Team-managed create screens can
   silently drop the assignee (leaving it `null`); if so, backfill immediately with
   `editJiraIssue fields: { "assignee": { "accountId": "<id>" } }` and re-confirm.
   (Except adhoc create where the user explicitly says otherwise.)
5. **Always put new tickets on the current sprint.** On every create, resolve the
   active sprint id (recipe below) and set `customfield_10022`. The sprint id changes
   each iteration — resolve it at runtime, never hardcode it. If no sprint is active,
   or the write is rejected, leave it in the backlog and say so (best-effort, never a
   gate).

---

## Resolving the ticket for a GH issue

Given a GH issue number `<#>`:

1. `gh issue view <#> --json number,title,body,labels,url,repository`
2. Look for a `Jira:\s*(AII-\d+)` line in `body`. If found → that's the ticket.
3. If the line is `Jira:\s*none` → the issue is **GH-only**. Skip the operation: for a
   lifecycle op (`review`, `uat`, `status`) print `⚠ Jira sync skipped: issue marked
   GH-only (Jira: none)` and continue; never backfill. (Only a deliberate `link`/`create`
   re-decision overwrites the sentinel.)
4. If not found and the operation needs a ticket (`review`, `uat`, `status`) →
   **backfill**: run the create path below first, then continue.
5. Repo name for the label = the repo the issue belongs to (from
   `gh repo view --json name -q .name`, or the `repository` field / current repo).

### Type mapping (GH → AII issue type)

Pick the first that matches: GH issue *type* field → labels
(`bug`/`defect` → **Bug**; `enhancement`/`feature` → **Story**;
`chore`/`tooling`/`maintenance` → **Task**) → branch prefix (`feat`→Story,
`bug`→Bug, `chore`→Task) → fallback **Story**.

### Create path (find-or-create)

If no marker exists:

1. `createJiraIssue` with:
   - `cloudId`, `projectKey: "AII"`, `issueTypeName` (from mapping), `summary` = GH title
   - `assignee_account_id` = Muzza's id
   - `contentFormat: "markdown"`, `description` = the **standard ticket body**
     (see "Ticket body" below), distilled from the GH issue — **not** a raw copy of
     the GH body.
   - `additional_fields: { "labels": ["<repo-name>"], "customfield_10022": <active-sprint-id> }`
     (resolve `<active-sprint-id>` via the sprint recipe below; omit the field if no
     sprint is active)
2. Note the returned key `AII-xxx`, and **confirm `assignee` is non-null** in the
   response. If it's `null`, backfill:
   `editJiraIssue(cloudId, key, fields: { "assignee": { "accountId": "<Muzza's id>" } })`.
3. Append the marker to the GH issue body (preserve existing body):
   `gh issue edit <#> --body "<existing body>\n\nJira: AII-xxx"`
   (Skip if a `Jira:` line is already present.)

---

## Ticket body (keep it simple)

Jira descriptions are **short and skimmable** — a distilled summary, never a paste of
the GH issue. Use exactly this structure (markdown), in this order, omitting a section
only if it genuinely has nothing to say:

```
GitHub: <issue-url>

## Description
<one paragraph — what this ticket delivers>

## Background
<short — why it's needed / the context, 1–2 sentences>

## Acceptance Criteria
1. <criterion>
2. <criterion>

## Testing notes
<how it's verified — QA steps, test users, what to check>

## Dev notes
<implementation pointers — affected services, gotchas, links>
```

Rules:
- Keep each section tight. Prose stays to a paragraph; ACs are an **ordered list**.
- The `GitHub: <url>` back-link is always the first line (before `## Description`).
- Distil from the GH issue — rewrite into these sections; don't dump the raw body.
- The `update` op rewrites the description in this same structure.

---

## Lifecycle operations (called by feature-worktree-workflow)

Phase A offers the user a **create / link-existing / skip** choice (the workflow prompts;
this skill executes whichever branch):

### `sync start <gh#>` — Phase A (create branch)
Find-or-create the ticket (create path above), then transition it to **In Progress**
(resolve transition by name per Golden Rule 1). Report the AII key + URL.

### link-existing branch — Phase A
Compose two adhoc ops: run **`link <gh#> AII-xxx`** (cross-link marker + `GitHub:` line +
repo label) then **`status AII-xxx In Progress`**. Report the key + URL.

### `skip <gh#>` — Phase A (skip branch)
Record the GH-only sentinel — append `Jira: none` to the GH issue body (idempotent;
`gh issue edit <#> --body "<existing body>\n\nJira: none"`, skip if a `Jira:` line is
already present). No ticket is created or touched. Later lifecycle ops read this and skip.

### `sync review <gh#>` — Phase C (after `gh pr ready`)
Resolve ticket (backfill if missing) → transition to **Code Review / Testing**. Add a
comment with the PR URL via `addCommentToJiraIssue` (e.g. `PR ready: <pr-url>`).

### `sync uat <gh#>` — Phase D (after merge/teardown)
Resolve ticket (backfill if missing) → transition to **Ready for UAT**.

For each: if already in the target status, skip the transition and say so. On any
failure, print `⚠ Jira sync skipped: <reason>` and let the GH workflow continue.

---

## Adhoc operations (direct invocation)

Tickets may be named by AII key **or** by GH issue number (resolve the marker).

- **`create`** — "create a story/bug in AII for X". `createJiraIssue` with the stated
  type (default **Story**), assignee = Muzza, repo label = current repo name if run
  inside a repo (else omit), and the **active sprint** (`customfield_10022`, resolved via
  the sprint recipe). If the user gives `--gh <#>` or names a GH issue, also run the
  linking (marker + `GitHub:` description line). Report key + URL.
- **`link`** — "link GH #123 to AII-456". Add the `Jira: AII-456` marker to GH #123 and
  ensure the ticket description has the `GitHub:` line + repo label. No status change.
- **`status`** — "move AII-456 to <status>" / "start|review|uat|done AII-456". Resolve
  transitions and move to the named status (**Done is allowed here**, unlike the
  automated flow). If the status isn't a reachable transition, list the reachable ones.
- **`update`** — "update AII-456 title/description …". `editJiraIssue` to set `summary`
  and/or `description` (`contentFormat: "markdown"`). Keep the description in the
  standard **Ticket body** structure above. One-shot, on demand.
- **`list`** — "show my AII tickets / what's on my board". `searchJiraIssuesUsingJql`
  with `project = AII AND assignee = currentUser() ORDER BY status`, fields
  `["key","summary","status","issuetype"]`. Present as a short grouped list.

---

## Transition recipe (reuse everywhere)

```
1. getTransitionsForJiraIssue(cloudId, issueIdOrKey)
2. Find the transition whose `.to.name` (or `.name`) equals the target status.
3. transitionJiraIssue(cloudId, issueIdOrKey, transition: { id: <that id> })
4. If no matching transition: report current status + the list of reachable targets.
```

Check current status first with `getJiraIssue(cloudId, key, fields:["status"])` to keep
transitions idempotent.

## Active-sprint recipe (reuse on every create)

The board is a scrum board (board 489) with a rolling active sprint. The sprint **field**
is stable (`customfield_10022`); the sprint **id** changes each iteration, so resolve it
live:

```
1. searchJiraIssuesUsingJql(cloudId,
     jql: "project = AII AND sprint in openSprints() ORDER BY updated DESC",
     fields: ["key"], maxResults: 1)                     → any issue key in the open sprint
2. getJiraIssue(cloudId, <that key>, fields: ["customfield_10022"])
3. From customfield_10022 (an array), take the entry with state == "active" → its `.id`.
4. Set that id (a NUMBER, e.g. 6353) on the new/target issue via
   createJiraIssue additional_fields or editJiraIssue fields: { "customfield_10022": <id> }.
```

If step 1 returns nothing, there is no active sprint — skip the field and note the ticket
landed in the backlog. Any sprint error is best-effort: never block the create.
