#!/usr/bin/env bash
set -euo pipefail

TMUX_SESSION="${TMUX_SESSION:-rhcsa}"

# Resolve scripts relative to this file so the repo is self-contained.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SCRIPT_DIR}"

UP="$SCRIPTS_DIR/rhcsa-up.sh"
STATUS="$SCRIPTS_DIR/rhcsa-status.sh"

VM1="${VM1:-vm1}"
VM2="${VM2:-vm2}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }
require_cmd tmux
require_cmd ssh
require_cmd mktemp
require_cmd chmod

[[ -x "$UP" ]] || { echo "ERROR: not executable: $UP" >&2; exit 1; }
[[ -x "$STATUS" ]] || { echo "ERROR: not executable: $STATUS" >&2; exit 1; }

# Attach if session exists.
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  exec tmux attach -t "$TMUX_SESSION"
fi

# Small helper scripts to avoid tmux send-keys quoting issues.
HOST_SH="$(mktemp /tmp/rhcsa-host.XXXXXX.sh)"
VM1_SH="$(mktemp /tmp/rhcsa-vm1.XXXXXX.sh)"
VM2_SH="$(mktemp /tmp/rhcsa-vm2.XXXXXX.sh)"

cat >"$HOST_SH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd ~
echo "[host] bringing lab up..."
"$UP"
echo
echo "[host] status:"
"$STATUS" || true
echo
tmux wait-for -S rhcsa-ready
echo "[host] ready"
exec bash
EOF

cat >"$VM1_SH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd ~
echo "[vm1] waiting for host readiness..."
tmux wait-for rhcsa-ready
echo "[vm1] connecting..."
exec ssh "$VM1"
EOF

cat >"$VM2_SH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd ~
echo "[vm2] waiting for host readiness..."
tmux wait-for rhcsa-ready
echo "[vm2] connecting..."
exec ssh "$VM2"
EOF

chmod +x "$HOST_SH" "$VM1_SH" "$VM2_SH"

# Layout:
# 0.0 = top-left (host)
# 0.1 = bottom-left (vm1)
# 0.2 = right (vm2)
tmux new-session -d -s "$TMUX_SESSION" -n lab
tmux split-window -h -t "$TMUX_SESSION":0
tmux split-window -v -t "$TMUX_SESSION":0.0

tmux set-option -t "$TMUX_SESSION" status on
tmux set-option -t "$TMUX_SESSION" status-left "#[bold] RHCSA #[default]"
tmux set-option -t "$TMUX_SESSION" status-right "Ctrl-b: arrows=panes | d=detach | c=new window"

tmux send-keys -t "$TMUX_SESSION":0.0 "$HOST_SH" C-m
tmux send-keys -t "$TMUX_SESSION":0.1 "$VM1_SH" C-m
tmux send-keys -t "$TMUX_SESSION":0.2 "$VM2_SH" C-m

tmux select-pane -t "$TMUX_SESSION":0.0
exec tmux attach -t "$TMUX_SESSION"