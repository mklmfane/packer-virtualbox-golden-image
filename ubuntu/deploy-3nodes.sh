#!/usr/bin/env bash
set -euo pipefail

OVF="${OVF:-$PWD/output-ubuntu2404/ubuntu-2404-k8s-template.ovf}"
HOSTONLY="${HOSTONLY:-auto}"
HOSTONLY_IP="${HOSTONLY_IP:-192.168.56.1}"
HOSTONLY_MASK="${HOSTONLY_MASK:-255.255.255.0}"

SSH_USER="${SSH_USER:-kube}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/k8s_kubespray}"

declare -A IPS=(
  [k8s-cp1]="192.168.56.11"
  [k8s-w1]="192.168.56.12"
  [k8s-w2]="192.168.56.13"
)

declare -A PFPORTS=(
  [k8s-cp1]="2222"
  [k8s-w1]="2223"
  [k8s-w2]="2224"
)

die(){ echo "ERROR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

need VBoxManage
need ssh
need awk
need sed
need sort
need comm

[[ -f "$OVF" ]] || die "OVF not found: $OVF"
[[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY (set SSH_KEY=...)"

list_hostonly() {
  VBoxManage list hostonlyifs |
    awk -F: '/^Name:/{n=$2; sub(/^[ \t]+/,"",n); sub(/[ \t]+$/,"",n); print n}' |
    sed '/^$/d'
}

ensure_hostonly() {
  echo "[*] Ensuring host-only interface exists..."

  local before after created picked
  before="$(list_hostonly | sort || true)"

  if [[ "${HOSTONLY}" != "auto" ]] && grep -qx "${HOSTONLY}" <<<"${before}"; then
    picked="${HOSTONLY}"
  else
    if [[ "${HOSTONLY}" == "auto" ]] && [[ -n "${before}" ]]; then
      picked="$(head -n1 <<<"${before}")"
      echo "[*] HOSTONLY=auto -> using existing: ${picked}"
    else
      echo "[*] Creating host-only interface..."
      VBoxManage hostonlyif create >/dev/null

      after="$(list_hostonly | sort || true)"
      created="$(comm -13 <(printf "%s\n" "${before}") <(printf "%s\n" "${after}") | head -n1 || true)"

      if [[ -n "${created}" ]]; then
        picked="${created}"
        echo "[*] Created: ${picked}"
      else
        picked="$(head -n1 <<<"${after}")"
        [[ -n "${picked}" ]] || die "No host-only interfaces found after create."
        echo "[*] Could not diff new name; using: ${picked}"
      fi
    fi
  fi

  HOSTONLY="${picked}"

  echo "[*] Setting VirtualBox host-only IP: ${HOSTONLY} -> ${HOSTONLY_IP}/${HOSTONLY_MASK}"
  VBoxManage hostonlyif ipconfig "${HOSTONLY}" --ip "${HOSTONLY_IP}" --netmask "${HOSTONLY_MASK}"
}

vm_exists() { VBoxManage list vms | grep -q "\"$1\""; }
vm_state() {
  VBoxManage showvminfo "$1" --machinereadable | awk -F= '/^VMState=/{gsub(/"/,"",$2); print $2}'
}
poweroff_if_running() {
  local name="$1"
  if [[ "$(vm_state "$name")" == "running" ]]; then
    echo "[*] Powering off $name ..."
    VBoxManage controlvm "$name" poweroff
  fi
}
import_vm_if_needed() {
  local name="$1"
  if vm_exists "$name"; then
    echo "[*] VM $name already exists (will reconfigure)."
    return
  fi
  echo "[*] Importing OVF as $name ..."
  VBoxManage import "$OVF" --vsys 0 --vmname "$name"
}

vb_mac_to_colon() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/../&:/g;s/:$//'; }
get_mac() {
  local name="$1" nic="$2"
  local raw
  raw="$(VBoxManage showvminfo "$name" --machinereadable |
    awk -F= -v k="macaddress${nic}" '$1==k {gsub(/"/,"",$2); print $2}')"
  [[ -n "$raw" ]] || die "Could not read macaddress${nic} for $name"
  vb_mac_to_colon "$raw"
}

configure_vm_nics() {
  local name="$1" pfport="$2"
  poweroff_if_running "$name"

  echo "[*] Configuring NICs for $name: NIC1 NAT + PF, NIC2 host-only (${HOSTONLY})"
  VBoxManage modifyvm "$name" --nic1 nat
  VBoxManage modifyvm "$name" --nic2 hostonly --hostonlyadapter2 "$HOSTONLY" --cableconnected2 on

  VBoxManage modifyvm "$name" --macaddress1 auto --macaddress2 auto

  VBoxManage modifyvm "$name" --natpf1 delete "ssh" >/dev/null 2>&1 || true
  VBoxManage modifyvm "$name" --natpf1 "ssh,tcp,127.0.0.1,${pfport},,22"
}

start_vm() {
  local name="$1"
  echo "[*] Starting $name ..."
  VBoxManage startvm "$name" --type headless >/dev/null
}

wait_for_ssh() {
  local pfport="$1"
  echo "[*] Waiting for SSH on 127.0.0.1:${pfport} ..."
  for _ in {1..120}; do
    if ssh -i "$SSH_KEY" -p "$pfport" \
      -o BatchMode=yes -o ConnectTimeout=2 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "${SSH_USER}@127.0.0.1" "true" >/dev/null 2>&1; then
      echo "    SSH is up."
      return 0
    fi
    sleep 2
  done
  return 1
}

apply_hostonly_netplan_via_nat() {
  local name="$1" ip="$2" pfport="$3"

  local mac1 mac2
  mac1="$(get_mac "$name" 1)"
  mac2="$(get_mac "$name" 2)"
  echo "[*] $name MAC1=$mac1 MAC2=$mac2"

  local netplan
  netplan="$(cat <<EOF
network:
  version: 2
  ethernets:
    nat0:
      match:
        macaddress: ${mac1}
      dhcp4: true
    host0:
      match:
        macaddress: ${mac2}
      dhcp4: false
      addresses: [${ip}/24]
EOF
)"

  echo "[*] Writing netplan (0600) + applying on $name via NAT..."
  printf "%s\n" "$netplan" | ssh -i "$SSH_KEY" -p "$pfport" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${SSH_USER}@127.0.0.1" \
    "sudo bash -c 'cat > /etc/netplan/99-hostonly.yaml && chmod 600 /etc/netplan/99-hostonly.yaml && netplan generate && netplan apply'"

  ssh -i "$SSH_KEY" -p "$pfport" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${SSH_USER}@127.0.0.1" \
    "ip -4 -br a; ping -c1 -W1 ${HOSTONLY_IP} || true"
}

ensure_hostonly

for name in k8s-cp1 k8s-w1 k8s-w2; do
  ip="${IPS[$name]}"
  pf="${PFPORTS[$name]}"

  import_vm_if_needed "$name"
  configure_vm_nics "$name" "$pf"
  start_vm "$name"

  wait_for_ssh "$pf" || die "SSH never came up on NAT port $pf for $name"

  apply_hostonly_netplan_via_nat "$name" "$ip" "$pf"
done

echo
echo "[*] Done."
echo "[*] Best (host-only):"
echo "    ssh -i ${SSH_KEY} ${SSH_USER}@${IPS[k8s-cp1]}"
echo "    ssh -i ${SSH_KEY} ${SSH_USER}@${IPS[k8s-w1]}"
echo "    ssh -i ${SSH_KEY} ${SSH_USER}@${IPS[k8s-w2]}"
echo
echo "[*] Fallback (NAT PF):"
echo "    ssh -i ${SSH_KEY} -p ${PFPORTS[k8s-cp1]} ${SSH_USER}@127.0.0.1"
echo "    ssh -i ${SSH_KEY} -p ${PFPORTS[k8s-w1]}  ${SSH_USER}@127.0.0.1"
echo "    ssh -i ${SSH_KEY} -p ${PFPORTS[k8s-w2]}  ${SSH_USER}@127.0.0.1"
