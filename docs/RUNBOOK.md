# RHCSA RHEL10 Lab Runbook

This runbook documents the operational procedures for the KVM/libvirt RHCSA two-VM lab.

---

## 0) Key facts / conventions

- Host OS: Ubuntu
- Libvirt connection: `qemu:///system`
- Network: `default` (NAT) → bridge `virbr0` (usually `192.168.122.1/24`)
- VMs:
  - `vm1` (expected IP: `192.168.122.31`)
  - `vm2` (expected IP: `192.168.122.66`)
- Disk model (UEFI-safe):
  - active: `vm{1,2}.qcow2`
  - baseline: `vm{1,2}.base.qcow2`

---

## 1) Day-to-day operations

### Bring lab up
```bash
~/scripts/rhcsa-up.sh
~/scripts/rhcsa-status.sh
Bring lab down
~/scripts/rhcsa-down.sh
Reset to clean (fast)

Resets active qcow2 from baseline qcow2, then restarts VMs.

~/scripts/rhcsa-reset-to-clean.sh
Hard destroy (rare)

Deletes VM definitions and qcow2 disks.

~/scripts/rhcsa-destroy-vms.sh
2) One-time baseline creation / refresh

You do this when the VMs are in a state you want to return to repeatedly (registered, updated, ssh configured, etc).

Procedure

POOL=/var/lib/libvirt/images/rhcsa

# power off VMs
sudo virsh destroy vm1 2>/dev/null || true
sudo virsh destroy vm2 2>/dev/null || true

# copy current "active" to "baseline"
sudo cp -f "$POOL/vm1.qcow2" "$POOL/vm1.base.qcow2"
sudo cp -f "$POOL/vm2.qcow2" "$POOL/vm2.base.qcow2"

# perms
sudo chown root:libvirt "$POOL/vm1.base.qcow2" "$POOL/vm2.base.qcow2"
sudo chmod 0660 "$POOL/vm1.base.qcow2" "$POOL/vm2.base.qcow2"

# start VMs again
sudo virsh start vm1
sudo virsh start vm2

When to refresh

after major OS updates you want “baked in”

after you change core lab defaults (users, ssh keys, hostname policy)

3) Troubleshooting
virbr0 shows DOWN

virbr0 may show NO-CARRIER or DOWN when no VMs are attached.
Once VMs are running, it should flip UP.

Quick fix:

sudo ip link set virbr0 up || true
sudo virsh net-start default || true
VMs running but domifaddr empty

virsh domifaddr is best-effort and may require guest agent.
Alternative: view DHCP leases:

sudo virsh net-dhcp-leases default
SSH “No route to host”

Usually:

VMs not up yet

network not active

virbr0 down

wrong IP cached

Checklist:

~/scripts/rhcsa-status.sh
sudo virsh list --all
sudo virsh net-info default
ip -br a | grep virbr0
sudo virsh net-dhcp-leases default
4) Recommended SSH config (host)

Add to ~/.ssh/config:

Host vm1
  HostName 192.168.122.31
  User student1
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519

Host vm2
  HostName 192.168.122.66
  User student1
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519
5) Tmux driver usage (optional)

If you use the tmux driver script:

one pane for host commands

one pane SSH to vm1

one pane SSH to vm2

Typical:

TMUX_SESSION=rhcsa ~/scripts/rhcsa.sh

