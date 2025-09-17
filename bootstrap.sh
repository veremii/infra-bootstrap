#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# Infrastructure Bootstrap Script
# ==============================================
# Простой скрипт для быстрого развёртывания
# инфраструктуры на новом сервере
# ==============================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
  cat <<'EOF'
Usage: bootstrap.sh [OPTIONS] [COMMAND]

Quick infrastructure deployment script.

Commands:
  install     Full installation (default)
  check       Only check configuration
  clean       Clean up after installation

Options:
  -H, --hostname HOST  Override hostname detection
  -y, --yes           Auto-confirm all prompts
  -h, --help          Show this help

Examples:
  # Full installation
  ./bootstrap.sh
  
  # Check configuration only
  ./bootstrap.sh check
  
  # Specific hostname
  ./bootstrap.sh -H prod-edge-1.example.com install

The script will:
1. Detect hostname and select appropriate configuration
2. Run interactive quickstart or step-by-step setup
3. Install system services and configurations
4. Optionally clean up installation files
EOF
}

# Параметры
HOSTNAME="${OVERRIDE_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
AUTO_CONFIRM=false
COMMAND="install"

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    -y|--yes)
      AUTO_CONFIRM=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    install|check|clean)
      COMMAND="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Проверка окружения
check_environment() {
  echo -e "${BLUE}=== Environment Check ===${NC}"
  echo "Hostname: $HOSTNAME"
  echo "User: $(whoami)"
  echo "OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown")"
  echo ""
  
  # Проверка, что мы в правильной директории
  if [ ! -f "Makefile" ] || [ ! -d "scripts" ]; then
    echo -e "${RED}Error: Not in infra-bootstrap directory${NC}"
    echo "Please run from the root of the extracted bundle"
    exit 1
  fi
  
  # Проверка прав
  if [ "$(id -u)" -eq 0 ]; then
    echo -e "${YELLOW}Warning: Running as root${NC}"
    echo "It's recommended to run as regular user (script will use sudo when needed)"
  fi
}

# Установка
do_install() {
  echo -e "${BLUE}=== Starting Installation ===${NC}"
  
  # Выбор конфигурации
  if [ -f "envs/hosts.yml" ] && [ -x "scripts/env-selector.sh" ]; then
    echo "Selecting configuration for hostname: $HOSTNAME"
    ./scripts/env-selector.sh -H "$HOSTNAME" || {
      echo -e "${YELLOW}Warning: Could not auto-select configuration${NC}"
    }
  fi
  
  # Запуск quickstart если есть
  if [ -x "scripts/quickstart.sh" ]; then
    echo -e "${BLUE}Running interactive setup...${NC}"
    if [ "$AUTO_CONFIRM" = "true" ]; then
      yes "" | ./scripts/quickstart.sh || true
    else
      ./scripts/quickstart.sh
    fi
  else
    # Fallback на обычную установку
    echo -e "${BLUE}Running standard installation...${NC}"
    
    # Проверка конфигурации
    make check-env || {
      echo -e "${RED}Configuration check failed${NC}"
      echo "Please create and configure .env file first"
      exit 1
    }
    
    # Предложение команд для выполнения
    echo ""
    echo -e "${GREEN}Configuration OK. Run these commands to complete setup:${NC}"
    echo ""
    echo "  # Basic setup"
    echo "  sudo make init users ssh ufw docker deploy_dir"
    echo ""
    echo "  # Optional: WireGuard VPN"
    echo "  sudo make wg-server"
    echo ""
    echo "  # Docker Swarm networks"
    echo "  sudo make net-bootstrap"
    echo ""
    echo "  # Services"
    echo "  sudo make traefik-up     # Traefik reverse proxy"
    echo "  sudo make logs-up        # Monitoring stack"
    echo "  sudo make portainer-up   # Docker UI"
    echo ""
    echo "  # Check status"
    echo "  make healthcheck"
  fi
}

# Проверка конфигурации
do_check() {
  echo -e "${BLUE}=== Configuration Check ===${NC}"
  
  # Выбор конфигурации
  if [ -f "envs/hosts.yml" ] && [ -x "scripts/env-selector.sh" ]; then
    ./scripts/env-selector.sh -H "$HOSTNAME" --dry-run || true
  fi
  
  # Проверка .env
  if [ -f ".env" ]; then
    echo -e "${GREEN}✓ .env file exists${NC}"
    make check-env || true
  else
    echo -e "${YELLOW}⚠ No .env file found${NC}"
    echo "Run 'make env-select' or create from .env.example"
  fi
  
  # Проверка здоровья системы
  if [ -x "scripts/healthcheck.sh" ]; then
    echo ""
    ./scripts/healthcheck.sh || true
  fi
}

# Очистка
do_clean() {
  echo -e "${BLUE}=== Cleanup ===${NC}"
  
  if [ "$AUTO_CONFIRM" != "true" ]; then
    read -p "Remove infra-bootstrap directory? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
  fi
  
  # Сохранение важных скриптов
  echo "Preserving useful scripts..."
  if [ -f "scripts/healthcheck.sh" ]; then
    sudo cp scripts/healthcheck.sh /usr/local/bin/infra-healthcheck 2>/dev/null || true
    sudo chmod +x /usr/local/bin/infra-healthcheck 2>/dev/null || true
    echo "  - Saved: /usr/local/bin/infra-healthcheck"
  fi
  
  if [ -f "scripts/wg-new-client.sh" ]; then
    sudo cp scripts/wg-new-client.sh /usr/local/bin/ 2>/dev/null || true
    sudo chmod +x /usr/local/bin/wg-new-client 2>/dev/null || true
    echo "  - Saved: /usr/local/bin/wg-new-client"
  fi
  
  # Сохранение .env
  if [ -f ".env" ]; then
    mkdir -p ~/infra-backup
    cp .env ~/infra-backup/
    echo "  - Saved: ~/infra-backup/.env"
  fi
  
  # Удаление
  cd ..
  rm -rf "$(basename "$(pwd)")"
  echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Main
main() {
  check_environment
  
  case "$COMMAND" in
    install)
      do_install
      ;;
    check)
      do_check
      ;;
    clean)
      do_clean
      ;;
    *)
      echo "Unknown command: $COMMAND"
      exit 1
      ;;
  esac
}

main "$@"