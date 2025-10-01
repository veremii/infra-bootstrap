#!/usr/bin/env bash
set -euo pipefail

ACTION=${1:-up}  # up|down
STACK=${STACK:-infra-storage}
MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-changeme123}
MINIO_DOMAIN=${MINIO_DOMAIN:-}
MINIO_CONSOLE_DOMAIN=${MINIO_CONSOLE_DOMAIN:-}
REDIS_PASSWORD=${REDIS_PASSWORD:-}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<'HLP'
Usage: stack-storage.sh [up|down]

Deploys MinIO (S3-compatible storage) and Redis to Docker Swarm.

Environment variables:
  MINIO_ROOT_USER          MinIO admin username (default: admin)
  MINIO_ROOT_PASSWORD      MinIO admin password (default: changeme123)
  MINIO_DOMAIN             Domain for MinIO S3 API (e.g., s3.example.com)
  MINIO_CONSOLE_DOMAIN     Domain for MinIO Console UI (e.g., minio.example.com)
  REDIS_PASSWORD           Redis password (optional, no auth if empty)

Examples:
  # Deploy with defaults
  ./stack-storage.sh up

  # Deploy with custom domains
  MINIO_DOMAIN=s3.example.com MINIO_CONSOLE_DOMAIN=minio.example.com ./stack-storage.sh up

  # Remove stack
  ./stack-storage.sh down
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
    ensure_network app
    
    tmpdir=$(mktemp -d); trap 'rm -rf "$tmpdir"' EXIT
    
    # Build MinIO labels if domains are set
    MINIO_LABELS=""
    if [[ -n "$MINIO_DOMAIN" ]]; then
      MINIO_LABELS+="        - \"traefik.enable=true\"\n"
      MINIO_LABELS+="        - \"traefik.http.routers.minio-api.rule=Host(\`$MINIO_DOMAIN\`)\"\n"
      MINIO_LABELS+="        - \"traefik.http.routers.minio-api.entrypoints=websecure\"\n"
      MINIO_LABELS+="        - \"traefik.http.routers.minio-api.tls.certresolver=le\"\n"
      MINIO_LABELS+="        - \"traefik.http.routers.minio-api.service=minio-api\"\n"
      MINIO_LABELS+="        - \"traefik.http.services.minio-api.loadbalancer.server.port=9000\"\n"
    fi
    
    if [[ -n "$MINIO_CONSOLE_DOMAIN" ]]; then
      MINIO_LABELS+="        - \"traefik.http.routers.minio-console.rule=Host(\`$MINIO_CONSOLE_DOMAIN\`)\"\n"
      MINIO_LABELS+="        - \"traefik.http.routers.minio-console.entrypoints=websecure\"\n"
      MINIO_LABELS+="        - \"traefik.http.routers.minio-console.tls.certresolver=le\"\n"
      MINIO_LABELS+="        - \"traefik.http.routers.minio-console.service=minio-console\"\n"
      MINIO_LABELS+="        - \"traefik.http.services.minio-console.loadbalancer.server.port=9001\"\n"
    fi
    
    MINIO_LABELS_SECTION=""
    if [[ -n "$MINIO_LABELS" ]]; then
      MINIO_LABELS_SECTION=$(printf "      labels:\n%b" "$MINIO_LABELS")
    fi
    
    # Redis command with optional password
    REDIS_CMD="redis-server"
    if [[ -n "$REDIS_PASSWORD" ]]; then
      REDIS_CMD="redis-server --requirepass $REDIS_PASSWORD"
    fi
    
    cat >"$tmpdir/stack.yml" <<YAML
version: "3.9"

networks:
  edge:
    external: true
  app:
    external: true

volumes:
  minio_data: {}
  redis_data: {}

services:
  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
    volumes:
      - minio_data:/data
    networks: [edge, app]
    deploy:
      placement:
        constraints: ["node.labels.role==edge"]
      restart_policy:
        condition: on-failure
${MINIO_LABELS_SECTION}

  redis:
    image: redis:7-alpine
    command: ${REDIS_CMD}
    volumes:
      - redis_data:/data
    networks: [app]
    deploy:
      replicas: 1
      placement:
        constraints: 
          - "node.labels.role==app"
          - "node.hostname==stg-be-1.routerra.ru"
      restart_policy:
        condition: on-failure
YAML
    
    docker stack deploy -c "$tmpdir/stack.yml" "$STACK"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  ✓ Storage stack deployed                              ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    echo "MinIO:"
    echo "  Root User:     $MINIO_ROOT_USER"
    echo "  Root Password: $MINIO_ROOT_PASSWORD"
    if [[ -n "$MINIO_DOMAIN" ]]; then
      echo "  S3 API:        https://$MINIO_DOMAIN"
    else
      echo "  S3 API:        http://<node-ip>:9000"
    fi
    if [[ -n "$MINIO_CONSOLE_DOMAIN" ]]; then
      echo "  Console:       https://$MINIO_CONSOLE_DOMAIN"
    else
      echo "  Console:       http://<node-ip>:9001"
    fi
    echo ""
    echo "Redis:"
    echo "  Host:          redis (from Swarm services)"
    echo "  Port:          6379"
    if [[ -n "$REDIS_PASSWORD" ]]; then
      echo "  Password:      $REDIS_PASSWORD"
    else
      echo "  Password:      (no auth)"
    fi
    echo ""
    ;;
    
  down)
    docker stack rm "$STACK" || true
    echo "✓ Storage stack removed"
    ;;
    
  *) 
    echo "Usage: $0 [up|down]" >&2
    exit 2
    ;;
esac

