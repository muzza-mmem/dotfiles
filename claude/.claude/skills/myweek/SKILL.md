---
name: myweek
description: Use when the user runs /myweek or asks for a summary/recap of the work, PRs, or shipping they did this week (or a given week) across the portal repos (core, qms, cga, lti) — produces a brief themed weekly summary from merged/closed PRs.
---

# My Week

## Overview

Summarise the work the current user shipped this week across the portal repos by
reading their merged/closed PRs and grouping them into brief themed bullets
(e.g. "stabilised core/cga/lti/qms release", "cleared dependency-security advisories").

Repos covered: `portal-core`, `portal-qms`, `portal-cga`, `portal-lti` (org taken
from the current repo's `origin` remote — default `mmem`).

## Steps

1. **Resolve identity, org, and week window** in one batch:
   ```bash
   gh api user --jq .login                        # GitHub username
   git remote get-url origin                      # org is the path segment before the repo
   date +%u                                        # ISO weekday (1=Mon..7=Sun)
   date +%Y-%m-%d                                  # today
   ```
   - Week start = Monday of the current week: `date -d "-$(( $(date +%u) - 1 )) days" +%Y-%m-%d`.
   - If the user names a week/date range, honour that instead of the current week.

2. **List merged/closed PRs per repo** authored by the user, closed since the week start:
   ```bash
   for repo in portal-core portal-qms portal-cga portal-lti; do
     echo "===== $repo ====="
     gh pr list --repo <org>/$repo --author <username> --state closed \
       --search "closed:>=<week-start>" \
       --json number,title,mergedAt,state \
       --template '{{range .}}#{{.number}} [{{.state}}] {{.title}}{{"\n"}}{{end}}'
   done
   ```
   Ignore `[CLOSED]` PRs that were never merged (superseded/duplicate) unless the
   user asks for everything.

3. **Group into themes, not a PR-by-PR list.** Read the titles, cluster by the
   underlying work (release/CI, security/deps, features per domain, docs, infra),
   and write ONE brief bullet per theme. Lead with the outcome, e.g.
   "Shipped trunk-based build-once release across all four repos", not the PR
   numbers.

## Output shape

- A one-line header: week range + total merged PRs across the repos.
- 5–10 brief bullets, each a distinct theme, outcome-first.
- Keep each bullet to one line. No PR dumps, no narration of the process.

## Common mistakes

- **Listing every PR** instead of grouping — the value is the themed recap.
- **Hardcoding org/username/week** — always resolve them at run time.
- **Counting unmerged `[CLOSED]` PRs** as delivered work.
- **Using `--author @me`** with `gh pr list` — pass the resolved login; `@me` is
  unreliable across repos in some `gh` versions. The search field `closed:>=DATE`
  needs the `--search` flag, not `--state` alone.
