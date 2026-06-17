#!/usr/bin/env bash
#
# install-tools.sh — the single place to extend the toolset.
#
# To add a tool: write an install_<name> function, then add it to the
# call list at the bottom. Each function runs as root during the image
# build. Keep functions self-contained so they're easy to reason about.
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt_update_once() {
  if [ -z "${_APT_UPDATED:-}" ]; then
    apt-get update -y
    _APT_UPDATED=1
  fi
}

# ----------------------------------------------------------------------------
# Base tools — git, ssh, and the small CLIs Claude leans on constantly.
# ----------------------------------------------------------------------------
install_base() {
  apt_update_once
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    git \
    openssh-client \
    jq \
    ripgrep \
    less \
    netcat-openbsd
}

# ----------------------------------------------------------------------------
# gh — GitHub CLI (official apt repo).
# ----------------------------------------------------------------------------
install_gh() {
  apt_update_once
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -y
  apt-get install -y --no-install-recommends gh
}

# ----------------------------------------------------------------------------
# gcloud — Google Cloud CLI (official apt repo).
# ----------------------------------------------------------------------------
install_gcloud() {
  apt_update_once
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg
  echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
  apt-get update -y
  apt-get install -y --no-install-recommends google-cloud-cli
}

# ----------------------------------------------------------------------------
# Call list — add new tools here.
# ----------------------------------------------------------------------------
install_base
install_gh
install_gcloud

# Cleanup to keep the image small.
apt-get clean
rm -rf /var/lib/apt/lists/*
