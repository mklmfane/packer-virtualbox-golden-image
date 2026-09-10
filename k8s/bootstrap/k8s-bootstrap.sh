#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

DONE_FILE="/var/lib/k8s-lab/bootstrap.done"
mkdir -p /var/lib/k8s-lab

# Run once (successful run)
if [[ -f "$DONE_FILE" ]]; then
  exit 0
fi

# Load env written by packer (export everything)
if [[ -f /etc/k8s-lab.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /etc/k8s-lab.env
  set +a
fi

: "${ROLE:=worker}"

# Netplan perms (netplan ignores “too open” files)
if [[ -f /etc/netplan/99-k8s-lab.yaml ]]; then
  chmod 600 /etc/netplan/99-k8s-lab.yaml || true
  netplan apply || true
fi

# ALWAYS ensure baseline (kubeadm/kubectl/crio) exists first
/opt/k8s-lab/scripts/common.sh

case "$ROLE" in
  controlplane) /opt/k8s-lab/scripts/master.sh ;;
  worker)       /opt/k8s-lab/scripts/node.sh   ;;
  *)
    echo "ERROR: Unknown ROLE='$ROLE' (expected controlplane|worker)"
    exit 1
    ;;
esac

touch "$DONE_FILE"
