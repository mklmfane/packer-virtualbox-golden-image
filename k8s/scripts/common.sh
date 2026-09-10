#!/usr/bin/env bash
set -euo pipefail
source /opt/k8s-lab/env.sh
export DEBIAN_FRONTEND=noninteractive
[[ "$KUBERNETES_MINOR" =~ ^1\.[0-9]+$ ]]
apt-get update
apt-get install -y ca-certificates curl gnupg conntrack socat ipset python3-yaml
swapoff -a
sed -ri '/^[^#].*[[:space:]]swap[[:space:]]/s/^/#/' /etc/fstab
modprobe overlay
modprobe br_netfilter
sysctl -w net.ipv4.ip_forward=1
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/Release.key" |
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes.gpg
curl -fsSL "https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${KUBERNETES_MINOR}/deb/Release.key" |
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/crio.gpg
printf 'deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v%s/deb/ /\n' "$KUBERNETES_MINOR" > /etc/apt/sources.list.d/kubernetes.list
printf 'deb [signed-by=/etc/apt/keyrings/crio.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v%s/deb/ /\n' "$KUBERNETES_MINOR" > /etc/apt/sources.list.d/cri-o.list
apt-get update
apt-get install -y cri-o kubelet kubeadm kubectl
apt-mark hold cri-o kubelet kubeadm kubectl
printf 'KUBELET_EXTRA_ARGS=--node-ip=%s\n' "$NODE_IP" > /etc/default/kubelet
systemctl enable --now crio
systemctl enable kubelet
# Kubelet can restart until kubeadm has configured the node.
dpkg-query -W cri-o kubelet kubeadm kubectl > /etc/k8s-package-versions.txt
