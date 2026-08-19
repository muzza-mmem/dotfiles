#!/usr/bin/env bash
#
# on-pane-event.sh - herdr runs this on pane.created and pane.closed. It works
# out which tab just changed shape and hands it to herdr-even-panes.
#
# pane.created is easy: herdr sets HERDR_TAB_ID to the new pane's tab. pane.closed
# is not - the pane is gone, so the event carries only its id and workspace, and
# "the focused tab" is the wrong guess: closing a whole tab fires one pane.closed
# per pane and would then flatten whichever unrelated tab you land on. So we keep
# our own pane -> tab map in the plugin state dir, refreshed on every event, and
# use it to name the tab a closed pane used to live in. A tab that has itself
# gone by then is skipped, which is what makes closing a tab a no-op here.
#
set -euo pipefail

SOCKET=${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}
STATE=${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr/plugins/muzza.even-panes}
PANE_TABS="$STATE/pane-tabs.json"

# herdr's own PATH reaches ~/.local/bin, but fall back to the stow path so a
# hand-run of this script behaves the same.
EVEN=$(command -v herdr-even-panes || printf '%s' "$HOME/.local/bin/herdr-even-panes")

herdr_api() {
	printf '%s\n' "$1" | timeout 5 nc -UN "$SOCKET" | head -1
}

[[ -S $SOCKET ]] || exit 0

# The map as it was before this event, then the map as it is now. Written
# through a temp file so a second event landing mid-write reads one or the
# other, never a half-file.
previous='{}'
if [[ -f $PANE_TABS ]]; then
	previous=$(cat "$PANE_TABS")
fi

current=$(herdr_api '{"id":"panes","method":"pane.list","params":{}}' |
	jq -c '[.result.panes[]? | {key: .pane_id, value: .tab_id}] | from_entries')
[[ -n $current ]] || exit 0
mkdir -p "$STATE"
printf '%s\n' "$current" >"$PANE_TABS.tmp" && mv "$PANE_TABS.tmp" "$PANE_TABS"

case "${HERDR_PLUGIN_EVENT:-}" in
pane.created)
	tab=${HERDR_TAB_ID:-}
	;;
pane.closed)
	pane=${HERDR_PANE_ID:-}
	tab=$(jq -r --arg p "$pane" '.[$p] // empty' <<<"$previous")
	# The tab went with it (a whole tab or workspace was closed): nothing to even.
	[[ -n $tab ]] && jq -e --arg t "$tab" 'any(.[]; . == $t)' <<<"$current" >/dev/null || exit 0
	;;
*) exit 0 ;;
esac

[[ -n $tab ]] || exit 0
"$EVEN" --skip-zoomed "$tab"
