#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo 'Run inside the build VM as root.' >&2; exit 1; }

# Installer packages already provide Python, SSH and the Ansible sudo account.
command -v python3
command -v cloud-init
visudo -cf /etc/sudoers.d/90-packer

swapoff -a
sed -ri '/^[^#].*[[:space:]]swap[[:space:]]/s/^/# disabled in golden image: /' /etc/fstab

cat > /etc/modules-load.d/90-kubernetes.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat > /etc/sysctl.d/90-kubernetes.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

# Only NAT is configured in the base image. Add a unique host-only address per clone.
# Prevent cloud-init from replacing this network file without explicit reconfiguration.
cat > /etc/cloud/cloud.cfg.d/99-z-golden-image.cfg <<'EOF'
datasource_list: [ NoCloud, None ]
network:
  config: disabled
preserve_hostname: false
ssh_pwauth: false
ssh_deletekeys: false
EOF

# New SSH host keys must exist before either socket-activated or regular SSH starts.
# The service runs on each boot; ssh-keygen -A preserves keys that already exist.
cat > /etc/systemd/system/golden-image-ssh-keys.service <<'EOF'
[Unit]
Description=Generate missing SSH host keys for this VM
DefaultDependencies=no
After=local-fs.target
Before=ssh.service ssh.socket shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
RequiredBy=ssh.service ssh.socket
EOF
systemctl enable golden-image-ssh-keys.service

cat > /etc/ssh/sshd_config.d/00-golden-image.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
/usr/sbin/sshd -t

{
  echo 'Image: ubuntu-2404-k8s-template'
  echo "Built at: $(date -u +%FT%TZ)"
  cat /etc/os-release
  echo "Build-boot kernel: $(uname -r)"
} > /etc/image-build-info
dpkg-query -W > /etc/image-package-manifest.txt
test -z "$(swapon --noheadings --show)"
test "$(sysctl -n net.ipv4.ip_forward)" = 1
python3 --version

# Do not install Kubernetes, etcd, Docker, containerd, or CNI here.
# The selected Kubespray release owns these versions and their configuration.
