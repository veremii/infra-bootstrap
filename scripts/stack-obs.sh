#!/usr/bin/env bash
set -euo pipefail

ACTION=${1:-up}  # up|down
STACK=${STACK:-infra-obs}
GRAFANA_DOMAIN=${GRAFANA_DOMAIN:-}
LOKI_VERSION=${LOKI_VERSION:-2.9.6}
PROMTAIL_VERSION=${PROMTAIL_VERSION:-2.9.6}
GRAFANA_VERSION=${GRAFANA_VERSION:-10.4.3}

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
    # Write promtail config for Docker logs → Loki
    cat >"$tmpdir/promtail-config.yml" <<'PCFG'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    static_configs:
      - targets: [localhost]
        labels:
          job: docker
          __path__: /var/lib/docker/containers/*/*.log
    pipeline_stages:
      - docker: {}
PCFG
    cat >"$tmpdir/stack.yml" <<YAML
version: "3.9"

networks:
  edge:
    external: true
  infra:
    external: true

volumes:
  loki_data: {}
  grafana_data: {}

configs:
  promtail_config:
    file: ./promtail-config.yml

services:
  loki:
    image: grafana/loki:${LOKI_VERSION}
    command: ["-config.file=/etc/loki/local-config.yaml"]
    volumes:
      - loki_data:/tmp
    networks: [infra]
    deploy:
      restart_policy:
        condition: on-failure

  promtail:
    image: grafana/promtail:${PROMTAIL_VERSION}
    command: ["-config.file=/etc/promtail/config.yml"]
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    configs:
      - source: promtail_config
        target: /etc/promtail/config.yml
        mode: 0444
    networks: [infra]
    deploy:
      mode: global
      restart_policy:
        condition: on-failure

  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
    networks: [edge, infra]
    deploy:
      restart_policy:
        condition: on-failure
      labels:$(if [ -n "$GRAFANA_DOMAIN" ]; then printf "\n        - \"traefik.enable=true\"\n        - \"traefik.http.routers.grafana.rule=Host(\`%s\`)\"\n        - \"traefik.http.routers.grafana.entrypoints=websecure\"\n        - \"traefik.http.routers.grafana.tls.certresolver=le\"\n        - \"traefik.http.services.grafana.loadbalancer.server.port=3000\"" "$GRAFANA_DOMAIN"; else printf " []"; fi)
YAML
    docker stack deploy -c "$tmpdir/stack.yml" "$STACK"
    ;;
  down)
    docker stack rm "$STACK" || true
    ;;
  *) echo "Usage: $0 [up|down]" >&2; exit 2 ;;
esac
