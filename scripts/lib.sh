#!/usr/bin/env bash
set -euo pipefail

# Load .env if present
if [ -f ".env" ]; then
  # shellcheck disable=SC2046
  set -a
  source .env
  set +a
fi

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Нужен root. Запусти: sudo make <target>" >&2
    exit 1
  fi
}

backup_file() {
  local f="$1"
  [ -f "$f" ] && cp -a "$f" "${f}.bak.$(date +%s)" || true
}

ensure_pkg() {
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

ensure_ufw() {
  ensure_pkg ufw
  ufw status || true
}
