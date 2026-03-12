# RHCSA RHEL 10 Lab Runbook (Ubuntu + KVM/libvirt NAT)

This runbook documents the RHCSA RHEL10 two-VM lab environment:

- Host: Ubuntu (libvirt system daemon)
- Network: libvirt NAT network `default` (bridge `virbr0`, subnet `192.168.122.0/24`)
- Guests:
  - `vm1` → `192.168.122.31`
  - `vm2` → `192.168.122.66`

Reset model:

- Maintain golden baselines:

  - `/var/lib/libvirt/images/rhcsa/vm1.base.qcow2`
  - `/var/lib/libvirt/images/rhcsa/vm2.base.qcow2`
- Reset by copying baseline → active qcow2 and restarting VMs (UEFI-safe, avoids snapshot-revert issues).

---

## 0) Source of truth and preferred entry point

Run all lab scripts from the repo root:

```bash
cd ~/<REPO_ROOT>
```

Preferred entry point:

```bash
TMUX_SESSION=rhcsa ./scripts/rhcsa.sh
```

That driver:

- brings the lab up
- prints status in the host pane
- opens tmux
- connects panes for `vm1` and `vm2`

Simpler helper flow:

```bash
./scripts/rhcsa-up.sh
./scripts/rhcsa-status.sh
./scripts/rhcsa-tmux.sh
```

Older duplicates under `~/scripts` should be considered legacy copies unless you intentionally keep them synchronized.

---

## 1) Quick health check

```bash
./scripts/rhcsa-status.sh
```

Expected:

- `libvirtd` active
- `default` network active + autostart
- `virbr0` exists
- VMs either `running` or `shut off`
- disk paths are `vm1.qcow2`, `vm2.qcow2` (not `*.clean` overlays)
- `SUMMARY: PASS`

---

## 2) Host prerequisites

Install packages:

```bash
sudo apt update
sudo apt install -y \
  qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
  virt-manager virt-viewer qemu-utils tmux
```

Enable libvirtd:

```bash
sudo systemctl enable --now libvirtd
sudo virsh --connect qemu:///system uri
```

---

## 3) Network: libvirt NAT default

Confirm:

```bash
sudo virsh net-info default
sudo virsh net-dumpxml default | sed -n '1,120p'
ip -br a | grep virbr0 || true
```

Bring bridge link up (if needed):

```bash
sudo ip link set virbr0 up || true
```

Notes:

- `virbr0` can show `NO-CARRIER` when no VMs are attached.
- Once VMs start, vnet interfaces appear and the bridge typically shows `UP`.

---

## 4) RHEL 10 ISO and disk provisioning

This repo assumes you already have access to a RHEL 10 DVD ISO through your Red Hat subscription.

Recommended host location:

```bash
sudo mkdir -p /var/lib/libvirt/images/iso
sudo cp -v ~/Downloads/rhel-10.1-x86_64-dvd.iso /var/lib/libvirt/images/iso/
sudo chown -R root:libvirt /var/lib/libvirt/images/iso
sudo chmod -R 0775 /var/lib/libvirt/images/iso
sudo chmod 0664 /var/lib/libvirt/images/iso/*.iso
```

By default, `scripts/rhcsa-create-vms.sh` expects:

```text
/var/lib/libvirt/images/iso/rhel-10.1-x86_64-dvd.iso
```

Override if needed:

```bash
ISO=/path/to/rhel-10.1-x86_64-dvd.iso ./scripts/rhcsa-create-vms.sh
```

The script creates the VM qcow2 disks automatically under:

```text
/var/lib/libvirt/images/rhcsa/
```

No manual `qemu-img create` step is normally required.

---

## 5) Create VMs (one-time)

```bash
chmod +x scripts/*.sh
./scripts/rhcsa-create-vms.sh
```

This script:

- creates disks under `/var/lib/libvirt/images/rhcsa/`
- creates vm1 + vm2 on `default`
- reserves DHCP entries for stable IPs (by MAC)

Complete OS installs via `virt-manager` or `virt-viewer`.

---

## 6) Guest post-install checklist (both VMs)

### 6.1 Hostnames

```bash
sudo hostnamectl set-hostname vm1   # on vm1
sudo hostnamectl set-hostname vm2   # on vm2
```

### 6.2 qemu-guest-agent (recommended)

Improves `virsh domifaddr` and some VM introspection:

