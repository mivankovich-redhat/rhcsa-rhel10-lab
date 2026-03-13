#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/rhcsa-env.sh
source "$SCRIPT_DIR/rhcsa-env.sh"

SESSION="${SESSION:-rhcsa}"
FORCE="${FORCE:-0}"

require_cmd tmux
require_cmd ssh

if tmux has-session -t "$SESSION" 2>/dev/null; then
  if [[ "$FORCE" == "1" ]]; then
    tmux kill-session -t "$SESSION"
  else
    exec tmux attach -t "$SESSION"
  fi
fi

tmux new-session -d -s "$SESSION" -n lab
tmux split-window -h -t "$SESSION:0.0"
tmux send-keys -t "$SESSION:0.1" "ssh $SERVERA_SSH_TARGET" C-m
tmux split-window -v -t "$SESSION:0.1"
tmux send-keys -t "$SESSION:0.2" "ssh $SERVERB_SSH_TARGET" C-m

tmux select-pane -t "$SESSION:0.0" -T "host" 2>/dev/null || true
tmux select-pane -t "$SESSION:0.1" -T "$SERVERA_NAME" 2>/dev/null || true
tmux select-pane -t "$SESSION:0.2" -T "$SERVERB_NAME" 2>/dev/null || true

tmux select-pane -t "$SESSION:0.0"
exec tmux attach -t "$SESSION"
