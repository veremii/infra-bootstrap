#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Infrastructure Bootstrap Quick Start ===${NC}"
echo ""

# Проверка операционной системы
check_os() {
  if grep -q "debian\|ubuntu" /etc/os-release 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Detected Debian/Ubuntu system"
  else
    echo -e "${YELLOW}⚠${NC}  This script is tested only on Debian/Ubuntu"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
  fi
}

# Проверка, что мы не под root
check_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    echo -e "${RED}✗${NC} This script should not be run as root"
    echo "Please run as regular user. The script will use sudo when needed."
    exit 1
  fi
}

# Генерация .env из примера или выбор из множественных окружений
create_env() {
  if [ -f .env ]; then
    echo -e "${GREEN}✓${NC} Found existing .env file"
    return
  fi

  # Проверяем наличие множественных окружений
  if [ -f envs/hosts.yml ] && [ -d envs/production ]; then
    echo -e "${BLUE}Multiple environments detected!${NC}"
    echo ""
    
    # Пытаемся автоматически определить конфигурацию
    if ./scripts/env-selector.sh --dry-run >/dev/null 2>&1; then
      echo "Auto-detecting configuration based on hostname..."
      if ./scripts/env-selector.sh; then
        echo -e "${GREEN}✓${NC} Configuration loaded from envs/"
        return
      fi
    fi
    
    # Если не удалось автоматически, предлагаем выбрать
    echo -e "${YELLOW}Could not auto-detect configuration${NC}"
    echo ""
    ./scripts/env-selector.sh --list
    echo ""
    echo "Options:"
    echo "1) Use default .env.example"
    echo "2) Select specific environment"
    echo "3) Exit"
    read -p "Choose [1-3]: " choice
    
    case $choice in
      1)
        if [ ! -f .env.example ]; then
          echo -e "${RED}✗${NC} .env.example not found!"
          exit 1
        fi
        cp .env.example .env
        ;;
      2)
        read -p "Enter environment name (e.g., production/edge-de1.env): " env_name
        if ./scripts/env-selector.sh --config "$env_name"; then
          return
        else
          echo -e "${RED}✗${NC} Failed to load configuration"
          exit 1
        fi
        ;;
      *)
        echo "Exiting..."
        exit 0
        ;;
    esac
  else
    # Стандартный путь с .env.example
    if [ ! -f .env.example ]; then
      echo -e "${RED}✗${NC} .env.example not found!"
      exit 1
    fi

    echo -e "${BLUE}Creating .env from template...${NC}"
    cp .env.example .env
  fi

  # Автоопределение публичного IP
  echo -n "Detecting public IP... "
  PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "")
  if [ -n "$PUBLIC_IP" ]; then
    sed -i "s/YOUR_PUBLIC_IP/$PUBLIC_IP/" .env
    echo -e "${GREEN}✓${NC} $PUBLIC_IP"
  else
    echo -e "${YELLOW}⚠${NC}  Failed to detect. Please set WG_ENDPOINT_IP manually in .env"
  fi
}

# Генерация SSH ключей
generate_ssh_keys() {
  source .env

  # Admin key
  if [ -z "${ADMIN_PUBKEY:-}" ] || [ "${ADMIN_PUBKEY}" = "ssh-ed25519 AAAAC3... your-key-here" ]; then
    echo ""
    echo -e "${BLUE}Generating SSH key for admin user...${NC}"
    if [ -f "$HOME/.ssh/admin_key" ]; then
      echo -e "${YELLOW}⚠${NC}  Found existing admin_key, using it"
      ADMIN_PUBKEY=$(cat "$HOME/.ssh/admin_key.pub")
    else
      ssh-keygen -t ed25519 -f "$HOME/.ssh/admin_key" -N "" -C "admin@infra-bootstrap"
      ADMIN_PUBKEY=$(cat "$HOME/.ssh/admin_key.pub")
      echo -e "${GREEN}✓${NC} Generated new key: $HOME/.ssh/admin_key"
    fi
    # Обновляем .env
    sed -i "s|^ADMIN_PUBKEY=.*|ADMIN_PUBKEY=\"$ADMIN_PUBKEY\"|" .env
  fi

  # Deploy key
  if [ -z "${DEPLOY_PUBKEY:-}" ] || [ "${DEPLOY_PUBKEY}" = "ssh-ed25519 AAAAC3... your-key-here" ]; then
    echo ""
    echo -e "${BLUE}Generating SSH key for deploy user...${NC}"
    if [ -f "$HOME/.ssh/deploy_key" ]; then
      echo -e "${YELLOW}⚠${NC}  Found existing deploy_key, using it"
      DEPLOY_PUBKEY=$(cat "$HOME/.ssh/deploy_key.pub")
    else
      ssh-keygen -t ed25519 -f "$HOME/.ssh/deploy_key" -N "" -C "deploy@infra-bootstrap"
      DEPLOY_PUBKEY=$(cat "$HOME/.ssh/deploy_key.pub")
      echo -e "${GREEN}✓${NC} Generated new key: $HOME/.ssh/deploy_key"
    fi
    # Обновляем .env
    sed -i "s|^DEPLOY_PUBKEY=.*|DEPLOY_PUBKEY=\"$DEPLOY_PUBKEY\"|" .env
  fi
}

