(
  set -euo pipefail

  PACKER_VERSION="1.16.0"
  PACKER_ARCH="$(dpkg --print-architecture)"
  PACKER_TMP="$(mktemp -d)"
  trap 'rm -rf "$PACKER_TMP"' EXIT

  cd "$PACKER_TMP"

  PACKER_ZIP="packer_${PACKER_VERSION}_linux_${PACKER_ARCH}.zip"
  PACKER_BASE="https://releases.hashicorp.com/packer/${PACKER_VERSION}"

  curl -fSLO "${PACKER_BASE}/${PACKER_ZIP}"
  curl -fSLO "${PACKER_BASE}/packer_${PACKER_VERSION}_SHA256SUMS"

  awk -v file="$PACKER_ZIP" '$2 == file' \
    "packer_${PACKER_VERSION}_SHA256SUMS" > checksum.txt

  test -s checksum.txt
  sha256sum -c checksum.txt

  unzip -q "$PACKER_ZIP"

  # Back up an existing manually installed binary.
  if [ -f /usr/local/bin/packer ]; then
    sudo cp -p /usr/local/bin/packer \
      "/usr/local/bin/packer.backup-$(date +%Y%m%d%H%M%S)"
  fi

  sudo install -m 0755 packer /usr/local/bin/packer
)