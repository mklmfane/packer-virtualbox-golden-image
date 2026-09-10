#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

for tool in packer VBoxManage ssh-keygen python3; do
  command -v "$tool" >/dev/null || { echo "Missing host command: $tool" >&2; exit 1; }
done
[[ ! -e values.pkrvars.hcl ]] || {
  echo 'values.pkrvars.hcl already exists. Edit it directly to preserve your settings.' >&2
  exit 1
}

# Reuse a dedicated local key, or create one without overwriting existing keys.
image_ssh_key="${1:-$HOME/.ssh/kubespray-lab}"
[[ "$image_ssh_key" = /* ]] || { echo 'Use an absolute SSH key path.' >&2; exit 1; }
if [[ ! -e "$image_ssh_key" && ! -e "$image_ssh_key.pub" ]]; then
  install -d -m 0700 "$(dirname -- "$image_ssh_key")"
  ssh-keygen -t ed25519 -N '' -C kubespray-lab -f "$image_ssh_key"
fi
[[ -f "$image_ssh_key" && -f "$image_ssh_key.pub" ]] || {
  echo 'Both the private key and matching .pub file are required.' >&2
  exit 1
}
derived_public_key=$(ssh-keygen -y -P '' -f "$image_ssh_key") || {
  echo 'This workflow requires a dedicated key without a passphrase.' >&2
  exit 1
}
python3 - "$image_ssh_key" "$derived_public_key" <<'PY'
import json
import pathlib
import sys
key = pathlib.Path(sys.argv[1])
public = pathlib.Path(str(key) + '.pub').read_text().strip()
if public.split()[:2] != sys.argv[2].split()[:2]:
    raise SystemExit('Public and private keys do not match.')
values = {
    'ssh_username': 'ubuntu',
    'ssh_private_key_file': str(key),
    'ssh_public_key_file': str(key) + '.pub',
    'vm_hostname': 'ubuntu-2404-k8s-template',
    'headless': True,
    'cpus': 2,
    'memory': 4096,
    'disk_size': 65536,
}
with open('values.pkrvars.hcl', 'x') as output:
    for name, value in values.items():
        output.write(f'{name} = {json.dumps(value)}\n')
pathlib.Path('values.pkrvars.hcl').chmod(0o600)
PY
echo 'Created values.pkrvars.hcl. Next: packer init .'

