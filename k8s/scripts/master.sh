#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

if [[ -f /etc/k8s-lab.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /etc/k8s-lab.env
  set +a
fi

: "${CONTROL_IP:?CONTROL_IP missing}"
: "${POD_CIDR:?POD_CIDR missing}"
: "${SERVICE_CIDR:?SERVICE_CIDR missing}"
: "${CALICO_VERSION:=3.30.3}"
: "${JOIN_SERVER_PORT:=8081}"

NODENAME="$(hostname -s)"
config_path="/opt/k8s-share"
mkdir -p "$config_path" /etc/cni/net.d

# Init once
if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  kubeadm reset -f || true
  rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /etc/cni/net.d || true
  mkdir -p /etc/cni/net.d

  kubeadm init \
    --apiserver-advertise-address="$CONTROL_IP" \
    --apiserver-cert-extra-sans="$CONTROL_IP" \
    --pod-network-cidr="$POD_CIDR" \
    --service-cidr="$SERVICE_CIDR" \
    --node-name "$NODENAME" \
    --cri-socket=unix:///var/run/crio/crio.sock \
    --ignore-preflight-errors Swap
fi

export KUBECONFIG=/etc/kubernetes/admin.conf

# kubeconfig for root
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config

# kubeconfig for SSH user (packer)
install -d -m 0755 -o packer -g packer /home/packer/.kube
cp -f /etc/kubernetes/admin.conf /home/packer/.kube/config
chown packer:packer /home/packer/.kube/config
chmod 600 /home/packer/.kube/config

# Share for workers
cp -f /etc/kubernetes/admin.conf "$config_path/config"
chmod 644 "$config_path/config"

kubeadm token create --print-join-command > "$config_path/join.sh"
sed -i 's|kubeadm join|kubeadm join --cri-socket=unix:///var/run/crio/crio.sock|' "$config_path/join.sh"
chmod +x "$config_path/join.sh"

# Calico
if ! kubectl -n kube-system get daemonset calico-node >/dev/null 2>&1; then
  curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml" \
    -o /tmp/calico.yaml
  kubectl apply -f /tmp/calico.yaml
fi

# Join server (serves /opt/k8s-share on port 8081)
systemctl enable --now k8s-join-server.service || true

echo "🎉 Control-plane setup complete."
