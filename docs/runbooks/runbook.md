# RHCSA RHEL 10 Lab Runbook (Ubuntu + KVM/libvirt, two-node exam-style layout)

This runbook documents the validated RHCSA RHEL 10 lab environment built on an Ubuntu host using KVM/libvirt.

Validated topology:

- `servera.lab.local` → `192.168.56.10`
  - infrastructure node
  - local HTTP package repo
  - NFS server
  - chrony source
  - Cockpit web console
- `serverb.lab.local` → `192.168.56.20`
  - practice node
  - main RHCSA storage / SELinux / firewall / systemd target
  - Cockpit web console

Validated lab network:

- libvirt network: `rhcsa-lab`
- bridge: `virbr-rhcsa`
- subnet: `192.168.56.0/24`

Reset strategy:

- active disks under `/var/lib/libvirt/images/rhcsa/`
- clean baselines as `*.base.qcow2`
- reset restores baseline → active disk and restarts the VMs

This avoids the UEFI/pflash snapshot-revert problems that often show up with libvirt snapshots.

Validated checkpoint tag:

- `validated-two-node-lab-v1`

---

## 1. Source of truth

Run all commands from the repo root:

```bash
cd ~/<REPO_ROOT>
```

Use the repo copies of the scripts under `./scripts/`.

Validated scripts in the current repo state:

- `rhcsa-env.sh`
- `rhcsa-create-vms.sh`
- `rhcsa-up.sh`
- `rhcsa-down.sh`
- `rhcsa-status.sh`
- `rhcsa-capture-baselines.sh`
- `rhcsa-reset-to-clean.sh`
- `rhcsa-destroy-vms.sh`
- `rhcsa-tmux.sh`
- `rhcsa.sh`

Not part of the final validated path in this repo state:

- `bootstrap-servera.sh`
- `bootstrap-serverb.sh`

---

## 2. Baseline build vs exam practice docs

This runbook is the source for the validated **lab baseline** build and service configuration.

The files under `docs/exams/` are different on purpose:

- this runbook optimizes for reproducible bring-up, stable reset behavior, and deterministic validation
- the exam task docs optimize for RHCSA-style repetition and muscle memory

That means some commands and file names differ between the runbook and the task docs without being contradictory.

Examples:

- this runbook uses `/mnt/rheliso` and `/etc/yum.repos.d/rhel10-local-iso.repo` for baseline guest bring-up
- `docs/exams/exam1/task_02_configure_local_dnf_repo.md` uses `/mnt` and `/etc/yum.repos.d/local.repo` for the local-media practice drill
- this runbook uses `http://192.168.56.10/rhel10/...` on `serverb` for deterministic baseline repo configuration
- the Task 2 practice doc may use `servera` by hostname to reinforce host resolution and service-consumer validation

Use this runbook to build and maintain the lab baseline. Use the task docs to rehearse exam workflows.

---

## 3. Host prerequisites

Install host packages:

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

Recommended ISO location:

```text
/var/lib/libvirt/images/iso/rhel-10.1-x86_64-dvd.iso
```

Host prep:

```bash
sudo mkdir -p /var/lib/libvirt/images/iso
sudo cp -v ~/Downloads/rhel-10.1-x86_64-dvd.iso /var/lib/libvirt/images/iso/
sudo chown -R root:libvirt /var/lib/libvirt/images/iso
sudo chmod -R 0775 /var/lib/libvirt/images/iso
sudo chmod 0664 /var/lib/libvirt/images/iso/*.iso
```

---

## 4. Create the lab

```bash
chmod +x scripts/*.sh
./scripts/rhcsa-create-vms.sh
```

Expected outcome:

- libvirt network `rhcsa-lab` exists and autostarts
- `servera` exists
- `serverb` exists
- disk images are created under `/var/lib/libvirt/images/rhcsa/`

Check status:

```bash
./scripts/rhcsa-status.sh
```

---

## 5. Guest install guidance

### ServerA

Recommended installer selections:

- Minimal Install
- hostname: `servera.lab.local`
- install to `vda` only
- automatic partitioning on `vda`

### ServerB

Recommended installer selections:

- Minimal Install
- hostname: `serverb.lab.local`
- install to `vda` only
- leave `vdb` / `vdc` / `vdd` / `vde` unselected

This is critical. The extra disks are for RHCSA storage work and must remain clean after install.

---

## 6. Post-install validated configuration

The final validated flow used manual guest configuration rather than the bootstrap scripts.

### 6.1 Ensure ISO media is actually inserted

If a guest sees a CD-ROM device but cannot mount `/dev/sr0`, check the host-side media assignment.

Example:

```bash
sudo virsh domblklist servera
sudo virsh change-media servera sda \
  --insert /var/lib/libvirt/images/iso/rhel-10.1-x86_64-dvd.iso \
  --live --config
```

Repeat for `serverb` if needed.

---

## 7. ServerA validated configuration

### 7.1 Temporary local ISO repos

Inside `servera` as root:

