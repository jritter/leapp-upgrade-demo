#!/usr/bin/env bash
# Destroy and recreate the LEAPP demo VMs.
# Usage: ./scripts/reset-vms.sh [all|rhel8|rhel9]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTION="${1:-all}"

case "${SELECTION}" in
  all)   PROFILES=(rhel8 rhel9) ;;
  rhel8) PROFILES=(rhel8) ;;
  rhel9) PROFILES=(rhel9) ;;
  -h|--help|help)
    cat <<'EOF' >&2
Usage: ./scripts/reset-vms.sh [all|rhel8|rhel9]

  all    Destroy and recreate both leapp-rhel8 and leapp-rhel9 (default)
  rhel8  Reset leapp-rhel8 only
  rhel9  Reset leapp-rhel9 only
EOF
    exit 1
    ;;
  *) echo "Unknown selection: ${SELECTION}" >&2; exit 1 ;;
esac

for profile in "${PROFILES[@]}"; do
  echo "=== Destroying ${profile} ==="
  "${REPO_ROOT}/lab/destroy-vm.sh" "${profile}"
  echo
  echo "=== Creating ${profile} ==="
  "${REPO_ROOT}/lab/create-vm.sh" "${profile}"
  echo
done

echo "All requested VMs have been reset."
