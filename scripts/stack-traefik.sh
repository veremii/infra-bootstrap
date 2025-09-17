#!/usr/bin/env bash
set -euo pipefail

ACTION=${1:-up}  # up|down
STACK=${STACK:-infra-traefik}
EMAIL=${TRAEFIK_ACME_EMAIL:-admin@example.com}
EDGE_LABEL=${EDGE_LABEL:-node.labels.role==edge}
TRAEFIK_VERSION=${TRAEFIK_VERSION:-v3.1}
# Optional: publish Traefik dashboard via domain with basic-auth
TRAEFIK_DASHBOARD_DOMAIN=${TRAEFIK_DASHBOARD_DOMAIN:-}
# Basic auth string in htpasswd format, e.g. user:hashed
BASIC_AUTH_HTPASSWD=${BASIC_AUTH_HTPASSWD:-}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<'HLP'
Usage: stack-traefik.sh [up|down]

Env options:
  TRAEFIK_ACME_EMAIL         Email for ACME resolver
  TRAEFIK_DASHBOARD_DOMAIN   If set, expose Traefik dashboard at this domain (TLS)
  BASIC_AUTH_HTPASSWD        If set (htpasswd format), protect dashboard and shared middleware

Notes:
  - Creates middleware "perimeter-auth" on Traefik when BASIC_AUTH_HTPASSWD is set
  - Other stacks can reuse it via label: traefik.http.routers.<r>.middlewares=perimeter-auth@docker
HLP
  exit 0
fi

ensure_network() {
  local net="$1"
  if ! docker network ls --format '{{.Name}}' | grep -q "^${net}$"; then
    docker network create --driver overlay --attachable "$net" >/dev/null
  fi
}

case "$ACTION" in
  up)
    ensure_network edge
    tmpdir=$(mktemp -d); trap 'rm -rf "$tmpdir"' EXIT
    # Build optional dashboard labels and middleware
    DASHBOARD_LABELS=""
    if [[ -n "$TRAEFIK_DASHBOARD_DOMAIN" ]]; then
      DASHBOARD_LABELS=$(cat <<LBL
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.traefik.rule=Host(\`$TRAEFIK_DASHBOARD_DOMAIN\`)"
        - "traefik.http.routers.traefik.entrypoints=websecure"
        - "traefik.http.routers.traefik.tls.certresolver=le"
        - "traefik.http.routers.traefik.service=api@internal"
LBL
)
    fi

    AUTH_LABELS=""
    if [[ -n "$BASIC_AUTH_HTPASSWD" ]]; then
      AUTH_LABELS=$(cat <<ALB
        - "traefik.http.middlewares.perimeter-auth.basicauth.removeheader=true"
        - "traefik.http.middlewares.perimeter-auth.basicauth.users=$BASIC_AUTH_HTPASSWD"
        - "traefik.http.routers.traefik.middlewares=perimeter-auth@docker"
ALB
)
    fi

    cat >"$tmpdir/stack.yml" <<YAML
version: "3.9"

networks:
  edge:
    external: true

volumes:
  traefik_letsencrypt: {}

services:
  traefik:
    image: traefik:${TRAEFIK_VERSION}
    command:
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.exposedByDefault=false"
      - "--providers.file.directory=/dynamic"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.le.acme.email=${EMAIL}"
      - "--certificatesresolvers.le.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.le.acme.httpchallenge=true"
      - "--certificatesresolvers.le.acme.httpchallenge.entrypoint=web"
      - "--api.dashboard=true"
      - "--api.insecure=false"
    ports:
      - target: 80
        published: 80
        protocol: tcp
        mode: host
      - target: 443
        published: 443
        protocol: tcp
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_letsencrypt:/letsencrypt
      - /var/lib/traefik/dynamic:/dynamic
    networks: [edge]
    deploy:
      placement:
        constraints: ["${EDGE_LABEL}"]
      restart_policy:
        condition: on-failure
      labels:
$(printf "%s" "${DASHBOARD_LABELS}" | sed 's/^/        /')
$(printf "%s" "${AUTH_LABELS}" | sed 's/^/        /')
YAML
    docker stack deploy -c "$tmpdir/stack.yml" "$STACK"
    ;;
  down)
    docker stack rm "$STACK" || true
    ;;
  *) echo "Usage: $0 [up|down]" >&2; exit 2 ;;
esac
