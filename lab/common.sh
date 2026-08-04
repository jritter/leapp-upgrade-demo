#!/usr/bin/env bash
# Shared helpers for leapp-upgrade-demo lab scripts.
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LAB_DIR}/.." && pwd)"

# Load optional local config and repo .env (RHSM credentials)
if [[ -f "${LAB_DIR}/config.env" ]]; then
  # shellcheck source=/dev/null
  source "${LAB_DIR}/config.env"
elif [[ -f "${LAB_DIR}/config.env.example" ]]; then
  # shellcheck source=/dev/null
  source "${LAB_DIR}/config.env.example"
fi

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.env"
  set +a
fi

LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
LIBVIRT_NETWORK="${LIBVIRT_NETWORK:-default}"
IMAGES_DIR="${IMAGES_DIR:-${LAB_DIR}/images}"
DISKS_DIR="${DISKS_DIR:-${LAB_DIR}/disks}"
CLOUD_INIT_DIR="${CLOUD_INIT_DIR:-${LAB_DIR}/cloud-init/generated}"
RHEL8_IMAGE="${RHEL8_IMAGE:-${IMAGES_DIR}/rhel-8.10-x86_64-kvm.qcow2}"
RHEL9_IMAGE="${RHEL9_IMAGE:-${IMAGES_DIR}/rhel-9.6-x86_64-kvm.qcow2}"
VM_VCPUS="${VM_VCPUS:-2}"
VM_MEMORY_MIB="${VM_MEMORY_MIB:-4096}"
VM_DISK_GIB="${VM_DISK_GIB:-40}"
VM_USER="${VM_USER:-cloud-user}"

mkdir -p "${IMAGES_DIR}" "${DISKS_DIR}" "${CLOUD_INIT_DIR}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

resolve_ssh_pubkey() {
  if [[ -n "${SSH_PUBKEY:-}" ]]; then
    printf '%s\n' "${SSH_PUBKEY}"
    return
  fi
  if [[ -n "${SSH_PUBKEY_FILE:-}" && -f "${SSH_PUBKEY_FILE}" ]]; then
    cat "${SSH_PUBKEY_FILE}"
    return
  fi
  for candidate in "${HOME}/.ssh/id_ed25519.pub" "${HOME}/.ssh/id_rsa.pub"; do
    if [[ -f "${candidate}" ]]; then
      cat "${candidate}"
      return
    fi
  done
  die "no SSH public key found; set SSH_PUBKEY or SSH_PUBKEY_FILE"
}

vm_name_for() {
  case "$1" in
    rhel8) echo "leapp-rhel8" ;;
    rhel9) echo "leapp-rhel9" ;;
    *) die "unknown profile '$1' (expected rhel8 or rhel9)" ;;
  esac
}

base_image_for() {
  case "$1" in
    rhel8) echo "${RHEL8_IMAGE}" ;;
    rhel9) echo "${RHEL9_IMAGE}" ;;
    *) die "unknown profile '$1'" ;;
  esac
}

os_variant_for() {
  case "$1" in
    rhel8) echo "rhel8-unknown" ;;
    rhel9) echo "rhel9-unknown" ;;
    *) die "unknown profile '$1'" ;;
  esac
}

guest_ipv4() {
  local name="$1"
  local ip=""
  # Prefer the guest agent / lease info from libvirt
  ip="$(virsh --connect "${LIBVIRT_URI}" domifaddr "${name}" --source lease 2>/dev/null \
    | awk '/ipv4/ {print $4}' | head -n1 | cut -d/ -f1 || true)"
  if [[ -z "${ip}" ]]; then
    ip="$(virsh --connect "${LIBVIRT_URI}" domifaddr "${name}" 2>/dev/null \
      | awk '/ipv4/ {print $4}' | head -n1 | cut -d/ -f1 || true)"
  fi
  printf '%s' "${ip}"
}

build_cloudinit_iso() {
  local name="$1"
  local out_iso="$2"
  local ssh_pubkey rhsm_org rhsm_key instance_id workdir

  require_cmd sed
  [[ -n "${RHSM_ORG:-}" ]] || die "RHSM_ORG is not set (see .env.example)"
  [[ -n "${RHSM_ACTIVATIONKEY:-}" ]] || die "RHSM_ACTIVATIONKEY is not set (see .env.example)"

  ssh_pubkey="$(resolve_ssh_pubkey | tr -d '\r')"
  rhsm_org="${RHSM_ORG}"
  rhsm_key="${RHSM_ACTIVATIONKEY}"
  instance_id="$(date +%s)"
  workdir="$(mktemp -d)"

  # Escape sed replacement metacharacters in the pubkey / secrets
  local esc_pubkey esc_org esc_key
  esc_pubkey="$(printf '%s' "${ssh_pubkey}" | sed -e 's/[&\\]/\\&/g')"
  esc_org="$(printf '%s' "${rhsm_org}" | sed -e 's/[&\\]/\\&/g')"
  esc_key="$(printf '%s' "${rhsm_key}" | sed -e 's/[&\\]/\\&/g')"

  sed \
    -e "s|__HOSTNAME__|${name}|g" \
    -e "s|__VM_USER__|${VM_USER}|g" \
    -e "s|__SSH_PUBKEY__|${esc_pubkey}|g" \
    -e "s|__RHSM_ORG__|${esc_org}|g" \
    -e "s|__RHSM_ACTIVATIONKEY__|${esc_key}|g" \
    "${LAB_DIR}/cloud-init/user-data.yaml.in" > "${workdir}/user-data"

  sed \
    -e "s|__HOSTNAME__|${name}|g" \
    -e "s|__INSTANCE_ID__|${instance_id}|g" \
    "${LAB_DIR}/cloud-init/meta-data.yaml.in" > "${workdir}/meta-data"

  if command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds "${out_iso}" "${workdir}/user-data" "${workdir}/meta-data"
  elif command -v genisoimage >/dev/null 2>&1; then
    genisoimage -output "${out_iso}" -volid cidata -joliet -rock \
      "${workdir}/user-data" "${workdir}/meta-data" >/dev/null
  elif command -v mkisofs >/dev/null 2>&1; then
    mkisofs -output "${out_iso}" -volid cidata -joliet -rock \
      "${workdir}/user-data" "${workdir}/meta-data" >/dev/null
  elif command -v xorriso >/dev/null 2>&1; then
    xorriso -as mkisofs -o "${out_iso}" -V cidata -J -R \
      "${workdir}/user-data" "${workdir}/meta-data" >/dev/null
  else
    rm -rf "${workdir}"
    die "need cloud-localds, genisoimage, mkisofs, or xorriso to build cloud-init ISO"
  fi

  cp "${workdir}/user-data" "${CLOUD_INIT_DIR}/${name}-user-data"
  cp "${workdir}/meta-data" "${CLOUD_INIT_DIR}/${name}-meta-data"
  rm -rf "${workdir}"
}
