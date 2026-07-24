# Jira Sync Skill — Design Spec

**Date:** 2026-07-20
**Author:** Muzza Khan
**Status:** Approved for planning

## Summary

A user-level personal skill, `jira-sync`, that mirrors a GitHub-issue's
development lifecycle onto the Jira **AII** board ("AI Initiatives") and serves
adhoc Jira edits. GitHub remains the source of truth and unit of work; the Jira
ticket is a mirror that tracks status on the board and is cross-linked to the GH
issue.

The skill is instruction-based (prose + guardrails that Claude follows, matching
the existing `feature-worktree-workflow` / `fast-track` skills) and performs all
Jira operations through the connected Atlassian MCP tools — no scripts, tokens,
or new dependencies.

This skill and its design live entirely at user level (`~/.claude/skills/`); no
artifacts are committed to any project repo.

## Goals

- Create AII Stories/Bugs/Tasks for work anchored to a GH issue.
- Cross-link the GH issue and the AII ticket, bidirectionally.
- Drive the AII ticket's status from the GH lifecycle (start → PR ready →
  merge/teardown).
- Support adhoc, direct invocation for one-off creates, links, status moves, and
  content edits.
- Every ticket lands on board 489 and is assigned to Muzza Khan.

## Non-Goals (YAGNI — explicitly scoped out)

- Epic / GH-milestone mirroring (tickets stay flat on the board).
- Continuous two-way content sync (content is copied on create and edited only on
  demand).
- Git/`gh` hooks for auto-firing (the workflow skills invoke it instead).
- Worklog / time tracking.

## Environment Constants (baked into the skill)

| Constant | Value |
|---|---|
| Cloud / site | `mmelectrical.atlassian.net` |
| cloudId | `933ff754-55b2-407d-a906-242eae0b78b7` |
| Project key | `AII` (id `11169`, team-managed / next-gen software) |
| Board | 489 (`https://mmelectrical.atlassian.net/jira/software/projects/AII/boards/489`) |
| Assignee (default) | Muzza Khan — accountId `712020:9e1ddbc5-33e0-44ed-b104-753d72974654` |
| Issue type — Story | id `11000` |
| Issue type — Bug | id `10999` |
| Issue type — Task | id `10998` |

**AII workflow statuses (board columns):**
`New → To Do → In Analysis → In Progress → Code Review / Testing → Ready for UAT → Done`

> Transitions in a team-managed project vary per issue. The skill MUST resolve
> transitions **dynamically at runtime** via `getTransitionsForJiraIssue`,
> matching by target status **name** — never hardcode transition IDs.

## Approach

**Chosen: MCP-driven, instruction-based skill.** The SKILL.md instructs Claude to
call the Atlassian MCP verbs (`createJiraIssue`, `transitionJiraIssue`,
`editJiraIssue`, `addCommentToJiraIssue`, `getTransitionsForJiraIssue`,
`getJiraIssue`, `searchJiraIssuesUsingJql`) with the constants above.

> **Verified constraint:** the Atlassian MCP has **no create-remote-link verb**
> (only `getJiraIssueRemoteIssueLinks`, read-only). The Jira → GitHub back-link is
> therefore carried in the ticket **description** as a `GitHub: <url>` line, not a
> native Jira remote link. `createJiraIssue` accepts `assignee_account_id`, labels
> via `additional_fields.labels`, and a Markdown `description` in a single call.

Rejected alternatives:
- **Script-based (`acli`/REST + API token):** more deterministic but adds token
  management, a new dependency, and drifts from the instruction-based skill idiom.
- **Hybrid:** most moving parts, least benefit.

## GH ↔ Jira relationship

- **GitHub is primary.** The GH issue is the unit of work (branch, worktree, PR).
- **Jira mirrors.** The AII ticket is created when work starts and its status is
  driven by the GH lifecycle.
- **Bidirectional link:**
  - On the **GH issue**: a single machine-readable marker line `Jira: AII-123`
    appended to the issue body (greppable via `gh issue view --json body`).
  - On the **AII ticket**: a `GitHub: <url>` line in the description pointing at the
    GH issue (the MCP has no create-remote-link verb, so the description is the
    back-link mechanism).
- **Rediscovery** across sessions/phases = read the `Jira:` marker from the GH
  issue body.

## Status mapping (lifecycle)

| GH lifecycle event | AII status |
|---|---|
| Issue created (work item exists) | To Do |
| Start feature (worktree/branch, Phase A) | In Progress |
| PR marked ready (`gh pr ready`, Phase C) | Code Review / Testing |
| PR merged + teardown (Phase D) | Ready for UAT |
| UAT passes | Done *(manual only — never set by the automated flow)* |

## Lifecycle operations (invoked by the workflow)

