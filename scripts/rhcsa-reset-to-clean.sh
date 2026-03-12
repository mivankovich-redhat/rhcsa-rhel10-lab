#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/rhcsa-env.sh
source "$SCRIPT_DIR/rhcsa-env.sh"

require_cmd sudo
require_cmd virsh
require_cmd cp
require_cmd sync
require_cmd ip

reset_vm_from_baseline() {
  local vm="$1"

  while IFS=: read -r label _size; do
    [[ -n "$label" ]] || continue

    local active base
    active="$(active_disk_path "$vm" "$label")"
    base="$(base_disk_path "$vm" "$label")"

    if [[ ! -f "$base" ]]; then
      echo "ERROR: missing baseline disk: $base" >&2
      echo "Run ./scripts/rhcsa-capture-baselines.sh first." >&2
      exit 1
    fi

    echo "==> Resetting $vm/$label"
    echo "    $base -> $active"
    sudoq cp -f "$base" "$active"
    sudoq chown root:libvirt "$active"
    sudoq chmod 0660 "$active"
  done < <(vm_disk_specs "$vm")
}

echo "==> Ensuring libvirt + network"
ensure_libvirtd
ensure_network_active

echo "==> Powering off VMs"
shutdown_wait "$SERVERA_NAME"
shutdown_wait "$SERVERB_NAME"

echo "==> Restoring active disks from baselines"
reset_vm_from_baseline "$SERVERA_NAME"
reset_vm_from_baseline "$SERVERB_NAME"

sync

echo "==> Starting VMs"
sudoq virsh start "$SERVERA_NAME" >/dev/null
sudoq virsh start "$SERVERB_NAME" >/dev/null

sleep 2

echo
sudoq virsh list --all
echo
sudoq virsh domifaddr "$SERVERA_NAME" 2>/dev/null || true
echo
sudoq virsh domifaddr "$SERVERB_NAME" 2>/dev/null || true
