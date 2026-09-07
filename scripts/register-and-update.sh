#!/usr/bin/env bash
# Register systems with Red Hat CDN, run Insights, update all packages, and reboot.
#
# Usage:
#   ./scripts/register-and-update.sh                 # all leapp_targets
#   ./scripts/register-and-update.sh leapp-rhel8     # single host
#
# Required environment variables:
#   RHSM_ORG            Red Hat Subscription Manager org ID
#   RHSM_ACTIVATIONKEY  Activation key for registration
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.env"
  set +a
fi

LIMIT="${1:-}"
PLAYBOOK="playbooks/00-register-and-update.yml"

if [[ -z "${RHSM_ORG:-}" || -z "${RHSM_ACTIVATIONKEY:-}" ]]; then
  cat <<'EOF' >&2
Error: RHSM_ORG and RHSM_ACTIVATIONKEY must be set.

  export RHSM_ORG="your_org_id"
  export RHSM_ACTIVATIONKEY="your_activation_key"
  ./scripts/register-and-update.sh
EOF
  exit 1
fi

# Source shared EE / navigator checks from run-with-navigator.sh context
EE_IMAGE="${EE_IMAGE:-localhost/leapp-upgrade-ee:2.16}"

NAV_ARGS=(run "${PLAYBOOK}" --mode stdout)
NAV_ARGS+=(-- -e "rhsm_org=${RHSM_ORG}" -e "rhsm_activationkey=${RHSM_ACTIVATIONKEY}")
if [[ -n "${LIMIT}" ]]; then
  NAV_ARGS+=(--limit "${LIMIT}")
fi

echo "==> ansible-navigator ${NAV_ARGS[*]}"
exec ansible-navigator "${NAV_ARGS[@]}"
