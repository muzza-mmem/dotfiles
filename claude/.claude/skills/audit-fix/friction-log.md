# Audit-fix friction log

The audit-fix skill's living knowledge base. **Read the "Known traps" summary
before every run** (Phase 0). When you hit a NEW trap, append a dated entry under
"Detailed log" and add its one-liner here. Tag repo-specific quirks with the repo.

Seeded 2026-07-09 from `~/code/audit-tools/docs/2026-07-08-audit-fix-hurdles.md`.

> **Base-branch note (2026-08-14).** Entries below were written when `main` was the base
> branch everywhere, so they say `origin/main` throughout. Read every one of those as
> **`origin/$BASE`** - the repo's base branch, which is `develop` in the migrated repos
> (portal-core, portal-qms) and still `main` elsewhere. The commands are otherwise
> unchanged. Historical entries are left verbatim as a record; **never check out or pull
> `main` on a dev machine** when applying them.

## Known traps (read first)

- **[portal-core] Overrides are a no-op against an existing lockfile** — adding a
  root `override` + `npm install` does NOTHING for an already-locked node. Use
  `audit-helpers.sh override <dir> <lock-path>` (surgical re-resolve). (#1)
- **[portal-qms] The `override` helper's full re-resolve can DEMOTE a prod
  transitive to dev-only nested copies and DROP the hoisted prod node** — for
  postcss (next hard-pins `postcss: 8.4.31`, prod; frontend has its own dev
  `postcss: ^8.5.10`), `del(node)+npm install` under the override scattered postcss
  to dev-only `frontend/`+`vite/` copies and left `node_modules/next` with NO
  reachable postcss (a leak from the parent worktree's node_modules masked it at
  runtime). Result: broken/incomplete lock that differs from main's topology. Fix:
  when only ONE root node is vulnerable and the patched version already exists
  elsewhere in the lock, do a **surgical in-place bump** of that node
  (version/resolved/integrity + dep ranges via a targeted text Edit), keep its
  dev/prod flag, then `npm ci` to reify. `npm ls` "invalid: <exact> from <parent>"
  is the EXPECTED override artifact (same as the exceljs-uuid case), not an error. (#29)
- **[portal-qms] Worktree nested UNDER a main root that HAS its own node_modules
  leaks into resolution** — `require.resolve` from the worktree walks up to
  `<main-root>/node_modules`, masking a missing/wrong node in the worktree. To PROVE
  a node is correctly placed, `mv <main-root>/node_modules aside` (restore straight
  after) and re-test in isolation, or just validate via `npm ci`. (#29)
- **`override` helper's guard mis-fires on SCOPED packages** — it checks
  `basename <lock-path>`, so `@azure/msal-node` reads as `msal-node` and dies "no
  root override" though the scoped key exists; pass `--force` (verify the override
  is really there first). (#23)
- **[portal-core] After a conflict re-resolve, on-disk `node_modules` drifts from
  the lock → pr-checks fails SPURIOUSLY** — surgical `jq del`+re-resolve and
  `generate-lockfiles` fix the *lock* but leave `node_modules` incomplete (vitest/
  prettier missing), so pr-checks reports fake TS/prettier/tests failures (prettier
  even fetches a WRONG version via `npx`). Fix: a plain `npm install` (syncs
  `node_modules` to the lock, lock stays byte-identical) BEFORE pr-checks. (#24)
- **Merging our nested override with main's flat version override on the SAME key**
  — main bumped `@azure/msal-node` via a flat `"^5.4.0"`; ours pinned its child via
  `{ "uuid": "^14.0.1" }`. Union with npm's combined form:
  `"@azure/msal-node": { ".": "^5.4.0", "uuid": "^14.0.1" }` (`"."` = the package's
  own version, keys = child overrides). (#24)
- **Resolving conflicts on a stale audit PR** — never trust git's line-merge of
  giant lockfiles. Per file: reset root lock to `origin/main` + `npm install`
  (direct-dep bumps ride in free; re-apply overrides surgically), regenerate any
  standalone lock main also touched, keep untouched locks as-is. (#23)
- **[portal-core] Never `rm -rf node_modules/@nestjs/platform-express/multer` — it
  is the package's OWN bundled `./multer` submodule, not a stray dupe.**
  platform-express@11's `index.js` does `require("./multer")` (alongside
  `./adapters`, `./interfaces`); the npm multer *package* lives separately at
  `.../platform-express/node_modules/multer`. Deleting the source submodule breaks
  the build with `Cannot find module './multer'`, and a plain `npm install` does
  NOT restore it (lock entry unchanged → no re-extract). Fix: `rm -rf` the WHOLE
  `node_modules/@nestjs/platform-express` dir + `npm install` to re-extract. (#25)
- **A parent bump won't fix an exactly-pinned transitive dep** — e.g. every
  `next@16.x` pins `postcss` exactly; needs an override, not just a bump. (#2)
- **[portal-core] Standalone per-service locks don't inherit root overrides** —
  `portal-core`, `lti-backend`, `portal-migration-runner` keep their own Docker
  `npm ci` lock (`generate-lockfiles` uses `--prefix`, which ignores root
  overrides). Check / regenerate each independently. (#8)
- **[portal-core] Private-registry auth is a prerequisite** — the `@mmem` scope
  needs a GitHub Packages token (`NODE_AUTH_TOKEN` env, or a literal PAT in
  `~/.npmrc`) or `npm install` fails. Prefer the env token; rotate any echoed PAT. (#4)
- **A Next frontend build needs workspace packages built first** —
  `npm run build:packages` before `next build`, or `@mmem/*` deps won't resolve. (#5)
- **First push must set upstream** — a `--no-track` branch has no upstream;
  use `./scripts/safe-push -u origin HEAD:<branch>` on the FIRST push. (#6)
- **[portal-core] pre-push hook re-runs pr-checks** — expect the extra minute; the
  suite can run up to 3× per push cycle. (#7)
- **[workspace] Run a boot/verification harness from INSIDE the service dir** — a
  workspace dep that npm nests under `services/<svc>/node_modules` (not hoisted to
  the worktree root) is invisible to a `require()` at the worktree root, which then
  escapes UP into the MAIN checkout's stale `node_modules` and tests the OLD version.
  Put the harness in `services/<svc>/` (the real Docker `npm ci` resolution root). (#9)
- **A major bump of a large subtree makes a huge git lock diff that is NOT unrelated
  churn** — don't trust `git diff --numstat` as the "scoped" signal for big-subtree
  bumps (OpenTelemetry ≈ 120 pkgs → ~12k lines). Verify SEMANTICALLY: parse both
  locks' `.packages` and compare added/removed/version-changed keys (order-independent). (#10)
- **[portal-core] `npm install` reconciles local workspace versions into the root
  lock** — a no-op install bumps a few `packages/*` versions (pre-existing
  lock-vs-workspace drift on main). These lines ride along in every audit PR; note
  them in the PR body, don't fight them. (#11)
- **[qms] A bare-version override on a package that's ALSO a direct dep →
  `EOVERRIDE`** — the standalone `frontend` lock needs its own override (root
  overrides don't reach it, #8/#12), but `frontend` has `postcss` as a *direct*
  devDep, so `overrides.postcss: ">=8.5.10"` errors `EOVERRIDE ... conflicts with
  direct dependency`. Use the reference form `overrides.postcss: "$postcss"`
  (pins the transitive copy to the direct dep's resolution). The ROOT lock had no
  direct postcss, so a bare version override worked there. (#13)
- **[portal-core] A root FLAT override does NOT reach a transitive dep nested under
  a WORKSPACE member's subtree** — `overrides.uuid` cleared `typeorm`/`packages/*`
  copies but NOT `@azure/msal-node`'s uuid (msal-node is a dep of the
  `services/portal-core` workspace). Add a TARGETED per-parent override
  (`overrides: { "@azure/msal-node": { "uuid": "^14" } }`) AND surgically re-resolve
  just those lock nodes (#1). For the standalone Docker lock, put the SAME overrides
  in the SERVICE's own package.json — `generate-lockfiles` runs `npm install --prefix`,
  so the service file is the override root there (#8). (#14)
- **A surgical re-resolve re-installs the node's whole PARENT subtree and can nest
  a NEW vulnerable sibling** — re-resolving `platform-express/.../multer` un-deduped
  `path-to-regexp@8.3.0` under platform-express (fresh advisory, latent flat override
  doesn't reach it). ALWAYS re-run `diff` after a re-resolve; delete any newly-ADDED
  advisory node too. And `generate-lockfiles` is a NO-OP for a TARGETED override on an
  already-locked nested node (#1) — `jq del` that entry from the service lock FIRST,
  then regenerate. Targeted (nested-key) overrides also sidestep the #13 `EOVERRIDE`. (#15)
- **[qms] In the ROOT WORKSPACE, the friction-#1 surgical re-resolve is itself a
  NO-OP for a NESTED (per-parent) override on a hoisted node** — `jq del` the node
  + `npm install`/`--package-lock-only`/`npm update <pkg>` all just PRUNE it and never
  re-add the overridden version (npm's incremental resolver honours the pkg's declared
  range, ignoring the override; only a full `rm lock` from-scratch applies it — but that
  re-hoists the ENTIRE tree, 868 add/1087 rm, unshippable). Two fixes by node position:
  (a) a ROOT-HOISTED copy with a single consumer → **hand-edit the lock node in place**
  (swap version/resolved/integrity/bin for the patched node, copied from a throwaway
  from-scratch lock which carries the fully-formed entry); (b) a NESTED copy where the
  patched version ALREADY exists at the (service) root → `jq del` the nested node in an
  isolated temp dir (service as root) + `--package-lock-only` → it dedupes UP to the
  root copy (this variant DOES work incrementally — it's a dedupe, not a fresh override
  resolve). Validate EITHER with `npm ci` (exit 0 = lock is CI-consistent). (#16)
- **[qms] A `migration-runner`-only PR triggers ZERO CI gates** — `migration-runner`
  is a FULLY STANDALONE package (NOT a root workspace member; root = backend/frontend/e2e)
  with its own package.json + lock + node_modules, and it appears in NO workflow. QMS
  `pr-checks` jobs are path-filtered to `backend/**`/`frontend/**`, so a migration-runner-only
  diff runs no CI. "pr-checks green" is vacuous — verify by hand INSIDE `migration-runner/`
  (`npm ci` exit 0 + `npx tsc --noEmit` exit 0 + a runtime API smoke), never symlink its
  node_modules, and audit it independently (`audit-helpers.sh baseline migration-runner`). (#17)
- **[qms] An esbuild advisory pinned by vite can clear via a vite PATCH bump, no
  vite 8** — vite `7.3.6` widened its esbuild range from `^0.27.0` to
  `^0.27.0 || ^0.28.0`, so `npm update vite esbuild` resolves esbuild to the patched
  `0.28.1` on vite 7. ALWAYS check `npm view vite@<latest-7.x> dependencies.esbuild`
  before reaching for a vite major. (#18)
- **[qms] Do NOT take vite to 8 for QMS test tooling** — vite 8 swaps rollup for
  **rolldown**, which removes `@rollup/pluginutils`; `unplugin-swc` (the backend
  vitest transform) hard-depends on it → backend config load fails → backend
  unit-test CI gate breaks. Vite 8 also pulls rolldown+lightningcss (~6k-line lock)
  and needs a `@vitejs/plugin-react` 4→6 major. Stay on vite 7. (#19)
- **[qms] The friction-#16 delete+`npm install` no-op ALSO hits a TRANSITIVE
  version bump (vite/esbuild) in the ROOT workspace** — deleting `node_modules/vite`
  (+esbuild+@esbuild/*) then `npm install` PRUNES them and re-adds nothing ("removed
  N packages"). For a transitive VERSION bump use `npm update <pkg> …` (explicit
  highest-in-range re-resolve), which works where the surgical delete doesn't. (#20)
- **[qms] vitest 4 removed `environmentMatchGlobs`** → the frontend TYPE-CHECK gate
  fails (`'environmentMatchGlobs' does not exist in type 'InlineConfig'`). Migrate to
  `test.projects` (one project per environment: node for lib/hooks, jsdom for
  components/app; `extends: true` inherits root plugins/coverage). Config-only, no
  test-file edits — but still a CONSENTED test-config change (repo/global TDD rule). (#21)
- **[qms] Standalone-lock regen for a vitest MAJOR (2→4) needs the vite subtree
  DROPPED from the seed first** — a plain `npm install --package-lock-only` seeded
  with the old lock bumps vitest 2→4 but leaves vite at 5 (impossible: vitest 4 needs
  vite ^6+), yielding a broken lock that still `npm ci`s. `jq del` all
  vite/vitest/@vitest/esbuild/@esbuild nodes from the seed, THEN regen. Also: the
  backend standalone lock has NO `@vitejs/plugin-react` cap, so it jumps vite→8 on
  regen — pin `overrides.vite: "^7.0.0"` in `backend/package.json` (workspace-member
  override, ignored by root, honoured by the `--prefix` standalone regen) to hold
  it on vite 7 and match the workspace. (#22)
- **[portal-core] `npm audit fix` surfaces TRANSIENT advisories between passes** —
  run it to a fixed point (repeat until the total stops dropping); check any scary
  new package name against the saved baseline file before treating it as a
  regression. (#26)
- **"fixAvailable=true" ≠ non-breaking** — the only patched version may sit OUTSIDE
  the parent's declared range (e.g. esbuild 0.28.1 vs `tsup`'s `^0.27.0`). Check
  `jq '.dependencies.<dep>' node_modules/<parent>/package.json`; if the fix doesn't
  satisfy the parent, defer it as its own issue rather than forcing an override. (#27)
- **[portal-core] FORCING an out-of-parent-range override (the #27 case, once the
  deferral is overruled): the `override` helper PRUNES, doesn't upgrade** — `esbuild
  ^0.28.1` vs tsup's `^0.27.0`: `jq del` + `npm install` (the helper) silently DROPS
  the esbuild node, leaving tsup with an unmet edge — a broken lock that `npm ci
  --dry-run` still "passes" (it doesn't validate transitive completeness). Fix =
  friction-#16 option (a) hand-splice: generate a throwaway from-scratch lock
  (`{dependencies:{esbuild:"^0.28.1"}}` + `npm install --package-lock-only`), then
  targeted-`jq` the REAL node's `version`/`resolved`/`integrity` + bump its
  `optionalDependencies` values to the new version (match the lock's convention —
  portal-core's root lock carries esbuild's optionalDeps LIST but NO separate
  `@esbuild/*` nodes, so don't add 26). A HAND-SPLICED node is STABLE under both
  `npm ci` AND `npm install` (neither re-prunes — the node already satisfies the
  override), unlike the delete+install path. Verify functionally: `npm run
  build:packages` (tsup) exit 0. (#28)
- **[portal-core] `cd services/<svc> && npm audit` audits the ROOT WORKSPACE tree,
  NOT the standalone Docker lock** — a workspace member walks UP to the root
  `package-lock.json`, so that command re-reports the ROOT's advisories. #683's
  "standalone locks each hold the esbuild low" was this artifact (all three rows were
  really the root audit). To audit a standalone lock for real, copy `package.json` +
  `package-lock.json` + `.npmrc` to an isolated temp dir (no parent workspace) and
  `npm audit --package-lock-only` there. esbuild was ABSENT from both standalone locks
  (only an optional peer of vitest's transitive vite@8) → no standalone change needed;
  the advisory lived ONLY in the root workspace lock. (#29)
- **[portal-cga] A whole OTel exporter cluster shows `fixAvailable:true` but
  `npm audit fix` leaves it — it belongs to the SDK-MAJOR issue, not the non-breaking
  bundle.** The advisory is on `@opentelemetry/core` (W3C-Baggage DoS, `<=2.7.1`); the
  exporters/propagators (zipkin, propagator-b3, sdk-trace-base, *-otlp-grpc/proto…) are
  flagged only for *depending* on vulnerable core and npm marks them `fixAvailable:true`.
  But `instrumentation-http@0.213` HARD-PINS `core@2.6` nested, and moving the exporters
  violates `sdk-node@0.213`'s ranges → npm only offers them under `--force` (→ `sdk-node
  0.220` major). Non-breaking `audit fix` bumps top-level core 2.7→2.9 (clears nothing on
  its own, harmless skew, tests green) and stops. PROVE the fixed point by running
  `npm audit fix` a SECOND time: a no-op (lock unchanged) = everything non-breaking is
  done; the rest is the SDK-major issue's. Don't chase `fixAvailable:true` with an
  override. (#28)
- **[portal-lti] Standalone-per-project repo — NO root workspace / NO root lock.**
  `backend`/`frontend`/`migration-runner` are each fully standalone (own package.json +
  lock + node_modules; the ONE lock is both dev and Docker `npm ci` lock). Remediate
  inside each dir; no root install/overrides. `scripts/sync-standalone-lockfiles --check`
  is the lock gate (also run inside `pr-checks`). Local `pr-checks --full` is stricter
  than CI (adds prettier + tests both projects) yet all green → `safe-push` needs NO
  `--no-verify` (unlike qms). (#29)
- **[portal-lti] Carve OTel out with targeted `npm update <in-range names>`, NOT
  `npm audit fix`.** Naming only the in-scope packages clears them lock-only with ZERO
  OTel churn (40→30), sidestepping the #28 trap where `audit fix` bumps OTel core for no
  gain. Prefer explicit `npm update <targets>` whenever a breaking cluster is its own
  issue. Frontend `$postcss` override + surgical re-resolve works identically to #13. (#29)
- **[multi-project] `audit-helpers.sh` baseline collides across projects** — it keys the
  state file by repo+branch only, so a 2nd project's baseline OVERWRITES the 1st. Run each
  with its own `AUDIT_FIX_STATE_DIR=$HOME/.cache/audit-fix/<proj>`. (#29)
- **jspdf 2.x→4.x is a near-drop-in for image-based use, but PNG decoding is now STRICT** —
  jspdf 4 replaced its bundled PNG handling with the `fast-png` dep, which throws
  `CRC mismatch for chunk IDAT` on a malformed PNG (2.x silently tolerated it). App code
  feeding browser `canvas.toDataURL('image/png')` is unaffected (valid CRCs); only bites a
  hand-crafted test fixture — encode smoke-test PNGs via `fast-png`'s own `encode()` for a
  guaranteed-valid checksum. All the image-mode APIs (constructor `('p','mm','a4')`,
  `addPage`/`addImage(data,'PNG',x,y,w,h)`/`text(str,x,y,{align})`/`setFontSize`/`setTextColor`/
  `getNumberOfPages`/`setPage`/`save`) and the named `jsPDF` export are unchanged 2→4. (#30)
- **[portal-cga] Root `package-lock.json` is a stale aggregate — NOT a build/CI gate; leave it
  to #59.** Docker builds each service from its OWN lock (`frontend/Dockerfile`:
  `COPY frontend/package.json frontend/package-lock.json` + `npm ci`), and `pr-checks` only
  lints/type-checks/tests the affected service (`npm install` inside `frontend/`). The root lock
  is untouched by both. Scope a per-service audit fix to that SERVICE's lock; don't churn the
  root aggregate (issue #59 owns "decide its fate"). (#30)
- **[portal-core] A "bump X in @mmem/<pkg> + publish" issue may be VERSION-BUMP-ONLY** — the
  package *source* can already be patched (a prior PR bumped the dep) while the last *published*
  release predates it. Diff `npm view @mmem/<pkg>@<ver> dependencies` vs source `package.json`; if
  source is fixed, the only change is `version:` +1 patch so a republish carries it. The vuln is
  NOT in portal-core's own audit (workspace resolves to local source) — "target cleared" = the
  republish will carry the fix; real clearing is post-merge `workflow_dispatch` publish + downstream.
  Don't commit `dist` (CI builds it); don't churn caret-range consumers. (#31)- **[portal-cga] OTel SDK 0.213→0.220 is a clean parent-bump of the THREE 0.2xx direct deps; `tracing.config.ts` uses `require()` so tsc does NOT gate the API — a runtime SDK-boot smoke is mandatory.** Bump `sdk-node`+`auto-instrumentations-node`(0.71→0.78, different line)+`exporter-trace-otlp-http` together; the aligned `@opentelemetry/*` subtree re-resolves onto patched `core@2.9` (nested `core@2.6` from `instrumentation-http@0.213` gone). Standalone-per-project (no root workspace) → remediate inside `backend/`. 29→3 (residuals xlsx/@mmem-portal-file-manager/uuid → #59). This is the `--force`-class fix for the #54/#28 exporter cluster. (#31)

- **[portal-lti] No `update-issue-status` script** (portal-core-only) — skip the In-Progress/Needs-Review status steps, just assign @me. A nested `$directdep` reference override (`exceljs: { uuid: "$uuid" }`) sidesteps #13 EOVERRIDE and DEDUPES up to the existing top-level copy (+0/−10), scoping the fix to one parent. (#31)

- **[portal-core] A "sanity-check"/sign-off milestone issue has no remediation — verify-only, NO worktree/PR.** ff main → `npm audit --json|jq .metadata.vulnerabilities` per lockfile + confirm milestone issues CLOSED, then finalise ON THE ISSUE (evidence comment → tick boxes → `gh issue close`); confirm before the outward close. Run the audit for ground truth — the issue body's stated audit state can be STALE (esbuild #628 was documented as a deferred residual but PR #685 had already fixed it → repo was 0-everywhere). Also confirmed in **portal-qms #335** (4 locks, each standalone audited in isolation per #29; the "accepted" #296 residual had MOVED — 0.2.8 bump resolved it → 0 everywhere; migration-runner hand-verified per #17). (#32)

- **[portal-lti] Before accepting an "upstream-tracked / no fix" residual on OUR OWN `@mmem` package, `npm view <pkg> versions` — a newer PATCH may already fix it.** #61's residual `uuid` (moderate, nested under `@mmem/portal-file-manager@0.2.7` which pinned `uuid: ^9.0.0`, unreachable to the fixed `>=11.1.1`) was documented as upstream-blocked — but `portal-file-manager@0.2.8` (published after the milestone was scoped) had already bumped its own `uuid` to `^14.0.1`. So a clean PARENT BUMP (`^0.2.7 → ^0.2.8` + `npm install` in the standalone `backend/`), not an override, cleared it: nested uuid re-resolved 9.0.1→14.0.1, audit 3→1, diff 11 lines. `npm audit`'s `fixAvailable: true` (vs `false` for the genuinely-unfixable `xlsx`) was the tell — it flips the moment upstream republishes, even if the issue body still says "no fix". A sanity-check verify (#32) is the right moment to re-check this. (#33)

---

## Detailed log

## 1. npm `overrides` are NOT re-applied against an existing lockfile  ⚠️ biggest one

**Symptom.** #575 needs the transitive `postcss` (bundled under `next` as an
*exact* `8.4.31`) forced up to `>=8.5.10`. The documented fix is a root
`overrides` entry. Adding `"postcss": "^8.5.10"` to root `overrides` and running
`npm install` did **nothing** — `node_modules/next/node_modules/postcss` stayed
at `8.4.31` and `npm audit` still flagged it.

**Not a bug in the override itself.** A minimal throwaway project with the same
override works fine. The pre-existing `"path-to-regexp": "8.4.0"` override in
portal-core's root `package.json` is *also* silently not honoured
(`@nestjs/swagger` still resolves `8.4.2`), so this has been latent on `main`.

**Root cause.** `npm install` honours the resolutions already pinned in
`package-lock.json`. It does **not** re-evaluate `overrides` for a node that is
already locked, even after you edit the override, and even after
`rm -rf node_modules` (the lockfile alone is enough to pin it). The override only
bites when npm resolves that node *from scratch*.

Corollary gotcha: `.packages[""].overrides` in the lockfile is `null` on this npm
(11.12.1) whether or not overrides are working — so it is **not** a reliable
signal. Check the actual installed tree / `npm ls`, never the lock's overrides
field.

**Two ways to force it, and why one is bad:**

- ❌ **Full re-resolve** — `rm -rf node_modules package-lock.json && npm install`.
  This *does* apply the override, but it re-dedupes the **entire** tree: for #575
  it churned ~6,380 lock lines across ~200 unrelated packages (webpack, redis,
  vitest/istanbul, rolldown, …). Only ~2 of those lines were next/postcss. That
  is unshippable in a scoped security PR and will collide with the sibling audit
  PRs (#570/#571/#572/#574) that also touch `package-lock.json`.

- ✅ **Surgical re-resolve of just the affected node.** Delete only that node's
  lock entry + its installed dir, then `npm install`:

  ```bash
  # after bumping next and running an in-place `npm install`:
  jq 'del(.packages["node_modules/next/node_modules/postcss"])' \
     package-lock.json > tmp && mv tmp package-lock.json
  rm -rf node_modules/next/node_modules/postcss
  npm install          # re-resolves that one node WITH the override -> 8.5.16, dedupes
  ```

  Result for #575: **127 lock lines changed, one entry removed**
  (`node_modules/next/node_modules/postcss`), advisory cleared, nothing else
  moved. This is the diff you want.

**Suggested tooling improvement.** Consider an `af override <pkg-path>` helper (or
a documented recipe) that does the jq-delete + targeted reinstall, so we don't
hand-roll it each time. At minimum, document this in the README — "adding an
override? you must surgically re-resolve, a plain `npm install` is a no-op."

## 2. Bumping the parent does not fix an exactly-pinned transitive dep

`next@16.2.10` (latest) still declares `"postcss": "8.4.31"` **exactly** — every
16.x does. So "bump next to the patched release" clears next's own 14 advisories
but leaves the postcss advisory untouched. Any advisory that lives in a
transitively *pinned* dep needs an override (see #1), not just a parent bump.
Worth knowing up front so you plan for the override step.

## 3. `af start` output is enormous and hides the useful numbers

The baseline `npm audit` dump for portal-core is ~250 lines (55 advisories, huge
OpenTelemetry tree). The single number you actually want — the vuln count and the
per-severity split — is buried. The baseline JSON is captured at
`~/.cache/audit-fix/<repo>--<branch>.baseline.json`; the fast read is:

```bash
jq -r '.metadata.vulnerabilities' ~/.cache/audit-fix/portal-core--<branch>.baseline.json
```

**Suggested improvement.** Have `af start` / `af check` print the
`.metadata.vulnerabilities` severity breakdown (total/low/moderate/high/critical),
not just npm's free-text tail. `af check` already diffs the *count of vulnerable
packages*; the severity split is more actionable.

## 4. Private registry auth is an undocumented prerequisite

`npm install` needs the `@mmem` scope pointing at GitHub Packages with a token.
On this machine it comes from `~/.npmrc`:

```
@mmem:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}   # repo .npmrc
//npm.pkg.github.com/:_authToken=<PAT>                # ~/.npmrc (literal token)
```

The repo's `.npmrc` expects `NODE_AUTH_TOKEN` in the env; the home `.npmrc` has a
literal PAT. `af start` will fail on install without one of these. The README
lists git/npm/jq/gh as requirements but not registry auth — **add it**.

> ⚠️ Security: the literal PAT in `~/.npmrc` is easy to leak — it prints in plain
> `cat ~/.npmrc` output. Prefer `NODE_AUTH_TOKEN` in the env over a literal token
> on disk, and rotate any token that has been echoed into a terminal/log.

## 5. Verifying a Next frontend build needs the workspace packages built first

`services/portal-shell` depends on `@mmem/portal-ui: "*"` (a workspace package).
A bare `next build` in the service can fail until the packages are built. Use:

```bash
npm run build:packages   # builds all workspaces --if-present (incl. the frontend)
# or explicitly: npm run build -w @mmem/portal-ui  then  npm run build -w services/portal-shell
```

The issue asks to verify "Next dev + production build"; `next build` (production)
exiting 0 with a route table is the signal. Dev server is interactive — skip it
in the isolated flow (matches af's "no running services" bar).

## 6. `af start`'s branch tracks `origin/main` — a bare `git push` is unsafe

`git worktree add -b <name> <dir> origin/main` sets the new branch's upstream to
`origin/main`. Consequences:

- A bare `git push` (and therefore `./scripts/safe-push`, which ends in a bare
  `git push`) is at best refused (`push.default=simple` rejects mismatched
  upstream/branch names) and at worst ambiguous. Push **explicitly** the first
  time:

  ```bash
  git push -u origin <branch>:<branch>
  ```

- `af done`'s pushed-check (`git log origin/<name>..HEAD`) only works *after*
  you've pushed to a same-named remote branch, so the explicit push above also
  satisfies it.

**Suggested improvement.** Have `af start` create the branch with its upstream
unset (or `--no-track`) so the standard `safe-push`/`git push` flow just works,
or print the exact `git push -u origin <branch>` to run.

## 7. portal-core has a git pre-push hook that re-runs pr-checks

Pushing triggers a pre-push hook that runs `./scripts/pr-checks` again ("All
checks passed! Proceeding with push..."). Harmless but adds a minute to the push
and means `af check` + `safe-push` + hook can run the suite three times. Not
worth fixing, just expect the wait.

## 8. Standalone per-service lockfiles + the "newer than lockfile" warning

`pr-checks` warns `<svc> package.json is newer than lockfile - may need
regeneration` and points at `./scripts/generate-lockfiles`. Context:

- `portal-core`, `lti-backend`, `portal-migration-runner` keep **standalone**
  `package-lock.json` files (for Docker `npm ci`); frontends use the root lock.
- These standalone locks are generated with `npm install --prefix <svc>`, which
  **ignores root `overrides`**. So a root override (like #575's postcss) does
  *not* propagate to them — check each service lock independently if the advisory
  could live there. For #575 they already had `postcss@8.5.16` (dev-only), so no
  action.
- The warning is often just an mtime artifact of the worktree checkout (equal
  mtimes still tripped it) — it's a warning, not a failure; `pr-checks` still
  passes. Only run `generate-lockfiles <svc>` if you actually changed that
  service's deps.

## 9. A Phase-B verification harness must run from INSIDE the service directory (#570)

**Symptom.** #570 bumped OpenTelemetry (declared only in `services/portal-core`).
A boot-smoke harness placed at the **worktree root** ran green but printed
`sdk-node 0.213.0` — the OLD version.

**Root cause.** npm nested the otel packages under
`services/portal-core/node_modules/@opentelemetry/*` (they weren't hoisted to the
worktree-root `node_modules`, since only portal-core uses them). Node's
`require()` from a worktree-root script walks UP the tree: worktree-root
`node_modules` (absent) → … → the **MAIN checkout's** `node_modules`
(`/home/…/portal-core/node_modules`, still at the old 0.213). So the harness
silently tested the parent repo's stale install.

**Fix.** Put runtime verification harnesses in `services/<svc>/` and run them
there — that resolves against the service's own `node_modules` (0.220), which is
also the Docker `npm ci` resolution root. Sanity-check with
`node -e "require.resolve('<pkg>/package.json')"` and assert the printed path is
under the **worktree**, not the parent repo. Delete the harness before committing.

## 10. Large-subtree major bumps make a huge git lock diff that is NOT unrelated churn (#570)

**Symptom.** Bumping the OpenTelemetry line produced a ~12,700/13,180-line
`package-lock.json` diff — looks exactly like friction-log-#1's forbidden full
re-resolve.

**Root cause.** The otel subtree is ~120 packages and its version strings appear
throughout every otel package's `dependencies` block, so a legitimate scoped bump
touches thousands of lines. It is NOT unrelated churn.

**Fix / how to tell them apart.** `git diff --numstat` is a **misleading** "scoped"
signal for big-subtree bumps. Verify SEMANTICALLY, order-independent — parse both
locks' `.packages` and diff by key:

```python
import json
base=json.load(open('/tmp/base.json')); cur=json.load(open('package-lock.json'))
bp,cp=base['packages'],cur['packages']; bk,ck=set(bp),set(cp)
added, removed = ck-bk, bk-ck
changed=[k for k in bk&ck if bp[k].get('version')!=cp[k].get('version')]
```

Confirm every added/removed/changed key is in the target subtree (here: 77 added /
109 removed, ALL `@opentelemetry`; 0 unrelated external version changes), and that
common keys keep their relative order. If so, the diff is scoped and shippable
despite the line count — say so explicitly in the PR body.

## 11. `npm install` reconciles local workspace versions into the root lock (#570)

**Symptom.** Even a **no-op** `npm install` (no package.json change) produced a
3-line root-lock diff bumping `packages/auth` 0.3.1→0.4.0,
`packages/portal-file-manager` 0.2.6→0.2.7, `packages/scaffold` 0.25.4→0.25.8.

**Root cause.** The committed root lock's `packages/*` version fields were stale
vs the actual workspace `package.json` versions on `main`; npm rewrites them to
match on every install. Pre-existing drift, unrelated to the advisory.

**Fix.** Leave them — reverting is pointless (the next install re-applies them) and
they reflect reality. Just list them in the PR body as "incidental workspace-version
reconciliations" so the reviewer isn't surprised.


## 13. [portal-qms] `EOVERRIDE` when overriding a package that's also a direct dep (#294, 2026-07-09)

**Symptom.** #294 forces next's pinned `postcss@8.4.31` up to `>=8.5.10` via an
override. The ROOT `package.json` override `"postcss": ">=8.5.10"` worked (postcss
isn't a root direct dep). But the standalone **`frontend`** lock also carries a
`node_modules/next/node_modules/postcss@8.4.31` and needs its own override
(root overrides don't propagate to standalone locks, #8/#12). Adding the same
`"postcss": ">=8.5.10"` to `frontend/package.json` failed:
`npm error code EOVERRIDE — Override for postcss@^8.5.10 conflicts with direct dependency`.

**Root cause.** `frontend` declares `postcss` as a **direct** devDep (`^8.5.10`).
npm refuses a bare-version override whose value could diverge from a same-named
direct dependency.

**Fix.** Use the **reference form** `"overrides": { "postcss": "$postcss" }` — it
pins every transitive `postcss` (incl. next's) to whatever the direct `postcss`
devDep resolves to (8.5.15 here). Regenerate the standalone lock in an isolated
temp dir with the override present + the nested entry deleted (surgical, #1):
```bash
tmp=$SCRATCH/regen-frontend; mkdir -p "$tmp"
cp frontend/package.json frontend/package-lock.json .npmrc "$tmp/"   # package.json already has the $ref override
( cd "$tmp"
  jq 'del(.packages["node_modules/next/node_modules/postcss"])' package-lock.json > pl && mv pl package-lock.json
  npm install --package-lock-only --no-audit --no-fund )
cp "$tmp/package-lock.json" frontend/package-lock.json
```
Then a root `npm install` reconciles the root lock (adding the frontend member
override does NOT churn the root lock or warn). Verified via `next build` (exit 0,
full route table) — postcss 8.5.15 works with next 16.x. Rule of thumb: **root
override → bare version; standalone-service override on a direct dep → `$name`
reference.**

## 12. [portal-qms] Missing portal-core helper scripts; standalone-lock regen; non-gate pr-checks (#290, 2026-07-09)

First audit-fix run in **portal-qms** — several portal-core assumptions don't hold:

- **No `scripts/update-issue-status` and no `scripts/generate-lockfiles`.** Those
  are portal-core-only. In QMS: assign with `gh issue edit <n> --add-assignee @me`;
  status is managed on a project board *if the issue is on one* (`gh issue view`
  shows `projects:` empty → nothing to move — skip it).

- **Standalone Docker locks are workspace MEMBERS, so `cd <svc> && npm install`
  resolves the ROOT workspace, not the service.** QMS root is a workspace
  (`backend`/`frontend`/`e2e`) with a root `package-lock.json`, but each service
  also ships its OWN standalone `package-lock.json` (root name = the service pkg)
  that Docker uses via `npm ci`. Root `npm update` does NOT touch them. Regenerate
  each in an **isolated temp dir** outside the worktree:
  ```bash
  tmp=$SCRATCH/regen-$svc; mkdir -p "$tmp"
  cp $svc/package.json $svc/package-lock.json .npmrc "$tmp/"   # seed with existing lock
  ( cd "$tmp" && npm update <target pkgs> --package-lock-only --no-audit --no-fund )
  cp "$tmp/package-lock.json" $svc/package-lock.json
  ```
  Seed with the existing lock + use `npm update <targets>` (a bare
  `npm install --package-lock-only` against a satisfying lock is a NO-OP; friction #1).

- **`npm audit fix` (no --force) pulls a huge unrelated vitest/vite subtree** —
  ~70 `add` lines of vite-node/tinyspy/chai/etc. Do NOT use it. Surgical
  `npm update @nestjs/platform-express @nestjs/swagger multer protobufjs js-yaml
  form-data` cleared all six in-range advisories with a scoped diff (the big
  root-lock line count is package **relocation**: backend-nested subtrees hoisting
  to root after dedupe — verify semantically, friction #10).

- **`safe-push` aborts on ANY `pr-checks` failure, and QMS `pr-checks` fails
  LOCALLY on non-gates** — Prettier (not a CI gate anywhere) + the frontend vitest
  suite (`@testing-library/jest-dom → vitest` setup breakage, local-only). The
  actual CI gates (`.github/workflows/pr-checks.yml`) are: **backend** lint +
  type-check + unit tests; **frontend** lint + type-check ONLY. Verify those five
  by hand, then push with `git push --no-verify` (safe-push has no skip flag).

- **[qms] next@16.x hard-pins `postcss@8.4.31`** — the frontend's *direct* postcss
  devDep already resolves ≥8.5.10 (8.5.15); the residual `node_modules/postcss@8.4.31`
  flagged by audit is next's copy → out of scope, needs the next/postcss override
  issue. So "postcss cleared" for a non-override issue = the direct devDep is safe,
  NOT that the advisory vanishes from `npm audit`.

## 14. [portal-core] Root flat override doesn't reach a workspace member's transitive dep (#572, 2026-07-09)

**Symptom.** #572 upgraded direct `uuid` to v14, but the advisory GHSA-w5hq-g745-h8pq
(`uuid <11.1.1`) stayed in `npm audit` via transitive copies: `typeorm` (11.1.0),
`@azure/msal-node` (8.3.2, both as portal-core's direct dep and nested under
`@azure/identity`), and the published `@mmem/portal-file-manager` tarball. Adding a
root flat `overrides: { "uuid": "^14.0.1" }` + surgical re-resolve (#1) cleared the
`typeorm` and `packages/*` copies (typeorm re-resolved to the patched 11.1.1 within
its own `^11.1.0` range) but left `@azure/msal-node`'s uuid at 8.3.2.

**Root cause.** `@azure/msal-node` is a dependency of the `services/portal-core`
**workspace member**, not of the monorepo root. A root *flat* override does not
reliably force a transitive dep that lives under a workspace member's subtree (on
npm 11.12.1). Note the flat override didn't even pull typeorm's uuid to 14 — the
11.1.1 there was just natural latest-in-range re-resolution, i.e. the flat override
was effectively inert for the transitive tree.

**Fix.** Add a TARGETED per-parent override alongside the flat one:
```json
"overrides": {
  "uuid": "^14.0.1",
  "@azure/msal-node": { "uuid": "^14.0.1" }
}
```
then surgically re-resolve just the affected lock nodes (delete the
`@azure/{msal-node,identity}/node_modules/uuid` entries + dirs, `npm install`, #1).
msal-node then deduped to the hoisted root uuid@14.0.1. Result: root lock clean, 49→45.

**Standalone Docker lock.** `services/portal-core` ships its own `npm ci` lock and
`generate-lockfiles` runs `npm install --prefix <svc>` — so the SERVICE's package.json
is the override root for that lock (#8). Adding the SAME `overrides` block to
`services/portal-core/package.json` and regenerating cleared the standalone lock too
(there the flat `uuid` override DID apply, since --prefix drops the workspace context).
A non-root workspace member's `overrides` is ignored by the root install, so this is
harmless to the monorepo root resolution.

**uuid v14 is ESM-only** (`"type": "module"`) — but `require('uuid')` works via Node's
require-ESM interop, and prod (`node:20-alpine` ≥20.19) already relies on it because
portal-core ships uuid v11 (also ESM) today. So forcing v14 onto CJS transitive
consumers (typeorm/msal-node, both use only `v4()`) is runtime-safe. Confirmed with a
require-smoke test run from INSIDE `services/portal-core` (#9).

## 15. [portal-core] A surgical re-resolve can NEST a NEW vulnerable sibling; standalone regen is a no-op for an already-locked targeted override (#574, 2026-07-09)

Upgrading `multer` to 2.2.0. Two sub-traps on top of the (repeat) friction-#14
pattern — services/portal-core has a DIRECT `multer` dep AND
`@nestjs/platform-express@11` pins `multer` EXACTLY `2.1.1` transitively, so the
flat root `overrides.multer` reached NEITHER. Fix was the #14 recipe: bump the
workspace member's direct dep (`services/portal-core` multer → `^2.2.0`) + a
TARGETED root override `"@nestjs/platform-express": { "multer": "^2.2.0" }`, then
surgical re-resolve. New bits:

- **A surgical re-resolve of a nested node re-installs that node's whole PARENT
  subtree, and can un-dedupe a sibling into a freshly-nested (vulnerable) copy.**
  Re-resolving `node_modules/@nestjs/platform-express/node_modules/multer`
  re-nested `path-to-regexp@8.3.0` under platform-express (a NEW high advisory,
  count 49→50) — the latently-un-honored flat `path-to-regexp: 8.4.0` override
  (friction #1) does NOT apply to the freshly-nested copy. **After any surgical
  re-resolve, re-run the baseline `diff` and check for newly-ADDED advisory
  modules**; if one appears, delete that nested sibling's lock node too and
  re-resolve it (it then dedupes to the overridden root copy). Cleanest: delete
  ALL offending nested nodes under the parent in one `jq del | del | del`, then a
  single `npm install`, and diff again.

- **`generate-lockfiles` is a no-op for a targeted override on an ALREADY-LOCKED
  nested node** (friction #1 applies — it runs `npm install --prefix
  --package-lock-only`, seeded from the existing lock). Adding
  `overrides: { "@nestjs/platform-express": { "multer": "^2.2.0" } }` to
  `services/portal-core/package.json` did NOT move the standalone lock's
  `platform-express/node_modules/multer@2.1.1`. Had to `jq del` that nested entry
  from `services/portal-core/package-lock.json` FIRST, THEN `generate-lockfiles
  portal-core` (which re-resolved it to dedupe on root 2.2.0). (#14 said a regen
  cleared it — but that was a FLAT override; a targeted override on a locked node
  still needs the surgical delete.)

- **A targeted (nested-key) override sidesteps the friction-#13 `EOVERRIDE`**: the
  service has `multer` as a DIRECT dep, so a bare `overrides.multer` would error,
  but keying the override under `@nestjs/platform-express` (not top-level `multer`)
  avoids the conflict entirely.

- multer 1→2 was runtime-safe: only consumed via NestJS `FileInterceptor` (memory
  storage) reading `file.buffer/mimetype/originalname/size` (unchanged in 2.x), and
  the runtime was ALREADY on 2.1.1 via platform-express. portal-core's own multer
  dep is type-only (`Express.Multer.File`). Bump `@types/multer` → `^2.0.0` alongside.

## 16. [qms] The friction-#1 surgical re-resolve is a NO-OP in the ROOT WORKSPACE for a per-parent override; fix by lock-position (#293, 2026-07-09)

**Context.** #293: `exceljs@4.4.0` pins `uuid@^8.3.0` (root-hoisted `node_modules/uuid@8.3.2`,
GHSA-w5hq-g745-h8pq). Strategy = targeted override `exceljs: { uuid: ">=11.1.1" }`
(scoped so the file-manager `uuid@9.0.1` / #296 and backend's direct `uuid@11.1.0`
stay put). The from-scratch resolve PROVED the override is effective (exceljs → 11.1.1).

**The trap.** Every incremental method to apply that override to the EXISTING root
workspace lock was a NO-OP:
- `audit-helpers.sh override . node_modules/uuid` (jq-del + `npm install`) → PRUNED the
  8.3.2 node and added **nothing** (exceljs left with an unmet uuid edge — a BROKEN lock,
  which superficially "cleared" the advisory because the node vanished).
- `npm install --package-lock-only` (seeded lock, node deleted) → "up to date", no re-add.
- `npm update uuid` (seeded) → no-op (honours exceljs's declared `^8.3.0`, IGNORES the
  override). npm 11.12.1's incremental resolver simply won't re-resolve a pruned node
  against a per-parent override.
- **Not the nested-worktree escape** (#9) — reproduced identically in a fully isolated
  temp dir with no parent `node_modules`.
- Only `rm package-lock.json` + from-scratch applied it — but that re-hoisted the ENTIRE
  tree (868 added / 1087 removed / 169 version drift incl. esbuild downgrades). Unshippable
  (#1's forbidden case).

**Fix — pick by the vulnerable node's position:**
- **(a) Root-hoisted copy, single consumer (the root lock here).** Hand-edit the ONE lock
  node in place: replace `.packages["node_modules/uuid"]` (version/resolved/integrity/bin)
  with the patched 11.1.1 node — copy the fully-formed entry (with `resolved`+`integrity`)
  from the throwaway from-scratch lock (a nested workspace copy like
  `backend/node_modules/uuid` often LACKS resolved/integrity, so don't copy from there).
  First confirm the target is the sole consumer of that hoisted node
  (`jq` the packages for who declares `uuid` in the old range → only exceljs). Diff: +8/-5,
  one node.
- **(b) Nested copy where the patched version already exists at the (service) root (the
  standalone `backend` lock here — `exceljs/node_modules/uuid@8.3.2` with root
  `uuid@11.1.1` present).** `jq del` the nested node in an isolated temp dir (service as
  root, #12) + `npm install --package-lock-only` → exceljs dedupes UP to root 11.1.1.
  This variant DOES work incrementally because it's a dedupe-to-existing, not a fresh
  override resolution. Diff: -10, one node removed.

**Both fixes need the override in the respective `package.json`** (root + standalone
service — root overrides don't reach the standalone lock, #8). Nested-key form
(`exceljs: { uuid }`) sidesteps #13 `EOVERRIDE` since backend has a direct `uuid`.

**Validation.** `npm ci` exit 0 on BOTH locks = they are CI-consistent (the real gate —
a hand-edited lock that npm ci accepts is shippable). Then a functional smoke: exceljs
wrote a workbook through its uuid code path (iconSet conditional-format ext) on uuid 11.1.1.
exceljs uses `const {v4} = require('uuid')` (modern named import) so v11 is compatible.

## 17. [qms] mssql 10→12 in migration-runner: standalone package, zero CI gates, clean bump (#295, 2026-07-10)

**Context.** #295: `mssql@^10.0.2` pins a vulnerable `@azure/identity`/`msal-node`/`tedious`/`uuid`
chain (5 moderate) in `migration-runner`. Strategy = direct major bump (breaking, `--force`-class).

**What made it easy (record so the next mssql-class bump is quick):**
- `migration-runner` is a **fully standalone** package — NOT one of the root workspaces
  (`backend`/`frontend`/`e2e`). Its own package.json + lock + node_modules. So remediate
  ENTIRELY inside `migration-runner/`: bump there, `npm install` there, `audit-helpers.sh
  baseline/diff/check-pkg migration-runner`. Root install/overrides are irrelevant.
- **Zero CI gates** (friction #17 one-liner) — nothing to satisfy in `pr-checks`; verify by hand.
- **`@types/mssql` jumps 9.x → 12.3.0** to match mssql 12 (mssql ships no bundled types).
- **mssql 12's tree is much leaner** than 10 (removed 107 packages / −1749 net lock lines) —
  the whole standalone lock IS the target subtree, so the big diff is inherently scoped
  (no semantic split needed like friction #10 — it's a one-package lock).
- **No source changes.** The migration-runner's `DatabaseService` only touches stable core
  APIs: `sql.connect(config)` (server/port/user/password/database/options/timeouts),
  `pool.request().input()/.query()`, `result.recordset`, `sql.ConnectionPool`,
  `new sql.Transaction(pool).begin()`. Unchanged 10→12 — the breaking surface is tedious
  (16→20) + Node floor, not these. `tsc --noEmit` 0 confirmed it.

**Verification without a DB (no local dev DB reachable, don't boot the stack).** `tsc --noEmit`
0 + `npm ci` 0 + a runtime API-surface smoke placed INSIDE `migration-runner/` (friction #9):
`require('mssql')`, construct `ConnectionPool` with the exact config shape, assert
`request().input/.query`, `new Transaction(pool).begin`, `pool.close` all exist on 12.7.0, and
assert `require.resolve` lands under the worktree (not a stale parent). The live connect/list
went into the QA plan on the ISSUE as the one manual step. Result: 5 moderate → 0, scoped diff.

## 18. [qms] vitest 2→4 (+vite/esbuild): clear esbuild on vite 7, NEVER vite 8 (#292, 2026-07-10)

**Context.** #292: `vitest`/`@vitest/coverage-v8` `2.1.9`→`4.1.10` (critical
GHSA-5xrq-8626-4rwp, backend+frontend devDeps) + the transitive vite/esbuild chain.
Baseline root = 8 (2 crit / 1 high / 5 mod). Ended 8→2 (the 2 residual = `@mmem/portal-file-manager`
#296 + `uuid` #293, both out of scope). Backend 722 unit tests pass on vitest 4.

**The core win — clear the pinned esbuild advisory with a vite PATCH, not a major.**
The plain vitest bump left ONE residual: `esbuild` low (GHSA-g7r4-m6w7-qqqr, patched
≥0.28.1). vite `7.3.5` pins `esbuild: ^0.27.0` (excludes 0.28.1). The instinct is
"needs vite 8" — WRONG. vite **7.3.6** (a patch) widened it to `^0.27.0 || ^0.28.0`,
so `npm update vite esbuild` → vite 7.3.6 + esbuild 0.28.1, advisory cleared, on vite 7.
**Before assuming a transitively-pinned advisory needs a parent MAJOR, check the latest
PATCH of the current major**: `npm view vite@^7 version` + `npm view vite@<that> dependencies.<dep>`.

**Why vite 8 is a trap here (chased it, reverted).** Reaching vite 8 required
`@vitejs/plugin-react` 4→6 (peer vite ^8) + a forced vite-subtree re-resolve. Then:
(a) vite 8 replaces rollup with **rolldown**, dropping `@rollup/pluginutils`, which
`unplugin-swc` (backend vitest transform) hard-requires → `failed to load config …
Cannot find module '@rollup/pluginutils'` → the **backend unit-test CI gate breaks**;
(b) the manual subtree surgery produced a subtly-BROKEN lock (missing that dep) that
`npm ci --dry-run` still "passed" (it replays whatever the lock lists — it does NOT
validate transitive completeness); (c) vite 8 pulls rolldown+lightningcss native
binaries (~6k-line lock). A fresh from-scratch vite-8 resolve IS complete but churns
the whole tree (unshippable, #1/#16). Net: vite 8 = fragile + huge + breaks tests,
all for a CVSS-2.5 Windows-only dev-server advisory. Not worth it — vite 7.3.6 wins.

**The mechanic that actually applies a transitive version bump (#20).** The friction-#16
"delete the lock node + `npm install`" no-op ALSO bites a transitive VERSION bump in the
root workspace: deleting `node_modules/vite`+`esbuild`+`@esbuild/*` then `npm install`
just PRUNES them ("removed N packages", vite=null) — npm won't re-resolve-up a pruned
transitive against a widened range. `npm update vite esbuild` DOES it (explicit
highest-in-range), and left next/postcss untouched (unlike an aggressive `jq del` of the
vite subtree, which reverted next's nested postcss to 8.4.31 and needed the #1 re-fix).

**vitest 4 config break (#21).** vitest 4 removed `environmentMatchGlobs` → the frontend
`tsc` type-check gate fails (`does not exist in type 'InlineConfig'`). Migrated
`frontend/vitest.config.ts` to `test.projects` (a `node` project for lib/hooks + a
`jsdom` project for components/app, each `extends: true` to inherit the root `react()`
plugin; coverage stays at root). Config-only, no test-file edits — but a CONSENTED
test-config change (asked first). Verified: FE type-check passes + FE vitest RUNS.
(One FE suite, `line-obligations.spec.ts`, fails on a missing `@/` alias in the vitest
config — PROVEN pre-existing on `main` under the original config; FE vitest is not a CI gate.)

**Standalone Docker locks (#22).** Both `backend`/`frontend` ship standalone locks
(friction #12). A plain seeded `npm install --package-lock-only` bumped vitest 2→4 but
left vite at 5 (impossible with vitest 4) → broken lock that still `npm ci`s. Fix: `jq del`
the vite/vitest/@vitest/esbuild/@esbuild nodes from the seed, THEN regen. The `frontend`
lock caps vite at 7 via `@vitejs/plugin-react@^4` (peer ^4..^7) → vite 7.3.6 naturally;
the `backend` lock has no such cap → jumps vite→8, so pin `overrides.vite: "^7.0.0"` in
`backend/package.json` (workspace-member override: ignored by the root install per #14,
honoured by the `npm install --prefix` standalone regen). Final: all three locks vitest
4.1.10 / vite 7.3.6 / esbuild 0.28.1; root+backend audit = 2 mod (out-of-scope siblings),
frontend = 0; `npm ci --dry-run` clean on all three. NOTE the backend Dockerfile runs
`npm ci` (all deps) but never runs vitest, so the standalone lock's vite is inert at
build — the pin is for consistency + minimal diff, not correctness.

### 2026-07-10 — [portal-core] Resolving conflicts on an audit PR whose lockfiles main also touched (#599)

**Situation.** PR #599 (mssql v12 + azure) went stale after sibling audit/OTel PRs
(#570/#598 OTel 0.220, #575 postcss) merged to main — all rewrite the giant root
`package-lock.json` + `services/portal-core/package-lock.json`. `gh` reported
CONFLICTING; a `git merge origin/main` only surfaced ONE textual conflict (root
`package.json` overrides: our `@azure/msal-node` vs main's `postcss`), but git had
*auto-merged* the giant lockfiles line-by-line — never trust that.

**Recipe that worked (per file, by who-touched-it):**
1. Root `package.json`: keep BOTH override entries (union), stage.
2. Root lock (both branches changed it): `git checkout origin/main -- package-lock.json`
   to start from main's complete tree, then `npm install` — direct-dep bumps in the
   merged workspace `package.json` (mssql ^12) ARE honoured, so the mssql/tedious tree
   comes in for free. The `@azure/msal-node` OVERRIDE did NOT (trap #1 — msal-node stuck
   at 5.1.1 under `@azure/identity`, still pulling `uuid@8.3.2`); fixed with the surgical
   `override` helper.
3. Standalone portal-core Docker lock (both changed it): `generate-lockfiles portal-core`
   from the merged service `package.json` — regenerates clean (OTel 0.220 + mssql 12 +
   msal-node 5.4.0 hoisted, no vulnerable uuid). Do NOT hand-merge it.
4. migration-runner lock (main did NOT touch it): keep ours untouched — no action.
   Decide per-file with: `for f in ...; do git diff --quiet <merge-base> origin/main -- $f && echo UNCHANGED || echo CHANGED; done`.
Final net diff vs main matched the original PR's 6-file scope; pr-checks green; the 4
target keys (`mssql`/`tedious`/`@azure/identity`/`@azure/msal-node`) all `check-pkg`-clear.

**Override helper trap — scoped packages (NEW).** `audit-helpers.sh override` guards on
`basename <lock-path>`, so for `.../node_modules/@azure/msal-node` it looks for an override
key literally named `msal-node` and dies "no root override for 'msal-node'" even though
`@azure/msal-node` IS in `overrides`. The re-resolve logic itself is fine — just pass
`--force` (after eyeballing that the scoped override really exists). One-liner added below.

### 2026-07-10 — [portal-core] uuid/ldapts/nodemailer PR #607 (#572) conflicts after #599 merged (#24)

**Situation.** Near-duplicate of the #599 entry above. PR #607 (uuid v14 / ldapts v8 /
nodemailer v9) went CONFLICTING after sibling audit PRs — including #599 (mssql/azure,
which added `@azure/msal-node: "^5.4.0"` to BOTH root+service `package.json`) — merged to
main. `git merge origin/main` textually conflicted on root `package.json` + both giant
locks; service `package.json` auto-merged cleanly (our ldapts/nodemailer/uuid bumps vs
main's msal-node/OTel/mssql bumps were in non-overlapping regions).

**What worked (followed the #599 recipe, with two new wrinkles):**
1. Root `package.json` overrides conflict: main added `postcss` + flat
   `@azure/msal-node: "^5.4.0"`; ours added `uuid: "^14.0.1"` + nested
   `@azure/msal-node: { uuid: "^14.0.1" }`. Union = keep `postcss`, keep `uuid`, and
   MERGE the msal-node key via the combined form `{ ".": "^5.4.0", "uuid": "^14.0.1" }`.
2. Root lock: `git checkout origin/main -- package-lock.json` + `npm install` — ldapts 8 /
   nodemailer 9 rode in free; msal-node deduped to 5.4.0 (no vulnerable uuid child). But
   the `uuid` override was a total no-op (#1): left typeorm's uuid at 11.1.0 (< 11.1.1,
   still vuln) and the PUBLISHED `@mmem/portal-file-manager` tarball's nested uuid@9.0.1.
   Fixed by `jq del`-ing BOTH nested nodes + `rm -rf` their dirs + one `npm install` →
   reproduced the original PR EXACTLY: hoisted `uuid@14.0.1` (portal-core direct dep;
   file-manager deduped up), typeorm nested at patched `11.1.1`. NOTE: the flat `^14`
   override does NOT force typeorm to 14 — typeorm keeps 11.1.1 (satisfies its own
   `^11.1.0`, and 14 is ESM-only which would break typeorm's CJS `require`). That's
   correct/desired, not a bug.
3. Standalone service lock: `git checkout origin/main -- services/.../package-lock.json`
   then `generate-lockfiles portal-core` from the merged service `package.json` —
   regenerated clean (msal-node 5.4.0 + ldapts 8 + nodemailer 9 + hoisted uuid 14, no
   `@types/uuid`, file-manager deduped). Here `--package-lock-only` DID apply the override
   (the direct uuid ^14 bump forced the re-resolve).
4. `portal-file-manager/package.json`: main didn't touch it → kept ours.

**NEW trap #24 — stale `node_modules` after re-resolve fails pr-checks spuriously.** After
all the `jq del`/surgical installs + `generate-lockfiles`, the LOCK was correct but on-disk
`node_modules` had drifted (missing vitest, prettier, nest/cli, coverage — `npm install
--dry-run` wanted +121 pkgs). pr-checks then reported FAKE failures: portal-core TS
("Cannot find module 'vitest'"), prettier flagging unrelated migration files (because
`npx prettier` fetched 3.9.5 instead of the pinned 3.3.3), and tests. Fix: a plain
`npm install` to sync `node_modules` to the lock (verified the lock came back
byte-identical), THEN pr-checks — all green. Diagnose this class with `npm install
--dry-run` (any "add N packages" = drift). Net diff vs main = the PR's original 5-file
scope; all 4 targets (`uuid`/`ldapts`/`nodemailer`/`GHSA-w5hq-g745-h8pq`) `check-pkg`-clear;
49→14 vuln (main already cleared the siblings). PR #607 is a READY (not draft) PR — left
its ready state alone; only pushed the merge so `mergeable` flipped to MERGEABLE.

### 2026-07-10 — [portal-core] multer PR #609 (#574) conflicts after #599/#607 merged; deleting platform-express's OWN ./multer submodule (#25)

**Situation.** Third in the #599/#607 series. PR #609 (multer 1→2) went CONFLICTING
after the mssql/uuid/ldapts/nodemailer siblings merged. `git merge origin/main`
textually conflicted on root `package.json` (overrides), `services/portal-core/
package.json` (deps + a SECOND `overrides` block git auto-merged in at a different
position → duplicate `overrides` key, invalid JSON — consolidate into one), and both
giant locks (auto-merged, untrustworthy). `packages/portal-file-manager/package.json`
auto-merged cleanly (our multer bumps vs main's uuid v14 bump — non-overlapping).

**Followed the #599/#607 recipe and it worked:**
1. Root `package.json` overrides: union of ours (`multer`, `@nestjs/platform-express.multer`)
   + main's (`postcss`, `uuid`, `@azure/msal-node`).
2. Root lock: `git checkout origin/main -- package-lock.json` + `npm install`. The
   multer DIRECT-dep bumps did NOT ride in free here (trap #1) — no hoisted
   `node_modules/multer@2.2.0` appeared and portal-core's `multer ^2.2.0` was left
   UNMET, platform-express still nested `2.1.1`. Ran `override` helper on
   `.../platform-express/node_modules/multer`; it re-nested a fresh vulnerable
   `path-to-regexp@8.3.0` + other siblings (trap #15). Cleanest fix that converged:
   `jq del` EVERY `node_modules/@nestjs/platform-express/node_modules/*` entry + `rm
   -rf` that dir + one `npm install` → all deduped to root, hoisted `multer@2.2.0`,
   no nested platform-express node (matches original PR f99eb41f exactly).
3. Standalone lock: `git checkout origin/main -- .../package-lock.json`, `jq del` the
   nested platform-express multer (targeted override is a no-op on the already-locked
   node — trap #15), then `generate-lockfiles portal-core`. Root `multer` direct bump
   `1.4.5-lts.2 → 2.2.0` DID re-resolve (out-of-range forces it). Net standalone delta
   vs main = pure multer subtree (multer/@types-multer/concat-stream/readable-stream +
   removal of multer-1-only transitives). A nested `@nestjs/swagger/.../path-to-regexp@8.3.0`
   appears but is NOT a flagged advisory (that GHSA affects <8.0.0) — benign.

**NEW trap #25 — deleting platform-express's OWN `./multer` submodule.** Early on I saw
`node_modules/@nestjs/platform-express/multer` (containing a nested `multer/`) and
`rm -rf`'d it as "corrupted". WRONG: platform-express@11 SHIPS a `./multer` source
submodule (`index.js` does `require("./multer")`, alongside `./adapters`/`./interfaces`).
The npm multer *package* is the separate `.../platform-express/node_modules/multer`.
Deleting the submodule passed every lock/audit check but broke pr-checks with
`Cannot find module './multer'` from `platform-express/index.js`; a plain `npm install`
did NOT restore it (lock unchanged → npm skips re-extract). Fix: `rm -rf` the WHOLE
`node_modules/@nestjs/platform-express` + `npm install`. Lesson: never hand-delete a
dir *inside* a package because it "looks duplicated" — only ever delete whole package
dirs (or lock nodes via the `override` helper).

Net diff vs main = the PR's original 5-file scope; multer + both GHSAs `check-pkg`-clear;
12 vuln (main-merge state was 14; our fix removed the 2 multer advisories, 0 new). PR
#609 is READY (not draft) like #607 — left its state alone; pushed the merge →
`mergeable` flipped CONFLICTING → MERGEABLE.

---

### 2026-07-10 — round-2 batch (#626/PR#627): transient advisories mid-audit-fix; "outside parent range" = defer

**[portal-core] `npm audit fix` (non-force) is iterative and surfaces TRANSIENT
advisories between passes.** Round-2 baseline was 12; pass 1 cleared 8 but the
re-resolve surfaced multer/path-to-regexp/@nestjs/platform-express (NONE in the
baseline — occurrence=0); pass 2 cleared those → 1 left; the intermediate names
were never real regressions. Lesson: run `audit fix` to a FIXED POINT (repeat
until total stops dropping), and check any scary new name against the baseline
file before panicking — `jq '[.vulnerabilities[]|...select(.key==$p)]|length'`
on the saved baseline tells you if it's genuinely new or just churn. (#26)

**Heuristic for "breaking → defer" when npm says fixAvailable=true.** npm can
report a transitive fix as non-major yet the ONLY patched version sits OUTSIDE
the parent's declared range. Round-2 esbuild: advisory `>=0.27.3 <0.28.1`, fix =
0.28.1, but `tsup@8.5.1` declares `esbuild: ^0.27.0` (excludes 0.28.x). Forcing
it via override pushes esbuild outside tsup's range = build-tooling risk, not an
in-range bump → split to its own deferred issue (#628). Check parent ranges
(`jq '.dependencies.<dep>' node_modules/<parent>/package.json`) before overriding
a transitive; if the fix version doesn't satisfy the parent, it's not "non-breaking". (#27)

**Best-case outcome: pure lockfile diff.** When every direct dep is already on a
caret range that admits the patched version, `npm audit fix` touches ONLY
`package-lock.json` (no package.json), and `generate-lockfiles` is a no-op if the
standalone locks were regenerated recently. 11/12 cleared this way; single-file diff.

## 28. [portal-cga] OTel exporter cluster: `fixAvailable:true` that `audit fix` won't apply belongs to the SDK-major issue (2026-07-16)

**Context.** Issue #54 = "remediate all NON-BREAKING advisories" across three service
locks (`backend`/`frontend`/`migration-runner`); the OTel SDK 0.213→0.220 major is a
separate issue (#56).

**Symptom.** After `npm audit fix` (non-breaking) in `backend`, 9 OTel advisories
(exporter-zipkin, propagator-b3, sdk-trace-base, exporter-logs/metrics-otlp-grpc/proto,
exporter-trace-otlp-grpc, otlp-grpc-exporter-base) still showed `fixAvailable: true`
(non-major) — looked like missed non-breaking fixes.

**Root cause.** The underlying advisory is on `@opentelemetry/core` (W3C-Baggage
unbounded-alloc DoS, range `<=2.7.1`). The exporters are flagged only for *depending*
on vulnerable core. `npm audit fix` bumped the TOP-LEVEL `core` 2.7→2.9, but
`@opentelemetry/instrumentation-http@0.213` (under `sdk-node@0.213` /
`auto-instrumentations-node@0.71`) HARD-PINS a nested `core@2.6`, and bumping the
exporters violates `sdk-node@0.213`'s pinned ranges. So npm reports `fixAvailable:true`
yet only actually applies it under `--force` (which pulls `sdk-node@0.220` — the #56
major). The top-level core 2.7→2.9 bump clears NO OTel advisory on its own (harmless
version skew; backend build + 285 tests stayed green).

**Fix / lesson.** Prove you're at the non-breaking fixed point by running `npm audit
fix` a SECOND time — a no-op (lockfile byte-identical, count unchanged) means every
in-range fix is applied and the remainder is the SDK-major issue's. Do NOT chase the
`fixAvailable:true` exporters with a surgical override; they need the coordinated major
bump. Net #54 result: backend 41→29 (12 cleared), migration-runner 6→5 (brace-expansion),
frontend 4→4 (all breaking → #55/#58). Concrete instance of #27.

## 29. [portal-lti] Standalone-per-project repo (no root workspace); targeted `npm update` cleanly excludes OTel (#56, 2026-07-16)

First portal-lti audit-fix run. Structure + approach worth recording:

- **[portal-lti] NO root workspace / NO root lock.** `backend/`, `frontend/`,
  `migration-runner/` are each a FULLY standalone package — own `package.json` +
  `package-lock.json` + `node_modules`, and each project's SINGLE lock is BOTH the dev
  lock AND the Docker `npm ci` lock (no dual dev-vs-standalone lock like qms/portal-core).
  Remediate ENTIRELY inside each project dir (`cd backend && npm update …`); there is no
  root install and root overrides are irrelevant. Simpler than qms.
- **[portal-lti] `scripts/sync-standalone-lockfiles [--check]`** is the lock-consistency
  tool (regenerates via `npm install --package-lock-only` in an isolated temp dir; `--check`
  runs `npm ci --dry-run`). `pr-checks` invokes `--check` as a gate step. A plain in-project
  `npm update`/`npm install` produced locks that passed `--check` directly — no separate regen
  step needed.
- **[portal-lti] local `pr-checks --full` is STRICTER than CI, and all green** — it runs
  lint + PRETTIER + type-check + TESTS for BOTH projects + `sync-standalone-lockfiles --check`.
  Everything passes, so `./scripts/safe-push` works cleanly with NO `--no-verify` (unlike qms,
  where prettier/FE-vitest fail locally). The actual CI gates (`.github/workflows/pr-checks.yml`)
  are narrower — backend lint+type-check+test, frontend lint+type-check, via `npm install` — but
  Docker image builds (`build-images.yml`) use `npm ci`, so keep the locks in sync.
- **[portal-lti] targeted `npm update <in-range targets>` avoids the entry-#28 OTel trap.**
  #56 = non-breaking bulk; OTel SDK-major is #57. Rather than `npm audit fix` (which bumps
  `@opentelemetry/core` and churns the OTel subtree for zero cleared advisories, per #28), I
  ran `npm update` naming ONLY the 10 in-scope packages
  (`@grpc/grpc-js @nestjs/platform-express @nestjs/swagger form-data multer protobufjs tmp
  @babel/core js-yaml qs`). Result: backend 40→30, lock-only (package.json untouched),
  **zero `@opentelemetry/*` nodes touched** (verified semantically, #10). All 30 remaining are
  out-of-scope OTel (#57) + no-fix/breaking residuals xlsx/@mmem-portal-file-manager/exceljs/uuid
  (#58/#61). Prefer explicit `npm update <targets>` over `npm audit fix` whenever OTel (or any
  breaking cluster) is carved into its own issue.
- **[portal-lti] frontend `$postcss` reference override behaves exactly like qms #13** — postcss
  is a direct devDep, so a bare-version override EOVERRIDEs; use `overrides.postcss: "$postcss"`
  + bump the direct devDep (`^8.5.4`→`^8.5.10`, resolved 8.5.16) + surgical re-resolve of
  `node_modules/next/node_modules/postcss` (the nested exact-pinned 8.4.31, friction #1/#2).
  Clears BOTH the `postcss` AND the `next` advisory (next's is `via:["postcss"]`). Frontend 3→1
  (jspdf critical → #59).
- **[portal-lti] baseline helper collides across projects.** `audit-helpers.sh` keys the state
  file by repo+branch only, so baselining `frontend` OVERWRITES the `backend` baseline. In a
  multi-project repo run each project with its own
  `AUDIT_FIX_STATE_DIR=$HOME/.cache/audit-fix/<proj>`.
- **[portal-lti] incidental root-version reconcile (instance of #11)** — main's `backend`
  committed lock had root version `0.1.0` while `backend/package.json` declares `1.0.2`;
  `npm update` rewrote the lock's root `.version`/`.packages[""].version` to `1.0.2`. Pre-existing
  drift, harmless — note it in the PR body, don't fight it.

### 2026-07-16 — [portal-core] esbuild #628: forcing an out-of-tsup-range override; standalone-lock audit artifact (#28, #29)

**Context.** #628 = the deferred esbuild low (GHSA-g7r4-m6w7-qqqr, CVSS 2.5,
Windows-dev-server-only), split from the round-2 batch precisely because it's the
friction-#27 "fix outside the parent's range" case. tsup@8.5.1 (still latest —
`npm view tsup@latest dependencies.esbuild` = `^0.27.0`) is the SOLE consumer of the
root-hoisted `node_modules/esbuild@0.27.4`; patched 0.28.1 is outside `^0.27.0`. User
overruled the deferral (option 2) → force it, accept the build-tooling risk.

**Trap #28 — the `override` helper PRUNES esbuild instead of upgrading it.** Added
flat `overrides.esbuild: "^0.28.1"` + `audit-helpers.sh override . node_modules/esbuild`
→ reported "found 0 vulnerabilities" but the esbuild node was DELETED entirely
(`jq '.packages["node_modules/esbuild"].version'` = null, `npm ls esbuild` empty), tsup
left with an unmet edge. `npm ci --dry-run` "passed" anyway (it replays the lock, does
NOT validate transitive completeness — same lesson as #19). The advisory "cleared" only
because the node vanished — a BROKEN lock. Root cause = friction-#16: npm 11's
incremental resolver won't place an override version that conflicts with the parent's
declared range; the surgical delete+install just prunes.

**Fix (friction-#16 option (a), generalised).** esbuild is root-hoisted, single
consumer → hand-splice. `git checkout package-lock.json` (undo the prune), generate a
throwaway from-scratch lock in $SCRATCH (`{"dependencies":{"esbuild":"^0.28.1"}}` +
`npm install --package-lock-only`) to get the fully-formed 0.28.1 node
(version/resolved/integrity), then targeted-`jq` the real node:
```bash
jq --arg v 0.28.1 --arg r "$RES" --arg i "$INT" '
  .packages["node_modules/esbuild"].version=$v
  | .packages["node_modules/esbuild"].resolved=$r
  | .packages["node_modules/esbuild"].integrity=$i
  | .packages["node_modules/esbuild"].optionalDependencies|=map_values($v)' \
  package-lock.json > tmp && mv tmp package-lock.json
```
CONVENTION MATTERS: portal-core's root lock carries esbuild's `optionalDependencies`
LIST (26 `@esbuild/*` entries) but NO separate `@esbuild/*` package nodes (and none on
disk — esbuild resolves its platform binary at install-time), so do NOT add 26 nodes;
just bump the listed values. Result: minimal 62-line lock diff, all esbuild + 2
incidental workspace-version reconciliations (#11). CRUCIAL: a hand-spliced node is
STABLE — a plain `npm install` did NOT re-prune it (esbuild stayed 0.28.1, 0 vulns),
because the on-lock node already satisfies the override so npm treats it as consistent.
`npm ci` also clean. Functionally verified: `npm run build:packages` (tsup for all 7
`@mmem/*` packages) exit 0 on 0.28.1; `pr-checks --full` green (1105 tests + all builds).

**Trap #29 — `cd services/<svc> && npm audit` audits the ROOT workspace, not the
standalone lock.** #628/#683 claimed the `services/portal-core` +
`services/portal-migration-runner` standalone Docker locks ALSO held the esbuild low.
False: a workspace member walks UP to the root `package-lock.json`, so `( cd
services/<svc> && npm audit )` re-reports the ROOT advisory. Once root was fixed, that
command showed esbuild=null for the services too — proving it was never reading their
standalone locks. Auditing each standalone lock in ISOLATION (copy package.json +
package-lock.json + .npmrc to a temp dir, `npm audit --package-lock-only`) showed
esbuild ABSENT from both (it's only an optional peer of vitest's transitive vite@8,
never installed/pinned there) — portal-core standalone had 17 OTHER out-of-scope
advisories, migration-runner 1, zero esbuild. So the esbuild advisory lived ONLY in the
root workspace lock; standalone locks needed NO change. Lesson: never trust a
workspace-member-cwd `npm audit` as a standalone-lock reading — isolate it.

## 30. [portal-cga] jspdf 2.x→4.x clean image-mode bump; fast-png strict CRC; root lock is not a gate (#55, 2026-07-16)

**Context.** #55 = critical jsPDF advisory cluster (LFI/path-traversal, ReDoS, DoS, PDF
injection) + transitive dompurify, `frontend` only. Strategy = direct major bump
`jspdf ^2.5.2 → ^4.2.1`.

**Outcome: a near-drop-in bump, zero source changes.** The ONLY jsPDF consumer is
`frontend/src/lib/pdf-export.ts` (image-based export: html2canvas → `addImage`). It uses
`new jsPDF('p','mm','a4')`, `addPage`, `addImage(data,'PNG',x,y,w,h)`, `text(str,x,y,{align})`,
`setFontSize`, `setTextColor`, `getNumberOfPages`, `setPage`, `save`, and resolves the ctor as
`mod.jsPDF || mod.default`. ALL unchanged across the 2→4 majors (verified against
`node_modules/jspdf/types/index.d.ts` + a runtime smoke). No jspdf-autotable, no app-level
DOMPurify. Frontend audit 4→2 (jspdf critical + dompurify moderate cleared; dompurify
re-resolved 2.5.9→3.4.12 via jspdf 4's optional `dompurify ^3.3.1`; residual next+postcss
moderates are #58). Lock diff perfectly scoped: +fast-png/pako/iobuffer/@types/{pako,trusted-types},
-atob/-btoa, ~jspdf/~dompurify (+ the #11 incidental root-version reconcile 0.1.0→1.0.2).

**Trap #30a — jspdf 4 PNG decoding is STRICT via the new `fast-png` dep.** A runtime smoke
feeding a hand-crafted 1×1 base64 PNG to `addImage` threw `Error: CRC mismatch for chunk IDAT`
from `fast-png` (jspdf 2.x tolerated malformed PNGs). Real app usage is fine — browser
`canvas.toDataURL('image/png')` emits valid CRCs — but encode smoke-test fixtures with
fast-png's own `encode({width,height,channels:4,data})` for a guaranteed-valid checksum.
With a valid PNG the smoke rendered a 2-page PDF (`%PDF-` header, 3912 bytes) exercising the
full used API surface.

**Trap #30b — portal-cga root `package-lock.json` is a stale aggregate, NOT a build/CI gate.**
The issue said "mirrored in the stale root lock", but: (1) `frontend/Dockerfile` builds from
`frontend/package-lock.json` (`COPY frontend/package.json frontend/package-lock.json` + `npm ci`);
(2) `scripts/pr-checks` only lints/type-checks/tests the affected service via `npm install`
inside `frontend/` — neither touches the root lock. So the frontend lock is the real target;
the root aggregate (still jspdf 2.5.2) is issue #59's "decide its fate" call — DON'T churn it
here. Also: portal-cga has NO `scripts/update-issue-status` and NO `scripts/generate-lockfiles`
(portal-core-only); assign via `gh issue edit --add-assignee @me`, and issues aren't on a
project board (`projectItems: []`) so there's no status to move (like qms #12).

**Verification (no browser).** pr-checks green (ESLint + Prettier + tsc type-check — the real
2→4 API-compat gate — + 8 vitest tests); runtime ESM smoke from INSIDE `frontend/` (#9,
`require.resolve` asserted under the worktree) proving text+image+multipage render on 4.2.1.
The one genuinely browser-only step (html2canvas DOM→canvas → visual PDF check) went into the
QA plan on the ISSUE as the manual step.

## 2026-07-16 — portal-core #684: publish-a-package fix (source already fixed, republish needed)

**Trap #31 — [portal-core] A "bump uuid in @mmem/portal-file-manager + publish" issue can be a
VERSION-BUMP-ONLY fix, not a dep change.** The issue named the vulnerable nested `uuid@9.0.1`
under the *published* `@mmem/portal-file-manager@0.2.7` tarball. But the package **source** at
HEAD already declared `uuid ^14.0.1` (bumped in #572, commit c883eb2e) — `0.2.7` was simply
published *before* that landed and never re-released. Confirm the gap before touching deps:
`npm view @mmem/portal-file-manager@<ver> dependencies` (registry) vs the source `package.json`.
If source is already patched, the ONLY change is `version: 0.2.7 → 0.2.8` so a fresh publish
carries the fixed manifest. No override, no source edit.

- **The vuln is NOT in portal-core's own audit.** The workspace resolves the file-manager to its
  local source (uuid ^14), so `npm audit` / `check-pkg uuid` / baseline are all 0 in-repo. The
  standard Verify gates still pass, but "target cleared" here means *the republish will carry the
  fix* — real clearing happens at publish + downstream (qms#296). Say so in the PR/QA plan.
- **`dist` is gitignored and built in CI** at publish (`publish-packages.yml`, `workflow_dispatch`).
  Don't commit dist. Verify locally with `npm run build --workspace=@mmem/portal-file-manager`.
- **Consumers use caret ranges** (`services/portal-core` `^0.2.6`, scaffold template `^0.2.7`) that
  already accept `0.2.8` — don't churn them. The publish workflow's `sync-template-versions.mjs`
  bumps the scaffold template automatically at publish time.
- **Publishing is a post-merge `workflow_dispatch`** (packages=portal-file-manager) — the PR only
  lands the version bump. `npm publish` fails on an already-existing version, which is exactly why
  the bump is mandatory. Put the dispatch + `npm view` + downstream reinstall in the QA plan.
- uuid v9→v14 API note: source used only `import { v4 } from 'uuid'` + `v4()` (no `buf` arg) — the
  advisory's `buf`-bounds path isn't even exercised; 108 tests pass unchanged.

## 31. [portal-cga] OTel SDK 0.213→0.220 major: parent-bump the 3 direct 0.2xx deps; require()-based init needs a runtime smoke (#56, 2026-07-16)

**Context.** #56 = the coordinated OTel SDK major, sibling to #54's non-breaking half (entry #28). portal-cga is standalone-per-project (root `package.json` has NO `workspaces`; `backend`/`frontend`/`migration-runner` each own a lock that is BOTH dev and Docker `npm ci` lock, like portal-lti #29). Remediate ENTIRELY inside `backend/`.

**Clean parent bump — no source changes, no overrides.** Three 0.2xx experimental direct deps move together: `@opentelemetry/sdk-node` ^0.213→^0.220, `@opentelemetry/auto-instrumentations-node` ^0.71→^0.78 (DIFFERENT version line — no 0.220.x exists for it; 0.78 aligns with the 0.220 SDK), `@opentelemetry/exporter-trace-otlp-http` ^0.213→^0.220 (a DIRECT dep at ^0.213, so a plain `npm install` won't move it — must bump its declared range too). `@opentelemetry/{api,resources,semantic-conventions}` left untouched: their ranges (^1.9 / ^2.6 / ^1.40) already satisfy sdk-node 0.220's needs (core 2.9, resources 2.9, semconv ^1.29) and re-resolve in range. `npm install` → single hoisted `core@2.9`, the nested `core@2.6` (pinned by `instrumentation-http@0.213`, entry #28's culprit) gone. All 26 `@opentelemetry/*` advisories cleared; backend 29→3 (residuals xlsx/@mmem-portal-file-manager/uuid = the no-fix set → #59).

**tsc does NOT gate the OTel API — `tracing.config.ts` uses `require()`, not `import`.** So the type-check gate is BLIND to a 0.220 API break (require returns any). A runtime SDK-boot smoke is MANDATORY: mirror the config exactly (NodeSDK({sampler,resource,traceExporter,instrumentations}).start()/.shutdown(), getNodeAutoInstrumentations, OTLPTraceExporter({url,headers}), resourceFromAttributes, ParentBasedSampler/TraceIdRatioBasedSampler, ATTR_SERVICE_NAME/VERSION) with an unreachable exporter URL. Place it INSIDE `backend/` (#9) and assert `require.resolve` lands under the worktree. All APIs present + start/shutdown OK on 0.220.

**Scoped-diff verification (#10).** numstat is huge (688/811) but semantic diff shows every added/removed/changed key is `@opentelemetry/*` OR an OTel-transitive dep re-resolving in range (pg-protocol, gaxios/gcp-metadata, systeminformation, import-in-the-middle/es-module-lexer/acorn-import-attributes, @grpc/proto-loader, @protobufjs/utf8, lru-cache de-dupe). ZERO app-level prod deps (nest/typeorm-core/mssql/bullmq/axios) moved. pr-checks green (285 tests). Live traces→OpenObserve went into the QA plan on the issue as the one manual step.

## 31. [portal-lti] No `update-issue-status` script; a nested `$directdep` override dedupes cleanly (2026-07-16, #58)

**Symptom.** Phase-0 `./scripts/update-issue-status <n> "In Progress"` → `no such
file or directory`. **Cause.** That project-status helper is portal-core-only;
portal-lti ships no equivalent. **Fix.** Skip both status steps (In Progress /
Needs Review), just `gh issue edit --add-assignee @me`; note it and carry on.

**Also (works-as-designed, worth knowing).** For an advisory reached via ONE
parent where the patched version is ALSO a direct dep, a nested per-parent
override with the `$name` reference form — `overrides: { exceljs: { uuid: "$uuid" } }`
— is the clean play: it sidesteps the #13 `EOVERRIDE` (bare root override vs the
direct `uuid` dep) AND, because the pinned version already exists at the top level,
the friction-#1 surgical `override` helper simply DEDUPES the nested node UP (diff
was +0/−10, one node removed) rather than re-adding a fresh copy. Scopes the fix to
exactly that parent, leaving a sibling residual (here `@mmem/portal-file-manager`'s
own uuid) untouched. exceljs kept ^4.4.0; runtime-safe because it only uses
`const {v4} = require('uuid')` (verified with a workbook-write smoke).

## 29. [portal-qms] postcss #334 — full re-resolve demotes a prod transitive; surgical in-place bump instead; nested-worktree node_modules leak (2026-07-16)

**Context.** Issue #334 = re-pin root `postcss` 8.4.31 → 8.5.15 (GHSA-qx2v-qp2m-jg93),
a regression of #294. Root `package.json` already had `overrides.postcss: ">=8.5.10"`
but the lock stayed on 8.4.31 (friction #1). Only ONE vulnerable node: root
`node_modules/postcss@8.4.31`, hoisted **prod** because `next@16.2.10` hard-pins
`postcss: 8.4.31` in its real manifest (frontend's own postcss is `devDependencies`).

**Trap A — the `override` helper's re-resolve produced a BROKEN, non-scoped lock.**
`del(node)+npm install` under the override did NOT re-hoist a prod postcss for next.
Instead it scattered postcss to dev-only `frontend/node_modules/postcss@8.5.15` +
`vite/node_modules/postcss`, marked `nanoid`/`picocolors`/`source-map-js` dev, and
left root `node_modules/next` (prod) with no reachable postcss. `npm audit` went
4→2 and reported no UNMET, so it LOOKED fixed — but the topology diverged from main
(which has root postcss prod) and the diff was a scatter, not the scoped bump #334
demanded. A full `rm -rf node_modules && npm install` reproduced the same scatter —
this is npm's genuine resolution under the override, not an incremental-reify glitch.

**Trap B — nested-worktree node_modules leak masked the breakage.** The worktree
(`<main-root>/worktrees/334-…`) sits under `<main-root>` which has its OWN
`node_modules`. `require.resolve('postcss',{paths:['node_modules/next']})` from the
worktree walked UP and resolved to `<main-root>/node_modules/postcss`, hiding the
missing worktree copy. Proof required `mv <main-root>/node_modules aside` (restore
immediately after) — then next failed `MODULE_NOT_FOUND`, confirming the scatter was
broken. Moving the ancestor aside did NOT change npm's scatter (Trap A is npm, not
the leak) — the leak only affects runtime `require.resolve`, not the lock.

**Fix — surgical in-place bump (matches what #334's author expected).** With only
one vulnerable root node and 8.5.15 already present elsewhere in the lock: reset the
lock to origin/main, then targeted-**Edit** the single `node_modules/postcss` block —
`version`/`resolved`/`integrity` (from `npm view postcss@8.5.15 dist.tarball
dist.integrity`) + the three dep ranges (`nanoid ^3.3.12`, `picocolors ^1.1.1`,
`source-map-js ^1.2.1`) — keeping NO dev flag (stays prod). Do NOT rewrite the file
via `JSON.stringify` (reformats the whole lock). Then `npm ci` (strict reify, never
`npm install` which would recompute and re-scatter). Result: 6-line diff confined to
the postcss node; root postcss@8.5.15 prod; next resolves it at the worktree root
(re-proved with ancestor hidden). `npm ls` shows `postcss@8.5.15 invalid: "8.4.31"
from node_modules/next` — EXPECTED override display artifact (identical to the
exceljs→uuid case), harmless; `npm ci` and CI are happy.

**Verify note.** pr-checks `--full` only `npm install`s a project if its
`node_modules` is missing (it wasn't → lock untouched, confirmed by before/after
sha256). portal-qms CI (`pr-checks.yml`) runs lint + type-check + `npm test` only —
NOT prettier; the local backend prettier failure is pre-existing drift on files this
lock-only PR never touched (confirmed `git diff origin/main` empty), so it can't gate
CI. `update-issue-status` does not exist in portal-qms — skip it, just assign @me. (#29)

## 32. [portal-core] A "sanity-check" milestone issue has NO remediation — verify-only, no worktree/PR (#683, 2026-07-16)

**Context.** #683 = the `audit-fix-preprod-2026-07` pre-prod sign-off issue: its
body ASSERTS the repo is clean except one accepted esbuild low (#628) and asks you
to *confirm* it. There is no package/advisory to fix — the deliverable is evidence,
not a lockfile diff.

**Handling.** Do NOT create a worktree or a draft PR (the skill's Phase 1 default) —
there is no diff to ship, so a worktree + empty PR is pure ceremony. Collapse to a
Phase-3-only run: ff local `main` to origin, then `npm audit --json | jq
'.metadata.vulnerabilities'` per lockfile (root + each standalone Docker lock +
`test/`), confirm the tracked-residual issue's state, and confirm every other
milestone issue is CLOSED (`gh issue list --milestone <name> --state all`). Finalise
ON THE ISSUE: evidence comment → tick the acceptance boxes (`gh issue view --json
body` → `sed 's/^- \[ \]/- [x]/'` → `gh issue edit --body`) → `gh issue close
--reason completed`. Closing a no-PR sign-off issue is outward-facing — get explicit
go-ahead first (I used AskUserQuestion).

**The residual had moved.** #683's body documented esbuild (#628) as a *deferred,
no-in-range-fix accepted residual*, but between issue-authoring and the check, PR
#685 (`force esbuild ^0.28.1`) actually REMEDIATED it (root override → single hoisted
`esbuild@0.28.1`), and #628 was CLOSED. So the audit showed **0 everywhere**, not
"0 + 1 accepted low" — the issue narrative was stale in the repo's favour. Lesson:
run the audit for ground truth; don't trust the issue body's stated audit state.
NB `npm ls esbuild` read `0.27.4` from a stale working-tree `node_modules` while the
LOCKFILE (and `npm audit`) had `0.28.1` — the lockfile is authoritative; `npm ls`
"invalid: 0.28.1 from node_modules/tsup" is the expected out-of-`^0.27.0`-range
override artifact.

### 2026-07-16 — [portal-cga] verifying a breaking DB-driver bump end-to-end (#57)
- **Context:** #57 (mssql 10→12) required a live "run a migration" check, but no MSSQL was up (docker present, port 1433 closed).
- **Technique that worked:** spin a throwaway `mcr.microsoft.com/mssql/server:2022-latest` on a spare host port (15433), poll readiness with the container's own `/opt/mssql-tools18/bin/sqlcmd -C`, create the target DB, then point the runner at it via `DB_HOST/DB_PORT/DB_PASSWORD/...` env + `DB_ENCRYPT=false DB_TRUST_SERVER_CERTIFICATE=true`. Tear the container down after (`docker rm -f`).
- **Trap — backend migrations don't run from the runner in isolation:** the migration-runner dynamic-imports backend `*.ts` migrations which `import { MigrationInterface, QueryRunner } from 'typeorm'`; typeorm isn't in `migration-runner/node_modules`, and `npm i --no-save typeorm` there does NOT fix it (Node resolves from the backend file's own dir tree, not the runner's). Pre-existing, unrelated to any bump. To verify the *driver* end-to-end, point `MIGRATION_PATHS` at a self-contained throwaway migration (a class with `async up(queryRunner)` doing real DDL/DML + a SELECT recordset readback) — the runner only needs `new Class().up(queryRunner)`, no typeorm. Exercise `beginTransaction`/`commit` separately via a tiny ts-node harness.
- **mssql 10→12 needed NO code changes:** `sql.connect`/`pool.request/input/query`/`result.recordset`/`sql.Transaction` unchanged; `@types/mssql@9` type-checks clean; encrypt/trustServerCertificate already explicit (immune to tedious default-encrypt change); Node floor >=18.19.0 met.
- **pr-checks only covers backend/ + frontend/** — a migration-runner-only change reports "nothing to check". Run migration-runner's own `type-check` + `build` manually for Gate 3.

### 2026-07-16 — [portal-cga] final re-audit / stale root aggregate lock (#59)
- **Stale root aggregate lock:** root package.json had NO `workspaces` + 7 devDeps, but root lock carried full backend+frontend trees (1370 entries → 62 phantom vulns that mirror the per-service locks). A plain `npm install` at root PRUNES the lock back to the real deps (1370→368); a clean `rm package-lock.json && npm install` is the canonical form. CI installs per-service (pr-checks working-directory backend/frontend), never at root — root lock only serves the e2e Playwright devDeps. Regenerate, then `npm audit fix` (non-breaking) cleared the residual dev-tool advisories → 0. Confirm `npx playwright --version` + `require('@playwright/test')` still resolve.
- **Baseline state-key collides across subdirs:** `audit-helpers.sh baseline .` then `baseline backend` write the SAME file (key = repo--branch, ignores subdir), so `diff` only reflects the LAST baseline. When a single issue touches multiple locks, track per-lock counts manually instead of relying on `diff`.
- **"No-fix" items go stale:** #59's tracked no-fix `@mmem/portal-file-manager`+`uuid` had a published fix by the time of the re-audit (pfm 0.2.8, `fixAvailable: true`). Always re-check `fixAvailable` on tracked no-fix items during a re-audit rather than trusting the old note.
- **pr-checks scope = backend/ + frontend/ only:** root and migration-runner changes report "nothing to check"; verify those locks' toolchains manually.

## 2026-07-16 — [portal-qms] #335 sanity-check sign-off: verify-only, 4 locks, residual moved (#32)

QMS instance of entry **#32** (the portal-core sanity-check playbook applied cleanly).
`audit-fix-preprod-2026-07`'s final gate #335 — a verify-only sign-off, **NO worktree/PR**.

- **Collapse to a Phase-3-only run.** `main` was already at `origin/main` (all sibling PRs
  merged). Audit each of QMS's **four** lockfiles: root workspace + `backend`/`frontend`/
  `migration-runner` standalone. Audit the standalone locks **in isolation** (copy
  `package.json`+`package-lock.json`+root `.npmrc` to a temp dir, `npm audit --package-lock-only
  --json | jq .metadata.vulnerabilities`) — `cd <svc> && npm audit` on a workspace member walks
  UP to the root lock (entry #29). Result: **0 everywhere** (info/low/mod/high/crit all 0).
- **The #296 "accepted residual" had MOVED (the #32 lesson, repeated).** #335's body said
  `#296` (portal-file-manager nested uuid) "may legitimately remain open/accepted". But it was
  already CLOSED — the `@mmem/portal-file-manager 0.2.7→0.2.8` bump (PR #337) resolved it at
  source. So the repo was **0 everywhere**, no carve-out. Don't trust the issue body's stated
  audit state — run the audit for ground truth.
- **Spot-check overrides are APPLIED IN THE LOCK, not just declared (#1).** `jq` the installed
  versions: root `postcss`=8.5.15 + `exceljs→uuid`=11.1.1; backend `uuid`=11.1.1 + `vite` pinned
  ^7 + file-manager nested uuid=14.0.1; frontend `postcss:"$postcss"`→8.5.15 (next's copy deduped
  up). Confirm NO `uuid <11.1.1` anywhere.
- **`migration-runner` has ZERO CI gates (#17) — hand-verify.** A `npm ci --dry-run` from the
  worktree reports a big "removed N" delta because its ON-DISK node_modules is stale (pre-#295
  mssql-10 tree) — that's not a lock inconsistency, just drift. Prove it clean with a FRESH
  isolated `npm ci` (copy the dir minus node_modules, + root `.npmrc`) → 152 pkgs clean +
  `npx tsc --noEmit` exit 0. mssql=12.7.0.
- **Don't run local `pr-checks` as a gate.** QMS `pr-checks` fails locally on non-gates
  (Prettier + FE-vitest, #12/#29) = noise. `main` is the aggregate of sibling PRs that each
  passed CI — cite that instead.
- **Finalise ON THE ISSUE** (outward-facing → get go-ahead first, e.g. AskUserQuestion): evidence
  comment (per-lock 0-table) → tick every box (`gh issue view --json body | sed 's/^- \[ \]/- [x]/'`
  → `gh issue edit --body-file`) → `gh issue close --reason completed`.
