#!/usr/bin/env bash
set -euo pipefail

ACTION=${1:-up}  # up|down
STACK=${STACK:-infra-portainer}
EDGE_LABEL=${EDGE_LABEL:-node.labels.role==edge}
PORTAINER_DOMAIN=${PORTAINER_DOMAIN:-}
PORTAINER_VERSION=${PORTAINER_VERSION:-2.20.3}

ensure_network() {
  local net="$1"
  if ! docker network ls --format '{{.Name}}' | grep -q "^${net}$"; then
    docker network create --driver overlay --attachable "$net" >/dev/null
  fi
}

case "$ACTION" in
  up)
    ensure_network edge
    ensure_network infra
    tmpdir=$(mktemp -d); trap 'rm -rf "$tmpdir"' EXIT
    cat >"$tmpdir/stack.yml" <<YAML
version: "3.9"

networks:
  edge:
    external: true
  infra:
    external: true

volumes:
  portainer_data: {}

services:
  portainer:
    image: portainer/portainer-ce:${PORTAINER_VERSION}
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks: [edge, infra]
    deploy:
      placement:
        constraints: ["node.labels.role==edge"]
      labels:$(if [ -n "$PORTAINER_DOMAIN" ]; then printf "\n        - \"traefik.enable=true\"\n        - \"traefik.http.routers.portainer.rule=Host(\`%s\`)\"\n        - \"traefik.http.routers.portainer.entrypoints=websecure\"\n        - \"traefik.http.routers.portainer.tls.certresolver=le\"\n        - \"traefik.http.services.portainer.loadbalancer.server.port=9000\"" "$PORTAINER_DOMAIN"; else printf " []"; fi)
YAML
    docker stack deploy -c "$tmpdir/stack.yml" "$STACK"
    ;;
  down)
    docker stack rm "$STACK" || true
    ;;
  *) echo "Usage: $0 [up|down]" >&2; exit 2 ;;
esac