```bash
sudo dnf -y install qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

### 6.3 SSH access

From host:

- either use IPs directly
- or set `~/.ssh/config` aliases (recommended)

Example host `~/.ssh/config`:

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

Validate:

```bash
ssh vm1 'hostname && whoami'
ssh vm2 'hostname && whoami'
```

---

## 7) Baseline strategy (critical)

### Why not libvirt snapshots?

UEFI/pflash guests often break internal snapshots. External disk snapshots can wedge the VM into `.clean` overlay states that are hard to revert cleanly.

### Baseline model (this lab)

- Treat `vm1.base.qcow2` / `vm2.base.qcow2` as golden images.
- Reset by copying baseline → active disks.

### Create or refresh baselines (one-time, when clean is correct)

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

Tip: only refresh baselines when you intentionally want a new clean point.

---

## 8) Day-to-day operations

### Preferred driver

```bash
TMUX_SESSION=rhcsa ./scripts/rhcsa.sh
```

### Simpler helper flow

```bash
./scripts/rhcsa-up.sh
./scripts/rhcsa-status.sh
./scripts/rhcsa-tmux.sh
```

### Reset to baseline

```bash
./scripts/rhcsa-reset-to-clean.sh
```

### Shut down

```bash
./scripts/rhcsa-down.sh
```

### Destroy everything (irreversible)

```bash
./scripts/rhcsa-destroy-vms.sh
```

---

## 9) Optional: passwordless sudo for lab automation

This step is optional. It reduces repeated sudo prompts for host-side lab automation, but it grants passwordless access to a limited set of libvirt/network management commands. Review it before enabling.

Create `/etc/sudoers.d/rhcsa-lab`:

```bash
sudo tee /etc/sudoers.d/rhcsa-lab >/dev/null <<'EOF'
# Passwordless sudo for RHCSA libvirt lab automation
# Replace <your-username> with your local Linux username.

User_Alias RHCSAUSER = <your-username>

Cmnd_Alias RHCSA_SYSTEMCTL = \
  /bin/systemctl enable --now libvirtd, \
  /bin/systemctl restart libvirtd, \
  /bin/systemctl is-active --quiet libvirtd

Cmnd_Alias RHCSA_VIRSH = /usr/bin/virsh *, /bin/virsh *

Cmnd_Alias RHCSA_IP = \
  /usr/sbin/ip link set virbr0 up, \
  /usr/sbin/ip link show virbr0, \
  /usr/sbin/ip -br a

RHCSAUSER ALL=(root) NOPASSWD: RHCSA_SYSTEMCTL, RHCSA_VIRSH, RHCSA_IP
EOF

sudo chmod 0440 /etc/sudoers.d/rhcsa-lab
sudo visudo -cf /etc/sudoers.d/rhcsa-lab
```

Validate:

```bash
sudo -n true && echo "NOPASSWD works"
sudo -n virsh list --all
sudo -n systemctl is-active --quiet libvirtd && echo "libvirtd active"
```

---

## 10) Troubleshooting

### 10.1 `virbr0` shows DOWN

If `virbr0` is `DOWN` before VMs start, that may be normal. If it stays down after starting VMs:

```bash
sudo ip link set virbr0 up
sudo virsh net-destroy default
sudo virsh net-start default
ip -br a | grep virbr0
```

### 10.2 `virsh domifaddr` says domain is not running

Start the VMs:

```bash
sudo virsh start vm1
sudo virsh start vm2
```

### 10.3 `virsh domifaddr` empty / unreliable

Install guest agent in the VM:

```bash
sudo dnf -y install qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

Fallback on host:

```bash
sudo virsh net-dhcp-leases default
```

### 10.4 `qemu-img info` fails with lock errors

That’s expected when a VM holds a write lock. Use `-U`:

```bash
sudo qemu-img info -U /var/lib/libvirt/images/rhcsa/vm1.qcow2
```

### 10.5 SSH: No route to host

Usually means VMs not up yet or `default` network/bridge not ready:

```bash
./scripts/rhcsa-status.sh
./scripts/rhcsa-up.sh
```

---

## 11) Cockpit notes (practice-friendly)

Enable cockpit:

```bash
sudo dnf -y install cockpit
sudo systemctl enable --now cockpit.socket
```

Then access from host:

- `https://vm1:9090/` or `https://192.168.122.31:9090/`
- `https://vm2:9090/` or `https://192.168.122.66:9090/`

---

## 12) Reference: scripts

- `scripts/rhcsa-up.sh` — start libvirt/network + VMs
- `scripts/rhcsa-down.sh` — shut down VMs
- `scripts/rhcsa-reset-to-clean.sh` — baseline disk-copy reset (UEFI-safe)
- `scripts/rhcsa-status.sh` — health/status report
- `scripts/rhcsa.sh` — preferred tmux driver
- `scripts/rhcsa-tmux.sh` — tmux helper (host/vm1/vm2 panes)
- `scripts/rhcsa-create-vms.sh` — create VMs + DHCP reservations
- `scripts/rhcsa-destroy-vms.sh` — destroy VM defs + disks
