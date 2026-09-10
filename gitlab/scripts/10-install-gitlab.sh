#!/usr/bin/env bash
set -euo pipefail

# GitLab Omnibus (Linux package)
# EXTERNAL_URL is used by omnibus during install/reconfigure.
: "${EXTERNAL_URL:=http://localhost:8080}"

# Community Edition repo
curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash

# Install GitLab and run initial reconfigure
EXTERNAL_URL="${EXTERNAL_URL}" apt-get install -y gitlab-ce


# Make clone URLs match the forwarded SSH port (host 2222 -> guest 22)
if ! grep -q "gitlab_shell_ssh_port" /etc/gitlab/gitlab.rb; then
  echo "gitlab_rails['gitlab_shell_ssh_port'] = 2222" >> /etc/gitlab/gitlab.rb
fi


gitlab-ctl reconfigure

# Show the main services (useful in build logs)
gitlab-ctl status || true
