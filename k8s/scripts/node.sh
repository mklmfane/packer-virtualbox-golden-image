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
: "${JOIN_SERVER_PORT:=8081}"

config_path="/opt/k8s-share"
NODENAME="$(hostname -s)"
mkdir -p "$config_path"

systemctl enable --now crio || true
systemctl restart crio || true

# Wait for control-plane join server to come up
echo "⏳ Waiting for join server http://${CONTROL_IP}:${JOIN_SERVER_PORT} ..."
for i in {1..60}; do
  if curl -fsS "http://${CONTROL_IP}:${JOIN_SERVER_PORT}/join.sh" -o /dev/null; then
    echo "✅ Join server reachable."
    break
  fi
  echo "[$i/60] not ready yet... sleeping 5s"
  sleep 5
done

# Fetch join.sh + config
curl -fsSL "http://${CONTROL_IP}:${JOIN_SERVER_PORT}/join.sh" -o "$config_path/join.sh"
chmod +x "$config_path/join.sh"

curl -fsSL "http://${CONTROL_IP}:${JOIN_SERVER_PORT}/config" -o "$config_path/config"
chmod 644 "$config_path/config"

# Join once
if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  echo "ℹ️ ${NODENAME} already joined. Skipping."
else
  kubeadm reset -f || true
  bash "$config_path/join.sh"
fi

systemctl restart kubelet || true

# Optional kubeconfig for troubleshooting on worker
mkdir -p /root/.kube
cp -f "$config_path/config" /root/.kube/config
chmod 600 /root/.kube/config

install -d -m 0755 -o packer -g packer /home/packer/.kube
cp -f "$config_path/config" /home/packer/.kube/config
chown packer:packer /home/packer/.kube/config
chmod 600 /home/packer/.kube/config

echo "🎉 Worker node ${NODENAME} joined."
