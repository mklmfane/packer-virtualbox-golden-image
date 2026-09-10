#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

. /etc/os-release
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  ${VERSION_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null


apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

# Allow runner to use Docker executor (you still need to register the runner after first boot)
# If Docker is installed later, we'll add the group then; avoid failing now.
if getent group docker >/dev/null 2>&1; then
  usermod -aG docker gitlab-runner || true
fi

# Allow GitLab Runner to use Docker executor
usermod -aG docker gitlab-runner || true
systemctl restart gitlab-runner || true