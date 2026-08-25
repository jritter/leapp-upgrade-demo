#!/usr/bin/env bash
# Build the custom LEAPP demo execution environment (ansible-core 2.16 + infra.leapp).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

EE_TAG="${EE_TAG:-localhost/leapp-upgrade-ee:2.16}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.env"
  set +a
fi

if ! command -v ansible-builder >/dev/null 2>&1; then
  cat <<'EOF' >&2
ERROR: ansible-builder not found on PATH.

Install into a venv with ansible-navigator:
  python3 -m venv venv_ansible
  ./venv_ansible/bin/pip install ansible-navigator ansible-builder
  source venv_ansible/bin/activate
EOF
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "ERROR: podman is required to build the execution environment" >&2
  exit 1
fi

TOKEN="${ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN:-${AUTOMATION_HUB_TOKEN:-}}"
if [[ -z "${TOKEN}" ]]; then
  cat <<'EOF' >&2
ERROR: Automation Hub token required to pull infra.leapp into the EE.

Set one of:
  export ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN="<hub-offline-token>"
  # or AUTOMATION_HUB_TOKEN in .env

Token URL: https://console.redhat.com/ansible/automation-hub/token
EOF
  exit 1
fi

export ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN="${TOKEN}"

echo "==> Ensuring registry.redhat.io login (base image pull)"
if ! podman pull --quiet registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9:2.16.19-1 >/dev/null 2>&1; then
  echo "Base image pull failed. Run: podman login registry.redhat.io" >&2
  exit 1
fi

echo "==> Building ${EE_TAG}"
ansible-builder build \
  -f execution-environment.yml \
  -t "${EE_TAG}" \
  --container-runtime podman \
  --build-arg ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN

echo
echo "EE ready: ${EE_TAG}"
echo "Run playbooks with: ./scripts/run-with-navigator.sh <playbook> [limit]"
