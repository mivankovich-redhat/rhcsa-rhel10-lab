# Exam 1 - Task 2 - Configure Local DNF/YUM Repositories

## Exam Workflow Note

Use this task in the following order during practice:

1. get a working repository on the host
2. validate package access
3. install and enable Cockpit **after** repo access exists, unless Cockpit is already installed
4. continue the rest of the task flow using Cockpit, tmux/SSH, or the VM console as needed

This avoids the dependency loop where `cockpit` cannot be installed until package repositories are available.

## Cockpit Usage Note

If `cockpit` is already installed on a host, you may enable and use it immediately:

```bash
systemctl enable --now cockpit.socket
systemctl status cockpit.socket --no-pager
```

If `cockpit` is **not** installed, complete Method A or Method B for that host first, then install it.

## Task

Configure local package repositories for RHCSA-style practice on `servera` and `serverb`.

This practice covers two methods:

1. **Method A** - configure `BaseOS` and `AppStream` from locally mounted installation media
2. **Method B** - configure `BaseOS` and `AppStream` from URL-based repositories using `dnf config-manager --add-repo`

## Domains Covered

- Manage software
- Configure access to RPM repositories

## Classification

- Exam-safe/manual practice

## Objective

Practice both local-media and URL-based repository configuration on both `servera` and `serverb`, with a clean reset step before each run so repository state is unambiguous.

## Important Caveat

The primary task here is **local repository configuration**.

A possible lab variation is configuring `serverb` to consume repositories served by `servera` over HTTP. That is worth practicing, but it is a different topology from mounting installation media locally.

## Repository Reset / Prep Step

Run this before testing each method on each host.

```bash
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
grep -q '^/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0$' /etc/fstab || echo '/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0' >> /etc/fstab
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
- `/etc/fstab` contains the persistent `/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0` entry
- `/etc/yum.repos.d/local.repo` exists with correct `file:///mnt/rheliso/...` baseurls
- `dnf repolist` shows `BaseOS` and `AppStream`
- isolated package listing works with only those two repos enabled

## Method A - Local Installation Media on `serverb`

Repeat the same workflow on `serverb`.

### 1) Method A: Ensure the installation media is mounted persistently at `/mnt/rheliso`

```bash
mkdir -p /mnt/rheliso
grep -q '^/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0$' /etc/fstab || echo '/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0' >> /etc/fstab
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
- `/etc/fstab` contains the persistent `/dev/sr0 /mnt/rheliso iso9660 ro,nofail 0 0` entry
- `/etc/yum.repos.d/local.repo` exists with correct `file:///mnt/rheliso/...` baseurls
- `dnf repolist` shows `BaseOS` and `AppStream`
- isolated package listing works with only those two repos enabled

## Reset Again Before Method B

Run the prep block again before starting Method B on each host.

```bash
mkdir -p /root/repo-practice-backup

mv /etc/yum.repos.d/local.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/localhost_rhel10_BaseOS.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/localhost_rhel10_AppStream.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/servera_rhel10_BaseOS.repo /root/repo-practice-backup/ 2>/dev/null || true
mv /etc/yum.repos.d/servera_rhel10_AppStream.repo /root/repo-practice-backup/ 2>/dev/null || true

dnf clean all
dnf repolist all
```

## Method B - URL-Based Repositories on `servera`

This method assumes `servera` is serving the installation tree over HTTP from `/var/www/html/rhel10`.

### 1) Verify the HTTP content is reachable

```bash
systemctl enable --now httpd
curl -I http://localhost/rhel10/BaseOS/repodata/repomd.xml
curl -I http://localhost/rhel10/AppStream/repodata/repomd.xml
```

Expected result: HTTP success such as `200 OK`.

### 2) Add the repositories

```bash
dnf config-manager --add-repo="http://localhost/rhel10/BaseOS"
dnf config-manager --add-repo="http://localhost/rhel10/AppStream"
```

### 3) Set `gpgcheck=0` in the generated repo files

```bash
grep -q '^gpgcheck=' /etc/yum.repos.d/localhost_rhel10_BaseOS.repo || echo 'gpgcheck=0' >> /etc/yum.repos.d/localhost_rhel10_BaseOS.repo
grep -q '^gpgcheck=' /etc/yum.repos.d/localhost_rhel10_AppStream.repo || echo 'gpgcheck=0' >> /etc/yum.repos.d/localhost_rhel10_AppStream.repo
sed -i 's/^gpgcheck=.*/gpgcheck=0/' /etc/yum.repos.d/localhost_rhel10_BaseOS.repo
sed -i 's/^gpgcheck=.*/gpgcheck=0/' /etc/yum.repos.d/localhost_rhel10_AppStream.repo
```

### 4) Validate

```bash
cat /etc/yum.repos.d/localhost_rhel10_BaseOS.repo
cat /etc/yum.repos.d/localhost_rhel10_AppStream.repo
dnf clean all
dnf repolist all
dnf --disablerepo='*' --enablerepo=localhost_rhel10_BaseOS --enablerepo=localhost_rhel10_AppStream list available | head
```

