#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/rhcsa-env.sh
source "$SCRIPT_DIR/rhcsa-env.sh"

TMUX_SESSION="${TMUX_SESSION:-rhcsa}"

UP="$SCRIPT_DIR/rhcsa-up.sh"
STATUS="$SCRIPT_DIR/rhcsa-status.sh"

SERVERA_LABEL="${SERVERA_NAME:-servera}"
SERVERB_LABEL="${SERVERB_NAME:-serverb}"
SERVERA_SSH_TARGET="${SERVERA_SSH_TARGET:-servera-lab}"
SERVERB_SSH_TARGET="${SERVERB_SSH_TARGET:-serverb-lab}"

require_cmd tmux
require_cmd ssh

[[ -x "$UP" ]] || { echo "ERROR: not executable: $UP" >&2; exit 1; }
[[ -x "$STATUS" ]] || { echo "ERROR: not executable: $STATUS" >&2; exit 1; }

if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  exec tmux attach -t "$TMUX_SESSION"
fi

echo "[host] bringing lab up before tmux session creation..."
"$UP"
echo
echo "[host] status:"
"$STATUS" || true
echo

tmux new-session -d -s "$TMUX_SESSION" -n lab

HOST_PANE="$(tmux display-message -p -t "$TMUX_SESSION:0.0" '#{pane_id}')"
SERVERA_PANE="$(tmux split-window -h -P -F '#{pane_id}' -t "$HOST_PANE")"
SERVERB_PANE="$(tmux split-window -v -P -F '#{pane_id}' -t "$SERVERA_PANE")"

tmux set-window-option -t "$TMUX_SESSION:0" main-pane-width 65%
tmux select-layout -t "$TMUX_SESSION:0" main-vertical

tmux set-option -t "$TMUX_SESSION" status on
tmux set-option -t "$TMUX_SESSION" status-left "#[bold] RHCSA #[default]"
tmux set-option -t "$TMUX_SESSION" status-right "Ctrl-b: arrows=panes | d=detach | c=new window"

tmux select-pane -t "$HOST_PANE" -T "host" 2>/dev/null || true
tmux select-pane -t "$SERVERA_PANE" -T "$SERVERA_LABEL" 2>/dev/null || true
tmux select-pane -t "$SERVERB_PANE" -T "$SERVERB_LABEL" 2>/dev/null || true

tmux send-keys -t "$SERVERA_PANE" "ssh $SERVERA_SSH_TARGET" C-m
tmux send-keys -t "$SERVERB_PANE" "ssh $SERVERB_SSH_TARGET" C-m

tmux select-pane -t "$HOST_PANE"
exec tmux attach -t "$TMUX_SESSION"