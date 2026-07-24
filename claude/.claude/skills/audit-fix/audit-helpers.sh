#!/usr/bin/env bash
# audit-helpers.sh — the fiddly/dangerous mechanics for the audit-fix skill.
# Behaviour lifted from ~/code/audit-tools/audit-fix (the retired `af` tool).
# The workflow itself lives in SKILL.md; this script is ONLY the error-prone bits:
#   baseline | diff | check-pkg | override
set -euo pipefail

STATE_DIR="${AUDIT_FIX_STATE_DIR:-$HOME/.cache/audit-fix}"

die()  { echo "audit-helpers: $*" >&2; exit 1; }
info() { echo "$*" >&2; }

# Derive a stable "<repo>--<branch>" state key from a worktree dir.
state_key() {
  local dir="$1"
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo: $dir"
  local common main_root repo branch
  common="$(git -C "$dir" rev-parse --git-common-dir)"
  case "$common" in /*) ;; *) common="$dir/$common" ;; esac   # may be relative
  main_root="$(cd "$common/.." && pwd)"
  repo="$(basename "$main_root")"
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
  echo "${repo}--${branch//\//-}"
}

baseline_file() { echo "$STATE_DIR/$(state_key "$1").baseline.json"; }

# One-line severity summary from an npm-audit --json file (or '?').
audit_severity_line() {
  jq -r 'if .metadata.vulnerabilities then .metadata.vulnerabilities
           | "\(.total) total — \(.critical) critical, \(.high) high, \(.moderate) moderate, \(.low) low"
         else "?" end' "$1" 2>/dev/null || echo '?'
}

do_baseline() {
  local dir="${1:-.}"
  command -v jq >/dev/null || die "jq is required"
  mkdir -p "$STATE_DIR"
  local bf; bf="$(baseline_file "$dir")"
  ( cd "$dir" && npm audit --json ) > "$bf" 2>/dev/null || true
  info "==> baseline severity: $(audit_severity_line "$bf")"
  info "==> baseline saved: $bf"
}

do_diff() {
  local dir="${1:-.}"
  command -v jq >/dev/null || die "jq is required"
  local bf tmp; bf="$(baseline_file "$dir")"; tmp="$(mktemp)"
  ( cd "$dir" && npm audit --json ) > "$tmp" 2>/dev/null || true
  local now base
  now="$(jq '(.vulnerabilities // {}) | length' "$tmp" 2>/dev/null || echo '?')"
  if [ -f "$bf" ]; then
    base="$(jq '(.vulnerabilities // {}) | length' "$bf" 2>/dev/null || echo '?')"
  else
    base="(no baseline)"
  fi
  info "==> vulnerable packages: baseline ${base} -> current ${now}"
  info "==> severity (baseline): $(audit_severity_line "$bf")"
  info "==> severity (current):  $(audit_severity_line "$tmp")"
  rm -f "$tmp"
}

# Exit 0 iff <target> is absent from npm audit; else exit 1 and print the offender.
do_check_pkg() {
  local dir="${1:-.}" target="${2:-}"
  [ -n "$target" ] || die "usage: check-pkg <dir> <package|GHSA-…|CVE-…>"
  command -v jq >/dev/null || die "jq is required"
  local tmp; tmp="$(mktemp)"
  ( cd "$dir" && npm audit --json ) > "$tmp" 2>/dev/null || true

  local rc=0
  case "$target" in
    GHSA-*|CVE-*|ghsa-*|cve-*)
      local owners
      owners="$(jq -r --arg id "$target" '
        [ (.vulnerabilities // {}) | to_entries[]
          | .key as $pkg | (.value.via[]? | objects)
          | select( ((.url  // "") | ascii_downcase | contains($id | ascii_downcase))
                 or ((.name // "") | ascii_downcase) == ($id | ascii_downcase)
                 or ((.source | tostring) == $id) )
          | $pkg ] | unique | .[]' "$tmp" 2>/dev/null || true)"
      if [ -z "$owners" ]; then
        info "==> remediated: advisory $target not present"
      else
        info "==> STILL PRESENT: $target via package(s): $(echo "$owners" | tr '\n' ' ')"
        rc=1
      fi
      ;;
    *)
      if jq -e --arg p "$target" '(.vulnerabilities // {}) | has($p) | not' "$tmp" >/dev/null 2>&1; then
        info "==> remediated: '$target' not in npm audit"
      else
        info "==> STILL PRESENT: '$target'"
        jq --arg p "$target" '.vulnerabilities[$p]
          | {severity, range, via: (.via | map(if type=="object" then .title else . end))}' \
          "$tmp" >&2 2>/dev/null || true
        ( cd "$dir" && npm ls "$target" ) >&2 2>/dev/null || true
        rc=1
      fi
      ;;
  esac
  rm -f "$tmp"
  return "$rc"
}

# Surgical re-resolve of one already-locked node so a freshly-added root override applies.
do_override() {
  local force=false
  [ "${1:-}" = "--force" ] && { force=true; shift; }
  local dir="${1:-.}" path="${2:-}"
  [ -n "$path" ] || die "usage: override [--force] <dir> <lock-path>  (e.g. node_modules/next/node_modules/postcss)"
  command -v jq >/dev/null || die "jq is required"
  [ -f "$dir/package-lock.json" ] || die "no package-lock.json in $dir"
  local leaf; leaf="$(basename "$path")"

  # Override-presence guard: a re-resolve without a matching root override is a no-op.
  if ! $force; then
    if ! jq -e --arg k "$leaf" \
          '[(.overrides? // {}) | .. | objects | keys[]] | index($k) != null' \
          "$dir/package.json" >/dev/null 2>&1; then
      die "no root override for '$leaf' in package.json — add it first (a re-resolve without one is a no-op), or pass --force"
    fi
  fi

  # Lock-entry guard: the entry must exist, else the delete is a silent no-op on a typo.
  jq -e --arg p "$path" '.packages | has($p)' "$dir/package-lock.json" >/dev/null 2>&1 \
    || die "no lock entry '$path' in package-lock.json — check the exact path via: npm ls $leaf"

  info "==> deleting lock entry: $path"
  local tmp; tmp="$(mktemp)"
  jq --arg p "$path" 'del(.packages[$p])' "$dir/package-lock.json" > "$tmp" \
    && mv "$tmp" "$dir/package-lock.json" \
    || { rm -f "$tmp"; die "failed to edit package-lock.json"; }

  info "==> removing installed dir: $path"
  rm -rf "${dir:?}/$path"

  info "==> re-resolving with npm install"
  ( cd "$dir" && npm install ) >&2 || die "npm install failed"

  info "==> package-lock.json delta:"
  git -C "$dir" diff --numstat -- package-lock.json >&2 || true
  info "==> done — confirm with: audit-helpers.sh check-pkg $dir $leaf"
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    baseline)   do_baseline "$@" ;;
    diff)       do_diff "$@" ;;
    check-pkg)  do_check_pkg "$@" ;;
    override)   do_override "$@" ;;
    ''|-h|--help|help)
      cat >&2 <<'EOF'
audit-helpers.sh — fiddly mechanics for the audit-fix skill
  baseline <dir>                          capture npm audit --json baseline + severity
  diff <dir>                              current vs baseline: counts + severity
  check-pkg <dir> <pkg|GHSA-…|CVE-…>       exit 0 iff target absent from npm audit (else 1)
  override [--force] <dir> <lock-path>    surgical single-node re-resolve
EOF
      ;;
    *) die "unknown command: $cmd (see: audit-helpers.sh help)" ;;
  esac
}
main "$@"
