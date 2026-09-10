#!/usr/bin/env python3
"""Build one Ubuntu golden image, then provision role VMs from its OVF."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
PROJECT = 'packer-virtualbox-golden-image'
GOLDEN = ROOT / 'ubuntu2404-golden-image'
OVF = GOLDEN / 'output-ubuntu2404/ubuntu-2404-k8s-template.ovf'


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, text=True, **kwargs)


def output(args):
    return run(args, capture_output=True).stdout.strip()


def config():
    path = ROOT / 'lab.local.json'
    if not path.exists():
        raise ValueError('Copy lab.example.json to lab.local.json and review it first.')
    c = json.loads(path.read_text())
    if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,30}', c['ssh_username']):
        raise ValueError('Invalid SSH username')
    c['ssh_private_key_file'] = str(Path(c['ssh_private_key_file']).expanduser().resolve())
    subnet = ipaddress.ip_network(c['hostonly_ip'] + '/24', strict=False)
    host = ipaddress.IPv4Address(c['hostonly_ip'])
    pods = ipaddress.ip_network(c['pod_cidr'])
    services = ipaddress.ip_network(c['service_cidr'])
    if pods.overlaps(services) or subnet.overlaps(pods) or subnet.overlaps(services):
        raise ValueError('Host-only, pod and service networks must not overlap.')
    names, ips = set(), {str(host)}
    for nodes in c['nodes'].values():
        for node in nodes:
            if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,61}[a-z0-9]', node['name']):
                raise ValueError('Invalid VM name')
            addr = ipaddress.IPv4Address(node['ip'])
            if addr not in subnet or addr in (subnet.network_address, subnet.broadcast_address):
                raise ValueError('Node IP must be a usable address in the host-only /24.')
            if node['name'] in names or node['ip'] in ips:
                raise ValueError('Duplicate VM name or IP')
            names.add(node['name']); ips.add(node['ip'])
    nodes = c['nodes']['k8s']
    if sum(n.get('role') == 'controlplane' for n in nodes) != 1:
        raise ValueError('This lab supports exactly one control plane.')
    if any(n.get('role') not in ('controlplane', 'worker') for n in nodes):
        raise ValueError('Kubernetes roles must be controlplane or worker.')
    if not re.fullmatch(r'1\.[0-9]+', c['kubernetes_minor']):
        raise ValueError('Invalid Kubernetes minor')
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', c['calico_version']):
        raise ValueError('Invalid Calico version')
    return c


def ensure_key(c):
    key = Path(c['ssh_private_key_file'])
    pub = Path(str(key) + '.pub')
    if not key.exists():
        raise ValueError(f'Missing key {key}. Run ubuntu2404-golden-image/configure.sh or set the key used by your existing golden image.')
    derived = output(['ssh-keygen', '-y', '-P', '', '-f', key])
    if not pub.exists() or pub.read_text().split()[:2] != derived.split()[:2]:
        raise ValueError('The .pub file must match the unencrypted private key.')


def ensure_network(c):
    blocks = output(['VBoxManage', 'list', 'hostonlyifs']).split('\n\n')
    interfaces = {}
    for block in blocks:
        fields = dict(line.split(':', 1) for line in block.splitlines() if ':' in line)
        fields = {k.strip(): v.strip() for k, v in fields.items()}
        if 'Name' in fields:
            interfaces[fields['Name']] = fields
    name = c['hostonly_adapter']
    if name not in interfaces:
        created = output(['VBoxManage', 'hostonlyif', 'create'])
        match = re.search(r"Interface '([^']+)'", created)
        if not match:
            raise ValueError('Could not parse created host-only interface; inspect VBoxManage list hostonlyifs.')
        actual = match.group(1)
        if actual != name:
            raise ValueError(f'Created {actual}; set hostonly_adapter to this name and configure its IP before retrying. No existing interface was changed.')
        run(['VBoxManage', 'hostonlyif', 'ipconfig', name, '--ip', c['hostonly_ip'], '--netmask', '255.255.255.0'])
    elif interfaces[name].get('IPAddress') != c['hostonly_ip'] or interfaces[name].get('NetworkMask') != '255.255.255.0':
        raise ValueError(f'{name} has another address. Choose a dedicated interface; existing networks are not changed.')
    # Reject DHCP pools overlapping any of the static addresses; do not disable shared DHCP.
    dhcp = output(['VBoxManage', 'list', 'dhcpservers'])
    for block in dhcp.split('\n\n'):
        fields = dict(line.split(':', 1) for line in block.splitlines() if ':' in line)
        fields = {k.strip(): v.strip() for k,v in fields.items()}
        if fields.get('NetworkName') != 'HostInterfaceNetworking-' + name or fields.get('Enabled', '').lower() not in ('yes','true','1'):
            continue
        lo = ipaddress.IPv4Address(fields['LowerIPAddress'])
        hi = ipaddress.IPv4Address(fields['UpperIPAddress'])
        if any(lo <= ipaddress.IPv4Address(n['ip']) <= hi for group in c['nodes'].values() for n in group):
            raise ValueError('Static node IP overlaps the host-only DHCP pool. Choose addresses outside the pool.')


def vm_info(name):
    result = subprocess.run(['VBoxManage','showvminfo',name,'--machinereadable'],text=True,capture_output=True)
    if result.returncode:
        if 'VBOX_E_OBJECT_NOT_FOUND' in result.stderr or 'Could not find a registered machine' in result.stderr:
            return None
        raise ValueError(result.stderr)
    return dict((k, v.strip('"')) for k,v in (line.split('=',1) for line in result.stdout.splitlines() if '=' in line))


def ssh(c, node, command, **kwargs):
    state = ROOT / '.lab'
    state.mkdir(mode=0o700, exist_ok=True)
    return run(['ssh', '-i', c['ssh_private_key_file'], '-o', 'IdentitiesOnly=yes',
                '-o','BatchMode=yes','-o','ConnectTimeout=5',
                '-o','StrictHostKeyChecking=accept-new',
                '-o',f'UserKnownHostsFile={state / "known_hosts"}',
                f'{c["ssh_username"]}@{node["ip"]}', command], **kwargs)


def start(c, node):
    info = vm_info(node['name'])
    if info['VMState'] == 'poweroff':
        run(['VBoxManage','startvm',node['name'],'--type','headless'])
    elif info['VMState'] != 'running':
        raise ValueError('VM is saved or transitioning; handle that state in VirtualBox first.')
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        try:
            ssh(c, node, 'sudo -n test -f /etc/lab-provisioned',capture_output=True)
            actual=json.loads(ssh(c,node,'sudo -n cat /etc/lab-node.json',capture_output=True).stdout)
            expected={'hostname':node['name'],'node_ip':node['ip'],'ssh_username':c['ssh_username']}
            if 'role' in node:
                expected.update(role=node['role'],control_ip=next(n['ip'] for n in c['nodes']['k8s'] if n['role']=='controlplane'))
                expected.update({k:c[k] for k in ['pod_cidr','service_cidr','kubernetes_minor','calico_version']})
            if any(actual.get(k)!=v for k,v in expected.items()):
                raise ValueError('Existing VM configuration differs; do not reuse it with changed settings.')
            return
        except subprocess.CalledProcessError:
            time.sleep(5)
    raise ValueError('SSH/provisioning check timed out. Inspect the VM console and Packer output. Existing host-key mismatches must be investigated, not automatically bypassed.')


def packer(c, directory, values):
    env = os.environ.copy()
    env.update({'PKR_VAR_'+k: str(v).lower() if isinstance(v,bool) else str(v) for k,v in values.items()})
    run(['packer','init','.'],cwd=directory,env=env)
    run(['packer','validate','.'],cwd=directory,env=env)
    run(['packer','build','.'],cwd=directory,env=env)


def up(c, group):
    if not OVF.is_file():
        raise ValueError('Build the golden image first: python3 scripts/lab.py golden')
    ensure_network(c)
    nodes=sorted(c['nodes'][group],key=lambda n:n.get('role')!='controlplane')
    control=next(n for n in c['nodes']['k8s'] if n['role']=='controlplane')
    for n in nodes:
        info=vm_info(n['name'])
        if info:
            tag=output(['VBoxManage','getextradata',n['name'],'lab.project'])
            if tag != 'Value: '+PROJECT:
                raise ValueError(f'Existing VM {n["name"]} is not owned by this workflow.')
        else:
            vals={k:c[k] for k in ['ssh_username','ssh_private_key_file','hostonly_adapter']}
            vals.update(golden_image=str(OVF),vm_name=n['name'],node_ip=n['ip'],cpus=n['cpus'],memory=n['memory'])
            if group=='k8s':
                vals.update({k:c[k] for k in ['pod_cidr','service_cidr','kubernetes_minor','calico_version']})
                vals.update(role=n['role'],control_ip=control['ip'])
            if group=='gitlab':vals['external_url']=f'http://{n["ip"]}:8080'
            packer(c, ROOT/group, vals)
        start(c,n)
        if group=='k8s':
            if n['role']=='controlplane':
                ssh(c,n,'sudo -n /opt/k8s-lab/master.sh')
            else:
                join=ssh(c,control,'sudo -n kubeadm token create --ttl 30m --print-join-command',capture_output=True).stdout
                ssh(c,n,'sudo -n /opt/k8s-lab/node.sh',input=join)
    if group=='k8s':
        ssh(c,control,'sudo -n kubectl --kubeconfig=/etc/kubernetes/admin.conf wait --for=condition=Ready nodes --all --timeout=600s')
        ssh(c,control,'sudo -n kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide')
    for n in nodes:
        print(f'SSH: ssh -i {c["ssh_private_key_file"]} {c["ssh_username"]}@{n["ip"]}')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['golden','up'])
    parser.add_argument('group',nargs='?',choices=['k8s','ubuntu','gitlab'])
    args=parser.parse_args()
    for tool in ['packer','VBoxManage','ssh','ssh-keygen']:
        if not shutil.which(tool):raise ValueError(f'Missing host command: {tool}')
    c=config();ensure_key(c)
    if args.action=='golden':
        if OVF.parent.exists():raise ValueError('Golden output already exists. Reuse it, or move the entire output directory to a backup before rebuilding.')
        packer(c,GOLDEN,{'ssh_username':c['ssh_username'],'ssh_private_key_file':c['ssh_private_key_file'],'ssh_public_key_file':c['ssh_private_key_file']+'.pub'})
    else:
        if not args.group:parser.error('up requires k8s, ubuntu or gitlab')
        up(c,args.group)


if __name__=='__main__':
    try:main()
    except (ValueError,subprocess.CalledProcessError) as error:
        sys.exit(str(error))
