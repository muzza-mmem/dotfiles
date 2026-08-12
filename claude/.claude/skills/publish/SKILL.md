---
name: publish
description: Use when the user runs /publish or asks to publish, post, or send output to md-mcp / the markdown viewer - "/publish", "publish that", "publish this to md-mcp", "put that in the viewer", "publish docs/foo.md". With no argument it publishes the previous output chunk from the conversation.
---

# publish - send markdown to the md-mcp viewer

Publish markdown as a page in the local md-mcp browser viewer
(http://127.0.0.1:4141) using the `mcp__md-mcp__publish` tool.

## Resolving what to publish

1. **No argument (the default):** publish the **previous output chunk** - the
   last substantive assistant response in the conversation before the /publish
   invocation (the analysis, summary, table, or report just produced). Publish
   it verbatim as markdown; do not rewrite, trim, or summarize it. Skip only
   pure tool-call narration lines ("Let me check...") if they were separate
   from the substantive content.
2. **A file path argument** (e.g. `/publish docs/foo.md`): read the file and
   publish its contents verbatim.
3. **Any other argument** ("publish the test results"): publish the matching
   content from the conversation.

If the resolved content is not already markdown (raw command output, a diff),
wrap it in an appropriate fenced code block rather than reformatting it.

## Publishing

Call `mcp__md-mcp__publish` with:

- `markdown` (required): the content.
- `title`: a short sidebar label. If the content has no leading `#` heading,
  set one; otherwise the first heading is used automatically.
- `key`: only when **updating** a page published earlier in the session - pass
  the same key to replace it in place. Otherwise omit it so a new page is
  appended. When publishing something likely to be revised (a draft, a status
  report being iterated on), set a stable slug key up front (e.g.
  `deploy-status`) so later /publish calls can update it.

The viewer supports GFM tables, task lists, syntax-highlighted code fences,
and mermaid diagrams in ```mermaid fences.

## After publishing

Confirm briefly with the page title and the viewer URL
(http://127.0.0.1:4141). If the tool call fails because the server is not
running, say so and ask the user to start md-mcp; do not retry blindly.

## Common mistakes

- Rewriting or summarizing the previous output instead of publishing it as-is.
- Publishing your *confirmation message* recursively on a follow-up /publish.
- Passing a `key` on a first publish "just in case" a page with that key from
  an earlier session might exist - keys are per-session; omit unless updating.
