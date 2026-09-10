#!/usr/bin/env bash
set -euo pipefail

apt-get update
apt-get -y upgrade

# Common tooling + postfix (GitLab recommends an MTA; we use "Local only" to keep it non-interactive)
apt-get install -y --no-install-recommends   ca-certificates curl openssh-server tzdata perl   apt-transport-https gnupg lsb-release debconf-utils

echo "postfix postfix/mailname string gitlab.local" | debconf-set-selections
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
apt-get install -y postfix

systemctl enable --now ssh
