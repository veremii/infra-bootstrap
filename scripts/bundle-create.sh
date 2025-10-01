#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
  cat <<'HLP'
Usage: bundle-create.sh [OPTIONS]

Create a deployment bundle for specific host or environment.

Options:
  -H, --hostname HOST   Create bundle for specific hostname
  -e, --env ENV        Create bundle for all hosts in environment
  -o, --output FILE    Output file (default: bundle-HOST.tar.gz)
  -i, --include FILES  Additional files to include (comma-separated)
  --minimal            Create minimal bundle (no examples/docs)
  -h, --help           Show this help

Examples:
  # Bundle for specific host
  ./scripts/bundle-create.sh -H prod-edge-1.example.com

  # Bundle for all staging hosts
  ./scripts/bundle-create.sh -e staging -o staging-bundle.tar.gz

  # Minimal bundle with custom files
  ./scripts/bundle-create.sh -H prod-app-1 --minimal -i "custom/,special.conf"

The bundle will include:
- Makefile and core scripts
- Specific .env for the host (auto-selected)
- envs/ directory with all configs
- Optional: documentation and examples
HLP
}

# Параметры по умолчанию
HOSTNAME=""
ENVIRONMENT=""
OUTPUT=""
INCLUDE_FILES=""
MINIMAL=false

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    -e|--env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT="$2"
      shift 2
      ;;
    -i|--include)
      INCLUDE_FILES="$2"
      shift 2
      ;;
    --minimal)
      MINIMAL=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Проверка параметров
if [ -z "$HOSTNAME" ] && [ -z "$ENVIRONMENT" ]; then
  echo -e "${RED}Error: Specify either --hostname or --env${NC}"
  exit 1
fi

# Определяем имя выходного файла
if [ -z "$OUTPUT" ]; then
  if [ -n "$HOSTNAME" ]; then
    OUTPUT="bundle-${HOSTNAME//[^a-zA-Z0-9-]/_}.tar.gz"
  else
    OUTPUT="bundle-${ENVIRONMENT}.tar.gz"
  fi
fi

# Создаём временную директорию
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo -e "${BLUE}Creating deployment bundle...${NC}"

# Базовая структура
BUNDLE_DIR="$TMPDIR/infra-bootstrap"
mkdir -p "$BUNDLE_DIR"

# Копируем основные файлы
echo "Adding core files..."
cp Makefile "$BUNDLE_DIR/"
cp -r scripts "$BUNDLE_DIR/"
[ -f .env.example ] && cp .env.example "$BUNDLE_DIR/"

# Копируем envs если есть
if [ -d envs ]; then
  echo "Adding environment configurations..."
  cp -r envs "$BUNDLE_DIR/"
fi

# Генерируем .env для конкретного хоста
if [ -n "$HOSTNAME" ]; then
  echo -e "${BLUE}Selecting configuration for: $HOSTNAME${NC}"
  
  # Используем env-selector для выбора конфигурации
  if [ -x scripts/env-selector.sh ]; then
    ./scripts/env-selector.sh -H "$HOSTNAME" -o "$BUNDLE_DIR/.env" || {
      echo -e "${YELLOW}Warning: Could not auto-select config for $HOSTNAME${NC}"
    }
  fi
fi

# Для окружения копируем все конфиги
if [ -n "$ENVIRONMENT" ]; then
  echo -e "${BLUE}Including all configs for environment: $ENVIRONMENT${NC}"
  
  if [ -d "envs/$ENVIRONMENT" ]; then
    # Создаём README с инструкциями
    cat > "$BUNDLE_DIR/DEPLOY.md" <<EOF
# Deployment Bundle for $ENVIRONMENT

This bundle contains configurations for all hosts in $ENVIRONMENT environment.

## Quick Start

1. Extract on target host:
   \`\`\`bash
   tar -xzf $(basename "$OUTPUT")
   cd infra-bootstrap
   \`\`\`

2. Auto-select configuration:
   \`\`\`bash
   make env-select
   # or manually:
   ./scripts/env-selector.sh
   \`\`\`

3. Deploy:
   \`\`\`bash
   make check-env
   sudo make init users ssh ufw docker
   \`\`\`

## Available Configurations

EOF
    find "envs/$ENVIRONMENT" -name "*.env" -type f 2>/dev/null | while read -r config; do
      echo "- $(basename "$config")" >> "$BUNDLE_DIR/DEPLOY.md"
    done
  fi
fi

# Добавляем дополнительные файлы
if [ -n "$INCLUDE_FILES" ]; then
  echo "Adding custom files..."
  IFS=',' read -ra FILES <<< "$INCLUDE_FILES"
  for file in "${FILES[@]}"; do
    if [ -e "$file" ]; then
      cp -r "$file" "$BUNDLE_DIR/"
      echo "  + $file"
    else
      echo -e "${YELLOW}  ! $file not found${NC}"
    fi
  done
fi

# Минимальный режим - удаляем лишнее
if [ "$MINIMAL" = "true" ]; then
  echo "Creating minimal bundle..."
  rm -f "$BUNDLE_DIR"/*.md
  rm -rf "$BUNDLE_DIR"/.github
  rm -f "$BUNDLE_DIR"/envs/*.md
  
  # Оставляем только нужные скрипты
  find "$BUNDLE_DIR/scripts" -type f -name "*.sh" | while read -r script; do
    case "$(basename "$script")" in
      lib.sh|env-selector.sh|quickstart.sh|healthcheck.sh|wg-new-client.sh)
        # Оставляем
        ;;
      *)
        rm -f "$script"
        ;;
    esac
  done
fi

# Создаём архив
echo -e "${BLUE}Creating archive: $OUTPUT${NC}"
cd "$TMPDIR"
tar -czf "$OUTPUT" infra-bootstrap/
mv "$OUTPUT" "$OLDPWD/"
cd "$OLDPWD"

# Статистика
SIZE=$(du -h "$OUTPUT" | cut -f1)
FILE_COUNT=$(tar -tzf "$OUTPUT" | wc -l)

echo -e "${GREEN}✓ Bundle created successfully${NC}"
echo "  File: $OUTPUT"
echo "  Size: $SIZE"
echo "  Files: $FILE_COUNT"

# Инструкции
echo ""
echo -e "${BLUE}Deployment instructions:${NC}"
echo "1. Copy to target host:"
echo "   scp $OUTPUT user@host:~/"
echo ""
echo "2. On target host:"
echo "   tar -xzf $OUTPUT"
echo "   cd infra-bootstrap"
echo "   make quickstart  # or make env-select"
echo ""
echo "3. Clean up after deployment:"
echo "   cd .. && rm -rf infra-bootstrap $OUTPUT"


