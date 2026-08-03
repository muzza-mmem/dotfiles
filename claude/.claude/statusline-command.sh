#!/usr/bin/env bash
# Claude Code status line — mirrors the gozilla Oh My Zsh theme

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "${cwd:-$(pwd)}")

model=$(echo "$input" | jq -r '.model.display_name // empty')
# Strip capability suffixes like "(1M context)" from the display name
model=$(echo "$model" | sed -E 's/ *\([^)]*\)//g')

# --- Reusable color-coded block progress bar ----------------------------
# usage: make_bar <percentage> <width>   -> echoes "███░░ " coloured by level
make_bar() {
  local pct=$1 width=$2
  local filled empty color
  pct=$(printf "%.0f" "$pct")
  filled=$(awk -v p="$pct" -v n="$width" 'BEGIN{f=int(p*n/100+0.5); if(f<0)f=0; if(f>n)f=n; print f}')
  empty=$((width - filled))

  if   [ "$pct" -gt 70 ]; then color='\033[0;31m'        # red
  elif [ "$pct" -gt 40 ]; then color='\033[38;5;208m'    # orange
  else                         color='\033[0;32m'        # green
  fi
  local dim='\033[0;90m' reset='\033[0m'

  local f e
  f=$(printf '%*s' "$filled" '' | tr ' ' '@'); f=${f//@/█}
  e=$(printf '%*s' "$empty"  '' | tr ' ' '@'); e=${e//@/░}
  printf "%b%s%b%s%b" "$color" "$f" "$dim" "$e" "$reset"
}

# --- Context window bar (10 blocks) --------------------------------------
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
context_str=""
if [ -n "$used" ]; then
  used_rounded=$(printf "%.0f" "$used")
  bar=$(make_bar "$used_rounded" 10)
  context_str="$(printf '\033[0;90m')Ctx$(printf '\033[0m') ${bar} ${used_rounded}%"
fi

# --- Effort + thinking indicators ----------------------------------------
effort=$(echo "$input" | jq -r '.effort.level // empty')
thinking=$(echo "$input" | jq -r '.thinking.enabled // empty')
case "$effort" in
  low)    effort_short="L" ;;
  medium) effort_short="M" ;;
  high)   effort_short="H" ;;
  xhigh)  effort_short="xH" ;;
  max)    effort_short="MAX" ;;
  *)      effort_short="$effort" ;;
esac
[ -n "$effort_short" ] && model="${model:+$model }(${effort_short})"
indicators=""
[ "$thinking" = "true" ] && indicators="🧠"

# --- Rate-limit bars (10 blocks each, matching Ctx): 5-hour and 7-day ----
rl_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_5h=""
rate_7d=""
[ -n "$rl_5h" ] && rate_5h="$(printf '\033[0;90m')5h$(printf '\033[0m') $(make_bar "$rl_5h" 10) $(printf "%.0f%%" "$rl_5h")"
[ -n "$rl_7d" ] && rate_7d="$(printf '\033[0;90m')7d$(printf '\033[0m') $(make_bar "$rl_7d" 10) $(printf "%.0f%%" "$rl_7d")"

# --- Git branch and status (skipping optional locks) ---------------------
git_status=""
if git -C "${cwd:-.}" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "${cwd:-.}" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    modified=$(git -C "${cwd:-.}" --no-optional-locks diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    staged=$(git -C "${cwd:-.}" --no-optional-locks diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git -C "${cwd:-.}" --no-optional-locks ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    status_icons=""
    [ "$staged" -gt 0 ]    && status_icons="${status_icons} ✈"
    [ "$modified" -gt 0 ]  && status_icons="${status_icons} ✭"
    [ "$untracked" -gt 0 ] && status_icons="${status_icons} ✱"

    git_status="(${branch}${status_icons})"
  fi
fi

# --- Compose two lines:
#   line 1: ➜ <dir> <git> | <model> (<effort>) <thinking>
#   line 2: Ctx | 5h | 7d
sep="$(printf '\033[0;37m')|$(printf '\033[0m')"
add() { [ -n "$1" ] && line="${line:+$line $sep }$1"; }
add2() { [ -n "$1" ] && line2="${line2:+$line2 $sep }$1"; }

head="$(printf '\033[1;31m')➜$(printf '\033[0m') $(printf '\033[0;36m')${dir}$(printf '\033[0m')"
[ -n "$git_status" ] && head="${head} $(printf '\033[1;34m')${git_status}$(printf '\033[0m')"

model_str="$model"
[ -n "$indicators" ] && model_str="${model_str:+$model_str }${indicators}"

line="$head"
add "$model_str"

line2=""
add2 "$context_str"
add2 "$rate_5h"
add2 "$rate_7d"

printf "%s" "$line"
[ -n "$line2" ] && printf "\n%s" "$line2"
