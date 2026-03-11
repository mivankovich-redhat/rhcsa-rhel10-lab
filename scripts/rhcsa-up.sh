#!/usr/bin/env bash
set -euo pipefail

# Bring up RHCSA lab (host): virbr0 + vm1/vm2
#
# Usage:
#   chmod +x ~/scripts/rhcsa-up.sh
#   ~/scripts/rhcsa-up.sh
#
# Overrides:
#   VM1_NAME=vm1 VM2_NAME=vm2 NET_NAME=default ~/scripts/rhcsa-up.sh

VM1_NAME="${VM1_NAME:-vm1}"
VM2_NAME="${VM2_NAME:-vm2}"
NET_NAME="${NET_NAME:-default}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }
}

echo "==> Preflight"
require_cmd sudo
require_cmd virsh
require_cmd ip

echo "==> Ensure libvirtd is running"
sudo systemctl enable --now libvirtd >/dev/null

echo "==> Ensure libvirt network '$NET_NAME' is active"
if ! sudo virsh net-info "$NET_NAME" >/dev/null 2>&1; then
  echo "ERROR: network '$NET_NAME' not found (qemu:///system)." >&2
  exit 1
fi

NET_ACTIVE="$(sudo virsh net-info "$NET_NAME" | awk -F': *' '/Active:/ {print $2}')"
if [[ "$NET_ACTIVE" != "yes" ]]; then
  sudo virsh net-start "$NET_NAME" >/dev/null
fi
sudo virsh net-autostart "$NET_NAME" >/dev/null || true

echo "==> Bring up virbr0 (if present)"
if ip link show virbr0 >/dev/null 2>&1; then
  sudo ip link set virbr0 up || true
fi

echo "==> Start VMs: $VM1_NAME $VM2_NAME"
sudo virsh start "$VM1_NAME" >/dev/null 2>&1 || true
sudo virsh start "$VM2_NAME" >/dev/null 2>&1 || true

sleep 3

echo
echo "==> Status:"
sudo virsh list --all

echo
echo "==> IPs (domifaddr may require qemu-guest-agent in guests):"
sudo virsh domifaddr "$VM1_NAME" || true
echo
sudo virsh domifaddr "$VM2_NAME" || true

echo
echo "==> DHCP leases (network '$NET_NAME'):"
sudo virsh net-dhcp-leases "$NET_NAME" || true

echo
echo "==> Host bridge:"
ip -br a | grep -E 'virbr0|vnet' || true
