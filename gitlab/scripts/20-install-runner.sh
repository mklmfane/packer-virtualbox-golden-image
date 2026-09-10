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
  --url "http://localhost:8080" \
  --token "<PASTE_TOKEN>" \
  --executor "docker" \
  --docker-image "alpine:latest"

Then verify:
sudo gitlab-runner list
TXT
EOF

chmod +x /usr/local/bin/register-runner-hint.sh

# Patch GitLab Runner clear-docker-cache for Docker 29+ (avoid forcing DOCKER_API_VERSION=1.41)
if [ -f /usr/share/gitlab-runner/clear-docker-cache ]; then
  cat >/usr/share/gitlab-runner/clear-docker-cache <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  exit 0
fi

FILTER_FLAG='label=com.gitlab.gitlab-runner.managed=true'
CMD="${1:-prune-volumes}"

case "$CMD" in
  prune)
    echo "Pruning unused containers..."
    docker system prune -af --filter "$FILTER_FLAG" || true
    ;;
  prune-volumes)
    echo "Pruning unused containers + volumes..."
    docker system prune -af --filter "$FILTER_FLAG" || true
    # Docker 29+ compatible: prune volumes separately (no forced API version)
    docker volume prune -f --filter "$FILTER_FLAG" || docker volume prune -f || true
    ;;
  space)
    docker system df
    ;;
  help|*)
    echo "Usage: clear-docker-cache [prune|prune-volumes|space|help]"
    ;;
esac
EOF
  chmod +x /usr/share/gitlab-runner/clear-docker-cache
fi
