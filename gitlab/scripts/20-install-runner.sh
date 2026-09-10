#!/usr/bin/env bash
set -euo pipefail

# Install GitLab Runner from the official GitLab Runner repository
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
apt-get install -y gitlab-runner


cat >/usr/local/bin/register-runner-hint.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat <<'TXT'
To register this runner (manual step):

1) In GitLab UI: create a **project runner** or **instance runner** and copy the token.
2) Run on the VM:

sudo gitlab-runner register \
  --url "http://GITLAB_VM_IP:8080" \
  --token "<PASTE_TOKEN>" \
  --executor "docker" \
  --docker-image "alpine:latest"

Then verify:
sudo gitlab-runner list
TXT
EOF

chmod +x /usr/local/bin/register-runner-hint.sh

