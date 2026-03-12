#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/rhcsa-env.sh
source "$SCRIPT_DIR/rhcsa-env.sh"

require_cmd sudo
require_cmd virsh
require_cmd rm
require_cmd find

remove_reservation() {
  local name="$1"
  local mac="$2"
  local ip="$3"

  if ! net_exists; then
    return 0
  fi

  local xml="<host mac='${mac}' name='${name}' ip='${ip}'/>"
  sudoq virsh net-update "$NET_NAME" delete ip-dhcp-host "$xml" --live --config >/dev/null 2>&1 || true
}

undefine_vm() {
  local vm="$1"
  if vm_exists "$vm"; then
    echo "==> Undefining $vm"
    sudoq virsh undefine "$vm" --nvram >/dev/null 2>&1 || sudoq virsh undefine "$vm" >/dev/null 2>&1 || true
  fi
}

delete_vm_disks() {
  local vm="$1"
  local delete_base="$2"

  while IFS=: read -r label _size; do
    [[ -n "$label" ]] || continue

    local active base
    active="$(active_disk_path "$vm" "$label")"
    base="$(base_disk_path "$vm" "$label")"

    if [[ -f "$active" ]]; then
      echo "==> Deleting $active"
      sudoq rm -f -- "$active"
    fi

    if [[ "$delete_base" == "1" && -f "$base" ]]; then
      echo "==> Deleting $base"
      sudoq rm -f -- "$base"
    fi
  done < <(vm_disk_specs "$vm")
}

echo "==> Stopping domains"
shutdown_wait "$SERVERA_NAME"
shutdown_wait "$SERVERB_NAME"

remove_reservation "$SERVERA_NAME" "$SERVERA_MAC" "$SERVERA_IP"
remove_reservation "$SERVERB_NAME" "$SERVERB_MAC" "$SERVERB_IP"

undefine_vm "$SERVERA_NAME"
undefine_vm "$SERVERB_NAME"

delete_vm_disks "$SERVERA_NAME" "$DELETE_BASE"
delete_vm_disks "$SERVERB_NAME" "$DELETE_BASE"

if [[ "$DELETE_NETWORK" == "1" ]] && net_exists; then
  echo "==> Removing network $NET_NAME"
  sudoq virsh net-destroy "$NET_NAME" >/dev/null 2>&1 || true
  sudoq virsh net-undefine "$NET_NAME" >/dev/null 2>&1 || true
fi

echo
sudoq virsh list --all || true
echo
if net_exists; then
  sudoq virsh net-info "$NET_NAME" || true
fi
