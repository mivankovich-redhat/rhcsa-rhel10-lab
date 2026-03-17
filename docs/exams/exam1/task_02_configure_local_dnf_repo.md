# Exam 1 - Task 2 - Configure Local DNF/YUM Repositories

## Exam Workflow Note

Use this task in the following order during practice:

1. get a working repository on the host
2. validate package access
3. install and enable Cockpit **after** repo access exists, unless Cockpit is already installed
4. continue the rest of the task flow using Cockpit, tmux/SSH, or the VM console as needed

This avoids the dependency loop where `cockpit` cannot be installed until package repositories are available.

## Repository Source Variants

The real exam objective is to configure access to RPM repositories. The exact source may vary by task wording or environment.

This task lets you practice three realistic variants:

1. **Method A** - attached optical device such as `/dev/sr0`
2. **Method B** - repo server URLs
3. **Method C** - ISO file downloaded locally and mounted with `loop`

## Cockpit Usage Note

If `cockpit` is already installed on a host, you may enable and use it immediately:

```bash
systemctl enable --now cockpit.socket
systemctl status cockpit.socket --no-pager
```

If `cockpit` is **not** installed, complete Method A, B, or C for that host first, then install it.

## Task

Configure local package repositories for RHCSA-style practice on `servera` and `serverb`.

## Domains Covered

- Manage software
- Configure access to RPM repositories

## Classification

- Exam-safe/manual practice

## Objective

Practice optical-device, URL-based, and loop-mounted ISO repository configuration patterns so you can adapt to task wording on the real exam.

## Important Caveat

The primary task here is **repository configuration**.

A possible lab variation is configuring `serverb` to consume repositories served by `servera` over HTTP. That is worth practicing, but it is a different topology from mounting installation media locally.

## Repository Reset / Prep Step

Run this before testing each method on each host.

```bash
umount /mnt/rheliso 2>/dev/null || true
umount /media/cdrom 2>/dev/null || true

mkdir -p /root/repo-practice-backup

mv /etc/yum.repos.d/local.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/localhost_rhel10_BaseOS.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/localhost_rhel10_AppStream.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/servera_rhel10_BaseOS.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/servera_rhel10_AppStream.repo /root/repo-practice-backup/ 2>/dev/null || true

dnf clean all
dnf repolist all
```

## Method A - Local Installation Media on `servera`

### 1) Ensure the installation media is mounted persistently at `/mnt/rheliso`

```bash
mkdir -p /mnt/rheliso
echo '/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0' >> /etc/fstab
mount -a
ls /mnt/rheliso
```

Expected output includes at least:

```text
BaseOS
AppStream
```

### 2) Create the local repository file

```bash
cat > /etc/yum.repos.d/local.repo <<'EOF'
[BaseOS]
name=RHEL 10 BaseOS
baseurl=file:///mnt/rheliso/BaseOS
enabled=1
gpgcheck=0

[AppStream]
name=RHEL 10 AppStream
baseurl=file:///mnt/rheliso/AppStream
enabled=1
gpgcheck=0
EOF
```

### 3) Validate

```bash
cat /etc/fstab
mount | grep rheliso
ls /mnt/rheliso
cat /etc/yum.repos.d/local.repo
dnf clean all
dnf repolist
dnf --disablerepo='*' --enablerepo=BaseOS --enablerepo=AppStream list available | head
```

### 4) Optional post-repo step: install Cockpit on `servera`

Once Method A is working on `servera`, install Cockpit if it is not already present:

```bash
dnf install -y cockpit
systemctl enable --now cockpit.socket
firewall-cmd --add-service=cockpit --permanent
firewall-cmd --reload
systemctl status cockpit.socket --no-pager
```

Validate from the Ubuntu host browser:

```text
https://192.168.56.10:9090
```

### Green Criteria

Method A on `servera` is green when:

- `/mnt/rheliso` contains `BaseOS` and `AppStream`
- `/etc/fstab` contains the `/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0` entry
- `/etc/yum.repos.d/local.repo` exists with correct `file:///mnt/rheliso/...` baseurls
- `dnf repolist` shows `BaseOS` and `AppStream`
- isolated package listing works with only those two repos enabled

## Method A - Local Installation Media on `serverb`

Repeat the same workflow on `serverb`.

### 1) Method A: Ensure the installation media is mounted persistently at `/mnt/rheliso`

```bash
mkdir -p /mnt/rheliso
echo '/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0' >> /etc/fstab
mount -a
ls /mnt/rheliso
```

### 2) Method A: Create the local repository file

```bash
cat > /etc/yum.repos.d/local.repo <<'EOF'
[BaseOS]
name=RHEL 10 BaseOS
baseurl=file:///mnt/rheliso/BaseOS
enabled=1
gpgcheck=0

[AppStream]
name=RHEL 10 AppStream
baseurl=file:///mnt/rheliso/AppStream
enabled=1
gpgcheck=0
EOF
```

