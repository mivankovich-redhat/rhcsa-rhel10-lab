# RHCSA RHEL 10 Lab (KVM/libvirt, exam-style two-node topology)

A reproducible RHCSA practice lab for an Ubuntu host using KVM/libvirt and a dedicated lab network.

Validated topology:

- `servera` — infrastructure node
  - local HTTP package repo
  - NFS server
  - chrony source
  - Cockpit web console
- `serverb` — primary exam/practice node
  - storage practice (LVM / partitions / swap / filesystems)
  - SELinux / firewall practice
  - systemd and troubleshooting work
  - Cockpit web console

Validated network and roles:

- libvirt network: `rhcsa-lab`
- bridge: `virbr-rhcsa`
- subnet: `192.168.56.0/24`
- `servera.lab.local` → `192.168.56.10`
- `serverb.lab.local` → `192.168.56.20`

The lab uses a deterministic baseline/reset model instead of libvirt snapshot-revert:

- active disks live under `/var/lib/libvirt/images/rhcsa/`
- clean baselines are captured as `*.base.qcow2`
- reset restores baseline → active disk and restarts the VMs

This workflow has been validated end to end and tagged as `validated-two-node-lab-v1`.

---

## What is validated

Tested and validated in this repo:

- `scripts/rhcsa-env.sh`
- `scripts/rhcsa-create-vms.sh`
- `scripts/rhcsa-up.sh`
- `scripts/rhcsa-down.sh`
- `scripts/rhcsa-reset-to-clean.sh`
- `scripts/rhcsa-status.sh`
- `scripts/rhcsa-destroy-vms.sh` (new topology lifecycle validated through create/reset/up/down; old lab teardown path also exercised manually)
- `scripts/rhcsa-capture-baselines.sh`
- `scripts/rhcsa-tmux.sh`
- `scripts/rhcsa.sh`

Not part of the final validated workflow in this repo state:

- `scripts/bootstrap-servera.sh`
- `scripts/bootstrap-serverb.sh`

Those bootstrap helpers should be validated separately against a fresh OS-only guest state before being merged.

---

## Repo layout

- `scripts/`
  - `rhcsa-env.sh` — shared environment and defaults for the lab scripts
  - `rhcsa-create-vms.sh` — create the two-node lab, network, and disk layout
  - `rhcsa-up.sh` — start the lab
  - `rhcsa-down.sh` — shut down the lab cleanly
  - `rhcsa-status.sh` — inspect network, domains, disks, and baselines
  - `rhcsa-capture-baselines.sh` — create clean baseline copies of all active disks
  - `rhcsa-reset-to-clean.sh` — restore active disks from baseline copies
  - `rhcsa-destroy-vms.sh` — irreversible destroy of the lab domains and disks
  - `rhcsa-tmux.sh` — simple tmux helper that opens host + `servera` + `serverb`
  - `rhcsa.sh` — validated wrapper that brings the lab up, shows status, and opens the tmux layout
- `docs/`
  - `runbooks/runbook.md` — detailed build, validation, and troubleshooting notes for the validated lab baseline
  - `exams/exam1/` — RHCSA-style task practice documents such as `task_01_reset_root_password.md` and `task_02_configure_local_dnf_repo.md`

---

## Host prerequisites

Install required packages on Ubuntu:

```bash
sudo apt update
sudo apt install -y \
  qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
  virt-manager virt-viewer qemu-utils tmux
```

Enable libvirt:

```bash
sudo systemctl enable --now libvirtd
sudo virsh --connect qemu:///system uri
```

---

## Required RHEL ISO

Place a RHEL 10 x86_64 DVD ISO at:

```text
/var/lib/libvirt/images/iso/rhel-10.1-x86_64-dvd.iso
```

Recommended host prep:

```bash
sudo mkdir -p /var/lib/libvirt/images/iso
sudo cp -v ~/Downloads/rhel-10.1-x86_64-dvd.iso /var/lib/libvirt/images/iso/
sudo chown -R root:libvirt /var/lib/libvirt/images/iso
sudo chmod -R 0775 /var/lib/libvirt/images/iso
sudo chmod 0664 /var/lib/libvirt/images/iso/*.iso
```

Override if needed:

```bash
ISO=/path/to/rhel-10.1-x86_64-dvd.iso ./scripts/rhcsa-create-vms.sh
```

---

## Validated topology details

### ServerA

- hostname: `servera.lab.local`
- IP: `192.168.56.10/24`
- role: infrastructure node
- OS disk:
  - `vda` 20 GiB
- services:
  - Apache HTTP repo
  - NFS server
  - chronyd
  - firewalld
  - Cockpit web console

### ServerB

- hostname: `serverb.lab.local`
- IP: `192.168.56.20/24`
- role: exam/practice node
- disks:
  - `vda` 20 GiB — OS disk only
  - `vdb` 10 GiB — standard LVM / partition / swap tasks
  - `vdc` 10 GiB — VDO / additional storage tasks
  - `vdd` 2 GiB — spare disk
  - `vde` 10 GiB — spare disk
- services:
  - Cockpit web console

During OS installation on `serverb`, install to `vda` only and leave `vdb` / `vdc` / `vdd` / `vde` untouched.

---

## Baseline build vs exam task docs

This repo now separates two related but different kinds of documentation:

- `docs/runbooks/runbook.md`
  - the validated **lab baseline** build and service configuration
  - optimized for reproducible bring-up, stable reset behavior, and deterministic validation
- `docs/exams/exam1/task_*.md`
  - **exam-practice task workflows**
  - optimized for RHCSA-style repetition and muscle memory

These may intentionally use different mount points, repo filenames, or validation patterns.

