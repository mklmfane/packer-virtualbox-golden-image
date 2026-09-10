#!/usr/bin/env bash
set -euo pipefail
source /opt/k8s-lab/env.sh

# Synchronize time before creating certificates or joining the cluster.
systemctl enable --now chrony
chronyc makestep
chronyc waitsync 60 0.1 0.0 2

[[ "$ROLE" == controlplane ]]
if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  # Fail on partial init; never reset or delete existing cluster data automatically.
  kubeadm init --kubernetes-version="$(kubeadm version -o short)" \
    --apiserver-advertise-address="$CONTROL_IP" \
    --control-plane-endpoint="${CONTROL_IP}:6443" \
    --apiserver-cert-extra-sans="$CONTROL_IP" \
    --pod-network-cidr="$POD_CIDR" --service-cidr="$SERVICE_CIDR" \
    --node-name="$HOSTNAME" --cri-socket=unix:///var/run/crio/crio.sock
fi
export KUBECONFIG=/etc/kubernetes/admin.conf
user_home=$(getent passwd "$SSH_USERNAME" | cut -d: -f6)
user_group=$(id -gn "$SSH_USERNAME")
install -d -m 0700 -o "$SSH_USERNAME" -g "$user_group" "$user_home/.kube"
install -m 0600 -o "$SSH_USERNAME" -g "$user_group" "$KUBECONFIG" "$user_home/.kube/config"
if ! kubectl -n kube-system get daemonset calico-node >/dev/null 2>&1; then
  curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml" -o /tmp/calico.yaml
  python3 - <<'PYTHON'
import os,yaml
p='/tmp/calico.yaml'
docs=list(yaml.safe_load_all(open(p)))
for d in docs:
    if d and d.get('kind')=='DaemonSet' and d['metadata']['name']=='calico-node':
        for c in d['spec']['template']['spec']['containers']:
            if c['name']=='calico-node':
                keys={'CALICO_IPV4POOL_CIDR':os.environ['POD_CIDR'],'IP_AUTODETECTION_METHOD':'interface=enp0s8'}
                c['env']=[e for e in c.get('env',[]) if e['name'] not in keys]
                c['env'] += [{'name':k,'value':v} for k,v in keys.items()]
with open(p,'w') as f: yaml.safe_dump_all(docs,f)
PYTHON
  kubectl apply -f /tmp/calico.yaml
fi
kubectl wait --for=condition=Ready "node/$HOSTNAME" --timeout=600s
