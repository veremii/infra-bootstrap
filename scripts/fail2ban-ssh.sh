#!/usr/bin/env bash
set -euo pipefail

SSH_PORT=${SSH_PORT:-1255}

show_help() {
  cat <<'HLP'
Usage: fail2ban-ssh [install|enable|disable|status]

Install and configure fail2ban for SSH with custom port.
Reads SSH_PORT from environment (default 1255).
HLP
}

ACTION=${1:-install}

case "$ACTION" in
  -h|--help) show_help; exit 0 ;;
  install)
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
    mkdir -p /etc/fail2ban
    cat >/etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port    = ${SSH_PORT}
logpath = %(sshd_log)s
backend = systemd
maxretry = 5
bantime = 1h
findtime = 10m
EOF
    systemctl enable --now fail2ban
    fail2ban-client status sshd || true
    ;;
  enable)
    systemctl enable --now fail2ban
    ;;
  disable)
    systemctl disable --now fail2ban || true
    ;;
  status)
    fail2ban-client status || true
    fail2ban-client status sshd || true
    ;;
  *) echo "Usage: $0 [install|enable|disable|status]" >&2; exit 2 ;;
esac
