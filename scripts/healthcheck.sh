#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Счетчики
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Функция проверки
check_service() {
  local name="$1"
  local check_cmd="$2"
  local required="${3:-true}"
  
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  
  printf "%-30s" "$name"
  
  if eval "$check_cmd" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
    return 0
  else
    if [ "$required" = "true" ]; then
      echo -e "${RED}✗ FAIL${NC}"
      CHECKS_FAILED=$((CHECKS_FAILED + 1))
    else
      echo -e "${YELLOW}⚠ WARN${NC}"
      CHECKS_WARNING=$((CHECKS_WARNING + 1))
    fi
    return 1
  fi
}

# Функция проверки порта
check_port() {
  local name="$1"
  local port="$2"
  local interface="${3:-}"
  
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  
  printf "%-30s" "$name"
  
  if [ -n "$interface" ]; then
    if ss -tlnp 2>/dev/null | grep -q ":$port.*$interface" || netstat -tlnp 2>/dev/null | grep -q ":$port"; then
      echo -e "${GREEN}✓ LISTENING${NC}"
      CHECKS_PASSED=$((CHECKS_PASSED + 1))
      return 0
    fi
  else
    if ss -tln 2>/dev/null | grep -q ":$port" || netstat -tln 2>/dev/null | grep -q ":$port"; then
      echo -e "${GREEN}✓ LISTENING${NC}"
      CHECKS_PASSED=$((CHECKS_PASSED + 1))
      return 0
    fi
  fi
  
  echo -e "${YELLOW}⚠ NOT LISTENING${NC}"
  CHECKS_WARNING=$((CHECKS_WARNING + 1))
  return 1
}

# Функция проверки файла
check_file() {
  local name="$1"
  local file="$2"
  
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  
  printf "%-30s" "$name"
  
  if [ -f "$file" ]; then
    echo -e "${GREEN}✓ EXISTS${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗ MISSING${NC}"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    return 1
  fi
}

# Функция проверки Docker сервиса
check_docker_service() {
  local name="$1"
  local service="$2"
  
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  
  printf "%-30s" "$name"
  
  if docker service ls 2>/dev/null | grep -q "$service"; then
    local replicas
    replicas=$(docker service ls --format "table {{.Replicas}}" --filter "name=$service" | tail -n +2)
    echo -e "${GREEN}✓ RUNNING${NC} ($replicas)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
    return 0
  else
    echo -e "${YELLOW}⚠ NOT DEPLOYED${NC}"
    CHECKS_WARNING=$((CHECKS_WARNING + 1))
    return 1
  fi
}

# Загрузка переменных окружения
load_env() {
  if [ -f .env ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' .env | xargs -d '\n' || true)
  fi
}

# Main
main() {
  cd "$(dirname "$0")/.."  # Переходим в корень проекта
  load_env
  
  echo -e "${BLUE}=== Infrastructure Health Check ===${NC}"
  echo ""
  
  # System checks
  echo -e "${BLUE}System Services:${NC}"
  check_service "SSH daemon" "systemctl is-active ssh || systemctl is-active sshd"
  check_port "SSH port ${SSH_PORT:-1255}" "${SSH_PORT:-1255}"
  check_service "UFW firewall" "ufw status | grep -q 'Status: active'" false
  check_service "SystemD" "systemctl --version"
  echo ""
  
  # Docker checks
  echo -e "${BLUE}Docker:${NC}"
  check_service "Docker daemon" "docker info"
  check_service "Docker Swarm mode" "docker info | grep -q 'Swarm: active'" false
  if docker info 2>/dev/null | grep -q 'Swarm: active'; then
    echo -n "  Swarm nodes: "
    docker node ls 2>/dev/null | grep -c Ready || echo "0"
  fi
  echo ""
  
  # Network checks
  echo -e "${BLUE}Docker Networks:${NC}"
  for net in edge app infra; do
    check_service "Network: $net" "docker network ls | grep -q \"$net\""
  done
  echo ""
  
  # WireGuard checks
  echo -e "${BLUE}WireGuard VPN:${NC}"
  check_service "WireGuard installed" "command -v wg"
  check_service "WireGuard interface ${WG_IF:-wg0}" "wg show ${WG_IF:-wg0}" false
  if wg show "${WG_IF:-wg0}" >/dev/null 2>&1; then
    echo -n "  Active peers: "
    wg show "${WG_IF:-wg0}" peers 2>/dev/null | wc -l || echo "0"
  fi
  check_port "WireGuard port ${WG_PORT:-51820}" "${WG_PORT:-51820}" "udp"
  echo ""
  
  # Configuration checks
  echo -e "${BLUE}Configuration:${NC}"
  check_file ".env file" ".env"
  check_file "Makefile" "Makefile"
  check_file "lib.sh" "scripts/lib.sh"
  echo ""
  
  # Service stacks
  echo -e "${BLUE}Service Stacks:${NC}"
  check_docker_service "Traefik" "traefik"
  check_docker_service "Portainer" "portainer"
  check_docker_service "Loki" "loki"
  check_docker_service "Promtail" "promtail"
  check_docker_service "Grafana" "grafana"
  echo ""
  
  # Ports check
  echo -e "${BLUE}Network Ports:${NC}"
  check_port "HTTP (80)" "80"
  check_port "HTTPS (443)" "443"
  check_port "Docker API (2377)" "2377"
  echo ""
  
  # Users check
  echo -e "${BLUE}System Users:${NC}"
  check_service "Admin user: ${ADMIN_USER:-admin}" "id ${ADMIN_USER:-admin}"
  check_service "Deploy user: ${DEPLOY_USER:-deployer}" "id ${DEPLOY_USER:-deployer}"
  echo ""
  
  # Summary
  echo -e "${BLUE}=== Summary ===${NC}"
  echo "Total checks: $CHECKS_TOTAL"
  echo -e "Passed: ${GREEN}$CHECKS_PASSED${NC}"
  echo -e "Warnings: ${YELLOW}$CHECKS_WARNING${NC}"
  echo -e "Failed: ${RED}$CHECKS_FAILED${NC}"
  echo ""
  
  if [ $CHECKS_FAILED -gt 0 ]; then
    echo -e "${RED}⚠ System has critical issues that need attention${NC}"
    exit 1
  elif [ $CHECKS_WARNING -gt 0 ]; then
    echo -e "${YELLOW}⚠ System is operational but has warnings${NC}"
    exit 0
  else
    echo -e "${GREEN}✓ All systems operational${NC}"
    exit 0
  fi
}

# Обработка параметров
case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Usage: healthcheck.sh [OPTIONS]

Infrastructure health check script.

Options:
  -h, --help   Show this help
  -v, --verbose Show detailed output (TODO)

The script checks:
- System services (SSH, UFW, Docker)
- Docker Swarm status and networks
- WireGuard VPN configuration
- Service stacks (Traefik, monitoring)
- Network ports availability
- System users

Exit codes:
  0 - All checks passed or only warnings
  1 - Critical failures detected
HELP
    ;;
  *)
    main
    ;;
esac

