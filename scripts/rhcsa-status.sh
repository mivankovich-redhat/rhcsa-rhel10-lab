#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/rhcsa-env.sh
source "$SCRIPT_DIR/rhcsa-env.sh"

require_cmd sudo
require_cmd virsh
require_cmd qemu-img
require_cmd ip
require_cmd stat

fail=0
warn=0

mark_fail() { fail=$((fail + 1)); }
mark_warn() { warn=$((warn + 1)); }

file_line() {
  local label="$1"
  local path="$2"

  if [[ -f "$path" ]]; then
    local sz
    sz="$(sudoq stat -c '%s' "$path" 2>/dev/null || echo 0)"
    echo "  - $label: $path ($(human_bytes "$sz"))"
  else
    echo "  FAIL: $label missing: $path"
    mark_fail
  fi
}

disk_info() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  sudoq qemu-img info -U "$path" 2>/dev/null | awk '
    /^image:/       {print "    " $0}
    /^file format:/ {print "    " $0}
    /^virtual size:/ {print "    " $0}
    /^disk size:/   {print "    " $0}
    /^backing file:/ {print "    " $0}
  '
}

domain_block() {
  local vm="$1"

  echo "-- $vm"
  if ! vm_exists "$vm"; then
    echo "  FAIL: domain not found"
    mark_fail
    echo
    return 0
  fi

  local st
  st="$(vm_state "$vm")"
  echo "  state: ${st:-unknown}"

  echo "  block devices:"
  sudoq virsh domblklist "$vm" --details 2>/dev/null | sed 's/^/    /' || true

  if [[ "$st" == "running" ]]; then
    echo "  addresses:"
    sudoq virsh domifaddr "$vm" 2>/dev/null | sed 's/^/    /' || echo "    (guest agent unavailable)"
  fi

  while IFS=: read -r label _size; do
    [[ -n "$label" ]] || continue
    local active
    active="$(active_disk_path "$vm" "$label")"
    if [[ -f "$active" ]]; then
      if sudoq qemu-img info -U "$active" 2>/dev/null | grep -q '^backing file:'; then
        echo "  WARN: backing file chain detected on $active"
        mark_warn
      fi
    fi
  done < <(vm_disk_specs "$vm")

  echo
}

echo "==> libvirt"
sudoq virsh uri || true
echo

echo "==> network"
if net_exists; then
  sudoq virsh net-info "$NET_NAME" | sed 's/^/  /'
  echo "  bridge: $(get_network_bridge)"
else
  echo "  FAIL: network '$NET_NAME' not found"
  mark_fail
fi
echo

echo "==> host interfaces"
bridge="$(get_network_bridge)"
if [[ -n "$bridge" ]] && ip link show "$bridge" >/dev/null 2>&1; then
  ip -br a show "$bridge" | sed 's/^/  /'
else
  echo "  WARN: bridge missing for network '$NET_NAME'"
  mark_warn
fi

if ip -br a | awk '$1 ~ /^vnet/ {exit 0} END {exit 1}'; then
  ip -br a | awk '$1 ~ /^vnet/ {print "  " $0}'
else
  echo "  (no vnet interfaces; OK if VMs are off)"
fi
echo

echo "==> domains"
sudoq virsh list --all || true
echo

domain_block "$SERVERA_NAME"
domain_block "$SERVERB_NAME"

echo "==> DHCP leases / reservations"
if net_exists; then
  sudoq virsh net-dhcp-leases "$NET_NAME" | sed 's/^/  /' || true
fi
echo

echo "==> expected active disks"
while read -r path; do
  file_line "active" "$path"
done < <(expected_active_disks)
echo

echo "==> expected baseline disks"
while read -r path; do
  file_line "baseline" "$path"
done < <(expected_base_disks)
echo

echo "==> active disk detail"
while read -r path; do
  [[ -f "$path" ]] || continue
  echo "  $path"
  disk_info "$path"
done < <(expected_active_disks)
echo

if [[ "$(vm_state "$SERVERA_NAME")" == "running" || "$(vm_state "$SERVERB_NAME")" == "running" ]]; then
  if ! ip -br a | awk '$1 ~ /^vnet/ {found=1} END {exit found?0:1}'; then
    echo "FAIL: a VM is running but no vnet interface exists on the host"
    mark_fail
  fi
fi

if [[ "$fail" -eq 0 ]]; then
  echo "SUMMARY: PASS (warnings=$warn)"
else
  echo "SUMMARY: FAIL (failures=$fail warnings=$warn)"
  exit 1
fi
