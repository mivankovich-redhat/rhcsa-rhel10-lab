#!/usr/bin/env bash
set -euo pipefail

# Destroy RHCSA lab VMs and disks (hard reset)
# - UEFI safe (undefine --nvram)
# - Best-effort removal of DHCP reservations on libvirt NAT network
# - Deletes vm1/vm2 disks AND any stray overlay files from old snapshot attempts
# - Optionally deletes baseline disks if DELETE_BASE=1
#
# Usage:
#   chmod +x ~/scripts/rhcsa-destroy-vms.sh
#   ~/scripts/rhcsa-destroy-vms.sh
#
# Delete baselines too:
#   DELETE_BASE=1 ~/scripts/rhcsa-destroy-vms.sh
#
# Overrides:
#   VM1_NAME=vm1 VM2_NAME=vm2 POOL_DIR=/var/lib/libvirt/images/rhcsa NET_NAME=default ~/scripts/rhcsa-destroy-vms.sh

VM1_NAME="${VM1_NAME:-vm1}"
VM2_NAME="${VM2_NAME:-vm2}"

POOL_DIR="${POOL_DIR:-/var/lib/libvirt/images/rhcsa}"
NET_NAME="${NET_NAME:-default}"

# MAC/IP defaults (only used for DHCP reservation cleanup best-effort)
VM1_MAC="${VM1_MAC:-52:54:00:d8:8d:2e}"
VM2_MAC="${VM2_MAC:-52:54:00:6d:66:99}"
VM1_IP="${VM1_IP:-192.168.122.31}"
VM2_IP="${VM2_IP:-192.168.122.66}"

VM1_DISK="${VM1_DISK:-$POOL_DIR/vm1.qcow2}"
VM2_DISK="${VM2_DISK:-$POOL_DIR/vm2.qcow2}"
VM1_BASE="${VM1_BASE:-$POOL_DIR/vm1.base.qcow2}"
VM2_BASE="${VM2_BASE:-$POOL_DIR/vm2.base.qcow2}"

DELETE_BASE="${DELETE_BASE:-0}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1" >&2; exit 1; }; }
require_cmd sudo
require_cmd virsh
require_cmd find

sudoq() {
  if sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
  else
    sudo "$@"
  fi
}

vm_exists() { sudoq virsh dominfo "$1" >/dev/null 2>&1; }
vm_state() { sudoq virsh domstate "$1" 2>/dev/null | tr -d '\r' || true; }

shutdown_wait() {
  local name="$1"
  local tries=45

  if ! vm_exists "$name"; then
    return 0
  fi

  local st
  st="$(vm_state "$name")"
  if [[ "$st" == "shut off" || "$st" == "shutoff" ]]; then
    return 0
  fi

  echo "==> Shutting down $name"
  sudoq virsh shutdown "$name" >/dev/null 2>&1 || true

  while (( tries > 0 )); do
    st="$(vm_state "$name")"
    if [[ "$st" == "shut off" || "$st" == "shutoff" ]]; then
      return 0
    fi
    sleep 2
    tries=$((tries - 1))
  done

  echo "==> $name did not shut down in time; forcing destroy"
  sudoq virsh destroy "$name" >/dev/null 2>&1 || true
}

net_exists() { sudoq virsh net-info "$NET_NAME" >/dev/null 2>&1; }

delete_dhcp_reservation_best_effort() {
  local name="$1"
  local mac="$2"
  local ip="$3"

  if ! net_exists; then
    echo "==> Network '$NET_NAME' not found (skip DHCP reservation cleanup)"
    return 0
  fi

  local xml="<host mac='${mac}' name='${name}' ip='${ip}'/>"
  echo "==> Removing DHCP reservation (best effort): ${name} -> ${ip} (${mac}) from network '$NET_NAME'"
  sudoq virsh net-update "$NET_NAME" delete ip-dhcp-host "${xml}" --live --config >/dev/null 2>&1 || true
}

undefine_vm() {
  local name="$1"
  if ! vm_exists "$name"; then
    echo "==> VM not found: $name (skip)"
    return 0
  fi
  echo "==> Undefining $name (remove NVRAM if present)"
  sudoq virsh undefine "$name" --nvram >/dev/null 2>&1 || sudoq virsh undefine "$name" >/dev/null
}

delete_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    echo "==> Deleting: $path"
    sudoq rm -f -- "$path"
  fi
}

delete_disk_family() {
  local stem="$1"
  # Delete vm*.qcow2 plus common overlay remnants:
  # - vm1.clean (old overlay)
  # - vm1.*.qcow2 (timestamped backups)
  # - vm1-*.qcow2 (other variants)
  sudoq find "$POOL_DIR" -maxdepth 1 -type f \
    \( -name "${stem}.qcow2" -o -name "${stem}.clean" -o -name "${stem}.*.qcow2" -o -name "${stem}-*.qcow2" \) \
    -print -delete || true
}

echo "==> Targets: $VM1_NAME $VM2_NAME"
echo "==> Pool dir: $POOL_DIR"
echo "==> Network: $NET_NAME"
echo "==> DELETE_BASE=$DELETE_BASE"
echo

shutdown_wait "$VM1_NAME"
shutdown_wait "$VM2_NAME"

delete_dhcp_reservation_best_effort "$VM1_NAME" "$VM1_MAC" "$VM1_IP"
delete_dhcp_reservation_best_effort "$VM2_NAME" "$VM2_MAC" "$VM2_IP"

undefine_vm "$VM1_NAME"
undefine_vm "$VM2_NAME"

echo "==> Deleting disks + overlays"
delete_disk_family "vm1"
delete_disk_family "vm2"

if [[ "$DELETE_BASE" == "1" ]]; then
  echo "==> Deleting baselines"
  delete_file "$VM1_BASE"
  delete_file "$VM2_BASE"
fi

echo
echo "==> Remaining domains:"
sudoq virsh list --all || true

echo
echo "==> DHCP leases (network '$NET_NAME'):"
sudoq virsh net-dhcp-leases "$NET_NAME" 2>/dev/null || true
