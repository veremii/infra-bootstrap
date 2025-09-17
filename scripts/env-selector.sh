#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Путь к директории с конфигурациями
ENVS_DIR="${ENVS_DIR:-$(dirname "$0")/../envs}"
HOSTS_FILE="${HOSTS_FILE:-$ENVS_DIR/hosts.yml}"

show_help() {
  cat <<'HLP'
Usage: env-selector.sh [OPTIONS]

Automatically selects and loads environment configuration based on hostname.

Options:
  -h, --help          Show this help
  -H, --hostname HOST Override hostname detection
  -e, --env ENV       Force specific environment (production/staging/development)
  -c, --config FILE   Use specific config file directly
  -l, --list          List all available configurations
  -s, --show          Show current host mapping
  -o, --output FILE   Write selected env to file (default: .env)
  --dry-run           Show what would be done without doing it

Examples:
  ./scripts/env-selector.sh                    # Auto-detect and load config
  ./scripts/env-selector.sh -H prod-app-1     # Use config for specific host
  ./scripts/env-selector.sh -e staging        # Force staging environment
  ./scripts/env-selector.sh --list            # Show all configs
  ./scripts/env-selector.sh --dry-run         # Test without changes

The script will:
1. Detect current hostname
2. Look up configuration in hosts.yml
3. Copy appropriate .env file from envs/ directory
4. Show what configuration was loaded
HLP
}

# Получить текущий hostname
get_hostname() {
  if [ -n "${OVERRIDE_HOSTNAME:-}" ]; then
    echo "$OVERRIDE_HOSTNAME"
  else
    hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown"
  fi
}

# Парсинг YAML (простой, для hosts.yml)
parse_yaml() {
  local file="$1"
  local prefix="${2:-}"
  
  # Требуется yq или python с pyyaml
  if command -v yq >/dev/null 2>&1; then
    yq eval "$prefix" "$file" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "
import yaml, sys
with open('$file', 'r') as f:
    data = yaml.safe_load(f)
    query = '$prefix'.strip('.')
    if query:
        for key in query.split('.'):
            data = data.get(key, {})
    print(yaml.dump(data, default_flow_style=False) if data else '')
" 2>/dev/null || true
  else
    echo -e "${YELLOW}⚠${NC}  YAML parser not found. Install yq or python3-yaml"
    return 1
  fi
}

# Найти конфигурацию для хоста
find_host_config() {
  local hostname="$1"
  local hosts_file="$2"
  
  if [ ! -f "$hosts_file" ]; then
    echo -e "${RED}✗${NC} Hosts file not found: $hosts_file"
    return 1
  fi
  
  # Ищем точное совпадение
  local config
  config=$(parse_yaml "$hosts_file" ".hosts.\"$hostname\".config")
  if [ -n "$config" ]; then
    echo "$config"
    return 0
  fi
  
  # Ищем по части имени (например, prod-* для prod-app-1.internal)
  local shortname="${hostname%%.*}"
  config=$(parse_yaml "$hosts_file" ".hosts.\"$shortname\".config")
  if [ -n "$config" ]; then
    echo "$config"
    return 0
  fi
  
  # Используем дефолтную конфигурацию
  config=$(parse_yaml "$hosts_file" ".defaults.config")
  if [ -n "$config" ]; then
    echo -e "${YELLOW}⚠${NC}  Using default config: $config" >&2
    echo "$config"
    return 0
  fi
  
  return 1
}

# Показать информацию о хосте
show_host_info() {
  local hostname="$1"
  local hosts_file="$2"
  
  echo -e "${BLUE}=== Host Information ===${NC}"
  echo "Hostname: $hostname"
  
  # Полная информация о хосте
  local info
  info=$(parse_yaml "$hosts_file" ".hosts.\"$hostname\"")
  if [ -z "$info" ]; then
    # Пробуем короткое имя
    local shortname="${hostname%%.*}"
    info=$(parse_yaml "$hosts_file" ".hosts.\"$shortname\"")
  fi
  
  if [ -n "$info" ]; then
    echo "$info" | while IFS= read -r line; do echo "  $line"; done
  else
    echo -e "${YELLOW}  No specific configuration found${NC}"
    echo "  Will use defaults:"
    parse_yaml "$hosts_file" ".defaults" | sed 's/^/    /'
  fi
}

