#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
phase=${1:-install}
case "$phase" in systemd|install|swarm) ;; *) echo 'Usage: sudo bash docker-wsl.sh systemd|install|swarm [advertise-IP]' >&2; exit 1;; esac
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || { echo 'Expected Ubuntu 24.04 inside WSL.' >&2; exit 1; }
grep -qi microsoft /proc/sys/kernel/osrelease || { echo 'Expected WSL.' >&2; exit 1; }
if [[ $phase == systemd ]]; then
    command -v python3 >/dev/null || { apt-get update; apt-get install -y python3; }
    python3 - <<'PY'
import configparser, pathlib, shutil, tempfile, os
path = pathlib.Path('/etc/wsl.conf')
config = configparser.ConfigParser(interpolation=None, strict=True)
if path.exists():
    config.read(path)
    if not path.with_suffix('.conf.before-docker').exists():
        shutil.copy2(path, path.with_suffix('.conf.before-docker'))
if not config.has_section('boot'): config.add_section('boot')
config.set('boot','systemd','true')
with tempfile.NamedTemporaryFile(mode='w', dir='/etc', delete=False) as f:
    config.write(f)
    temp = f.name
os.chmod(temp,0o644)
os.replace(temp,path)
PY
    echo 'systemd configured. Exit Ubuntu and terminate ONLY this distro from Windows, then reopen it.'
    exit 0
fi
[[ $(ps -p 1 -o comm=) == systemd ]] || { echo 'systemd is not PID 1. Run the systemd phase and restart this WSL distribution.' >&2; exit 1; }
if [[ $phase == install ]]; then
    # Fail clearly instead of removing another runtime or an existing Docker installation.
    for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
            echo "Conflicting package found: $package. Review its workloads before replacing it." >&2
            exit 1
        fi
    done
    if command -v docker >/dev/null && ! dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q 'install ok installed'; then
        echo 'A Docker client/runtime from another installation exists. Inspect it before proceeding.' >&2
        exit 1
    fi
    # Existing Docker sources may use another keyring or package policy. Preserve them.
    if grep -Rqs 'download.docker.com' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null && [[ ! -f /etc/apt/sources.list.d/windowslab-docker.sources ]]; then
        echo 'An existing Docker APT source was found. Inspect it before adding this one.' >&2
        exit 1
    fi
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    temp_key=$(mktemp)
    trap 'rm -f "$temp_key"' EXIT
    curl --fail --silent --show-error --location https://download.docker.com/linux/ubuntu/gpg --output "$temp_key"
    install -m 0644 "$temp_key" /etc/apt/keyrings/windowslab-docker.asc
    cat > /etc/apt/sources.list.d/windowslab-docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/windowslab-docker.asc
EOF
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now containerd docker
    docker version
    docker compose version
    [[ $(docker info --format '{{.OSType}}') == linux ]] || { echo 'Expected Linux engine.' >&2; exit 1; }
    dpkg-query -W docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /var/log/windowslab-docker-versions.txt
    echo 'Linux Docker Engine and Compose installed. Swarm commands are built into Engine.'
    echo 'Use sudo docker; membership in the docker group is not required.'
    exit 0
fi
systemctl start docker
state=$(docker info --format '{{.Swarm.LocalNodeState}}')
[[ $state == inactive ]] || { echo "Existing Swarm state: $state. No reset or reinitialization performed."; exit 0; }
node_ip=${2:-$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')}
python3 - "$node_ip" <<'PY'
import ipaddress,sys
ipaddress.IPv4Address(sys.argv[1])
PY
ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$node_ip" || { echo 'Advertise IP is not assigned inside WSL.' >&2; exit 1; }
docker swarm init --advertise-addr "$node_ip" --data-path-addr "$node_ip"
docker node ls
echo 'Single-node lab Swarm initialized. WSL NAT/IP lifecycle needs separate design for remote workers.'