```bash
mkdir -p /mnt/rheliso
mount /dev/sr0 /mnt/rheliso

cat >/etc/yum.repos.d/rhel10-local-iso.repo <<'EOF2'
[rhel10-local-baseos]
name=RHEL 10 Local ISO BaseOS
baseurl=file:///mnt/rheliso/BaseOS
enabled=1
gpgcheck=0

[rhel10-local-appstream]
name=RHEL 10 Local ISO AppStream
baseurl=file:///mnt/rheliso/AppStream
enabled=1
gpgcheck=0
EOF2

dnf clean all
dnf repolist
dnf install -y qemu-guest-agent httpd nfs-utils chrony firewalld cockpit
systemctl enable --now cockpit.socket
```

Note: a missing virtio guest-agent port warning is not a functional blocker for the lab.

### 7.2 Hostname, IP, and hosts file

```bash
hostnamectl set-hostname servera.lab.local
nmcli con mod "enp1s0" ipv4.method manual ipv4.addresses 192.168.56.10/24 ipv6.method disabled
nmcli con up "enp1s0"

cat >> /etc/hosts <<'EOF2'
192.168.56.10 servera.lab.local servera
192.168.56.20 serverb.lab.local serverb
192.168.56.30 serverc.lab.local serverc
EOF2
```

If the NetworkManager connection name is not `enp1s0`, use the exact name from `nmcli con show`.

### 7.3 HTTP repo, NFS, chrony, firewall

```bash
systemctl enable --now httpd chronyd nfs-server firewalld

mkdir -p /var/www/html/rhel10
mount --bind /mnt/rheliso /var/www/html/rhel10

mkdir -p /srv/nfs/share
echo "RHCSA lab share from servera" > /srv/nfs/share/README.txt
echo "/srv/nfs/share 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -rav

printf '\nallow 192.168.56.0/24\nlocal stratum 10\n' >> /etc/chrony.conf
systemctl restart chronyd

firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=nfs --permanent
firewall-cmd --add-service=mountd --permanent
firewall-cmd --add-service=rpc-bind --permanent
firewall-cmd --add-service=ntp --permanent
firewall-cmd --add-service=cockpit --permanent
firewall-cmd --reload
```

### 7.4 Persist the ISO and bind mount

`/etc/fstab` should contain these lines in this order:

```fstab
/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0
/mnt/rheliso /var/www/html/rhel10 none bind 0 0
```

Then:

```bash
systemctl daemon-reload
mount -a
```

### 7.5 ServerA validation

```bash
hostnamectl
ip a
mount | egrep 'rheliso|rhel10'
showmount -e localhost
curl -I http://127.0.0.1/
systemctl is-active httpd nfs-server chronyd firewalld cockpit.socket
sudo firewall-cmd --list-services
```

Expected results:

- hostname = `servera.lab.local`
- IP includes `192.168.56.10/24`
- NFS export visible
- Apache responds
- services active
- firewall includes `http nfs mountd rpc-bind ntp cockpit`

A `403 Forbidden` from Apache root is acceptable; it still proves Apache is reachable.

---

## 8. ServerB validated configuration

### 8.1 Temporary local ISO repos for initial package install

Inside `serverb` as root:

```bash
mkdir -p /mnt/rheliso
mount /dev/sr0 /mnt/rheliso

cat >/etc/yum.repos.d/rhel10-local-iso.repo <<'EOF2'
[rhel10-local-baseos]
name=RHEL 10 Local ISO BaseOS
baseurl=file:///mnt/rheliso/BaseOS
enabled=1
gpgcheck=0

[rhel10-local-appstream]
name=RHEL 10 Local ISO AppStream
baseurl=file:///mnt/rheliso/AppStream
enabled=1
gpgcheck=0
EOF2

dnf clean all
dnf repolist
```

### 8.2 Hostname, IP, and hosts file

```bash
hostnamectl set-hostname serverb.lab.local
nmcli con mod "enp1s0" ipv4.method manual ipv4.addresses 192.168.56.20/24 ipv6.method disabled
nmcli con up "enp1s0"

cat >> /etc/hosts <<'EOF2'
192.168.56.10 servera.lab.local servera
192.168.56.20 serverb.lab.local serverb
192.168.56.30 serverc.lab.local serverc
EOF2
```

Again, if the NetworkManager connection name differs, use the exact connection name from `nmcli con show`.

### 8.3 Install client packages, Cockpit, and chrony config

```bash
dnf install -y chrony nfs-utils autofs cockpit
systemctl enable --now cockpit.socket
printf '\nserver 192.168.56.10 iburst\n' >> /etc/chrony.conf
systemctl enable --now chronyd
systemctl restart chronyd
```

### 8.4 Switch to ServerA HTTP repos

For the validated baseline, use the static IP for deterministic configuration:

```bash
cat >/etc/yum.repos.d/lab-http.repo <<'EOF2'
[lab-baseos]
name=Lab BaseOS
baseurl=http://192.168.56.10/rhel10/BaseOS
enabled=1
gpgcheck=0

[lab-appstream]
name=Lab AppStream
baseurl=http://192.168.56.10/rhel10/AppStream
enabled=1
gpgcheck=0
EOF2

mv /etc/yum.repos.d/rhel10-local-iso.repo /etc/yum.repos.d/rhel10-local-iso.repo.disabled
dnf clean all
dnf repolist
dnf makecache
```

