#!/usr/bin/env bash
# Shared configuration + helpers for the RHCSA exam-style lab.
# shellcheck shell=bash

set -euo pipefail

LAB_NAME="${LAB_NAME:-rhcsa}"
NET_NAME="${NET_NAME:-rhcsa-lab}"
NET_BRIDGE="${NET_BRIDGE:-virbr-rhcsa}"

SUBNET_CIDR="${SUBNET_CIDR:-192.168.56.0/24}"
NET_GATEWAY="${NET_GATEWAY:-192.168.56.1}"
DHCP_START="${DHCP_START:-192.168.56.100}"
DHCP_END="${DHCP_END:-192.168.56.254}"

POOL_DIR="${POOL_DIR:-/var/lib/libvirt/images/rhcsa}"
ISO="${ISO:-/var/lib/libvirt/images/iso/rhel-10.1-x86_64-dvd.iso}"

RAM_MB="${RAM_MB:-4096}"
VCPUS="${VCPUS:-2}"
OS_VARIANT="${OS_VARIANT:-rhel10.0}"
GRAPHICS="${GRAPHICS:-spice}"
UEFI="${UEFI:-1}"

SERVERA_NAME="${SERVERA_NAME:-servera}"
SERVERA_FQDN="${SERVERA_FQDN:-servera.lab.local}"
SERVERA_IP="${SERVERA_IP:-192.168.56.10}"
SERVERA_MAC="${SERVERA_MAC:-52:54:00:56:10:0a}"

SERVERB_NAME="${SERVERB_NAME:-serverb}"
SERVERB_FQDN="${SERVERB_FQDN:-serverb.lab.local}"
SERVERB_IP="${SERVERB_IP:-192.168.56.20}"
SERVERB_MAC="${SERVERB_MAC:-52:54:00:56:10:14}"

SERVERC_NAME="${SERVERC_NAME:-serverc}"
SERVERC_FQDN="${SERVERC_FQDN:-serverc.lab.local}"
SERVERC_IP="${SERVERC_IP:-192.168.56.30}"
SERVERC_MAC="${SERVERC_MAC:-52:54:00:56:10:1e}"

DELETE_BASE="${DELETE_BASE:-0}"
DELETE_NETWORK="${DELETE_NETWORK:-0}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

sudoq() {
  if sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
  else
    sudo "$@"
  fi
}

vm_exists() { sudoq virsh dominfo "$1" >/dev/null 2>&1; }
vm_state()  { sudoq virsh domstate "$1" 2>/dev/null | tr -d '\r' || true; }
net_exists() { sudoq virsh net-info "$NET_NAME" >/dev/null 2>&1; }

ensure_libvirtd() {
  sudoq systemctl enable --now libvirtd >/dev/null
}

ensure_pool_dir() {
  sudoq mkdir -p "$POOL_DIR"
  sudoq chown root:libvirt "$POOL_DIR"
  sudoq chmod 0775 "$POOL_DIR"
}

active_disk_path() {
  local vm="$1"
  local label="$2"
  echo "$POOL_DIR/${vm}-${label}.qcow2"
}

base_disk_path() {
  local vm="$1"
  local label="$2"
  echo "$POOL_DIR/${vm}-${label}.base.qcow2"
}

servera_disk_specs() {
  cat <<'EOF'
os:20
EOF
}

serverb_disk_specs() {
  cat <<'EOF'
os:20
sdb:10
sdc:10
sdd:2
sde:10
EOF
}

vm_disk_specs() {
  local vm="$1"
  case "$vm" in
    "$SERVERA_NAME") servera_disk_specs ;;
    "$SERVERB_NAME") serverb_disk_specs ;;
    *)
      echo "ERROR: unknown VM '$vm'" >&2
      return 1
      ;;
  esac
}