# Настройка email для Let's Encrypt
setup_email() {
  source .env
  
  if [ "${TRAEFIK_ACME_EMAIL:-}" = "admin@example.com" ]; then
    echo ""
    echo -e "${BLUE}Let's Encrypt email configuration${NC}"
    read -p "Enter email for SSL certificates (or press Enter to skip): " email
    if [ -n "$email" ]; then
      sed -i "s/^TRAEFIK_ACME_EMAIL=.*/TRAEFIK_ACME_EMAIL=$email/" .env
      echo -e "${GREEN}✓${NC} Email set to: $email"
    else
      echo -e "${YELLOW}⚠${NC}  Skipped. Remember to set TRAEFIK_ACME_EMAIL before deploying Traefik"
    fi
  fi
}

# Показать следующие шаги
show_next_steps() {
  echo ""
  echo -e "${GREEN}=== Setup Complete! ===${NC}"
  echo ""
  echo "Your configuration has been saved to .env"
  echo ""
  echo -e "${BLUE}SSH Keys location:${NC}"
  echo "  Admin: $HOME/.ssh/admin_key (private), $HOME/.ssh/admin_key.pub (public)"
  echo "  Deploy: $HOME/.ssh/deploy_key (private), $HOME/.ssh/deploy_key.pub (public)"
  echo ""
  echo -e "${BLUE}Next steps:${NC}"
  echo "1. Review and adjust settings in .env if needed"
  echo "2. Run the bootstrap process:"
  echo ""
  echo "   ${GREEN}# Basic setup (users, SSH, firewall, Docker)${NC}"
  echo "   sudo make init users ssh ufw docker deploy_dir"
  echo ""
  echo "   ${GREEN}# Setup WireGuard VPN server${NC}"
  echo "   sudo make wg-server"
  echo ""
  echo "   ${GREEN}# Bootstrap Docker Swarm networks${NC}"
  echo "   sudo make net-bootstrap"
  echo ""
  echo "   ${GREEN}# Deploy Traefik (on edge node)${NC}"
  echo "   sudo make traefik-up"
  echo ""
  echo "   ${GREEN}# Optional: monitoring and management${NC}"
  echo "   sudo make logs-up      # Loki + Promtail + Grafana"
  echo "   sudo make portainer-up # Portainer CE"
  echo ""
  echo -e "${YELLOW}Important:${NC} After SSH setup, you'll need to reconnect on the new port"
  echo "specified in SSH_PORT (default: 1255)"
}

# Интерактивный режим
interactive_mode() {
  echo ""
  echo -e "${BLUE}Running in interactive mode${NC}"
  echo "This will help you set up the initial configuration"
  echo ""
  
  # Проверяем наличие make
  if ! command -v make >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing make...${NC}"
    sudo apt-get update -y && sudo apt-get install -y make
  fi
  
  create_env
  generate_ssh_keys
  setup_email
  
  # Валидация конфигурации
  echo ""
  echo -e "${BLUE}Validating configuration...${NC}"
  if make check-env; then
    show_next_steps
  else
    echo ""
    echo -e "${RED}Configuration validation failed!${NC}"
    echo "Please edit .env and fix the issues above"
    exit 1
  fi
}

# Main
main() {
  cd "$(dirname "$0")/.."  # Переходим в корень проекта
  
  check_not_root
  check_os
  
  case "${1:-interactive}" in
    -h|--help)
      cat <<'HELP'
Usage: quickstart.sh [MODE]

Quick start script for infrastructure bootstrap.

Modes:
  interactive  Interactive setup (default)
  check        Only validate configuration
  -h, --help   Show this help

The script will:
1. Create .env from template
2. Auto-detect public IP
3. Generate SSH keys if needed
4. Configure email for Let's Encrypt
5. Validate configuration
6. Show next steps

Examples:
  ./scripts/quickstart.sh              # Interactive mode
  ./scripts/quickstart.sh check        # Only validate
HELP
      ;;
    check)
      if [ ! -f .env ]; then
        echo -e "${RED}✗${NC} .env not found. Run without arguments for interactive setup."
        exit 1
      fi
      make check-env
      ;;
    interactive|"")
      interactive_mode
      ;;
    *)
      echo "Unknown mode: $1"
      echo "Run with --help for usage"
      exit 1
      ;;
  esac
}

main "$@"
