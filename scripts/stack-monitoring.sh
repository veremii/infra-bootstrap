#!/usr/bin/env bash
set -euo pipefail

ACTION=${1:-up}  # up|down
STACK=${STACK:-infra-monitoring}
PROMETHEUS_DOMAIN=${PROMETHEUS_DOMAIN:-}
ALERTMANAGER_DOMAIN=${ALERTMANAGER_DOMAIN:-}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<'HLP'
Usage: stack-monitoring.sh [up|down]

Deploys Prometheus, Alertmanager, and Node Exporter for metrics monitoring.

Environment variables:
  PROMETHEUS_DOMAIN        Domain for Prometheus UI (e.g., prometheus.example.com)
  ALERTMANAGER_DOMAIN      Domain for Alertmanager UI (e.g., alerts.example.com)
  TELEGRAM_BOT_TOKEN       Telegram bot token for alerts
  TELEGRAM_CHAT_ID         Telegram chat ID for alerts

Examples:
  # Deploy with Telegram alerts
  TELEGRAM_BOT_TOKEN=123:ABC TELEGRAM_CHAT_ID=-100123 ./stack-monitoring.sh up

  # Deploy without Telegram
  ./stack-monitoring.sh up

  # Remove stack
  ./stack-monitoring.sh down
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
    ensure_network infra
    
    tmpdir=$(mktemp -d); trap 'rm -rf "$tmpdir"' EXIT
    
    # Prometheus configuration
    cat >"$tmpdir/prometheus.yml" <<'PROM'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - '/etc/prometheus/alerts.yml'

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter (metrics from all nodes)
  - job_name: 'node-exporter'
    dns_sd_configs:
      - names: ['tasks.node-exporter']
        type: A
        port: 9100

  # Docker Swarm services
  - job_name: 'docker'
    dockerswarm_sd_configs:
      - host: unix:///var/run/docker.sock
        role: tasks
    relabel_configs:
      - source_labels: [__meta_dockerswarm_service_name]
        target_label: service
PROM

    # Alert rules
    cat >"$tmpdir/alerts.yml" <<'ALERTS'
groups:
  - name: infrastructure
    interval: 30s
    rules:
      - alert: NodeDown
        expr: up{job="node-exporter"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Node {{ $labels.instance }} is down"
          description: "Node exporter on {{ $labels.instance }} has been down for more than 1 minute."

      - alert: HighCPU
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80% for more than 5 minutes."

      - alert: HighMemory
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 85% for more than 5 minutes."

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Disk space is below 15% on root partition."

      - alert: ServiceDown
        expr: up{job=~".*"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.job }} is down"
          description: "Service {{ $labels.job }} has been down for more than 2 minutes."
ALERTS

    # Alertmanager configuration
    ALERTMANAGER_CONFIG=""
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
      ALERTMANAGER_CONFIG=$(cat <<AMCFG
route:
  receiver: 'telegram'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h

receivers:
  - name: 'telegram'
    telegram_configs:
      - bot_token: '$TELEGRAM_BOT_TOKEN'
        chat_id: $TELEGRAM_CHAT_ID
        parse_mode: 'HTML'
        message: |
          🚨 <b>{{ .GroupLabels.alertname }}</b>
          
          <b>Severity:</b> {{ .CommonLabels.severity }}
          <b>Summary:</b> {{ .CommonAnnotations.summary }}
          <b>Description:</b> {{ .CommonAnnotations.description }}
          
          <b>Time:</b> {{ .StartsAt.Format "15:04:05 02.01.2006" }}
AMCFG
)
    else
      ALERTMANAGER_CONFIG=$(cat <<AMCFG
route:
  receiver: 'default'
  
receivers:
  - name: 'default'
AMCFG
)
    fi
    
    echo "$ALERTMANAGER_CONFIG" > "$tmpdir/alertmanager.yml"
    
    # Build Prometheus labels
    PROM_LABELS=""
    if [[ -n "$PROMETHEUS_DOMAIN" ]]; then
      PROM_LABELS+="        - \"traefik.enable=true\"\n"
      PROM_LABELS+="        - \"traefik.http.routers.prometheus.rule=Host(\`$PROMETHEUS_DOMAIN\`)\"\n"
      PROM_LABELS+="        - \"traefik.http.routers.prometheus.entrypoints=websecure\"\n"
      PROM_LABELS+="        - \"traefik.http.routers.prometheus.tls.certresolver=le\"\n"
      PROM_LABELS+="        - \"traefik.http.services.prometheus.loadbalancer.server.port=9090\"\n"
    fi
    
    PROM_LABELS_SECTION=""
    if [[ -n "$PROM_LABELS" ]]; then
      PROM_LABELS_SECTION=$(printf "      labels:\n%b" "$PROM_LABELS")
    fi
    
    # Build Alertmanager labels
    AM_LABELS=""
    if [[ -n "$ALERTMANAGER_DOMAIN" ]]; then
      AM_LABELS+="        - \"traefik.enable=true\"\n"
      AM_LABELS+="        - \"traefik.http.routers.alertmanager.rule=Host(\`$ALERTMANAGER_DOMAIN\`)\"\n"
      AM_LABELS+="        - \"traefik.http.routers.alertmanager.entrypoints=websecure\"\n"
      AM_LABELS+="        - \"traefik.http.routers.alertmanager.tls.certresolver=le\"\n"
      AM_LABELS+="        - \"traefik.http.services.alertmanager.loadbalancer.server.port=9093\"\n"
    fi
    
    AM_LABELS_SECTION=""
    if [[ -n "$AM_LABELS" ]]; then
      AM_LABELS_SECTION=$(printf "      labels:\n%b" "$AM_LABELS")
    fi
    
    cat >"$tmpdir/stack.yml" <<YAML