Examples:

- the validated baseline runbook uses `/mnt/rheliso` and `rhel10-local-iso.repo` during initial build
- the Task 2 exam-practice doc uses `/mnt` and `/etc/yum.repos.d/local.repo` for local-media drills
- the validated baseline runbook uses `http://192.168.56.10/rhel10/...` for deterministic HTTP repo configuration on `serverb`
- the Task 2 exam-practice doc may use `servera` by hostname for repo-consumer drills to reinforce name resolution and service access

Use the runbook to build and maintain the lab. Use the task docs to practice RHCSA objectives.

---

## Cockpit access

Cockpit is installed on both lab VMs as a browser-based administrative surface and terminal convenience layer. Use it when you want GUI-backed terminal access or quick service, storage, and networking inspection from the Ubuntu host browser.

Recommended URLs:

- `https://192.168.56.10:9090`
- `https://192.168.56.20:9090`

Use `virt-manager` for GRUB, `rd.break`, and recovery-console work. Use `tmux + SSH` for the fastest repeated CLI practice. See `docs/runbooks/runbook.md` for the installation and access details.

---

## One-time build flow

### 1. Create the lab

```bash
chmod +x scripts/*.sh
./scripts/rhcsa-create-vms.sh
```

This creates:

- libvirt network `rhcsa-lab`
- `servera` and `serverb`
- disk images under `/var/lib/libvirt/images/rhcsa/`

### 2. Install RHEL 10 manually in both guests

Use `virt-manager`.

Recommended installer choices:

- `servera`
  - Minimal Install
  - install to `vda` only
- `serverb`
  - Minimal Install
  - install to `vda` only
  - leave `vdb` / `vdc` / `vdd` / `vde` unselected

### 3. Configure the guests

The validated flow used manual guest configuration rather than the repo bootstrap scripts.

#### ServerA (validated role)

- mount the attached ISO locally
- create temporary local `dnf` repo definitions from the ISO
- install `httpd`, `nfs-utils`, `chrony`, `firewalld`, and `cockpit`
- set hostname and static IP
- mount the ISO under `/mnt/rheliso`
- bind-mount it under `/var/www/html/rhel10`
- export `/srv/nfs/share`
- configure chrony as local source
- open firewall services for HTTP, NFS, NTP, and Cockpit

#### ServerB (validated role)

- temporarily mount the attached ISO and use it for initial `dnf`
- set hostname and static IP
- install `chrony`, `nfs-utils`, `autofs`, and `cockpit`
- configure HTTP repos pointing to `servera`
- verify NFS, repo access, and Cockpit access

See `docs/runbooks/runbook.md` for the full step-by-step validated baseline sequence.

For RHCSA-style practice tasks, see:

- `docs/exams/exam1/task_01_reset_root_password.md`
- `docs/exams/exam1/task_02_configure_local_dnf_repo.md`

---

## SSH aliases for tmux helpers

The validated tmux helpers assume host-side SSH aliases for the two lab guests. Add these to `~/.ssh/config` on the Ubuntu host:

```sshconfig
Host servera-lab
  HostName 192.168.56.10
  User student
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  PreferredAuthentications publickey
  PasswordAuthentication no
  StrictHostKeyChecking accept-new

Host serverb-lab
  HostName 192.168.56.20
  User student
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  PreferredAuthentications publickey
  PasswordAuthentication no
  StrictHostKeyChecking accept-new
```

Then copy the key into the guests:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub student@192.168.56.10
ssh-copy-id -i ~/.ssh/id_ed25519.pub student@192.168.56.20
```

---

## Day-to-day usage

Start the lab:

```bash
./scripts/rhcsa-up.sh
```

Check state:

```bash
./scripts/rhcsa-status.sh
```

Shut it down:

```bash
./scripts/rhcsa-down.sh
```

Capture fresh clean baselines:

```bash
./scripts/rhcsa-capture-baselines.sh
```

Reset to clean state:

```bash
./scripts/rhcsa-reset-to-clean.sh
```

Destroy everything:

```bash
./scripts/rhcsa-destroy-vms.sh
```

Open the validated tmux helpers:

```bash
./scripts/rhcsa-tmux.sh
TMUX_SESSION=rhcsa-followup ./scripts/rhcsa.sh
```

---

## Validated reset model

The following flow was validated:

1. build both guests
2. configure `servera` and `serverb`
3. capture clean baselines
4. introduce guest-side drift on `serverb`
5. run `rhcsa-reset-to-clean.sh`
6. confirm the drift is gone and the disk state is restored

This gives a reproducible exam-style reset path without relying on libvirt snapshots.

---

## Notes and gotchas

- A `403 Forbidden` response from `curl -I http://192.168.56.10/` is acceptable. It proves Apache is reachable; directory listing of `/` is intentionally not the real repo validation check.
- Use `dnf repolist` and `dnf makecache` on `serverb` to validate repo access.
- `showmount` requires `nfs-utils` on the client.
- If the guest sees `/dev/sr0` but it cannot be mounted, confirm the VM CD tray actually has the ISO inserted.
- If `qemu-guest-agent` warns about a missing virtio port, that does not block lab functionality; it only limits some host-side introspection.
- `virsh domifaddr` may only show `serverb` if guest agent / DHCP reporting is incomplete on `servera`. The lab can still be healthy.
- `rhcsa.sh` brings the lab up before opening tmux. Depending on your host sudo policy, you may still see a host-side sudo prompt before the session opens.

---

## Next recommended follow-up work

- validate and integrate `bootstrap-servera.sh`
- validate and integrate `bootstrap-serverb.sh`
- continue adding RHCSA task bundles under `docs/exams/`
