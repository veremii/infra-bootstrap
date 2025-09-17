#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HLP'
Usage: wg-client-apply [-i IFACE] -f CONFIG

Apply a WireGuard client config on this node and enable it.

Options:
  -i IFACE   WireGuard interface name (default: wg0)
  -f CONFIG  Path to client config file (.conf)
  -h         Show this help

Steps:
  - Installs wireguard if missing
  - Copies CONFIG to /etc/wireguard/IFACE.conf
  - chmod 600 and systemctl enable --now wg-quick@IFACE

Env:
  IF (same as -i)
HLP
}

IFACE=${IF:-wg0}
CONFIG=""

while getopts ":i:f:h" opt; do
  case "$opt" in
    i) IFACE="$OPTARG" ;;
    f) CONFIG="$OPTARG" ;;
    h) show_help; exit 0 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done

if [[ -z "$CONFIG" ]]; then
  echo "Missing -f CONFIG" >&2
  exit 2
fi

if ! command -v wg >/dev/null 2>&1; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard
fi

install -m 0700 -d /etc/wireguard
install -m 0600 "$CONFIG" "/etc/wireguard/${IFACE}.conf"
systemctl enable --now "wg-quick@${IFACE}"
wg show || true
echo "Applied /etc/wireguard/${IFACE}.conf and started wg-quick@${IFACE}"







