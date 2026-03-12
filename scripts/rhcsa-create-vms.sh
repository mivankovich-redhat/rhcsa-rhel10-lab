#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/rhcsa-env.sh
source "$SCRIPT_DIR/rhcsa-env.sh"

require_cmd sudo
require_cmd virsh
require_cmd virt-install
require_cmd qemu-img
require_cmd ip
require_cmd mktemp

if [[ ! -f "$ISO" ]]; then
  echo "ERROR: ISO not found: $ISO" >&2
  echo "Set ISO=/absolute/path/to/rhel-10.x-x86_64-dvd.iso" >&2
  exit 1
fi

build_vm_disks() {
  local vm="$1"
  while IFS=: read -r label size; do
    [[ -n "$label" ]] || continue
    create_qcow2_if_missing "$(active_disk_path "$vm" "$label")" "$size"
  done < <(vm_disk_specs "$vm")
}

build_vm() {
  local vm="$1"
  local mac="$2"

  if vm_exists "$vm"; then
    echo "==> Domain already exists: $vm (skip virt-install)"
    return 0
  fi

  local args=()
  args+=(sudoq virt-install)
  args+=(--name "$vm")
  args+=(--ram "$RAM_MB" --vcpus "$VCPUS")
  args+=(--os-variant "$OS_VARIANT")
  args+=(--cdrom "$ISO")
  args+=(--network "network=$NET_NAME,model=virtio,mac=$mac")
  args+=(--graphics "$GRAPHICS")
  args+=(--noautoconsole)

  if [[ "$UEFI" == "1" ]]; then
    args+=(--boot uefi)
  fi

  while IFS=: read -r label _size; do
    [[ -n "$label" ]] || continue
    args+=(--disk "path=$(active_disk_path "$vm" "$label"),bus=virtio,format=qcow2")
  done < <(vm_disk_specs "$vm")

  echo "==> Creating domain: $vm"
  "${args[@]}"
}

print_disk_layout() {
  local vm="$1"
  echo "  $vm"
  while IFS=: read -r label size; do
    [[ -n "$label" ]] || continue
    printf '    - %-3s %s (%s)\n' "$label" "$(active_disk_path "$vm" "$label")" "${size}G"
  done < <(vm_disk_specs "$vm")
}

echo "==> Ensuring libvirt + pool + network"
ensure_libvirtd
ensure_pool_dir
ensure_network_active

echo "==> Reserving DHCP entries"
reserve_dhcp_host "$SERVERA_NAME" "$SERVERA_MAC" "$SERVERA_IP"
reserve_dhcp_host "$SERVERB_NAME" "$SERVERB_MAC" "$SERVERB_IP"

echo "==> Configuration"
echo "  network: $NET_NAME (${SUBNET_CIDR}) bridge=$(get_network_bridge)"
echo "  pool:    $POOL_DIR"
echo "  iso:     $ISO"
echo "  sizing:  RAM_MB=$RAM_MB VCPUS=$VCPUS"
echo "  hosts:"
printf '    - %s %s %s\n' "$SERVERA_NAME" "$SERVERA_IP" "$SERVERA_MAC"
printf '    - %s %s %s\n' "$SERVERB_NAME" "$SERVERB_IP" "$SERVERB_MAC"
echo "  disks:"
print_disk_layout "$SERVERA_NAME"
print_disk_layout "$SERVERB_NAME"
echo

build_vm_disks "$SERVERA_NAME"
build_vm_disks "$SERVERB_NAME"

build_vm "$SERVERA_NAME" "$SERVERA_MAC"
build_vm "$SERVERB_NAME" "$SERVERB_MAC"

echo
echo "==> Domains"
sudoq virsh list --all

echo
echo "==> DHCP leases / reservations"
sudoq virsh net-dhcp-leases "$NET_NAME" || true

cat <<EOF

Next steps:
1) Install RHEL on $SERVERA_NAME and $SERVERB_NAME from the attached ISO.
2) Inside each guest, install qemu-guest-agent so virsh domifaddr works reliably.
3) Run the guest bootstrap scripts in this order:
     scripts/bootstrap-servera.sh
     scripts/bootstrap-serverb.sh
4) Once both guests are in the desired clean state, capture baselines:
     ./scripts/rhcsa-capture-baselines.sh

EOF
