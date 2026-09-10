#!/usr/bin/env bash
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

for tool in packer VBoxManage ssh-keygen python3; do
  command -v "$tool" >/dev/null || {
    echo "Missing host command: $tool" >&2
    exit 1
  }
done

# If your existing configuration uses another key, pass its absolute path.
image_ssh_key="${1:-$HOME/.ssh/kubespray-lab}"

[[ "$image_ssh_key" = /* ]] || {
  echo 'Use an absolute SSH key path.' >&2
  exit 1
}

mkdir -p -- "$(dirname -- "$image_ssh_key")"

# Refuse unexpected file types or dangling symlinks.
for key_file in "$image_ssh_key" "$image_ssh_key.pub"; do
  if [[ -L "$key_file" || ( -e "$key_file" && ! -f "$key_file" ) ]]; then
    echo "Expected a regular key file: $key_file" >&2
    exit 1
  fi
done

if [[ ! -f "$image_ssh_key" ]]; then
  # Preserve any public key left behind after deleting the private key.
  if [[ -f "$image_ssh_key.pub" ]]; then
    backup=$(mktemp "${image_ssh_key}.pub.backup.XXXXXX")
    mv -- "$image_ssh_key.pub" "$backup"
    echo "Preserved old public key: $backup"
  fi

  ssh-keygen -t ed25519 -N '' \
    -C kubespray-lab \
    -f "$image_ssh_key"

  echo 'Created a NEW key pair.'
  echo 'Existing VMs and golden images still trust the OLD public key.'
fi

chmod 600 "$image_ssh_key"

derived_public_key=$(ssh-keygen -y -P '' -f "$image_ssh_key") || {
  echo 'This workflow requires a valid private key without a passphrase.' >&2
  exit 1
}

# A missing public key can be recovered from an existing private key.
if [[ ! -f "$image_ssh_key.pub" ]]; then
  printf '%s\n' "$derived_public_key" > "$image_ssh_key.pub"
fi

python3 - "$image_ssh_key" "$derived_public_key" <<'PY'
import json
import pathlib
import sys

key = pathlib.Path(sys.argv[1])
public_path = pathlib.Path(str(key) + ".pub")
public = public_path.read_text().strip()

if public.split()[:2] != sys.argv[2].split()[:2]:
    raise SystemExit(
        "Public and private keys do not match. "
        "No existing configuration was changed."
    )

config = pathlib.Path("values.pkrvars.hcl")

if config.exists():
    print(f"Preserved existing {config}.")
    print("Ensure its SSH paths match:")
    print(f"ssh_private_key_file = {json.dumps(str(key))}")
    print(f"ssh_public_key_file  = {json.dumps(str(public_path))}")
else:
    values = {
        "ssh_username": "ubuntu",
        "ssh_private_key_file": str(key),
        "ssh_public_key_file": str(public_path),
        "vm_hostname": "ubuntu-2404-k8s-template",
        "headless": True,
        "cpus": 2,
        "memory": 4096,
        "disk_size": 65536,
    }
    with config.open("x") as output:
        for name, value in values.items():
            output.write(f"{name} = {json.dumps(value)}\n")
    print(f"Created {config}.")

config.chmod(0o600)
PY

echo 'SSH key preparation complete.'