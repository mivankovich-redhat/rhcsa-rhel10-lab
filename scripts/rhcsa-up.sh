#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/rhcsa-env.sh
source "$SCRIPT_DIR/rhcsa-env.sh"

require_cmd sudo
require_cmd virsh
require_cmd ip

echo "==> Ensuring libvirt + network"
ensure_libvirtd
ensure_network_active

for vm in "$SERVERA_NAME" "$SERVERB_NAME"; do
  if vm_exists "$vm"; then
    echo "==> Starting $vm"
    sudoq virsh start "$vm" >/dev/null 2>&1 || true
  else
    echo "WARN: domain missing: $vm"
  fi
done

sleep 2

echo
sudoq virsh list --all
echo
sudoq virsh domifaddr "$SERVERA_NAME" 2>/dev/null || true
echo
sudoq virsh domifaddr "$SERVERB_NAME" 2>/dev/null || true
echo
sudoq virsh net-dhcp-leases "$NET_NAME" 2>/dev/null || true