### 3) Method A Validate

```bash
cat /etc/fstab
mount | grep rheliso
ls /mnt/rheliso
cat /etc/yum.repos.d/local.repo
dnf clean all
dnf repolist
dnf --disablerepo='*' --enablerepo=BaseOS --enablerepo=AppStream list available | head
```

### 4) Optional post-repo step: install Cockpit on `serverb`

Once Method A is working on `serverb`, install Cockpit if it is not already present:

```bash
dnf install -y cockpit
systemctl enable --now cockpit.socket
systemctl status cockpit.socket --no-pager
```

If you later enable `firewalld` on `serverb`, also open the Cockpit service:

```bash
firewall-cmd --add-service=cockpit --permanent
firewall-cmd --reload
```

Validate from the Ubuntu host browser:

```text
https://192.168.56.20:9090
```

### Method A Green Criteria

Method A on `serverb` is green when:

- `/mnt/rheliso` contains `BaseOS` and `AppStream`
- `/etc/fstab` contains the `/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0` entry
- `/etc/yum.repos.d/local.repo` exists with correct `file:///mnt/rheliso/...` baseurls
- `dnf repolist` shows `BaseOS` and `AppStream`
- isolated package listing works with only those two repos enabled

## Reset Again Before Method B

Run the prep block again before starting Method B on each host.

```bash
umount /mnt/rheliso 2>/dev/null || true
umount /media/cdrom 2>/dev/null || true

mkdir -p /root/repo-practice-backup

mv /etc/yum.repos.d/local.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/localhost_rhel10_BaseOS.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/localhost_rhel10_AppStream.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/servera_rhel10_BaseOS.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/servera_rhel10_AppStream.repo /root/repo-practice-backup/ 2>/dev/null || true

dnf clean all
dnf repolist all
```

## Method B - Repo Server URLs Using `servera`

This method matches the exam-style pattern where the task gives you two explicit repository URLs.

In this lab, use the actual repo-server URLs hosted by `servera`:

- `http://192.168.56.10/rhel10/BaseOS`
- `http://192.168.56.10/rhel10/AppStream`

On the real exam, replace these with the exact repo server IP and file paths given in the task.

### Method B on `servera`

#### 1) Verify the repo server URLs are reachable

```bash
systemctl enable --now httpd
curl -I http://192.168.56.10/rhel10/BaseOS/repodata/repomd.xml
curl -I http://192.168.56.10/rhel10/AppStream/repodata/repomd.xml
```

Expected result: HTTP success such as `200 OK`.

#### 2) Create the repository file

```bash
cat > /etc/yum.repos.d/local.repo <<'EOF'
[BaseOS]
name=RHEL 10 BaseOS
baseurl=http://192.168.56.10/rhel10/BaseOS
enabled=1
gpgcheck=0

[AppStream]
name=RHEL 10 AppStream
baseurl=http://192.168.56.10/rhel10/AppStream
enabled=1
gpgcheck=0
EOF
```

#### 3) Validate

```bash
cat /etc/yum.repos.d/local.repo
dnf clean all
dnf repolist
dnf --disablerepo='*' --enablerepo=BaseOS --enablerepo=AppStream list available | head
```

#### 4) Optional post-repo step: install Cockpit on `servera`

Once Method B is working on `servera`, install Cockpit if it is not already present:

```bash
dnf install -y cockpit
systemctl enable --now cockpit.socket
firewall-cmd --add-service=cockpit --permanent
firewall-cmd --reload
systemctl status cockpit.socket --no-pager
```

### Method B Green Criteria on `servera`

Method B on `servera` is green when:

- the repo server URLs respond successfully
- `/etc/yum.repos.d/local.repo` exists with the expected `http://192.168.56.10/rhel10/...` baseurls
- `dnf repolist` shows `BaseOS` and `AppStream`
- isolated package listing works with only those two repos enabled

### Method B on `serverb`

#### 1) Verify the repo server URLs are reachable

```bash
curl -I http://192.168.56.10/rhel10/BaseOS/repodata/repomd.xml
curl -I http://192.168.56.10/rhel10/AppStream/repodata/repomd.xml
```

Expected result: HTTP success such as `200 OK`.

#### 2) Create the repository file

```bash
cat > /etc/yum.repos.d/local.repo <<'EOF'
[BaseOS]
name=RHEL 10 BaseOS
baseurl=http://192.168.56.10/rhel10/BaseOS
enabled=1
gpgcheck=0

[AppStream]
name=RHEL 10 AppStream
baseurl=http://192.168.56.10/rhel10/AppStream
enabled=1
gpgcheck=0
EOF
```

#### 3) Validate

```bash
cat /etc/yum.repos.d/local.repo
dnf clean all
dnf repolist
dnf --disablerepo='*' --enablerepo=BaseOS --enablerepo=AppStream list available | head
```

