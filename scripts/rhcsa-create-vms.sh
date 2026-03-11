#!/usr/bin/env bash
set -euo pipefail

# RHCSA 2-VM lab builder (Ubuntu host + KVM/libvirt NAT) with STATIC DHCP LEASES
#
# Creates vm1 + vm2 using libvirt "default" NAT network and pins:
# - vm1 -> 192.168.122.31
# - vm2 -> 192.168.122.66
#
# Approach:
# - Set stable MACs on each VM NIC
# - Reserve IPs in libvirt network via `virsh net-update ... ip-dhcp-host`
#
# UEFI note:
# - Do NOT use libvirt snapshot-revert workflows for this lab.
# - Internal snapshots are unsupported with pflash/UEFI, and external overlays
#   can leave the VM in awkward states.
# - This repo uses baseline qcow2 copies instead:
#     vm1.base.qcow2 -> vm1.qcow2
#     vm2.base.qcow2 -> vm2.qcow2
#   via `rhcsa-reset-to-clean.sh`.
#
# Usage:
#   chmod +x scripts/rhcsa-create-vms.sh
#   ./scripts/rhcsa-create-vms.sh
#
# Overrides:
#   ISO=/path/to/rhel-10.1-x86_64-dvd.iso RAM_MB=8192 VCPUS=4 DISK_GB=60 ./scripts/rhcsa-create-vms.sh
#
# Static DHCP overrides:
#   VM1_IP=192.168.122.31 VM2_IP=192.168.122.66 VM1_MAC=52:54:00:aa:bb:31 VM2_MAC=52:54:00:aa:bb:66 ./scripts/rhcsa-create-vms.sh

ISO="${ISO:-/var/lib/libvirt/images/iso/rhel-10.1-x86_64-dvd.iso}"
POOL_DIR="${POOL_DIR:-/var/lib/libvirt/images/rhcsa}"

RAM_MB="${RAM_MB:-6144}"
VCPUS="${VCPUS:-2}"
DISK_GB="${DISK_GB:-40}"

NET_NAME="${NET_NAME:-default}" # libvirt NAT network (virbr0 192.168.122.0/24 typically)

VM1_NAME="${VM1_NAME:-vm1}"
VM2_NAME="${VM2_NAME:-vm2}"

# Stable MACs (must be unique; 52:54:00 is qemu OUI)
VM1_MAC="${VM1_MAC:-52:54:00:d8:8d:2e}"
VM2_MAC="${VM2_MAC:-52:54:00:6d:66:99}"

# Reserved IPs (must match your NAT subnet; default is 192.168.122.0/24)
VM1_IP="${VM1_IP:-192.168.122.31}"
VM2_IP="${VM2_IP:-192.168.122.66}"

VM1_DISK="${VM1_DISK:-$POOL_DIR/vm1.qcow2}"
VM2_DISK="${VM2_DISK:-$POOL_DIR/vm2.qcow2}"

OS_VARIANT="${OS_VARIANT:-rhel10.0}" # virt-install naming; rhel10.0 is fine for 10.1
GRAPHICS="${GRAPHICS:-spice}"        # spice | vnc | none (headless)
UEFI="${UEFI:-1}"                    # 1 to use UEFI

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

vm_exists() {
  sudo virsh dominfo "$1" >/dev/null 2>&1
}

create_disk() {
  local path="$1"
  if [[ -f "$path" ]]; then
    echo "==> Disk already exists: $path (skipping create)"
  else
    echo "==> Creating disk: $path (${DISK_GB}G qcow2)"
    sudo qemu-img create -f qcow2 "$path" "${DISK_GB}G" >/dev/null
    sudo chown root:libvirt "$path"
    sudo chmod 0660 "$path"
  fi
}

ensure_network_active() {
  echo "==> Ensure libvirt network '$NET_NAME' exists and is active (system connection)"
  if ! sudo virsh net-info "$NET_NAME" >/dev/null 2>&1; then
    echo "ERROR: libvirt network '$NET_NAME' not found under qemu:///system." >&2
    echo "Try: sudo virsh net-define /usr/share/libvirt/networks/default.xml && sudo virsh net-start default" >&2
    exit 1
  fi

  local active
  active="$(sudo virsh net-info "$NET_NAME" | awk -F': *' '/Active:/ {print $2}')"
  if [[ "$active" != "yes" ]]; then
    echo "==> Starting network '$NET_NAME'"
    sudo virsh net-start "$NET_NAME"
  fi
  sudo virsh net-autostart "$NET_NAME" >/dev/null || true

  if ip link show virbr0 >/dev/null 2>&1; then
    sudo ip link set virbr0 up || true
  fi
}