`feature-worktree-workflow` gets a one-line "sync Jira" step added at each phase.
`fast-track` reuses those phases, so it needs no separate wiring.

| Called at | Operation | Behaviour |
|---|---|---|
| Phase A — after GH issue confirmed + assigned | `sync start <gh#>` | Find-or-create the AII ticket (idempotent via marker). On create: type auto-mapped from GH, summary = GH title, description = the standard simple ticket body (`GitHub: <url>` line + Description / Background / ACs / Testing notes / Dev notes — distilled from the GH issue, not a raw copy), assignee = Muzza, **repo label** = the GH repo name (e.g. `portal-core`). Write `Jira: AII-xxx` into the GH issue body. Transition ticket → **In Progress**. |
| Phase C — after `gh pr ready` | `sync review <gh#>` | Resolve ticket from marker → transition to **Code Review / Testing**; add a ticket comment with the PR URL. |
| Phase D — after merge/teardown | `sync uat <gh#>` | Resolve ticket → transition to **Ready for UAT**. |

## Adhoc operations (direct invocation)

All operate on AII with Muzza as assignee. Tickets may be addressed by AII key **or**
by GH issue number (marker resolved).

| Trigger (natural language) | Operation | Behaviour |
|---|---|---|
| "create a story/bug in AII for X" | `create` | Create a ticket directly (type as stated, default Story), repo label applied (see Repo label below). Optional `--gh <#>` also links a GH issue in the same step. Standalone if no GH issue. |
| "link GH #123 to AII-456" | `link` | Cross-link existing GH issue ↔ existing AII ticket (marker + remote link). No status change. |
| "move AII-456 to <status>" / "start/review/uat/done AII-456" | `status` | Transition to any AII status by name (including **Done**, which the automated flow never sets). Resolved at runtime. |
| "update AII-456 title/description …" | `update` | Edit summary and/or description. One-shot, on demand. |
| "what's on my AII board / show my tickets" | `list` | JQL `project = AII AND assignee = currentUser() ORDER BY status`. |

## Details & edge cases

- **Content format / ticket body:** the Jira description is kept **simple** — a
  distilled summary, not a paste of the GH body (which stays verbose on its own side).
  Fixed structure: `GitHub: <url>` back-link line, then `## Description` (one para),
  `## Background` (short), `## Acceptance Criteria` (ordered list), `## Testing notes`,
  `## Dev notes`. The MCP accepts Markdown (`contentFormat: "markdown"`) and converts
  to ADF, so pass Markdown directly.
- **Type mapping precedence:** GH issue *type* field → labels
  (`bug`/`defect` → Bug, `enhancement`/`feature` → Story, `chore`/`tooling` → Task)
  → branch prefix (`feat`/`bug`/`chore`) → fallback **Story**.
- **Assignee:** always set to Muzza's accountId on create. Adhoc `create` may be
  left unassigned only if explicitly requested.
- **Repo label:** on create, apply a Jira label equal to the GH repo name
  (`portal-core`, `portal-cga`, `portal-lti`, `portal-qms`, …), derived from the
  GH repo the issue belongs to. This lets AII board cards be filtered/grouped by
  repo. For adhoc `create` with no linked GH issue, use the current repo's name if
  invoked inside a repo, otherwise omit. The label is idempotent (never duplicated
  on re-run).
- **Idempotency:** re-running any op is safe. Existing marker ⇒ no duplicate
  ticket; already in target status ⇒ skip the transition.
- **Backfill:** if a later phase finds no `Jira:` marker (issue predates the
  skill), create + link the ticket first, then apply the status.
- **Ambiguous resolution:** GH number → no ticket (non-create op) ⇒ backfill.
  AII key that doesn't exist ⇒ report, never create silently. Requested status not
  a reachable transition ⇒ list the reachable ones instead of guessing.
- **Failure isolation:** any Jira error during a workflow phase prints
  `⚠ Jira sync skipped: <reason>` and continues the GH flow. Jira is a mirror,
  never a gate — it must not block a commit, PR, or merge.

## Files

1. **New:** `~/.claude/skills/jira-sync/SKILL.md`
2. **Edit:** `~/.claude/skills/feature-worktree-workflow/SKILL.md` — add the
   one-line Jira sync step to Phases A, C, D and the quick-reference table.
3. `fast-track` — no edit required (reuses those phases).

## Success criteria

- Running the normal feature workflow produces an AII card that moves
  To Do → In Progress → Code Review / Testing → Ready for UAT in lockstep with the
  GH lifecycle, cross-linked both ways, assigned to Muzza, on board 489.
- Re-running any phase never creates a duplicate ticket or errors on an
  already-applied status.
- Adhoc create / link / status / update / list all work from natural-language
  invocation, addressing tickets by AII key or GH number.
- A Jira/MCP outage degrades gracefully — the GH workflow completes with a warning.