#### 4) Optional post-repo step: install Cockpit on `serverb`

Once Method B is working on `serverb`, install Cockpit if it is not already present:

```bash
dnf install -y cockpit
systemctl enable --now cockpit.socket
systemctl status cockpit.socket --no-pager
```

If you later enable `firewalld` on `serverb`, also open the Cockpit service.

### Method B Green Criteria on `serverb`

Method B on `serverb` is green when:

- the repo server URLs respond successfully
- `/etc/yum.repos.d/local.repo` exists with the expected `http://192.168.56.10/rhel10/...` baseurls
- `dnf repolist` shows `BaseOS` and `AppStream`
- isolated package listing works with only those two repos enabled

## Reset Again Before Method C

Run the prep block again before starting Method C.

```bash
umount /mnt/rheliso 2>/dev/null || true
umount /media/cdrom 2>/dev/null || true
rm -f /root/boot.iso

mkdir -p /root/repo-practice-backup

mv /etc/yum.repos.d/local.repo /root/repo-practice-backup/ 2>/dev/null || true

dnf clean all
dnf repolist all
```

## Method C - ISO File Downloaded Locally and Mounted via Loop Device

This method practices the case where the task gives you an ISO file path instead of an attached optical device.

### 1) Download the ISO locally

```bash
cd /root
wget ftp://192.168.0.254/pub/boot.iso
```

### 2) Mount it persistently at `/media/cdrom`

```bash
mkdir -p /media/cdrom
echo '/root/boot.iso /media/cdrom iso9660 ro,loop 0 0' >> /etc/fstab
mount -a
ls /media/cdrom
```

Expected output includes at least:

```text
BaseOS
AppStream
```

### 3) Create the local repository file

```bash
cat > /etc/yum.repos.d/local.repo <<'EOF'
[BaseOS]
name=RHEL 10 BaseOS
baseurl=file:///media/cdrom/BaseOS
enabled=1
gpgcheck=0

[AppStream]
name=RHEL 10 AppStream
baseurl=file:///media/cdrom/AppStream
enabled=1
gpgcheck=0
EOF
```

### 4) Method C Validate

```bash
cat /etc/fstab
mount | grep cdrom
ls /media/cdrom
cat /etc/yum.repos.d/local.repo
dnf clean all
dnf repolist
dnf --disablerepo='*' --enablerepo=BaseOS --enablerepo=AppStream list available | head
```

### 5) Optional post-repo step: install Cockpit

Once Method C is working on the host, install Cockpit if it is not already present:

```bash
dnf install -y cockpit
systemctl enable --now cockpit.socket
systemctl status cockpit.socket --no-pager
```

If `firewalld` is enabled on that host, also open the Cockpit service:

```bash
firewall-cmd --add-service=cockpit --permanent
firewall-cmd --reload
```

### Method C Green Criteria

Method C is green when:

- `/root/boot.iso` exists
- `/media/cdrom` contains `BaseOS` and `AppStream`
- `/etc/fstab` contains the `/root/boot.iso /media/cdrom iso9660 ro,loop 0 0` entry
- `/etc/yum.repos.d/local.repo` exists with correct `file:///media/cdrom/...` baseurls
- isolated package listing works with only those two repos enabled

## Suggested Practice Run Order

Use this order for a complete repetition cycle:

1. Reset repo state on `servera`
2. Practice Method A on `servera`
3. Install and validate Cockpit on `servera` if needed
4. Reset repo state on `serverb`
5. Practice Method A on `serverb`
6. Install and validate Cockpit on `serverb` if needed
7. Reset repo state on `servera`
8. Practice Method B on `servera`
9. Reset repo state on `serverb`
10. Practice Method B on `serverb`
11. Reset repo state
12. Practice Method C on a host where you want loop-mount reps

## Common Mistakes

- trying to install `cockpit` before any working repos exist
- forgetting to remove older practice repo files before retesting
- forgetting `AppStream`
- using `baseurl=/mnt/...` instead of `file:///mnt/rheliso/...`
- using `loop` for `/dev/sr0` instead of only for ISO files
- appending duplicate `/etc/fstab` entries for `/mnt/rheliso` or `/media/cdrom`
- assuming the real exam repo URLs will always be served by the local host
- forgetting to set `gpgcheck=0` when the task explicitly requires it
- validating against all enabled repos instead of isolating only the target repos

## Validation Summary

A repository method is green when:

- the target repo definitions exist in `/etc/yum.repos.d/`
- the baseurls point to the intended source
- DNF lists the repos as enabled
- `dnf --disablerepo='*' --enablerepo=... list available | head` succeeds using only the target repos

## Lab Note

Method A is the primary answer for a task that explicitly says to use attached installation media.

Method B is the right pattern when the task gives you two explicit repo server URLs.

Method C is the right pattern when the task gives you a regular ISO file path and expects a loop-mounted filesystem.