net_reserve_ip() {
  local name="$1"
  local mac="$2"
  local ip="$3"

  local xml
  xml="<host mac='${mac}' name='${name}' ip='${ip}'/>"

  echo "==> Reserving DHCP: ${name} -> ${ip} (${mac}) on network '${NET_NAME}'"

  sudo virsh net-update "$NET_NAME" delete ip-dhcp-host "${xml}" --live --config >/dev/null 2>&1 || true
  sudo virsh net-update "$NET_NAME" add ip-dhcp-host "${xml}" --live --config >/dev/null
}

build_vm() {
  local name="$1"
  local disk="$2"
  local mac="$3"

  if vm_exists "$name"; then
    echo "==> VM already exists: $name (skipping virt-install)"
    return 0
  fi

  local boot_args=()
  if [[ "$UEFI" == "1" ]]; then
    boot_args+=(--boot uefi)
  fi

  echo "==> Creating VM: $name (MAC $mac)"
  sudo virt-install \
    --name "$name" \
    --ram "$RAM_MB" --vcpus "$VCPUS" \
    --disk "path=$disk,size=$DISK_GB,bus=virtio,format=qcow2" \
    --os-variant "$OS_VARIANT" \
    --cdrom "$ISO" \
    --network "network=$NET_NAME,model=virtio,mac=$mac" \
    --graphics "$GRAPHICS" \
    "${boot_args[@]}"
}

echo "==> Preflight checks"
require_cmd sudo
require_cmd virsh
require_cmd virt-install
require_cmd qemu-img
require_cmd ip

echo "==> Ensure libvirtd is running"
sudo systemctl enable --now libvirtd >/dev/null

ensure_network_active

echo "==> Ensure pool directory permissions"
sudo mkdir -p "$POOL_DIR"
sudo chown -R root:libvirt "$POOL_DIR"
sudo chmod 0775 "$POOL_DIR"

if [[ ! -f "$ISO" ]]; then
  echo "ERROR: ISO not found at: $ISO" >&2
  echo "Place your ISO at: /var/lib/libvirt/images/iso/rhel-10.1-x86_64-dvd.iso" >&2
  echo "or run with: ISO=/path/to/rhel-10.1-x86_64-dvd.iso ./scripts/rhcsa-create-vms.sh" >&2
  exit 1
fi

echo "==> Using ISO: $ISO"
echo "==> Pool dir: $POOL_DIR"
echo "==> VM sizing: RAM_MB=$RAM_MB VCPUS=$VCPUS DISK_GB=$DISK_GB"
echo "==> Static DHCP:"
echo "    $VM1_NAME -> $VM1_IP ($VM1_MAC)"
echo "    $VM2_NAME -> $VM2_IP ($VM2_MAC)"
echo

echo "==> Create disks"
create_disk "$VM1_DISK"
create_disk "$VM2_DISK"

echo
echo "==> Create VMs"
build_vm "$VM1_NAME" "$VM1_DISK" "$VM1_MAC"
build_vm "$VM2_NAME" "$VM2_DISK" "$VM2_MAC"

echo
echo "==> Configure DHCP reservations on network '$NET_NAME'"
net_reserve_ip "$VM1_NAME" "$VM1_MAC" "$VM1_IP"
net_reserve_ip "$VM2_NAME" "$VM2_MAC" "$VM2_IP"

echo
echo "==> Current domains (system):"
sudo virsh list --all

echo
echo "==> DHCP leases (network '$NET_NAME'):"
sudo virsh net-dhcp-leases "$NET_NAME" || true

cat <<EOF

Next steps:
1) Complete the RHEL install in the console(s) (virt-manager or virt-viewer).
2) After first boot, get guest IPs:
     sudo virsh domifaddr $VM1_NAME
     sudo virsh domifaddr $VM2_NAME
     sudo virsh net-dhcp-leases $NET_NAME
3) Set hostnames inside guests:
     sudo hostnamectl set-hostname $VM1_NAME
     sudo hostnamectl set-hostname $VM2_NAME
4) Install guest agent inside guests (recommended):
     sudo dnf -y install qemu-guest-agent
     sudo systemctl enable --now qemu-guest-agent
5) Create your golden baselines once the guests are in the desired clean state:
     sudo cp -f $VM1_DISK $POOL_DIR/${VM1_NAME}.base.qcow2
     sudo cp -f $VM2_DISK $POOL_DIR/${VM2_NAME}.base.qcow2

EOF