### 5) Optional post-repo step: install Cockpit on `servera`

Once Method B is working on `servera`, install Cockpit if it is not already present:

```bash
dnf install -y cockpit
systemctl enable --now cockpit.socket
firewall-cmd --add-service=cockpit --permanent
firewall-cmd --reload
systemctl status cockpit.socket --no-pager
```

### Method B Green Criteria

Method B on `servera` is green when:

- the two generated `.repo` files exist
- both use the expected `http://localhost/rhel10/...` baseurls
- both have `gpgcheck=0`
- both appear enabled in `dnf repolist all`
- isolated package listing works with only those two repos enabled

## Method B - URL-Based Repositories on `serverb`

### Recommended Practice Variant

For `serverb`, use `servera` as the HTTP source. This gives you both URL-based repo practice and remote repo-consumer practice.

Before starting, ensure:

- `servera` is serving `/var/www/html/rhel10`
- `httpd` is running on `servera`
- `serverb` can resolve `servera`
- HTTP access from `serverb` to `servera` is allowed

### 1) Practice Variant: Verify `servera` is reachable from `serverb`

```bash
curl -I http://servera/rhel10/BaseOS/repodata/repomd.xml
curl -I http://servera/rhel10/AppStream/repodata/repomd.xml
```

Expected result: HTTP success such as `200 OK`.

### 2) Practice Variant: Add the repositories from `servera`

```bash
dnf config-manager --add-repo="http://servera/rhel10/BaseOS"
dnf config-manager --add-repo="http://servera/rhel10/AppStream"
```

### 3) Practice Variant: Discover the generated repo files and set `gpgcheck=0`

Confirm which files were generated on your host before editing them:

```bash
grep -Rni 'servera/rhel10' /etc/yum.repos.d
```

Then set variables for the actual generated files and update them:

```bash
BASEOS_REPO_FILE=$(grep -Ril 'baseurl=http://servera/rhel10/BaseOS' /etc/yum.repos.d)
APPSTREAM_REPO_FILE=$(grep -Ril 'baseurl=http://servera/rhel10/AppStream' /etc/yum.repos.d)

grep -q '^gpgcheck=' "$BASEOS_REPO_FILE" || echo 'gpgcheck=0' >> "$BASEOS_REPO_FILE"
grep -q '^gpgcheck=' "$APPSTREAM_REPO_FILE" || echo 'gpgcheck=0' >> "$APPSTREAM_REPO_FILE"

sed -i 's/^gpgcheck=.*/gpgcheck=0/' "$BASEOS_REPO_FILE"
sed -i 's/^gpgcheck=.*/gpgcheck=0/' "$APPSTREAM_REPO_FILE"
```

### 4) Practice Variant: Validate

```bash
cat "$BASEOS_REPO_FILE"
cat "$APPSTREAM_REPO_FILE"
dnf clean all
dnf repolist all
dnf --disablerepo='*' --enablerepo="$(basename "$BASEOS_REPO_FILE" .repo)" --enablerepo="$(basename "$APPSTREAM_REPO_FILE" .repo)" list available | head
```

### 5) Optional post-repo step: install Cockpit on `serverb`

Once Method B is working on `serverb`, install Cockpit if it is not already present:

```bash
dnf install -y cockpit
systemctl enable --now cockpit.socket
systemctl status cockpit.socket --no-pager
```

If you later enable `firewalld` on `serverb`, also open the Cockpit service.

### Practice Variant: Green Criteria

Method B on `serverb` is green when:

- the two generated `.repo` files exist
- both use the expected `http://servera/rhel10/...` baseurls
- both have `gpgcheck=0`
- both appear enabled in `dnf repolist all`
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
10. Practice Method B on `serverb` using `servera` as the source

## Common Mistakes

- trying to install `cockpit` before any working repos exist
- forgetting to remove older practice repo files before retesting
- forgetting `AppStream`
- using `baseurl=/mnt/...` instead of `file:///mnt/rheliso/...`
- appending duplicate `/etc/fstab` entries for `/mnt/rheliso`
- assuming URL-based repo IDs instead of inspecting what was generated
- forgetting to set `gpgcheck=0` when the task explicitly requires it
- validating against all enabled repos instead of isolating only the target repos
- assuming `serverb` should always use `localhost` for Method B

## Validation Summary

A repository method is green when:

- the target repo definitions exist in `/etc/yum.repos.d/`
- the baseurls point to the intended source
- DNF lists the repos as enabled
- `dnf --disablerepo='*' --enablerepo=... list available | head` succeeds using only the target repos

## Lab Note

Method A is the primary answer for a task that explicitly says to mount installation media and configure `BaseOS` and `AppStream` from it.

Method B is a valid alternate pattern when a repository URL is provided or when one system is intended to consume repositories served by another host.
