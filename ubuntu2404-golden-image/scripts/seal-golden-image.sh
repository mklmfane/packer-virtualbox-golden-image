#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo 'Run inside the build VM as root.' >&2; exit 1; }

apt-get clean
rm -rf /var/lib/apt/lists/*
# Installer records may include the build account password hash and public key.
rm -rf /var/log/installer
rm -f /root/.bash_history /home/*/.bash_history

# Remove build-instance state, cached seed, logs and the cloned machine ID.
cloud-init clean --logs --machine-id --seed
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
rm -f /var/lib/systemd/random-seed
rm -f /var/lib/dhcp/*.leases /var/lib/dhcp/*.leases~
sync
shutdown -P now
