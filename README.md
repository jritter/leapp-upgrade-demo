# LEAPP Upgrade Demo (`redhat.leapp`)

Local lab that provisions disposable RHEL guests with **libvirt** (`virt-install` + cloud-init) and walks through the supported **`redhat.leapp`** Ansible collection for in-place upgrades against **Red Hat CDN**:

| Path | Guest | Limit |
|------|--------|--------|
| RHEL 8 → RHEL 9 | `leapp-rhel8` | `--limit leapp-rhel8` |
| RHEL 9 → RHEL 10 | `leapp-rhel9` | `--limit leapp-rhel9` |

Workflow: **prepare → analysis → remediate → analysis → upgrade → verify**.

Playbooks run through **ansible-navigator** and a custom **execution environment** (`localhost/leapp-upgrade-ee:2.16`). That EE pins **ansible-core 2.16**, which can still manage RHEL 8; recent host ansible-core (for example 2.20 on Fedora) cannot talk to RHEL 8's `python3-dnf` / `platform-python`.

## Prerequisites

**Host**

- KVM / libvirt (`virsh`, `virt-install`, `qemu-img`)
- One of: `cloud-localds`, `genisoimage`, `mkisofs`, or `xorriso` (cloud-init ISO)
- Podman
- `ansible-navigator` and `ansible-builder` from a local venv (see below) — Fedora has no `ansible-navigator` RPM
- SSH key pair (`~/.ssh/id_ed25519.pub` or `id_rsa.pub`)
- Enough resources for Leapp guests: **2 vCPU, 4 GiB RAM, ≥40 GiB disk** each

**Red Hat**

- Active subscription (Developer subscription is enough)
- Activation key + organization ID from [console.redhat.com](https://console.redhat.com)
- Registry login for the EE base image: `podman login registry.redhat.io`
- Automation Hub offline token to bake `redhat.leapp` into the EE: [Automation Hub token](https://console.redhat.com/ansible/automation-hub/token)
- RHEL **KVM guest** qcow2 images (not the installer ISO), for example:
  - `rhel-8.10-x86_64-kvm.qcow2`
  - `rhel-9.6-x86_64-kvm.qcow2`

Place images under `lab/images/` (or set `RHEL8_IMAGE` / `RHEL9_IMAGE` in `lab/config.env`).

## Quick start

```bash
cp .env.example .env
# edit RHSM_ORG, RHSM_ACTIVATIONKEY, and AUTOMATION_HUB_TOKEN (or ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN)

cp lab/config.env.example lab/config.env
# point RHEL8_IMAGE / RHEL9_IMAGE at your qcow2 files if needed

# Tooling (Fedora): no ansible-navigator RPM — use a repo-local venv
python3 -m venv venv_ansible
./venv_ansible/bin/pip install ansible-navigator ansible-builder
source venv_ansible/bin/activate
# ansible-navigator and ansible-builder are then on PATH via venv_ansible/bin/

podman login registry.redhat.io
chmod +x lab/*.sh scripts/*.sh
./scripts/build-ee.sh
```

Keep the venv activated (or put `venv_ansible/bin` on your `PATH`) for every later step — `build-ee.sh`, the demos, and `run-with-navigator.sh` all expect `ansible-navigator` / `ansible-builder` from that environment.

### Guided demos

```bash
source venv_ansible/bin/activate   # if this shell is new
./scripts/demo-8to9.sh             # creates leapp-rhel8 if needed, then runs the full workflow
./scripts/demo-9to10.sh            # creates leapp-rhel9 if needed, then runs the full workflow
```

### Manual steps

```bash
./lab/create-vm.sh rhel8          # or rhel9
./scripts/inventory-from-libvirt.sh

./scripts/run-with-navigator.sh playbooks/00-prepare.yml leapp-rhel8
./scripts/run-with-navigator.sh playbooks/01-analysis.yml leapp-rhel8
# review /var/log/leapp/leapp-report.txt on the guest and playbooks/host_vars/
./scripts/run-with-navigator.sh playbooks/02-remediate.yml leapp-rhel8
./scripts/run-with-navigator.sh playbooks/01-analysis.yml leapp-rhel8
./scripts/run-with-navigator.sh playbooks/03-upgrade.yml leapp-rhel8
./scripts/run-with-navigator.sh playbooks/99-verify.yml leapp-rhel8
```

Equivalent direct `ansible-navigator` calls (settings come from [`ansible-navigator.yml`](ansible-navigator.yml)):

```bash
ansible-navigator run playbooks/00-prepare.yml --mode stdout -- --limit leapp-rhel8
```

Tear down:

```bash
./lab/destroy-vm.sh rhel8
./lab/destroy-vm.sh rhel9
```

## Execution environment

[`execution-environment.yml`](execution-environment.yml) builds `localhost/leapp-upgrade-ee:2.16` from `ee-minimal-rhel9:2.16.19-1` and installs `redhat.leapp` + `redhat.rhel_system_roles` from Automation Hub (`ee/requirements.yml`).

```bash
./scripts/build-ee.sh
# or:
# export ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN="<hub-offline-token>"
# ansible-builder build -f execution-environment.yml -t localhost/leapp-upgrade-ee:2.16 \
#   --container-runtime podman --build-arg ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN
```

Do **not** run these playbooks with host `ansible-playbook` against RHEL 8 when the control node has a recent ansible-core — use the EE path above.

### Optional: host-side collections

`scripts/bootstrap-collections.sh` can still install `redhat.leapp` on the control node (RPM → Automation Hub → Galaxy `infra.leapp` rename). That is not required for the navigator/EE workflow; collections are already in the image.

## Layout

```
lab/                  # virt-install / cloud-init / destroy helpers
inventory/            # hosts + group_vars (CDN, path-specific upgrade opts)
playbooks/            # prepare, analysis, remediate, upgrade, verify
scripts/              # EE build, navigator wrapper, inventory refresh, guided demos
ee/                   # galaxy requirements + ansible.cfg for the EE build
execution-environment.yml
ansible-navigator.yml
```

CDN defaults live in `inventory/group_vars/all.yml` (`leapp_upgrade_type: cdn`). Target versions are in:

- `inventory/group_vars/leapp_rhel8.yml` — `--target-version 9.8`
- `inventory/group_vars/leapp_rhel9.yml` — `--target 10.0`

Bump those strings when you need a newer supported minor.

## Notes

- On Fedora, use `./venv_ansible` for `ansible-navigator` / `ansible-builder` (`source venv_ansible/bin/activate`). Host `ansible-playbook` is not the supported control path for RHEL 8 guests.
- Upgrades are **long** and reboot the guest; keep the laptop powered and the libvirt network up.
- Not every inhibitor can be fixed by `redhat.leapp.remediate`; some need manual fixes before upgrade.
- Third-party / non-RHEL packages are out of scope for the upgrade role.
- Official docs:
  - [Upgrading from RHEL 8 to RHEL 9 — Ansible roles](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/upgrading_from_rhel_8_to_rhel_9/upgrading-large-deployments-by-using-ansible-roles_upgrading-from-rhel-8-to-rhel-9)
  - [Upgrading from RHEL 9 to RHEL 10 — Ansible roles](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/upgrading_from_rhel_9_to_rhel_10/upgrading-large-deployments-by-using-ansible-roles)
  - Upstream collection: [redhat-cop/infra.leapp](https://github.com/redhat-cop/infra.leapp)
