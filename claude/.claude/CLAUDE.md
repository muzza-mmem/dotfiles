# Global working rules

## Never use em dashes

**IMPORTANT:** In all written output - documentation, code comments, commit
messages, PR descriptions, issue text, and any draft message intended for a
third party - **never use a long dash**: no em dash (U+2014) and no en dash
(U+2013). Always use the plain ASCII hyphen-minus (U+002D, the `-` key),
surrounded by spaces when it is acting as a separator.

This applies to text I will read as well as text that leaves the machine. If a
sentence feels like it needs an em dash, either use a spaced hyphen or rewrite
it with a comma, colon, or full stop.

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
