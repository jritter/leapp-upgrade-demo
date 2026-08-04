#!/usr/bin/env bash
# Run a demo playbook via ansible-navigator + the LEAPP execution environment.
# ansible-core 2.16 in the EE can still manage RHEL 8; host ansible-core 2.20 cannot.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

PLAYBOOK="${1:-}"
LIMIT="${2:-}"
EE_IMAGE="${EE_IMAGE:-localhost/leapp-upgrade-ee:2.16}"

[[ -n "${PLAYBOOK}" ]] || {
  cat <<'EOF' >&2
Usage: ./scripts/run-with-navigator.sh <playbook> [limit]

Examples:
  ./scripts/run-with-navigator.sh playbooks/00-prepare.yml leapp-rhel8
  ./scripts/run-with-navigator.sh playbooks/01-analysis.yml leapp-rhel9
EOF
  exit 1
}

if ! command -v ansible-navigator >/dev/null 2>&1; then
  cat <<'EOF' >&2
ERROR: ansible-navigator not found on PATH.

On Fedora, install into a venv (there is no ansible-navigator RPM):
  python3 -m venv venv_ansible
  ./venv_ansible/bin/pip install ansible-navigator ansible-builder
  source venv_ansible/bin/activate
EOF
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "ERROR: podman is required to run the execution environment" >&2
  exit 1
fi

if ! podman image exists "${EE_IMAGE}" 2>/dev/null; then
  if ! podman info >/dev/null 2>&1; then
    echo "ERROR: podman is not usable (is the service running?)" >&2
    exit 1
  fi
  cat <<EOF >&2
ERROR: execution environment image not found: ${EE_IMAGE}

Build it first:
  ./scripts/build-ee.sh
EOF
  exit 1
fi

NAV_ARGS=(run "${PLAYBOOK}" --mode stdout)
if [[ -n "${LIMIT}" ]]; then
  NAV_ARGS+=(-- --limit "${LIMIT}")
fi

echo "==> ansible-navigator ${NAV_ARGS[*]}"
exec ansible-navigator "${NAV_ARGS[@]}"
