---
name: seed-release-docs
description: Use when filling in or refreshing a release train's release-document pages — RDI, PCD, Rollback & contingency, Post-release & closure — in the Confluence PCRELEASE space, from whatever source the user supplies (a CAB report, design doc, runbook, incident review, Jira issue, GitHub release, or pasted notes). Triggers include "seed the release docs", "fill in the RDI/PCD from this", "source this into the release pages", "put the CAB info into the release pages".
---

# Seed Release Documents

## Overview

Each release train in Confluence space **`PCRELEASE`** has four release-document child pages —
**RDI**, **PCD**, **Rollback & contingency**, **Post-release & closure**. CI creates them as bare
stubs and never writes to them again. This skill fills them in from a source the user provides.

**Core principle:** the source is a *starting point, not a transcript*. Every checkable claim in it
gets verified against the code before it lands on a governance page, every value that isn't in it
gets carried as a visible `TBD` rather than invented, and the content map gets confirmed with the
user before anything is written.

**The source is whatever the user gives you.** A CAB report is only the most common case. Accept a
Confluence page (URL, page ID, or `/wiki/x/` tiny link), a local file, a Jira issue, a GitHub
release / PR / issue, or text pasted straight into the conversation. Never assume it's a CAB report,
and never require one — resolve what you were handed and work from that.

## Fixed coordinates

| Item | Value |
|---|---|
| Cloud site (`cloudId`) | `mmelectrical.atlassian.net` |
| Space key | `PCRELEASE` |
| **Release Register** (train index) | page `3519054129` |
| **_Template: Release** | page `3518103839` |
| Train page | `<TRAIN>` (e.g. `2026R1`) — discover it, don't hardcode |
| The four document pages | `<TRAIN> — RDI` · `— PCD` · `— Rollback & contingency` · `— Post-release & closure` — discover their IDs per train |

Per-service evidence lives on `<TRAIN> — SVC-<KEY>` pages. Those are **CI-owned**; never write to
them from here.

## Ownership boundaries (read before touching anything)

Getting this wrong means either destroying CI output or having your work silently overwritten.

| Region | Owner | Rule |
|---|---|---|
| The four release-document pages | **You** | CI creates them once per train and never touches their contents again. Safe to write in full. |
| Train page → **Release status** table | **CI** | Overwritten whole on every preflight, RC and deploy. **Never hand-edit.** Read it for versions and audit posture. |
| Train page → **Services in this release** table | Human | CI reads it, never writes it. This is the authoritative scope for the train. |
| Train page → everything else (Readiness, Sign-off, schedule) | Human | Editable, but out of scope here unless asked. |
| `<TRAIN> — SVC-<KEY>` pages | **CI** | Read-only from this skill. |
| `_Template: Release` | Human | Hand-edited only; changing it does not retro-fit existing trains. |

## Tooling

Use the **Atlassian MCP** with `contentFormat: "html"`. Read with `markdown` (compact, good for
reasoning), write with `html`, verify read-back with `html`.

- **`acli` is not installed** on this machine. Don't reach for it.
- **Do not use the `confluence` npm CLI** (`scripts/confluence-update`, `scripts/confluence-sync`)
  for these pages. It writes storage-format XHTML; these pages are ADF-backed, and the round-trip
  mangles content.
- HTML comments (`<!-- … -->`) **do not survive** the ADF round-trip. Never use them as markers.

If the user explicitly asks for a CLI, say `acli` is absent and the npm CLI is unsafe for ADF pages,
then recommend the MCP — but honour their decision if they insist.

## Process

### 1. Access check (MANDATORY, first)

1. `mcp__claude_ai_Atlassian__atlassianUserInfo`. If it errors, run
   `mcp__claude_ai_Atlassian__authenticate`, share the URL, then `complete_authentication`.
2. Fetch the train page. A 403/404 means no access — **STOP** and report.

### 2. Resolve the source and the train

Resolve the source into text you can quote. For a Confluence source use `getConfluencePage` with
`contentFormat: "markdown"`; for a tiny link pass the encoded part as `pageId`.

Find the train with CQL, then read the train page for the real scope and versions:

```
searchConfluenceUsingCql: space = PCRELEASE and type = page order by title
```

The train page's **Release documents** table carries the four page IDs. Fetch all four — you need to
know whether they're still bare stubs or already have content worth preserving.

**If a page already has real content, do not silently overwrite it.** Show the user what's there and
ask whether to merge or replace.

### 3. Reconcile source scope against train scope (do not skip)

Source documents lag reality. Compare, explicitly:

- **Services** — is every service in the train's *Services in this release* table covered by the
  source? Is the source covering something the train has dropped?
- **Versions** — do the versions cited in the source match the *Release status* table?
- **Any other drift** — environments, dates, owners, architecture.

**Ask the user how to reconcile any mismatch.** Don't pick silently. Then record the mismatch on the
page in a warning panel with a named follow-up (e.g. an addendum to the source document), because a
governance page that quietly disagrees with its own source is worse than one that flags the gap.

### 4. Verify every checkable claim against the code

**This is the highest-value step and the one most easily skipped.** Source documents assert things
like "all 28 migrations define a `down()`", "five have empty bodies", "that workflow input isn't a
backout mechanism". Check each one in the repo — `~/code/portal-core`, and the sibling domain repos
(`../portal-cga`, `../portal-lti`, `../portal-qms`, …) for domain claims.

