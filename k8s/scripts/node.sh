#!/usr/bin/env bash
set -euo pipefail
source /opt/k8s-lab/env.sh
[[ "$ROLE" == worker ]]
if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  echo 'Worker is already joined.'
  exit 0
fi
# The host supplies a fresh join command through SSH stdin, never through HTTP.
python3 -c '
import shlex,sys,subprocess
args=shlex.split(sys.stdin.read())
if args[:2] != ["kubeadm","join"]:
    raise SystemExit("Expected kubeadm join command")
subprocess.run(args+["--cri-socket=unix:///var/run/crio/crio.sock"],check=True)
'
