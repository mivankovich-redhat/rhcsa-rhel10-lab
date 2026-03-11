# RHCSA RHEL 10 Lab (KVM/libvirt + NAT)

A small, deterministic RHCSA practice lab on an Ubuntu host using KVM/libvirt with the default NAT network.

## What you get
- Two RHEL VMs: `vm1` and `vm2`
- NAT network: libvirt `default` (bridge `virbr0`, typically `192.168.122.0/24`)
- Stable addressing (in practice):  
  - `vm1` → `192.168.122.31`  
  - `vm2` → `192.168.122.66`
- One-command flows:
  - bring lab up/down
  - show full status
  - reset to “clean” via baseline disk copy (UEFI-safe)

## Repo layout
- `scripts/`
  - `rhcsa-up.sh` – start libvirtd/network/virbr0 + boot VMs
  - `rhcsa-down.sh` – clean shutdown VMs
  - `rhcsa-status.sh` – high-signal health/status report
  - `rhcsa-reset-to-clean.sh` – reset active disks from baseline + restart VMs
  - `rhcsa-destroy-vms.sh` – hard destroy VMs + disks
  - `rhcsa-create-vms.sh` – create disks + VMs from ISO (installer-driven)
  - `rhcsa-tmux.sh` – tmux helper (optional)
  - `rhcsa.sh` – tmux “driver” that brings lab up and attaches panes (if present)

## Prereqs (host)
```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst virt-manager tmux
sudo usermod -aG libvirt,kvm $USER
newgrp libvirt

Enable libvirt:

sudo systemctl enable --now libvirtd
Quick start
cd scripts
./rhcsa-up.sh
./rhcsa-status.sh

SSH (if your ~/.ssh/config has Host entries for vm1/vm2):

ssh vm1
ssh vm2
Baseline model (important)

This lab avoids libvirt snapshot-revert (UEFI/pflash + external snapshots can wedge).

Instead:

Baseline images:

/var/lib/libvirt/images/rhcsa/vm1.base.qcow2

/var/lib/libvirt/images/rhcsa/vm2.base.qcow2

Active images:

/var/lib/libvirt/images/rhcsa/vm1.qcow2

/var/lib/libvirt/images/rhcsa/vm2.qcow2

Reset is a simple copy: base -> active, then reboot VMs.

See RUNBOOK.md for the one-time “create baseline” procedure.

Safety notes

rhcsa-destroy-vms.sh deletes VM definitions + qcow2 disks. Use carefully.

Prefer rhcsa-reset-to-clean.sh for day-to-day practice resets.