Then add a short **Verification record** section listing what you checked and whether it held. If a
claim is *wrong*, say so on the page and tell the user — do not quietly propagate it.

Useful checks:

```bash
# Migration count
ls services/portal-core/src/migrations/*.ts | wc -l

# Migrations with an empty down() — prints non-comment line count per file
cd services/portal-core/src/migrations
for f in *.ts; do
  n=$(awk '/public async down/,0' "$f" | sed -n '2,$p' \
      | awk '{ if ($0 ~ /^  \}/) exit; if ($0 !~ /^[[:space:]]*(\/\/|\/\*|\*|$)/) c++ } END{print c+0}')
  printf "%-3s %s\n" "$n" "$f"
done

# Deploy workflow step order and conditions — check always() / if: guards
grep -nE "^\s+- name:|if: " .github/workflows/deploy-prd.yml

# Config and secret NAMES (never values)
grep -oE "^[A-Z][A-Z0-9_]*=" services/portal-core/.env.example | tr -d '='
```

### 5. Map the source onto the pages, then confirm before writing

Each page has a distinct job:

| Page | Carries |
|---|---|
| **RDI** | Scope + versions, deploy order, pre-deploy gates, the deploy sequence mapped to the *actual* workflow steps, migration detail, downtime/window, post-deploy verification. |
| **PCD** | Topology, schema layout, secret inventory **by name only**, integration config (SSO, proxy, AD, email, Redis, observability), feature-flag state, DNS/certs, dependency posture. |
| **Rollback** | Trigger and abort criteria, the tiers, the ordered revert reality, reversibility caveats, known-wrong-looking controls, residual risks, incident record. |
| **Post-release** | Monitoring phases, verification re-run, source items that a successful deploy does *not* discharge, incident log, retro, closure checklist. |

**Cover only what the source plus your repo verification actually supports.** If the source says
nothing useful for a page, say so and ask — offer a structural scaffold with `TBD`s, or leave the
page alone. Never pad a governance page with invented content.

Present the mapping as a short table, note what you'll leave as `TBD`, and **get confirmation before
the first write.**

### 6. Write

Write each page in one `updateConfluencePage` call with a `versionMessage` naming the source.

Include on every page:
- A provenance panel at the top: `panel-info` linking the source, the date, and a note that repo
  detail was used to supplement it.
- Cross-links to the sibling pages where the reader will actually need them.
- `<span data-type="status" data-color="red">TBD</span>` for every unresolved value.

**ADF nesting rules that will reject or mangle your write:**

| Rule | Consequence |
|---|---|
| Panels cannot contain tables, expands, blockquotes or other panels | Rejected. Put the table *after* the panel. |
| Task/decision items are inline-only | No nested blocks inside `<li data-type="task-item">`. |
| Wrap table cell content in `<p>` | Otherwise spacing and macros render badly. |
| Never invent opaque IDs | Omit `data-local-id` on new nodes; only copy IDs from fetched content. |
| Escape `&` as `&amp;` | Including in page titles like `Rollback &amp; contingency`. |

Useful HTML+: `<div data-type="panel-info|panel-note|panel-success|panel-warning|panel-error">`,
`<span data-type="status" data-color="red|yellow|green|blue|neutral|purple">`,
`<ul data-type="task-list"><li data-type="task-item"><input type="checkbox"> …</li></ul>`,
`<time datetime="YYYY-MM-DD">`.

### 7. Verify and report

Read at least one page back with `contentFormat: "html"` and confirm panels, status macros, task
lists and tables survived. **A markdown read-back flattens panels, so it cannot prove they
rendered** — use `html` for this check.

Report: page URLs and versions, what you verified against the code and whether it held, anything the
source got wrong, the reconciliation decisions, and the full list of remaining `TBD`s so the user
knows exactly what's still owed.

## Rules

- **Never invent a value.** Windows, owners, on-call names, timeouts, dates, hostnames, flag state —
  if it isn't in the source, it's a `TBD` status marker.
- **Secret names only, never values**, on the PCD or anywhere else. Reference the retrieval command
  instead.
- **Never hand-edit the CI-owned Release status table** or the `SVC-<KEY>` evidence pages.
- **Verify before you transcribe.** An unverified claim copied onto a governance page inherits false
  authority from the page.
- **Confirm the content map before writing**, and confirm again before overwriting any page that
  already has content.
- **Don't assume the source is a CAB report** and don't require one.
- **Don't pad.** A page with three honest sections beats one with ten invented ones.
- Flag governance actions you cannot perform (source addenda, sign-offs, approvals) rather than
  implying the documentation discharged them.

## Common mistakes

| Mistake | Fix |
|---|---|
| Transcribing the source verbatim | Verify its checkable claims; add a Verification record. |
| Filling a gap with a plausible value | `TBD` status marker. Always. |
| Silently resolving source-vs-train drift | Ask, then record the mismatch in a warning panel with an owner. |
| Editing the Release status table | It's CI-owned and overwritten on every deploy. |
| Using the `confluence` npm CLI, or `acli` | Storage-format writes mangle ADF; `acli` isn't installed. Use the MCP. |
| Putting a table inside a panel | ADF rejects it. Panel, then table. |
| Confirming render via markdown read-back | Markdown flattens panels. Read back as `html`. |
| Writing all four pages when the source only supports two | Say what isn't supported and ask. |
