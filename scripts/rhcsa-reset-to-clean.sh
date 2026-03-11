#!/usr/bin/env bash
set -euo pipefail

# RHCSA reset-to-clean (UEFI-safe, deterministic, minimal sudo)
#
# Model:
# - Keep golden baselines:
#     /var/lib/libvirt/images/rhcsa/vm1.base.qcow2
#     /var/lib/libvirt/images/rhcsa/vm2.base.qcow2
# - Reset by copying base -> active qcow2 and restarting VMs.
#
# This version assumes you've already set pool perms so the *user* can overwrite disks:
#   sudo chown -R root:libvirt /var/lib/libvirt/images/rhcsa
#   sudo chmod 0775 /var/lib/libvirt/images/rhcsa
#   sudo find /var/lib/libvirt/images/rhcsa -maxdepth 1 -type f -name 'vm*.qcow2*' -exec chmod 0660 {} \;
# and your user is in group libvirt.
#
# One-time baseline creation (run when VMs are in desired "clean" state):
#   POOL=/var/lib/libvirt/images/rhcsa
#   sudo virsh destroy vm1 2>/dev/null || true
#   sudo virsh destroy vm2 2>/dev/null || true
#   cp -f "$POOL/vm1.qcow2" "$POOL/vm1.base.qcow2"
#   cp -f "$POOL/vm2.qcow2" "$POOL/vm2.base.qcow2"
#   # baseline files should end up root:libvirt 0660 (optional)
#   sudo chown root:libvirt "$POOL/vm1.base.qcow2" "$POOL/vm2.base.qcow2"
#   sudo chmod 0660 "$POOL/vm1.base.qcow2" "$POOL/vm2.base.qcow2"
#
# Usage:
#   chmod +x ~/scripts/rhcsa-reset-to-clean.sh
#   ~/scripts/rhcsa-reset-to-clean.sh
#
# Overrides:
#   VM1_NAME=vm1 VM2_NAME=vm2 POOL_DIR=/var/lib/libvirt/images/rhcsa NET_NAME=default \
#     ~/scripts/rhcsa-reset-to-clean.sh

VM1_NAME="${VM1_NAME:-vm1}"
VM2_NAME="${VM2_NAME:-vm2}"

POOL_DIR="${POOL_DIR:-/var/lib/libvirt/images/rhcsa}"
NET_NAME="${NET_NAME:-default}"

VM1_DISK="${VM1_DISK:-$POOL_DIR/vm1.qcow2}"
VM2_DISK="${VM2_DISK:-$POOL_DIR/vm2.qcow2}"
VM1_BASE="${VM1_BASE:-$POOL_DIR/vm1.base.qcow2}"
VM2_BASE="${VM2_BASE:-$POOL_DIR/vm2.base.qcow2}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1" >&2; exit 1; }; }
require_cmd sudo
require_cmd virsh
require_cmd ip
require_cmd cp
require_cmd sync
require_cmd id

sudoq() {
  if sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
  else
    sudo "$@"
  fi
}

vm_exists() { sudoq virsh dominfo "$1" >/dev/null 2>&1; }
vm_state() { sudoq virsh domstate "$1" 2>/dev/null | tr -d '\r' || true; }

ensure_pool_writable_or_die() {
  # We expect disk copies (base->active) to run WITHOUT sudo.
  # This requires group libvirt membership and pool perms.
  if ! id -nG "$USER" | tr ' ' '\n' | grep -Fxq libvirt; then
    echo "ERROR: user '$USER' is not in group 'libvirt'." >&2
    echo "Fix: sudo usermod -aG libvirt,kvm \"$USER\" && newgrp libvirt" >&2
    exit 1
  fi

  if [[ ! -d "$POOL_DIR" ]]; then
    echo "ERROR: pool dir missing: $POOL_DIR" >&2
    exit 1
  fi

  if [[ ! -w "$POOL_DIR" ]]; then
    echo "ERROR: pool dir not writable by '$USER': $POOL_DIR" >&2
    echo "Fix (one-time): sudo chown -R root:libvirt $POOL_DIR && sudo chmod 0775 $POOL_DIR" >&2
    exit 1
  fi
}

