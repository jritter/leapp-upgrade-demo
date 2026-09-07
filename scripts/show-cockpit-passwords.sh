#!/usr/bin/env bash
# Fetch and display the Cockpit passwords for the LEAPP demo VMs.
# Usage: ./scripts/show-cockpit-passwords.sh [all|rhel8|rhel9]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lab/common.sh
source "${REPO_ROOT}/lab/common.sh"

SELECTION="${1:-all}"

case "${SELECTION}" in
  all)   PROFILES=(rhel8 rhel9) ;;
  rhel8) PROFILES=(rhel8) ;;
  rhel9) PROFILES=(rhel9) ;;
  *) echo "Usage: $0 [all|rhel8|rhel9]" >&2; exit 1 ;;
esac

for profile in "${PROFILES[@]}"; do
  name="$(vm_name_for "${profile}")"
  ip="$(guest_ipv4 "${name}" || true)"

  if [[ -z "${ip}" ]]; then
    echo "${name}: IP not found (is the VM running?)"
    continue
  fi

  pass="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q \
    "${VM_USER}@${ip}" "cat ~/.cockpit-password 2>/dev/null" 2>/dev/null || true)"

  if [[ -n "${pass}" ]]; then
    echo "${name} (${ip}):  ${pass}"
    echo "  Cockpit: https://${ip}:9090"
  else
    echo "${name} (${ip}):  password file not found"
  fi
done
