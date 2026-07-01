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
# Base tools — ssh and the small CLIs Claude leans on constantly. git is built
# separately (see install_git) because the distro version is too old.
# ----------------------------------------------------------------------------
install_base() {
  apt_update_once
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    openssh-client \
    jq \
    ripgrep \
    less \
    netcat-openbsd \
    tzdata

  # Point the clock at the requested zone now (TZ is exported in the
  # Containerfile) so every later build step runs on local time.
  local tz="${TZ:-Asia/Tbilisi}"
  ln -snf "/usr/share/zoneinfo/${tz}" /etc/localtime
  echo "$tz" > /etc/timezone
}

# ----------------------------------------------------------------------------
# git — built from source. Debian's git is 2.39, which predates relative
# worktree links (git 2.48+, `worktree.useRelativePaths`). ccbox relies on
# that so a worktree created inside the container resolves on the host too.
# Build deps are purged afterwards to keep the image lean; only the runtime
# shared libs the binary links against are kept.
# ----------------------------------------------------------------------------
install_git() {
  apt_update_once
  local ver="2.51.0"
  local build_deps="build-essential libssl-dev libcurl4-openssl-dev libexpat1-dev zlib1g-dev libpcre2-dev"
  local make_flags="USE_LIBPCRE=YesPlease NO_TCLTK=YesPlease NO_GETTEXT=YesPlease NO_PERL=YesPlease NO_PYTHON=YesPlease"

  apt-get install -y --no-install-recommends $build_deps
  # Runtime libs the built binary needs; installed explicitly (marked manual)
  # so the build-deps purge below cannot autoremove them out from under git.
  apt-get install -y --no-install-recommends libcurl4 libexpat1 zlib1g libpcre2-8-0

  local src; src="$(mktemp -d)"
  curl -fsSL "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${ver}.tar.gz" \
    | tar -xz -C "$src"
  make -C "$src/git-${ver}" -j"$(nproc)" prefix=/usr/local $make_flags all
  make -C "$src/git-${ver}" prefix=/usr/local $make_flags install
  rm -rf "$src"

  # Relative worktree links are the whole point of the newer git: make it the
  # container-wide default. System scope keeps the preference out of the user's
  # home volume and out of every repo, so nothing leaks to the host side of a
  # bind mount.
  install -d /usr/local/etc
  git config --system worktree.useRelativePaths true

  apt-get purge -y $build_deps
  apt-get autoremove -y --purge
  hash -r
  git --version
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
install_git
install_gh
install_gcloud

# Cleanup to keep the image small.
apt-get clean
rm -rf /var/lib/apt/lists/*
