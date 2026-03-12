#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/rhcsa-env.sh
source "$SCRIPT_DIR/rhcsa-env.sh"

require_cmd sudo
require_cmd virsh
require_cmd cp
require_cmd sync

copy_baseline_for_vm() {
  local vm="$1"

  while IFS=: read -r label _size; do
    [[ -n "$label" ]] || continue

    local active base
    active="$(active_disk_path "$vm" "$label")"
    base="$(base_disk_path "$vm" "$label")"

    if [[ ! -f "$active" ]]; then
      echo "ERROR: active disk missing: $active" >&2
      exit 1
    fi

    echo "==> Capturing baseline: $active -> $base"
    sudoq cp -f "$active" "$base"
    sudoq chown root:libvirt "$base"
    sudoq chmod 0660 "$base"
  done < <(vm_disk_specs "$vm")
}

echo "==> Stopping VMs before baseline capture"
shutdown_wait "$SERVERA_NAME"
shutdown_wait "$SERVERB_NAME"

copy_baseline_for_vm "$SERVERA_NAME"
copy_baseline_for_vm "$SERVERB_NAME"

sync

echo
echo "==> Baselines captured:"
expected_base_disks | sed 's#^#  - #'
