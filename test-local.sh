#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# Local Testing Script
# ==============================================
# Тестирует основные функции локально
# без реального развёртывания
# ==============================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Infrastructure Bootstrap Local Test ===${NC}"
echo ""

# Проверка структуры
echo -e "${BLUE}Checking project structure...${NC}"
for file in Makefile scripts/quickstart.sh scripts/env-selector.sh envs/hosts.yml; do
  if [ -e "$file" ]; then
    echo -e "  ${GREEN}✓${NC} $file"
  else
    echo -e "  ${RED}✗${NC} $file missing"
  fi
done

# Проверка скриптов на синтаксис
echo -e "\n${BLUE}Checking shell scripts syntax...${NC}"
for script in scripts/*.sh; do
  if bash -n "$script" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $(basename "$script")"
  else
    echo -e "  ${RED}✗${NC} $(basename "$script")"
    bash -n "$script"
  fi
done

# Тест env-selector
echo -e "\n${BLUE}Testing env-selector...${NC}"
if [ -x scripts/env-selector.sh ]; then
  echo "Available configurations:"
  ./scripts/env-selector.sh --list || true
  echo ""
  echo "Testing hostname detection:"
  ./scripts/env-selector.sh --show || true
fi

# Тест bundle-create
echo -e "\n${BLUE}Testing bundle creation...${NC}"
if [ -x scripts/bundle-create.sh ]; then
  # Создаём тестовый bundle
  echo "Creating test bundle for development..."
  ./scripts/bundle-create.sh -H dev-local -o test-bundle.tar.gz || {
    echo -e "${YELLOW}Bundle creation failed (might be normal if no matching config)${NC}"
  }
  
  if [ -f test-bundle.tar.gz ]; then
    echo -e "${GREEN}✓ Bundle created${NC}"
    echo "Contents:"
    tar -tzf test-bundle.tar.gz | head -10
    rm -f test-bundle.tar.gz
  fi
fi

# Проверка Makefile targets
echo -e "\n${BLUE}Testing Makefile targets...${NC}"
echo "Checking env validation:"
if [ -f .env.example ]; then
  cp .env.example .env.test
  # Добавляем тестовые значения (совместимо с macOS и Linux)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/YOUR_PUBLIC_IP/1.2.3.4/' .env.test
    sed -i '' 's/admin@example.com/test@example.com/' .env.test
  else
    sed -i 's/YOUR_PUBLIC_IP/1.2.3.4/' .env.test
    sed -i 's/admin@example.com/test@example.com/' .env.test
  fi
  mv .env .env.backup 2>/dev/null || true
  mv .env.test .env
  
  make check-env && echo -e "${GREEN}✓ Env check passed${NC}" || echo -e "${RED}✗ Env check failed${NC}"
  
  mv .env.backup .env 2>/dev/null || true
  rm -f .env.test
fi

# Проверка healthcheck
echo -e "\n${BLUE}Testing healthcheck script...${NC}"
if [ -x scripts/healthcheck.sh ]; then
  # Запускаем в dry-run режиме (не все проверки пройдут)
  ./scripts/healthcheck.sh || true
fi

# Итоги
echo -e "\n${BLUE}=== Test Summary ===${NC}"
echo "This was a local syntax and structure test."
echo "For full testing, deploy to a test VM."
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Create your environment configs in envs/"
echo "2. Update envs/hosts.yml with your infrastructure"
echo "3. Test on a VM: make bundle-create HOST=test-vm"
echo "4. Deploy: scp bundle-*.tar.gz user@vm:~/"
