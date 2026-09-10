#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

# Export env if present
if [[ -f /etc/k8s-lab.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /etc/k8s-lab.env
  set +a
fi

# ---- DNS normalization ----
# Prefer DNS_SERVERS (space-separated). If only DNS_SERVERS_NETPLAN exists (comma-separated), derive it.
DNS_SERVERS="${DNS_SERVERS:-${DNS_SERVERS_NETPLAN:-}}"
DNS_SERVERS="${DNS_SERVERS//,/ }"
DNS_SERVERS="$(echo "${DNS_SERVERS:-}" | xargs)"
DNS_SERVERS="${DNS_SERVERS:-8.8.8.8 1.1.1.1}"

# ---- Kubernetes minor for repo path ----
KUBERNETES_VERSION_SHORT="${KUBERNETES_VERSION_SHORT:-}"
if [[ -z "$KUBERNETES_VERSION_SHORT" && -n "${KUBERNETES_VERSION:-}" ]]; then
  KUBERNETES_VERSION_SHORT="$(echo "$KUBERNETES_VERSION" | awk -F. '{print $1"."$2}')"
fi
KUBERNETES_VERSION_SHORT="${KUBERNETES_VERSION_SHORT:-1.34}"

echo "=== [1/6] apt update + base deps ==="
apt-get update -y
# Avoid full dist-upgrade at boot (slow + can disrupt networking)
apt-get install -y \
  ca-certificates curl gnupg jq \
  ipvsadm ipset socat conntrack ebtables ethtool \
  apt-transport-https python3

echo "=== [2/6] DNS (systemd-resolved) ==="
mkdir -p /etc/systemd/resolved.conf.d/
cat >/etc/systemd/resolved.conf.d/dns_servers.conf <<EOF
[Resolve]
DNS=${DNS_SERVERS}
EOF
systemctl restart systemd-resolved || true

echo "=== [3/6] Disable swap ==="
swapoff -a || true
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
sed -i '/ swap / s/^/#/' /etc/fstab || true

echo "=== [4/6] Kernel modules + sysctl ==="
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay || true
modprobe br_netfilter || true

cat >/etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo "=== [5/6] Install CRI-O ==="
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/Release.key \
  -o /etc/apt/keyrings/cri-o-apt-keyring.asc

cat >/etc/apt/sources.list.d/cri-o.list <<EOF
deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.asc] https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/ /
EOF

apt-get update -y
apt-get install -y cri-o
systemctl enable --now crio

mkdir -p /etc/crio/crio.conf.d
cat >/etc/crio/crio.conf.d/99-pause.conf <<EOF
[crio.image]
pause_image = "registry.k8s.io/pause:3.10.1"
EOF
systemctl restart crio

echo "=== [6/6] Install kubeadm/kubelet/kubectl ==="
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION_SHORT}/deb/Release.key" \
  -o /etc/apt/keyrings/kubernetes-apt-keyring.asc

cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.asc] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION_SHORT}/deb/ /
EOF

apt-get update -y

# If KUBERNETES_VERSION contains '*' (like 1.34.*) DO NOT pin (apt can’t install wildcards)
if [[ -n "${KUBERNETES_VERSION:-}" && "${KUBERNETES_VERSION}" != *"*"* ]]; then
  apt-get install -y kubelet="${KUBERNETES_VERSION}" kubeadm="${KUBERNETES_VERSION}" kubectl="${KUBERNETES_VERSION}"
else
  apt-get install -y kubelet kubeadm kubectl
fi

apt-mark hold kubelet kubeadm kubectl cri-o >/dev/null || true

# kubelet node-ip (prefer env NODE_IP)
local_ip="${NODE_IP:-}"
if [[ -z "$local_ip" ]]; then
  local_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
fi
if [[ -z "$local_ip" ]]; then
  local_ip="$(ip -4 -o addr show | awk '!/ lo /{print $4}' | head -n1 | cut -d/ -f1)"
fi

cat >/etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS=--node-ip=${local_ip}
EOF

systemctl daemon-reload || true
systemctl restart kubelet || true

echo "=== ✅ common.sh complete ==="
