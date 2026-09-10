#!/usr/bin/env bash
set -euo pipefail

# Require sufficient root capacity before installing GitLab.
root_bytes=$(df -B1 --output=size / | tail -n 1 | tr -d ' ')
if (( root_bytes < 50 * 1024 * 1024 * 1024 )); then
  echo 'Rebuild the shared golden image with disk_size=65536 for GitLab.' >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade

# Common tooling + postfix (GitLab recommends an MTA; we use "Local only" to keep it non-interactive)
apt-get install -y --no-install-recommends   ca-certificates curl openssh-server tzdata perl   apt-transport-https gnupg lsb-release debconf-utils

echo "postfix postfix/mailname string gitlab.local" | debconf-set-selections
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
apt-get install -y postfix

systemctl enable --now ssh

