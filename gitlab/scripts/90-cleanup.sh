#!/usr/bin/env bash
set -euo pipefail

apt-get autoremove -y
apt-get clean -y
rm -rf /var/lib/apt/lists/*

# Remove machine-id so clones don't collide
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/dbus/machine-id || true
ln -sf /etc/machine-id /var/lib/dbus/machine-id || true