vm_identity() {
  local vm="$1"
  case "$vm" in
    "$SERVERA_NAME")
      printf '%s\n%s\n%s\n' "$SERVERA_FQDN" "$SERVERA_IP" "$SERVERA_MAC"
      ;;
    "$SERVERB_NAME")
      printf '%s\n%s\n%s\n' "$SERVERB_FQDN" "$SERVERB_IP" "$SERVERB_MAC"
      ;;
    "$SERVERC_NAME")
      printf '%s\n%s\n%s\n' "$SERVERC_FQDN" "$SERVERC_IP" "$SERVERC_MAC"
      ;;
    *)
      echo "ERROR: unknown VM '$vm'" >&2
      return 1
      ;;
  esac
}

for_each_disk_spec() {
  local vm="$1"
  local callback="$2"

  while IFS=: read -r label size; do
    [[ -n "$label" ]] || continue
    "$callback" "$vm" "$label" "$size"
  done < <(vm_disk_specs "$vm")
}

expected_active_disks() {
  local vm
  for vm in "$SERVERA_NAME" "$SERVERB_NAME"; do
    while IFS=: read -r label _size; do
      [[ -n "$label" ]] || continue
      active_disk_path "$vm" "$label"
    done < <(vm_disk_specs "$vm")
  done
}

expected_base_disks() {
  local vm
  for vm in "$SERVERA_NAME" "$SERVERB_NAME"; do
    while IFS=: read -r label _size; do
      [[ -n "$label" ]] || continue
      base_disk_path "$vm" "$label"
    done < <(vm_disk_specs "$vm")
  done
}

get_network_bridge() {
  sudoq virsh net-info "$NET_NAME" 2>/dev/null | awk -F': *' '/Bridge:/ {print $2}'
}

ensure_network_defined() {
  if net_exists; then
    return 0
  fi

  local tmp_xml
  tmp_xml="$(mktemp)"
  cat >"$tmp_xml" <<EOF
<network>
  <name>${NET_NAME}</name>
  <forward mode='nat'/>
  <bridge name='${NET_BRIDGE}' stp='on' delay='0'/>
  <ip address='${NET_GATEWAY}' netmask='255.255.255.0'>
    <dhcp>
      <range start='${DHCP_START}' end='${DHCP_END}'/>
    </dhcp>
  </ip>
</network>
EOF

  sudoq virsh net-define "$tmp_xml" >/dev/null
  rm -f "$tmp_xml"
}

ensure_network_active() {
  ensure_network_defined

  local active
  active="$(sudoq virsh net-info "$NET_NAME" | awk -F': *' '/Active:/ {print $2}')"
  if [[ "$active" != "yes" ]]; then
    sudoq virsh net-start "$NET_NAME" >/dev/null
  fi
  sudoq virsh net-autostart "$NET_NAME" >/dev/null || true

  local bridge
  bridge="$(get_network_bridge)"
  if [[ -n "$bridge" ]] && ip link show "$bridge" >/dev/null 2>&1; then
    sudoq ip link set "$bridge" up || true
  fi
}

reserve_dhcp_host() {
  local name="$1"
  local mac="$2"
  local ip="$3"

  local xml="<host mac='${mac}' name='${name}' ip='${ip}'/>"
  sudoq virsh net-update "$NET_NAME" delete ip-dhcp-host "$xml" --live --config >/dev/null 2>&1 || true
  sudoq virsh net-update "$NET_NAME" add ip-dhcp-host "$xml" --live --config >/dev/null
}

create_qcow2_if_missing() {
  local path="$1"
  local size_gb="$2"

  if [[ -f "$path" ]]; then
    echo "==> Disk already exists: $path"
    return 0
  fi

  echo "==> Creating $path (${size_gb}G)"
  sudoq qemu-img create -f qcow2 "$path" "${size_gb}G" >/dev/null
  sudoq chown root:libvirt "$path"
  sudoq chmod 0660 "$path"
}

shutdown_wait() {
  local name="$1"
  local tries="${2:-45}"

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

human_bytes() {
  local n="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$n"
  else
    echo "${n}B"
  fi
}
