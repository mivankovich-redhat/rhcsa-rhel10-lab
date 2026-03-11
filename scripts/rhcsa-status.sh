#!/usr/bin/env bash
set -euo pipefail

# RHCSA lab status (host): vm1/vm2 + libvirt network + disks + baselines
#
# Goals:
# - Fast, readable health snapshot
# - Works whether VMs are running or shut off
# - Treats virbr0 "DOWN" as OK when no vnet ports exist (no carrier)
# - Adds a single PASS/FAIL summary at the end
#
# Usage:
#   chmod +x ~/scripts/rhcsa-status.sh
#   ~/scripts/rhcsa-status.sh
#
# Overrides:
#   VM1_NAME=vm1 VM2_NAME=vm2 NET_NAME=default POOL_DIR=/var/lib/libvirt/images/rhcsa ~/scripts/rhcsa-status.sh

VM1_NAME="${VM1_NAME:-vm1}"
VM2_NAME="${VM2_NAME:-vm2}"
NET_NAME="${NET_NAME:-default}"
POOL_DIR="${POOL_DIR:-/var/lib/libvirt/images/rhcsa}"

VM1_DISK="${VM1_DISK:-$POOL_DIR/vm1.qcow2}"
VM2_DISK="${VM2_DISK:-$POOL_DIR/vm2.qcow2}"
VM1_BASE="${VM1_BASE:-$POOL_DIR/vm1.base.qcow2}"
VM2_BASE="${VM2_BASE:-$POOL_DIR/vm2.base.qcow2}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1" >&2; exit 1; }; }
require_cmd virsh
require_cmd qemu-img
require_cmd ip
require_cmd stat
require_cmd sudo

has_cmd() { command -v "$1" >/dev/null 2>&1; }

sudoq() {
  if sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
  else
    sudo "$@"
  fi
}

human_bytes() {
  local n="$1"
  if has_cmd numfmt; then
    numfmt --to=iec --suffix=B "$n"
  else
    echo "${n}B"
  fi
}

hr() { echo "--------------------------------------------------------------------------------"; }

fail=0
warn=0

mark_fail() { fail=$((fail + 1)); }
mark_warn() { warn=$((warn + 1)); }

echo "==> libvirt URI (system):"
sudoq virsh uri || true
echo

echo "==> Network '$NET_NAME' (system):"
if sudoq virsh net-info "$NET_NAME" >/dev/null 2>&1; then
  sudoq virsh net-info "$NET_NAME" | sed 's/^/  /'
else
  echo "  FAIL: network '$NET_NAME' not found"
  mark_fail
fi
echo

echo "==> Host bridge/interfaces:"
# Capture virbr0 details
if ip link show virbr0 >/dev/null 2>&1; then
  echo "  virbr0:"
  ip -br a | awk '$1=="virbr0"{print "    " $0}'
  ip link show virbr0 | sed 's/^/    /'
else
  echo "  WARN: virbr0 not present (unexpected if using libvirt default NAT)"
  mark_warn
fi

# vnet ports (only present when VMs run)
VNETS="$(ip -br a | awk '$1 ~ /^vnet/ {print $1}' || true)"
if [[ -n "$VNETS" ]]; then
  echo "  vnet ports:"
  ip -br a | awk '$1 ~ /^vnet/ {print "    " $0}'
else
  echo "  vnet ports: (none)  # OK if VMs are shut off"
fi
echo

echo "==> Domains (system):"
sudoq virsh list --all || true
echo

vm_exists() { sudoq virsh dominfo "$1" >/dev/null 2>&1; }
vm_state()  { sudoq virsh domstate "$1" 2>/dev/null | tr -d '\r' || true; }

