# Exam 1 - Task 01 - Reset Forgotten Root Password

## Task

You have forgotten the root password for `serverb`. Securely reset the root password to `password` to regain access to the system.

## Domains Covered

- Operate running systems
- Interrupt the boot process in order to gain access to a system

## Classification

- Exam-safe/manual practice

## Objective

Recover access to the system by interrupting the boot process, entering the `rd.break` recovery environment, resetting the `root` password, and allowing SELinux to relabel the system on reboot.

## Canonical RHCSA-Style Procedure

1. Reboot the system.
2. At the GRUB menu, highlight the desired boot entry and press `e` to edit it.
3. Locate the line beginning with `linux`.
4. Append the following to the end of that line:

   ```text
   rd.break
   ```

5. Boot with `Ctrl-x`.
6. At the recovery shell, run:

   ```bash
   mount -o remount,rw /sysroot
   chroot /sysroot
   passwd root
   touch /.autorelabel
   exit
   exit
   ```

7. When prompted by `passwd`, set the root password to:

   ```text
   password
   ```

8. Allow the system to continue booting. SELinux relabeling may take several minutes.
9. Log in as `root` with the new password.

## Validation

After login, verify:

```bash
whoami
getenforce
```

Expected output:

```text
root
Enforcing
```

## Lab-Specific Result on `serverb`

During practice on `serverb`, the default GRUB kernel entry accepted `rd.break` but did not drop to a usable recovery shell. Instead, it entered dracut emergency mode and prompted for the root password for maintenance.

The `0-rescue` GRUB entry worked reliably for this task.

### Working Lab Procedure on `serverb`

1. Reboot `serverb`.
2. At the GRUB menu, select the `0-rescue` entry.
3. Press `e` to edit it.
4. Locate the line beginning with `linux`.
5. Append:

   ```text
   rd.break
   ```

6. Boot with `Ctrl-x`.
7. Run:

   ```bash
   mount -o remount,rw /sysroot
   chroot /sysroot
   passwd root
   touch /.autorelabel
   exit
   exit
   ```

8. Log in as `root` with the new password after reboot.

## Notes

- The core exam skill is editing the GRUB kernel entry and appending `rd.break`.
- `mount -o remount,rw /sysroot` is required so the installed system is writable.
- `chroot /sysroot` ensures the password change is applied to the real system, not only the initramfs environment.
- `touch /.autorelabel` is required so SELinux contexts are corrected on the next boot.
- For repetition, memorize the recovery command sequence until it is fast and reliable.

## Common Mistakes

- Appending `rd.break` to the wrong line
- Forgetting to remount `/sysroot` read-write
- Forgetting `chroot /sysroot`
- Forgetting `touch /.autorelabel`
- Pressing `Ctrl-d` and continuing boot instead of completing the recovery procedure
- Assuming every GRUB entry behaves identically in a lab VM

## Practice Outcome

- Boot interruption successful
- Root password reset successful
- Login with new root password successful
- SELinux relabel completed successfully

## Optional Lab Investigation

On `serverb`, inspection showed that the normal kernel entry and rescue entry used the same root and LVM arguments, but different initramfs images:

- Normal entry:
  - `/boot/initramfs-6.12.0-124.8.1.el10_1.x86_64.img`
- Rescue entry:
  - `/boot/initramfs-0-rescue-<machine-id>.img`

The rescue initramfs was larger and behaved more reliably for this recovery task. This is a useful lab note, but not required for RHCSA execution of the objective.
