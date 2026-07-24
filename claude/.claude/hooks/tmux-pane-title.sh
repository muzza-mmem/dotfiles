#!/usr/bin/env bash
# Set the current tmux pane title to "<branch>  <glyph> <task>" so multiple
# Claude Code instances running in split panes are easy to tell apart.
#
# Wired up from ~/.claude/settings.json as a hook on several events; the mode
# is passed as $1:
#   prompt   (UserPromptSubmit) - task = summary of the prompt, "working" glyph
#   idle     (Stop)             - keep last task, "idle" glyph
#   waiting  (Notification)     - keep last task, "needs input" glyph
#   session  (SessionStart)     - reset, "idle" glyph
#
# The hook process inherits $TMUX_PANE, so it always targets the right pane.
# It never blocks Claude: it exits 0 no matter what.

set -u
mode="${1:-idle}"

# Not inside tmux? Nothing to do.
[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0

input="$(cat 2>/dev/null || true)"

json() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

cwd="$(json '.cwd')"
[ -n "$cwd" ] || cwd="$PWD"

# --- branch (the stable "which feature" part) -------------------------------
branch="$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [ -z "$branch" ]; then
  sha="$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)"
  if [ -n "$sha" ]; then branch="@$sha"; else branch="$(basename "$cwd")"; fi
fi
# Trim an overlong branch name.
if [ "${#branch}" -gt 24 ]; then branch="${branch:0:23}…"; fi

# --- per-pane state file (remembers the task between events) -----------------
state_dir="${TMPDIR:-/tmp}/claude-pane-title"
mkdir -p "$state_dir" 2>/dev/null || true
state_file="$state_dir/${TMUX_PANE//[^A-Za-z0-9]/_}"

case "$mode" in
  prompt)
    task="$(json '.prompt')"
    # first non-empty line, whitespace squeezed, trimmed, truncated
    task="$(printf '%s' "$task" | tr '\n\t' '  ' | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')"
    if [ "${#task}" -gt 48 ]; then task="${task:0:47}…"; fi
    printf '%s' "$task" > "$state_file" 2>/dev/null || true
    glyph="▸"
    ;;
  session)
    : > "$state_file" 2>/dev/null || true
    task=""
    glyph="·"
    ;;
  waiting)
    task="$(cat "$state_file" 2>/dev/null || true)"
    glyph="◆"
    ;;
  idle|*)
    task="$(cat "$state_file" 2>/dev/null || true)"
    glyph="✓"
    ;;
esac

if [ -n "$task" ]; then
  title="$branch  $glyph $task"
else
  title="$branch  $glyph"
fi

tmux select-pane -t "$TMUX_PANE" -T "$title" 2>/dev/null || true
exit 0
