#!/usr/bin/env bash
# Wait until a libvirt guest has an IPv4 lease and accepts SSH.
# Usage: ./lab/wait-ssh.sh <domain-name> [timeout-seconds]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

NAME="${1:-}"
TIMEOUT="${2:-300}"
[[ -n "${NAME}" ]] || die "usage: $0 <domain-name> [timeout-seconds]"

require_cmd virsh
require_cmd ssh

deadline=$((SECONDS + TIMEOUT))
ip=""

echo -n "Waiting for IPv4 lease"
while (( SECONDS < deadline )); do
  ip="$(guest_ipv4 "${NAME}")"
  if [[ -n "${ip}" ]]; then
    echo " -> ${ip}"
    break
  fi
  echo -n "."
  sleep 3
done
[[ -n "${ip}" ]] || die "timed out waiting for IPv4 on ${NAME}"

echo -n "Waiting for SSH on ${ip}"
while (( SECONDS < deadline )); do
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=3 -o BatchMode=yes \
      "${VM_USER}@${ip}" "test -f /var/lib/cloud/instance/leap-lab-ready || true" 2>/dev/null; then
    # Prefer ready marker when present; accept plain SSH as sufficient after cloud-init network
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 -o BatchMode=yes \
        "${VM_USER}@${ip}" "true" 2>/dev/null; then
      echo " -> ok"
      exit 0
    fi
  fi
  echo -n "."
  sleep 3
done

die "timed out waiting for SSH on ${NAME} (${ip})"
