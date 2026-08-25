#!/usr/bin/env bash
# Record the LEAPP demo with asciinema inside a tmux session.
# Pane 0: ansible playbook output (demo.sh)
# Pane 1: RHEL 8 VM console
# Pane 2: RHEL 9 VM console
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECORDING_DIR="${REPO_ROOT}/recordings"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SELECTION="${1:-all}"
RECORDING_FILE="${RECORDING_DIR}/leapp-demo-${SELECTION}-${TIMESTAMP}.cast"
SESSION_NAME="leapp-demo"

for cmd in asciinema tmux; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "Error: ${cmd} is not installed." >&2
    echo "Install it with:  sudo dnf install ${cmd}" >&2
    exit 1
  fi
done

mkdir -p "${RECORDING_DIR}"

# Kill a leftover session with the same name
tmux kill-session -t "${SESSION_NAME}" 2>/dev/null || true

# --- Build the tmux session (detached) ---

tmux new-session -d -s "${SESSION_NAME}" -x "$(tput cols)" -y "$(tput lines)"
tmux split-window -v -t "${SESSION_NAME}"
tmux split-window -v -t "${SESSION_NAME}"
tmux select-layout -t "${SESSION_NAME}" even-vertical

# Pane titles
tmux set-option -t "${SESSION_NAME}" pane-border-status top
tmux set-option -t "${SESSION_NAME}" pane-border-format " #{pane_index}: #{T:pane_title} "
tmux select-pane -t "${SESSION_NAME}:0.0" -T "Ansible Playbook"
tmux select-pane -t "${SESSION_NAME}:0.1" -T "RHEL 8 Console"
tmux select-pane -t "${SESSION_NAME}:0.2" -T "RHEL 9 Console"

# Status bar
tmux set-option -t "${SESSION_NAME}" status-style "bg=colour235,fg=colour248"
tmux set-option -t "${SESSION_NAME}" status-left "#[bg=colour25,fg=white,bold] LEAPP Demo #[default] "
tmux set-option -t "${SESSION_NAME}" status-left-length 30
tmux set-option -t "${SESSION_NAME}" status-right "#[fg=colour248] %H:%M  %d-%b-%Y "
tmux set-option -t "${SESSION_NAME}" status-right-length 30
tmux set-option -t "${SESSION_NAME}" window-status-current-format ""
tmux set-option -t "${SESSION_NAME}" window-status-format ""

# Pane 0: run the demo, then kill the tmux session so asciinema stops
tmux send-keys -t "${SESSION_NAME}:0.0" \
  "${REPO_ROOT}/scripts/demo.sh ${SELECTION}; sleep 10; tmux kill-session -t ${SESSION_NAME}" C-m

# Panes 1 & 2: VM consoles
tmux send-keys -t "${SESSION_NAME}:0.1" "virsh console leapp-rhel8" C-m
tmux send-keys -t "${SESSION_NAME}:0.2" "virsh console leapp-rhel9" C-m

sleep 2
tmux send-keys -t "${SESSION_NAME}:0.1" C-d
tmux send-keys -t "${SESSION_NAME}:0.2" C-d

# Focus pane 0
tmux select-pane -t "${SESSION_NAME}:0.0"

# --- Record the tmux session with asciinema ---

echo "Recording to: ${RECORDING_FILE}"
echo "Starting asciinema + tmux session..."

asciinema rec \
  --title "LEAPP Upgrade Demo (${SELECTION})" \
  --command "tmux attach-session -t ${SESSION_NAME}" \
  "${RECORDING_FILE}"

echo
echo "Recording saved to: ${RECORDING_FILE}"
echo "Play it back with:  asciinema play ${RECORDING_FILE}"
echo "Upload it with:     asciinema upload ${RECORDING_FILE}"
