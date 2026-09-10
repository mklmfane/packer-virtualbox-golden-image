#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PYTHON'
import ipaddress,json,pathlib,re,subprocess
c=json.loads(pathlib.Path('/etc/lab-node.json').read_text())
name=c['hostname']
if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,61}[a-z0-9]',name):
    raise SystemExit('Invalid hostname')
ip=str(ipaddress.IPv4Address(c['node_ip']))
if not pathlib.Path('/sys/class/net/enp0s8').exists():
    raise SystemExit('Expected VirtualBox host-only NIC enp0s8 is missing')
subprocess.run(['hostnamectl','set-hostname',name],check=True)
p=pathlib.Path('/etc/hosts')
lines=[line for line in p.read_text().splitlines() if not line.startswith('127.0.1.1')]
p.write_text('\n'.join(lines)+f'\n127.0.1.1 {name}\n')
# Keep the installed NAT network, and persist host-only networking for the next boot.
p=pathlib.Path('/etc/netplan/99-lab.yaml')
p.write_text(f'network:\n  version: 2\n  ethernets:\n    enp0s8:\n      dhcp4: false\n      dhcp6: false\n      addresses: [{ip}/24]\n')
p.chmod(0o600)
pathlib.Path('/etc/cloud/cloud.cfg.d/99-zz-lab-hostname.cfg').write_text('preserve_hostname: true\n')
subprocess.run(['netplan','generate'],check=True)
# Applying only the second NIC avoids disrupting Packer's NAT SSH connection.
subprocess.run(['ip','link','set','enp0s8','up'],check=True)
subprocess.run(['ip','address','replace',ip+'/24','dev','enp0s8'],check=True)
PYTHON