domain_block() {
  local name="$1"

  echo "-- $name"
  if ! vm_exists "$name"; then
    echo "  FAIL: domain not found"
    mark_fail
    echo
    return 0
  fi

  local st
  st="$(vm_state "$name")"
  echo "  state: ${st:-unknown}"

  echo "  disks:"
  sudoq virsh domblklist "$name" --details 2>/dev/null | sed 's/^/    /' || echo "    (domblklist failed)"

  echo "  ip(s):"
  if [[ "$st" == "running" ]]; then
    sudoq virsh domifaddr "$name" 2>/dev/null | sed 's/^/    /' || echo "    (no agent / domifaddr failed)"
  else
    echo "    (VM not running)"
  fi

  # Check for snapshot overlays (vda pointing to *.clean or backing chain)
  local vda
  vda="$(sudoq virsh domblklist "$name" --details 2>/dev/null | awk '$3=="vda"{print $4; exit}' || true)"
  if [[ -n "$vda" ]]; then
    if [[ "$vda" == *.clean ]]; then
      echo "  WARNING: vda points to *.clean overlay ($vda) — baseline reset model expects *.qcow2"
      mark_warn
    fi
    if [[ -f "$vda" ]]; then
      if sudoq qemu-img info -U "$vda" 2>/dev/null | grep -q '^backing file:'; then
        echo "  WARNING: disk has backing file chain ($vda) — overlays still in play"
        mark_warn
      fi
    fi
  fi

  echo
}

echo "==> Domain detail:"
domain_block "$VM1_NAME"
domain_block "$VM2_NAME"

echo "==> DHCP leases (network '$NET_NAME'):"
if sudoq virsh net-dhcp-leases "$NET_NAME" >/dev/null 2>&1; then
  sudoq virsh net-dhcp-leases "$NET_NAME" | sed 's/^/  /'
else
  echo "  (no leases / network not found)"
fi
echo

file_line() {
  local label="$1"
  local p="$2"
  if [[ -f "$p" ]]; then
    local sz
    sz="$(sudoq stat -c '%s' "$p" 2>/dev/null || echo 0)"
    echo "  - $label: $p ($(human_bytes "$sz"))"
  else
    echo "  FAIL: $label missing: $p"
    mark_fail
  fi
}

echo "==> Disks:"
file_line "vm1 baseline" "$VM1_BASE"
file_line "vm2 baseline" "$VM2_BASE"
file_line "vm1 active" "$VM1_DISK"
file_line "vm2 active" "$VM2_DISK"
echo

disk_summary() {
  local label="$1"
  local p="$2"
  echo "-- $label: $p"
  if [[ ! -f "$p" ]]; then
    echo "  (missing)"
    return 0
  fi

  local out
  if ! out="$(sudoq qemu-img info -U "$p" 2>/dev/null)"; then
    echo "  (qemu-img info failed; likely locked by running QEMU without -U or permissions issue)"
    return 0
  fi

  echo "$out" | awk '
    /^image:/ {print "  " $0}
    /^file format:/ {print "  " $0}
    /^virtual size:/ {print "  " $0}
    /^disk size:/ {print "  " $0}
    /^backing file:/ {print "  " $0}
  '
  echo
}

echo "==> Disk detail (qemu-img info summary):"
disk_summary "vm1 active" "$VM1_DISK"
disk_summary "vm2 active" "$VM2_DISK"

# Bridge health interpretation:
# - virbr0 shows NO-CARRIER/state DOWN when no vnet ports exist (VMs off) — OK
# - If any VM is running but no vnet ports exist — FAIL
VM1_ST="$(vm_state "$VM1_NAME")"
VM2_ST="$(vm_state "$VM2_NAME")"
ANY_RUNNING=0
[[ "$VM1_ST" == "running" ]] && ANY_RUNNING=1
[[ "$VM2_ST" == "running" ]] && ANY_RUNNING=1

if [[ "$ANY_RUNNING" -eq 1 && -z "$VNETS" ]]; then
  echo "==> FAIL: VM(s) running but no vnet ports detected on host (bridge attach issue)"
  mark_fail
fi

hr
if [[ "$fail" -eq 0 ]]; then
  echo "SUMMARY: PASS (warnings=$warn)"
else
  echo "SUMMARY: FAIL (failures=$fail warnings=$warn)"
  exit 1
fi
