#!/usr/bin/env bash
# Guided LEAPP demo for RHEL 8 → 9 and/or RHEL 9 → 10 (via ansible-navigator EE).
# Default: upgrade both guests in one run against the leapp_targets group.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"
# shellcheck source=../lab/common.sh
source "${REPO_ROOT}/lab/common.sh"

RUN_PB="${REPO_ROOT}/scripts/run-with-navigator.sh"
SELECTION="${1:-all}"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

banner() {
  local title="$1"
  local subtitle="${2:-}"
  local width=60
  local border padded

  border=$(printf '═%.0s' $(seq 1 "${width}"))
  echo
  echo -e "${CYAN}╔${border}╗${RESET}"

  printf -v padded "%-${width}s" ""
  printf -v padded "%*s%s%*s" \
    $(( (width - ${#title}) / 2 )) "" \
    "${title}" \
    $(( (width + 1 - ${#title}) / 2 )) ""
  echo -e "${CYAN}║${RESET}${BOLD}${padded}${RESET}${CYAN}║${RESET}"

  if [[ -n "${subtitle}" ]]; then
    printf -v padded "%*s%s%*s" \
      $(( (width - ${#subtitle}) / 2 )) "" \
      "${subtitle}" \
      $(( (width + 1 - ${#subtitle}) / 2 )) ""
    echo -e "${CYAN}║${RESET}${DIM}${padded}${RESET}${CYAN}║${RESET}"
  fi

  echo -e "${CYAN}╚${border}╝${RESET}"
  echo
}

STAGE_NAMES=(
  "Prepare"
  "Analysis"
  "Remediate"
  "Re-analysis"
  "Upgrade"
  "Verify"
)
STAGE_DESCS=(
  "Install Leapp packages and configure target repositories"
  "Run leapp preupgrade to detect inhibitors and risks"
  "Apply automated fixes for known inhibitors"
  "Verify that inhibitors have been resolved"
  "Run leapp upgrade and reboot into the new RHEL version"
  "Confirm the upgrade completed successfully"
)

STAGE_DELAY=8

countdown() {
  for ((i = STAGE_DELAY; i > 0; i--)); do
    printf "\r${DIM}  Continuing in %d...${RESET} " "${i}"
    sleep 1
  done
  printf "\r%*s\r" 30 ""
}

transition() {
  local completed="$1"
  local total="$2"
  local width=60
  local line
  line=$(printf '─%.0s' $(seq 1 "${width}"))

  echo
  echo -e "${YELLOW}${line}${RESET}"

  if [[ "${completed}" -gt 0 ]]; then
    echo -e "  ${GREEN}✔ Done:${RESET}  ${BOLD}${STAGE_NAMES[$((completed - 1))]}${RESET}"
    echo -e "         ${DIM}${STAGE_DESCS[$((completed - 1))]}${RESET}"
  fi

  if [[ "${completed}" -lt "${total}" ]]; then
    [[ "${completed}" -gt 0 ]] && echo
    echo -e "  ${CYAN}▶ Next:${RESET}  ${BOLD}Stage $((completed + 1))/${total}: ${STAGE_NAMES[${completed}]}${RESET}"
    echo -e "         ${DIM}${STAGE_DESCS[${completed}]}${RESET}"
  fi

  echo -e "${YELLOW}${line}${RESET}"
  countdown
}

usage() {
  cat <<'EOF' >&2
Usage: ./scripts/demo.sh [all|rhel8|rhel9]

  all    Run the full upgrade workflow on leapp-rhel8 and leapp-rhel9 (default)
  rhel8  RHEL 8 → RHEL 9 only
  rhel9  RHEL 9 → RHEL 10 only

VMs are expected to exist already. Refresh the inventory with
  ./scripts/inventory-from-libvirt.sh
EOF
  exit 1
}

case "${SELECTION}" in
  all|rhel8|rhel9) ;;
  -h|--help|help) usage ;;
  *) usage ;;
esac

PROFILES=()
case "${SELECTION}" in
  all) PROFILES=(rhel8 rhel9) ;;
  rhel8) PROFILES=(rhel8) ;;
  rhel9) PROFILES=(rhel9) ;;
esac

if [[ "${SELECTION}" == "all" ]]; then
  LIMIT="leapp_targets"
  DEMO_TITLE="RHEL 8 → 9  &  RHEL 9 → 10"
elif [[ "${SELECTION}" == "rhel8" ]]; then
  LIMIT="leapp-rhel8"
  DEMO_TITLE="RHEL 8 → RHEL 9"
else
  LIMIT="leapp-rhel9"
  DEMO_TITLE="RHEL 9 → RHEL 10"
fi

TOTAL_STAGES=6

# ── Inventory ────────────────────────────────────────────────

echo "==> Refreshing inventory"
./scripts/inventory-from-libvirt.sh

# ── Welcome ──────────────────────────────────────────────────

banner "LEAPP In-Place Upgrade Demo" "${DEMO_TITLE} (CDN)"

echo -e "  Stages  : prepare → analysis → remediate → re-analysis → upgrade → verify"

run_pb() {
  local pb="$1"
  echo
  "${RUN_PB}" "${pb}" "${LIMIT}"
}

# ── Stage 1: Prepare ────────────────────────────────────────

transition 0 ${TOTAL_STAGES}
run_pb playbooks/00-prepare.yml

# ── Stage 2: Analysis ───────────────────────────────────────

transition 1 ${TOTAL_STAGES}
run_pb playbooks/01-analysis.yml

# ── Stage 3: Remediate ──────────────────────────────────────

transition 2 ${TOTAL_STAGES}
run_pb playbooks/02-remediate.yml

# ── Stage 4: Re-analysis ────────────────────────────────────

transition 3 ${TOTAL_STAGES}
run_pb playbooks/01-analysis.yml

# ── Stage 5: Upgrade ────────────────────────────────────────

transition 4 ${TOTAL_STAGES}
run_pb playbooks/03-upgrade.yml

# ── Stage 6: Verify ─────────────────────────────────────────

transition 5 ${TOTAL_STAGES}
run_pb playbooks/99-verify.yml

# ── Done ─────────────────────────────────────────────────────

banner "Demo Complete" "${DEMO_TITLE}"
echo -e "  ${GREEN}All stages finished for ${BOLD}${LIMIT}${RESET}${GREEN}.${RESET}"
echo
sleep 10