version: "3.9"

networks:
  edge:
    external: true
  infra:
    external: true

volumes:
  prometheus_data: {}
  alertmanager_data: {}

configs:
  prometheus_config:
    file: ./prometheus.yml
  prometheus_alerts:
    file: ./alerts.yml
  alertmanager_config:
    file: ./alertmanager.yml

services:
  prometheus:
    image: prom/prometheus:latest
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    volumes:
      - prometheus_data:/prometheus
      - /var/run/docker.sock:/var/run/docker.sock:ro
    configs:
      - source: prometheus_config
        target: /etc/prometheus/prometheus.yml
      - source: prometheus_alerts
        target: /etc/prometheus/alerts.yml
    networks: [edge, infra]
    deploy:
      placement:
        constraints: ["node.labels.role==edge"]
      restart_policy:
        condition: on-failure
${PROM_LABELS_SECTION}

  alertmanager:
    image: prom/alertmanager:latest
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    volumes:
      - alertmanager_data:/alertmanager
    configs:
      - source: alertmanager_config
        target: /etc/alertmanager/alertmanager.yml
    networks: [edge, infra]
    deploy:
      placement:
        constraints: ["node.labels.role==edge"]
      restart_policy:
        condition: on-failure
${AM_LABELS_SECTION}

  node-exporter:
    image: prom/node-exporter:latest
    command:
      - '--path.rootfs=/host'
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /:/host:ro,rslave
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
    networks: [infra]
    deploy:
      mode: global
      restart_policy:
        condition: on-failure
YAML
    
    docker stack deploy -c "$tmpdir/stack.yml" "$STACK"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  ✓ Monitoring stack deployed                           ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    echo "Prometheus:"
    if [[ -n "$PROMETHEUS_DOMAIN" ]]; then
      echo "  URL:           https://$PROMETHEUS_DOMAIN"
    else
      echo "  URL:           http://<edge-node-ip>:9090"
    fi
    echo ""
    echo "Alertmanager:"
    if [[ -n "$ALERTMANAGER_DOMAIN" ]]; then
      echo "  URL:           https://$ALERTMANAGER_DOMAIN"
    else
      echo "  URL:           http://<edge-node-ip>:9093"
    fi
    if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
      echo "  Telegram:      Enabled ✓"
      echo "  Chat ID:       $TELEGRAM_CHAT_ID"
    else
      echo "  Telegram:      Not configured"
    fi
    echo ""
    echo "Node Exporter:"
    echo "  Mode:          Global (on all nodes)"
    echo "  Metrics:       http://<any-node>:9100/metrics"
    echo ""
    ;;
    
  down)
    docker stack rm "$STACK" || true
    echo "✓ Monitoring stack removed"
    ;;
    
  *) 
    echo "Usage: $0 [up|down]" >&2
    exit 2
    ;;
esac



