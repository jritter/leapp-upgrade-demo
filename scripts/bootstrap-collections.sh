#!/usr/bin/env bash
# Optional host-side install of infra.leapp (or a lab-local alias of infra.leapp).
# Prefer ./scripts/build-ee.sh + ansible-navigator; collections are baked into the EE.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTIONS_DIR="${REPO_ROOT}/collections"
mkdir -p "${COLLECTIONS_DIR}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.env"
  set +a
fi

echo "==> Prefer supported install paths when available"

if command -v rpm >/dev/null 2>&1 && rpm -q ansible-collection-redhat-leapp >/dev/null 2>&1; then
  echo "ansible-collection-redhat-leapp is already installed via RPM"
  exit 0
fi

if command -v dnf >/dev/null 2>&1 && grep -qi 'red hat\|rhel' /etc/os-release 2>/dev/null; then
  echo "Attempting: dnf install ansible-collection-redhat-leapp rhel-system-roles"
  if sudo dnf install -y ansible-collection-redhat-leapp rhel-system-roles; then
    echo "Installed infra.leapp from AppStream"
    exit 0
  fi
  echo "RPM install unavailable; continuing with Galaxy/Hub fallback"
fi

if [[ -n "${AUTOMATION_HUB_TOKEN:-}" ]]; then
  echo "Installing infra.leapp from Automation Hub"
  mkdir -p "${HOME}/.ansible"
  cat > "${HOME}/.ansible/galaxy_token" <<EOF
token: ${AUTOMATION_HUB_TOKEN}
EOF
  ansible-galaxy collection install \
    infra.leapp redhat.rhel_system_roles \
    -p "${COLLECTIONS_DIR}" \
    -s https://console.redhat.com/api/automation-hub/ \
    --force
  echo "Installed infra.leapp into ${COLLECTIONS_DIR}"
  exit 0
fi

echo "Lab fallback: install infra.leapp from Galaxy and expose as infra.leapp"
ansible-galaxy collection install -r "${REPO_ROOT}/requirements.yml" -p "${COLLECTIONS_DIR}" --force

SRC="${COLLECTIONS_DIR}/ansible_collections/infra/leapp"
DST_NS="${COLLECTIONS_DIR}/ansible_collections/redhat"
DST="${DST_NS}/leapp"

[[ -d "${SRC}" ]] || {
  echo "ERROR: expected ${SRC} after Galaxy install" >&2
  exit 1
}

rm -rf "${DST}"
mkdir -p "${DST_NS}"
cp -a "${SRC}" "${DST}"

# Mirror the downstream RPM rename so playbooks can use infra.leapp.*
find "${DST}" -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.md' -o -name '*.py' -o -name '*.rst' \) -print0 \
  | xargs -0 sed -i \
    -e 's/infra\.leapp/infra.leapp/g' \
    -e "s/leapp_system_roles_collection: fedora.linux_system_roles/leapp_system_roles_collection: redhat.rhel_system_roles/g" \
    -e "s/default('fedora.linux_system_roles')/default('redhat.rhel_system_roles')/g" \
    -e 's/| fedora.linux_system_roles |/| redhat.rhel_system_roles |/g'

if [[ -f "${DST}/galaxy.yml" ]]; then
  sed -i \
    -e 's/^namespace: infra/namespace: redhat/' \
    -e 's/"fedora\.linux_system_roles"/"redhat.rhel_system_roles"/' \
    "${DST}/galaxy.yml"
fi

# Provide redhat.rhel_system_roles alias from fedora.linux_system_roles when needed
FSSR="${COLLECTIONS_DIR}/ansible_collections/fedora/linux_system_roles"
RHSR_NS="${COLLECTIONS_DIR}/ansible_collections/redhat"
RHSR="${RHSR_NS}/rhel_system_roles"
if [[ -d "${FSSR}" && ! -d "${RHSR}" ]]; then
  mkdir -p "${RHSR_NS}"
  cp -a "${FSSR}" "${RHSR}"
  if [[ -f "${RHSR}/galaxy.yml" ]]; then
    sed -i -e 's/^namespace: fedora/namespace: redhat/' \
      -e 's/^name: linux_system_roles/name: rhel_system_roles/' \
      "${RHSR}/galaxy.yml" || true
  fi
fi

echo "infra.leapp is available under ${DST}"
echo "Verify with: ansible-galaxy collection list | grep leapp"
