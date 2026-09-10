#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
echo 'Use the shared golden image to create the three Kubernetes VMs.'
exec python3 "$root/scripts/lab.py" up k8s