ensure_libvirt_ready() {
  echo "==> Ensure libvirtd is running"
  sudoq systemctl enable --now libvirtd >/dev/null

  echo "==> Ensure libvirt network '$NET_NAME' exists + active"
  if ! sudoq virsh net-info "$NET_NAME" >/dev/null 2>&1; then
    echo "ERROR: libvirt network '$NET_NAME' not found under qemu:///system." >&2
    echo "Try: sudo virsh net-define /usr/share/libvirt/networks/default.xml && sudo virsh net-start default" >&2
    exit 1
  fi

  local active
  active="$(sudoq virsh net-info "$NET_NAME" | awk -F': *' '/Active:/ {print $2}')"
  if [[ "$active" != "yes" ]]; then
    sudoq virsh net-start "$NET_NAME" >/dev/null
  fi
  sudoq virsh net-autostart "$NET_NAME" >/dev/null || true

  # Bring virbr0 up if present. Note: bridge may show NO-CARRIER/DOWN if VMs are off.
  if ip link show virbr0 >/dev/null 2>&1; then
    sudoq ip link set virbr0 up || true
  fi
}

power_off() {
  local name="$1"
  vm_exists "$name" || { echo "ERROR: VM not found: $name" >&2; exit 1; }

  local st
  st="$(vm_state "$name")"
  if [[ "$st" == "shut off" || "$st" == "shutoff" ]]; then
    return 0
  fi

  echo "==> Shutting down $name"
  sudoq virsh shutdown "$name" >/dev/null 2>&1 || true

  for _ in {1..30}; do
    st="$(vm_state "$name")"
    [[ "$st" == "shut off" || "$st" == "shutoff" ]] && return 0
    sleep 1
  done

  echo "==> $name did not shut down in time; forcing destroy"
  sudoq virsh destroy "$name" >/dev/null 2>&1 || true
}

reset_disk_from_base() {
  local base="$1"
  local disk="$2"

  [[ -f "$base" ]] || {
    echo "ERROR: baseline missing: $base" >&2
    echo "Create it once from a known-good state (see header comments)." >&2
    exit 1
  }

  # Ensure we can overwrite target without sudo.
  if [[ -f "$disk" && ! -w "$disk" ]]; then
    echo "ERROR: disk not writable by '$USER': $disk" >&2
    echo "Fix (one-time): sudo chown root:libvirt $disk && sudo chmod 0660 $disk" >&2
    exit 1
  fi

  echo "==> Reset disk:"
  echo "    $base -> $disk"
  cp -f "$base" "$disk"
}

echo "==> Resetting VMs via baseline disk copy"
echo "==> Pool: $POOL_DIR"
echo

ensure_pool_writable_or_die
ensure_libvirt_ready

power_off "$VM1_NAME"
power_off "$VM2_NAME"

reset_disk_from_base "$VM1_BASE" "$VM1_DISK"
reset_disk_from_base "$VM2_BASE" "$VM2_DISK"

sync

echo "==> Starting VMs"
sudoq virsh start "$VM1_NAME" >/dev/null
sudoq virsh start "$VM2_NAME" >/dev/null

sleep 2

echo
echo "==> Status:"
sudoq virsh list --all

echo
echo "==> IPs (domifaddr may require qemu-guest-agent in guests):"
sudoq virsh domifaddr "$VM1_NAME" 2>/dev/null || true
echo
sudoq virsh domifaddr "$VM2_NAME" 2>/dev/null || true

echo
echo "==> DHCP leases (network '$NET_NAME'):"
sudoq virsh net-dhcp-leases "$NET_NAME" 2>/dev/null || true
