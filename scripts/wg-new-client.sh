#!/usr/bin/env bash
set -euo pipefail

IF="${1:-wg0}"
NAME="${2:-client-$(date +%s)}"
ADDR="${3:-10.88.0.100}"
PORT="${4:-51820}"
ENDPOINT_IP="${5:-1.2.3.4}"
ALLOWED="${6:-10.88.0.0/24}"
KEEPALIVE="${7:-25}"

WG_DIR="/etc/wireguard"

if ! [ -f "${WG_DIR}/${IF}.conf" ]; then
  echo "Не найден ${WG_DIR}/${IF}.conf — подними WG-сервер" >&2
  exit 1
fi

SERVER_PUB=$(wg show "${IF}" public-key)

umask 077

# Проверяем, не существует ли уже клиент с таким IP
if wg show "${IF}" allowed-ips | grep -q "${ADDR}/32"; then
  echo "WARNING: Client with IP ${ADDR} already exists on ${IF}" >&2
  echo "Use a different IP address or remove existing peer first" >&2
  exit 1
fi

CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
CLIENT_PSK=$(wg genpsk)

# Добавляем peer на сервер
wg set "${IF}" peer "${CLIENT_PUB}" preshared-key <(echo "$CLIENT_PSK") allowed-ips "${ADDR}/32"
wg-quick save "${IF}"

# Конфиг клиента
cat > "${NAME}.conf" <<CFG
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = ${ADDR}/32
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUB}
PresharedKey = ${CLIENT_PSK}
AllowedIPs = ${ALLOWED}
Endpoint = ${ENDPOINT_IP}:${PORT}
PersistentKeepalive = ${KEEPALIVE}
CFG

echo "Готово: $(pwd)/${NAME}.conf"