If you want hostname-based RHCSA practice instead, use the exam task docs under `docs/exams/exam1/`.

### 8.5 ServerB validation

```bash
ping -c 3 servera
getent hosts servera
curl -I http://192.168.56.10/
showmount -e servera
chronyc sources -v
lsblk
dnf repolist
systemctl is-active cockpit.socket
```

Expected results:

- `servera` resolves and pings
- HTTP on `servera` is reachable
- NFS export visible
- `lsblk` shows `vda`, `vdb`, `vdc`, `vdd`, `vde`
- `dnf repolist` shows HTTP repos backed by `servera`
- Cockpit socket is active

---

## 9. Cockpit access on servera and serverb

Cockpit is installed on both VMs as a browser-based administrative surface and terminal convenience layer.

Access from the Ubuntu host browser:

- `https://192.168.56.10:9090`
- `https://192.168.56.20:9090`

If host-side name resolution is configured, hostname-based access also works:

- `https://servera:9090`
- `https://serverb:9090`

Use this split:

- `virt-manager` for boot, GRUB, `rd.break`, and emergency console work
- Cockpit for GUI-backed terminal access and quick inspection of services, storage, logs, networking, and system state
- `tmux + SSH` for the fastest repeated CLI practice

Notes:

- on `servera`, Cockpit requires the `cockpit` service to be open in `firewalld`
- on `serverb`, baseline access works without additional firewall work because `firewalld` is not part of the validated baseline there
- if you enable `firewalld` on `serverb` later, also open the `cockpit` service

Quick validation:

```bash
systemctl is-active cockpit.socket
ss -ltnp | grep 9090
```

---

## 10. Host SSH setup for tmux helpers

The validated tmux helpers use host-side SSH aliases.

Add these to `~/.ssh/config` on the Ubuntu host:

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

Validate:

```bash
ssh servera-lab
ssh serverb-lab
```

---

## 11. Baseline capture

Once both guests are in the desired clean state:

```bash
./scripts/rhcsa-capture-baselines.sh
```

This captures:

- `servera-os.base.qcow2`
- `serverb-os.base.qcow2`
- `serverb-sdb.base.qcow2`
- `serverb-sdc.base.qcow2`
- `serverb-sdd.base.qcow2`
- `serverb-sde.base.qcow2`

Then verify:

```bash
./scripts/rhcsa-status.sh
```

Expected:

- baselines exist for all active disks
- `SUMMARY: PASS`

---

## 12. Reset-to-clean validation

Validated flow:

1. create a harmless guest-side change on `serverb`
2. run `./scripts/rhcsa-reset-to-clean.sh`
3. confirm the drift is gone after reboot

Example drift check that was validated:

- create `/root/reset-test.txt` on `serverb`
- run reset-to-clean
- confirm `/root/reset-test.txt` no longer exists

This proves the reset lifecycle is working.

---

## 13. Day-to-day commands

Start the lab:

```bash
./scripts/rhcsa-up.sh
```

Stop the lab:

```bash
./scripts/rhcsa-down.sh
```

Full status:

```bash
./scripts/rhcsa-status.sh
```

Capture new baselines:

```bash
./scripts/rhcsa-capture-baselines.sh
```

Reset to clean:

```bash
./scripts/rhcsa-reset-to-clean.sh
```

Destroy the lab:

```bash
./scripts/rhcsa-destroy-vms.sh
```

Open the validated tmux helpers:

```bash
./scripts/rhcsa-tmux.sh
TMUX_SESSION=rhcsa-followup ./scripts/rhcsa.sh
```

---

## 14. Troubleshooting

### Apache root returns 403

`curl -I http://192.168.56.10/` may return `403 Forbidden`.
That is acceptable and still proves Apache is reachable.
Use `dnf repolist` / `dnf makecache` on `serverb` as the real repo validation.

### `showmount: command not found`

Install `nfs-utils` on the client:

```bash
dnf install -y nfs-utils
```

### `/dev/sr0` exists but mount fails

The guest CD tray may be empty. Verify and insert ISO from the host with `virsh change-media`.

### Guest agent warning about missing virtio port

This does not block core lab functionality. It only limits some host-side introspection like address reporting.

### `firewall-cmd --list-services` fails as student user

Run it with `sudo`.

### `servera` address may not show in host-side status

If guest-agent or DHCP reporting is incomplete, `rhcsa-status.sh` may still pass even if `servera` does not show an address. Validate `servera` from inside the guests and by service checks.

### `rhcsa.sh` prompts for sudo before tmux opens

That can be expected depending on the host sudo policy. The validated wrapper brings the lab up before creating the tmux session.

### Cockpit page does not load

Check:

```bash
systemctl status cockpit.socket --no-pager
ss -ltnp | grep 9090
curl -kI https://127.0.0.1:9090
```

On `servera`, also verify `firewalld` allows the `cockpit` service.

---

## 15. Recommended next improvements

- validate and integrate `bootstrap-servera.sh`
- validate and integrate `bootstrap-serverb.sh`
- continue expanding RHCSA task bundles under `docs/exams/`