# Список всех конфигураций
list_configs() {
  local envs_dir="$1"
  
  echo -e "${BLUE}=== Available Configurations ===${NC}"
  
  for env_dir in "$envs_dir"/{production,staging,development,clients}; do
    if [ -d "$env_dir" ]; then
      local env_name
      env_name=$(basename "$env_dir")
      echo -e "\n${GREEN}$env_name:${NC}"
      
      for config in "$env_dir"/*.env; do
        if [ -f "$config" ]; then
          local config_name
          config_name=$(basename "$config")
          echo "  - $config_name"
          
          # Показать первые несколько строк с метаданными
          grep -E "^# (Location|Role):" "$config" 2>/dev/null | sed 's/^#/   /' || true
        fi
      done
    fi
  done
}

# Копировать конфигурацию
copy_config() {
  local config_path="$1"
  local output_file="$2"
  local envs_dir="$3"
  
  # Полный путь к конфигурации
  local full_path="$envs_dir/$config_path"
  
  if [ ! -f "$full_path" ]; then
    echo -e "${RED}✗${NC} Config file not found: $full_path"
    return 1
  fi
  
  # Копируем с сохранением прав
  cp "$full_path" "$output_file"
  chmod 600 "$output_file"
  
  echo -e "${GREEN}✓${NC} Loaded configuration: $config_path"
  echo -e "${GREEN}✓${NC} Written to: $output_file"
  
  # Показать summary
  echo -e "\n${BLUE}Configuration summary:${NC}"
  grep -E "^(NODE_|SSH_PORT|WG_)" "$output_file" | head -10 | sed 's/=.*/=***/' | sed 's/^/  /'
  
  return 0
}

# Main
main() {
  local hostname=""
  local force_env=""
  local force_config=""
  local output_file=".env"
  local dry_run=false
  local action="load"
  
  # Парсинг аргументов
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -H|--hostname)
        hostname="$2"
        shift 2
        ;;
      -e|--env)
        force_env="$2"
        shift 2
        ;;
      -c|--config)
        force_config="$2"
        shift 2
        ;;
      -l|--list)
        action="list"
        shift
        ;;
      -s|--show)
        action="show"
        shift
        ;;
      -o|--output)
        output_file="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
  
  # Проверка наличия hosts.yml
  if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}✗${NC} hosts.yml not found at: $HOSTS_FILE"
    echo "Please create it or set HOSTS_FILE environment variable"
    exit 1
  fi
  
  # Выполнение действия
  case "$action" in
    list)
      list_configs "$ENVS_DIR"
      ;;
      
    show)
      [ -z "$hostname" ] && hostname=$(get_hostname)
      show_host_info "$hostname" "$HOSTS_FILE"
      ;;
      
    load)
      # Определение конфигурации
      if [ -n "$force_config" ]; then
        config_path="$force_config"
        echo -e "${BLUE}Using forced config: $config_path${NC}"
      else
        [ -z "$hostname" ] && hostname=$(get_hostname)
        echo -e "${BLUE}Detected hostname: $hostname${NC}"
        
        config_path=$(find_host_config "$hostname" "$HOSTS_FILE")
        if [ -z "$config_path" ]; then
          echo -e "${RED}✗${NC} No configuration found for host: $hostname"
          exit 1
        fi
      fi
      
      # Применение окружения если указано
      if [ -n "$force_env" ]; then
        # Ищем первый подходящий конфиг в указанном окружении
        if [ -d "$ENVS_DIR/$force_env" ]; then
          config_path="$force_env/$(find "$ENVS_DIR/$force_env" -name "*.env" -type f 2>/dev/null | head -1 | xargs basename)"
          echo -e "${BLUE}Forcing environment: $force_env${NC}"
        else
          echo -e "${RED}✗${NC} Environment not found: $force_env"
          exit 1
        fi
      fi
      
      # Выполнение или dry-run
      if $dry_run; then
        echo -e "\n${YELLOW}DRY RUN - Would perform:${NC}"
        echo "  Copy: $ENVS_DIR/$config_path"
        echo "  To:   $output_file"
        show_host_info "$hostname" "$HOSTS_FILE"
      else
        copy_config "$config_path" "$output_file" "$ENVS_DIR"
      fi
      ;;
  esac
}

# Запуск только если не sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
