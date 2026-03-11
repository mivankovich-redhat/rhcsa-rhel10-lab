#!/usr/bin/env bash
set -euo pipefail

# Bring down RHCSA lab VMs (host): vm1/vm2
#
# Usage:
#   chmod +x ~/scripts/rhcsa-down.sh
#   ~/scripts/rhcsa-down.sh
#
# Overrides:
#   VM1_NAME=vm1 VM2_NAME=vm2 ~/scripts/rhcsa-down.sh

VM1_NAME="${VM1_NAME:-vm1}"
VM2_NAME="${VM2_NAME:-vm2}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }
}

vm_exists() { sudo virsh dominfo "$1" >/dev/null 2>&1; }
vm_state()  { sudo virsh domstate "$1" 2>/dev/null | tr -d '\r'; }

shutdown_wait() {
  local name="$1"
  local tries=30

  if ! vm_exists "$name"; then
    echo "==> VM not found: $name (skip)"
    return 0
  fi

  local st
  st="$(vm_state "$name" || true)"
  if [[ "$st" == "shut off" || "$st" == "shutoff" ]]; then
    echo "==> $name already shut off"
    return 0
  fi

  echo "==> Shutting down $name"
  sudo virsh shutdown "$name" >/dev/null || true

  while (( tries > 0 )); do
    st="$(vm_state "$name" || true)"
    if [[ "$st" == "shut off" || "$st" == "shutoff" ]]; then
      echo "==> $name is shut off"
      return 0
    fi
    sleep 2
    tries=$((tries - 1))
  done

  echo "==> $name did not shut down in time; forcing destroy"
  sudo virsh destroy "$name" >/dev/null || true
}

echo "==> Preflight"
require_cmd sudo
require_cmd virsh

shutdown_wait "$VM1_NAME"
shutdown_wait "$VM2_NAME"

echo
echo "==> Status:"
sudo virsh list --all
