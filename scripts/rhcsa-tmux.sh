#!/usr/bin/env bash
set -euo pipefail

SESSION="${SESSION:-rhcsa}"
VM1_HOST="${VM1_HOST:-vm1}"
VM2_HOST="${VM2_HOST:-vm2}"
FORCE="${FORCE:-0}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
need tmux
need ssh

if tmux has-session -t "$SESSION" 2>/dev/null; then
  if [[ "$FORCE" == "1" ]]; then
    tmux kill-session -t "$SESSION"
  else
    exec tmux attach -t "$SESSION"
  fi
fi

tmux new-session -d -s "$SESSION" -n lab

# Pane 0 (left): host shell

# Split right (pane 1): vm1
tmux split-window -h -t "$SESSION:0.0"
tmux send-keys -t "$SESSION:0.1" "ssh $VM1_HOST" C-m

# Split pane 1 vertically (pane 2): vm2
tmux split-window -v -t "$SESSION:0.1"
tmux send-keys -t "$SESSION:0.2" "ssh $VM2_HOST" C-m

tmux select-pane -t "$SESSION:0.0" -T "host" 2>/dev/null || true
tmux select-pane -t "$SESSION:0.1" -T "vm1" 2>/dev/null || true
tmux select-pane -t "$SESSION:0.2" -T "vm2" 2>/dev/null || true

tmux select-pane -t "$SESSION:0.0"
exec tmux attach -t "$SESSION"
