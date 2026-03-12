# RHCSA RHEL 10 Lab (KVM/libvirt + NAT + 2 VMs)

A deterministic RHCSA practice lab on an Ubuntu host using KVM/libvirt with the default NAT network (`default` / `virbr0`) and **two RHEL 10 VMs**:

- `vm1` → `192.168.122.31`
- `vm2` → `192.168.122.66`

This repo uses a reset model that avoids libvirt snapshot-revert issues on UEFI/pflash guests:

- keep `*.base.qcow2` golden baselines
- reset by copying baseline → active disk and restarting VMs

---

## Source of truth

Use the **repo copies** of the scripts under `./scripts/`.

Run commands from the repo root:

```bash
cd ~/<REPO_ROOT>
```

Do not rely on older duplicate copies under `~/scripts` unless you intentionally keep both locations in sync.

---

## Preferred usage

Preferred multi-pane entry point:

```bash
TMUX_SESSION=rhcsa ./scripts/rhcsa.sh
```

What `rhcsa.sh` does:

- brings the lab up
- prints status in the host pane
- opens a tmux session
- connects panes for `vm1` and `vm2`

Simpler manual workflow:

```bash
./scripts/rhcsa-up.sh
./scripts/rhcsa-status.sh
./scripts/rhcsa-tmux.sh
```

Reset lab back to baseline:

```bash
./scripts/rhcsa-reset-to-clean.sh
```

Shut down:

```bash
./scripts/rhcsa-down.sh
```

Destroy everything (irreversible):

```bash
./scripts/rhcsa-destroy-vms.sh
```

---

## Repo layout

- `scripts/`
  - `rhcsa-create-vms.sh` — create VMs on NAT network (with stable MACs + DHCP reservations)
  - `rhcsa-up.sh` — bring libvirt/network up and start VMs
  - `rhcsa-down.sh` — shut down VMs cleanly
  - `rhcsa-status.sh` — health/status report for host + network + VMs + disks
  - `rhcsa-reset-to-clean.sh` — deterministic reset (baseline disk copy)
  - `rhcsa-destroy-vms.sh` — **irreversible** destroy (VM defs + disks)
  - `rhcsa-tmux.sh` — tmux helper with panes: host / vm1 / vm2
  - `rhcsa.sh` — preferred tmux driver for the repo

- `docs/`
  - `runbook.md` — detailed runbook + troubleshooting

---

## Prereqs (Ubuntu host)

Install the host packages you need:

```bash
sudo apt update
sudo apt install -y \
  qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
  virt-manager virt-viewer qemu-utils tmux
```

Confirm libvirt is healthy:

```bash
sudo systemctl enable --now libvirtd
sudo virsh --connect qemu:///system net-info default
```

---

## RHEL 10 ISO

Download a RHEL 10 x86_64 DVD ISO using your Red Hat subscription and place it at:

`/var/lib/libvirt/images/iso/rhel-10.1-x86_64-dvd.iso`

Recommended host-side preparation:

```bash
sudo mkdir -p /var/lib/libvirt/images/iso
sudo cp -v ~/Downloads/rhel-10.1-x86_64-dvd.iso /var/lib/libvirt/images/iso/
sudo chown -R root:libvirt /var/lib/libvirt/images/iso
sudo chmod -R 0775 /var/lib/libvirt/images/iso
sudo chmod 0664 /var/lib/libvirt/images/iso/*.iso
```

The create script uses that path by default. Override if needed:

```bash
ISO=/path/to/rhel-10.1-x86_64-dvd.iso ./scripts/rhcsa-create-vms.sh
```

The create script provisions the VM qcow2 disks automatically under `/var/lib/libvirt/images/rhcsa/`; no manual `qemu-img create` step is normally required.

---

## One-time: create the VMs

```bash
chmod +x scripts/*.sh
./scripts/rhcsa-create-vms.sh
```

Then complete the OS installs in `virt-manager` or `virt-viewer`.

After first boot inside each guest, set hostnames:

```bash
sudo hostnamectl set-hostname vm1   # on vm1
sudo hostnamectl set-hostname vm2   # on vm2
```

Optional but recommended for nicer host-side visibility:

```bash
sudo dnf -y install qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

---

## One-time: host SSH convenience

On the host, add `~/.ssh/config` entries (example):

```sshconfig
Host vm1
  HostName 192.168.122.31
  User student1
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host vm2
  HostName 192.168.122.66
  User student1
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

Then test:

```bash
ssh vm1 'hostname && whoami'
ssh vm2 'hostname && whoami'
```

---

## One-time: create golden baselines for deterministic reset

When both VMs are in your desired clean state:

```bash
POOL=/var/lib/libvirt/images/rhcsa

sudo virsh destroy vm1 2>/dev/null || true
sudo virsh destroy vm2 2>/dev/null || true

sudo cp -f "$POOL/vm1.qcow2" "$POOL/vm1.base.qcow2"
sudo cp -f "$POOL/vm2.qcow2" "$POOL/vm2.base.qcow2"

sudo chown root:libvirt "$POOL/vm1.base.qcow2" "$POOL/vm2.base.qcow2"
sudo chmod 0660 "$POOL/vm1.base.qcow2" "$POOL/vm2.base.qcow2"

sudo virsh start vm1
sudo virsh start vm2
```

From here on, `rhcsa-reset-to-clean.sh` resets by copying baseline → active.

---

## Notes / gotchas

- UEFI/pflash guests make libvirt internal snapshots unusable. Avoid `snapshot-revert`.
- `qemu-img info` will fail with lock errors while the VM is running unless you use `qemu-img info -U`.
- `virbr0` can show `NO-CARRIER` when no VMs are attached; it should become `UP` once VM vnet interfaces exist.
- `virsh domifaddr` is best with `qemu-guest-agent` installed in guests.

See `docs/runbook.md` for the full runbook + troubleshooting.
