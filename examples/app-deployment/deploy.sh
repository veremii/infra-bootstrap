#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# Application Deployment Script
# ==============================================
# Деплоит ваше приложение используя инфраструктуру
# созданную через infra-bootstrap
# ==============================================

# Конфигурация
STACK_NAME="${STACK_NAME:-myapp}"
STACK_FILE="${STACK_FILE:-stack.yml}"
VERSION="${VERSION:-latest}"
SECRETS_ENV="${SECRETS_ENV:-.env.production}"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
  cat <<EOF
Usage: deploy.sh [OPTIONS] COMMAND

Commands:
  deploy     Deploy or update the application
  rollback   Rollback to previous version
  status     Show deployment status
  logs       Show application logs
  secrets    Update secrets from env file

Options:
  -s, --stack NAME      Stack name (default: $STACK_NAME)
  -f, --file FILE       Stack file (default: $STACK_FILE)
  -v, --version TAG     Image version (default: $VERSION)
  -e, --env FILE        Secrets env file (default: $SECRETS_ENV)
  -h, --help            Show this help

Examples:
  # Deploy latest version
  ./deploy.sh deploy

  # Deploy specific version
  ./deploy.sh -v v1.2.3 deploy

  # Update secrets and deploy
  ./deploy.sh secrets
  ./deploy.sh deploy

  # Check status
  ./deploy.sh status
EOF
}

# Парсинг аргументов
COMMAND=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--stack)
      STACK_NAME="$2"
      shift 2
      ;;
    -f|--file)
      STACK_FILE="$2"
      shift 2
      ;;
    -v|--version)
      VERSION="$2"
      shift 2
      ;;
    -e|--env)
      SECRETS_ENV="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    deploy|rollback|status|logs|secrets)
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

# Проверка Docker Swarm
check_swarm() {
  if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo -e "${RED}Error: Docker Swarm is not active${NC}"
    echo "Initialize swarm first: docker swarm init"
    exit 1
  fi
}

# Загрузка секретов
load_secrets() {
  echo -e "${BLUE}Loading secrets from $SECRETS_ENV...${NC}"
  
  if [ ! -f "$SECRETS_ENV" ]; then
    echo -e "${RED}Error: Secrets file not found: $SECRETS_ENV${NC}"
    exit 1
  fi
  
  # Используем secrets-to-swarm.sh из infra-bootstrap
  if command -v secrets-to-swarm.sh >/dev/null 2>&1; then
    secrets-to-swarm.sh -f "$SECRETS_ENV" -p "${STACK_NAME}_"
  else
    # Fallback на ручное создание
    while IFS='=' read -r key value; do
      [ -z "$key" ] || [[ "$key" =~ ^# ]] && continue
      secret_name="${STACK_NAME}_${key}"
      echo "Creating secret: $secret_name"
      docker secret rm "$secret_name" 2>/dev/null || true
      echo -n "$value" | docker secret create "$secret_name" -
    done < "$SECRETS_ENV"
  fi
  
  echo -e "${GREEN}✓ Secrets loaded${NC}"
}

# Деплой приложения
deploy_app() {
  echo -e "${BLUE}Deploying $STACK_NAME version $VERSION...${NC}"
  
  if [ ! -f "$STACK_FILE" ]; then
    echo -e "${RED}Error: Stack file not found: $STACK_FILE${NC}"
    exit 1
  fi
  
  # Проверяем сети
  for network in app edge; do
    if ! docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
      echo -e "${YELLOW}Warning: Network '$network' not found${NC}"
      echo "Run 'make net-bootstrap' on infra-bootstrap first"
    fi
  done
  
  # Деплоим с версией
  VERSION="$VERSION" docker stack deploy -c "$STACK_FILE" "$STACK_NAME"
  
  echo -e "${GREEN}✓ Deployment started${NC}"
  echo ""
  echo "Monitor progress:"
  echo "  docker service ls --filter label=com.docker.stack.namespace=$STACK_NAME"
  echo "  docker stack ps $STACK_NAME"
}

# Откат
rollback_app() {
  echo -e "${BLUE}Rolling back $STACK_NAME...${NC}"
  
  # Получаем текущие сервисы
  services=$(docker service ls --filter label=com.docker.stack.namespace=$STACK_NAME --format '{{.Name}}')
  
  for service in $services; do
    echo "Rolling back $service..."
    docker service rollback "$service" || true
  done
  
  echo -e "${GREEN}✓ Rollback initiated${NC}"
}

# Статус
show_status() {
  echo -e "${BLUE}=== $STACK_NAME Status ===${NC}"
  echo ""
  
  # Сервисы
  echo "Services:"
  docker service ls --filter label=com.docker.stack.namespace=$STACK_NAME
  echo ""
  
  # Задачи
  echo "Tasks:"
  docker stack ps "$STACK_NAME" --format "table {{.Name}}\t{{.Image}}\t{{.Node}}\t{{.CurrentState}}"
  echo ""
  
  # Секреты
  echo "Secrets:"
  docker secret ls --filter name="${STACK_NAME}_" --format "table {{.Name}}\t{{.CreatedAt}}"
}

# Логи
show_logs() {
  echo -e "${BLUE}=== $STACK_NAME Logs ===${NC}"
  
  # Список сервисов для выбора
  services=$(docker service ls --filter label=com.docker.stack.namespace=$STACK_NAME --format '{{.Name}}')
  
  if [ -z "$services" ]; then
    echo "No services found for stack $STACK_NAME"
    exit 1
  fi
  
  echo "Available services:"
  echo "$services" | nl
  echo ""
  read -p "Select service number (or 0 for all): " selection
  
  if [ "$selection" -eq 0 ]; then
    # Все сервисы
    for service in $services; do
      echo -e "\n${BLUE}=== $service ===${NC}"
      docker service logs --tail 50 -f "$service" &
    done
    wait
  else
    # Конкретный сервис
    service=$(echo "$services" | sed -n "${selection}p")
    docker service logs --tail 100 -f "$service"
  fi
}

# Main
main() {
  if [ -z "$COMMAND" ]; then
    echo "Error: No command specified"
    show_help
    exit 1
  fi
  
  check_swarm
  
  case "$COMMAND" in
    deploy)
      deploy_app
      ;;
    rollback)
      rollback_app
      ;;
    status)
      show_status
      ;;
    logs)
      show_logs
      ;;
    secrets)
      load_secrets
      ;;
    *)
      echo "Unknown command: $COMMAND"
      show_help
      exit 1
      ;;
  esac
}

main

