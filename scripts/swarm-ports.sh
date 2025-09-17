#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HLP'
Usage: swarm-ports [open|close] [-i IFACE]

Open/close Docker Swarm inter-node ports restricted to a specific interface (e.g., wg0) via UFW.

Ports:
  - TCP 2377 (manager)
  - TCP/UDP 7946 (serf)
  - UDP 4789 (VXLAN)

Options:
  -i IFACE   Network interface to scope rules (default: wg0)
  -h         Show this help

Requires: ufw installed.
HLP
}

ACTION=""
IFACE=${IF:-wg0}

case "${1:-}" in
  open|close) ACTION="$1" ;;
  -h|--help) show_help; exit 0 ;;
  *) echo "Specify action: open|close" >&2; show_help; exit 2 ;;
esac
shift || true

while getopts ":i:h" opt; do
  case "$opt" in
    i) IFACE="$OPTARG" ;;
    h) show_help; exit 0 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done

if ! command -v ufw >/dev/null 2>&1; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
fi

if [[ "$ACTION" == "open" ]]; then
  ufw allow in on "$IFACE" to any port 2377 proto tcp || true
  ufw allow in on "$IFACE" to any port 7946 proto tcp || true
  ufw allow in on "$IFACE" to any port 7946 proto udp || true
  ufw allow in on "$IFACE" to any port 4789 proto udp || true
  echo "Opened Swarm ports on $IFACE"
else
  ufw delete allow in on "$IFACE" to any port 2377 proto tcp || true
  ufw delete allow in on "$IFACE" to any port 7946 proto tcp || true
  ufw delete allow in on "$IFACE" to any port 7946 proto udp || true
  ufw delete allow in on "$IFACE" to any port 4789 proto udp || true
  echo "Closed Swarm ports on $IFACE"
fi

ufw status verbose || true

