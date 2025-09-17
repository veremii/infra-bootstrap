#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# Project Validation Script
# ==============================================
# Проверяет готовность проекта к использованию
# ==============================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo -e "${BLUE}=== Infrastructure Bootstrap Validation ===${NC}"
echo ""

# Функция проверки
check() {
  local name="$1"
  local condition="$2"
  local level="${3:-error}"  # error или warning
  
  printf "%-50s" "$name"
  
  if eval "$condition" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
  else
    if [ "$level" = "warning" ]; then
      echo -e "${YELLOW}⚠${NC}"
      WARNINGS=$((WARNINGS + 1))
    else
      echo -e "${RED}✗${NC}"
      ERRORS=$((ERRORS + 1))
    fi
  fi
}

# Проверка структуры
echo -e "${BLUE}Project Structure:${NC}"
check "Makefile exists" "[ -f Makefile ]"
check "bootstrap.sh exists and executable" "[ -x bootstrap.sh ]"
check ".env.example exists" "[ -f .env.example ]"
check ".gitignore exists" "[ -f .gitignore ]"
check "LICENSE exists" "[ -f LICENSE ]"
check "README.md exists" "[ -f README.md ]"
check "CHANGELOG.md exists" "[ -f CHANGELOG.md ]"
check "QUICKSTART.md exists" "[ -f QUICKSTART.md ]"
echo ""

# Проверка скриптов
echo -e "${BLUE}Core Scripts:${NC}"
for script in quickstart.sh env-selector.sh bundle-create.sh healthcheck.sh; do
  check "scripts/$script executable" "[ -x scripts/$script ]"
done
echo ""

# Проверка stack скриптов
echo -e "${BLUE}Stack Scripts:${NC}"
for script in stack-traefik.sh stack-obs.sh stack-portainer.sh; do
  check "scripts/$script exists" "[ -f scripts/$script ]"
done
echo ""

# Проверка утилит
echo -e "${BLUE}Utility Scripts:${NC}"
for script in wg-new-client.sh fail2ban-ssh.sh net-bootstrap.sh; do
  check "scripts/$script exists" "[ -f scripts/$script ]"
done
echo ""

# Проверка окружений
echo -e "${BLUE}Environment Configuration:${NC}"
check "envs/hosts.yml exists" "[ -f envs/hosts.yml ]"
check "envs/README.md exists" "[ -f envs/README.md ]"
check "Production example exists" "[ -f envs/production/example.env ]"
check "Production configs" "ls envs/production/*.env 2>/dev/null | grep -q '.env'" "warning"
check "Staging configs" "ls envs/staging/*.env 2>/dev/null | grep -q '.env'" "warning"
echo ""

# Проверка CI/CD
echo -e "${BLUE}CI/CD:${NC}"
check ".github/workflows/ci.yml exists" "[ -f .github/workflows/ci.yml ]"
check ".github/workflows/deploy.yml.example exists" "[ -f .github/workflows/deploy.yml.example ]"
check ".pre-commit-config.yaml exists" "[ -f .pre-commit-config.yaml ]"
echo ""

# Проверка примеров
echo -e "${BLUE}Examples:${NC}"
check "App deployment example" "[ -d examples/app-deployment ]"
check "Stack.yml example" "[ -f examples/app-deployment/stack.yml ]"
check "Deploy.sh example" "[ -x examples/app-deployment/deploy.sh ]"
echo ""

# Проверка синтаксиса скриптов
echo -e "${BLUE}Shell Script Syntax:${NC}"
for script in scripts/*.sh bootstrap.sh test-local.sh; do
  if [ -f "$script" ]; then
    name=$(basename "$script")
    check "$name syntax" "bash -n $script"
  fi
done
echo ""

# Проверка YAML файлов
echo -e "${BLUE}YAML Syntax:${NC}"
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
  for yaml in envs/hosts.yml .github/workflows/*.yml .pre-commit-config.yaml; do
    if [ -f "$yaml" ]; then
      name=$(basename "$yaml")
      check "$name syntax" "python3 -c 'import yaml; yaml.safe_load(open(\"$yaml\"))'"
    fi
  done
elif command -v yq >/dev/null 2>&1; then
  for yaml in envs/hosts.yml .github/workflows/*.yml .pre-commit-config.yaml; do
    if [ -f "$yaml" ]; then
      name=$(basename "$yaml")
      check "$name syntax" "yq eval '.' $yaml >/dev/null"
    fi
  done
else
  echo -e "${YELLOW}Skipping (no YAML parser found)${NC}"
fi
echo ""

# Проверка Makefile targets
echo -e "${BLUE}Makefile Targets:${NC}"
check "help target" "make help >/dev/null"
check "check-env target" "grep -q '^check-env:' Makefile"
check "bundle-create target" "grep -q '^bundle-create:' Makefile"
check "healthcheck target" "grep -q '^healthcheck:' Makefile"
echo ""

# Итоги
echo -e "${BLUE}=== Validation Summary ===${NC}"
echo -e "Errors:   ${ERRORS}"
echo -e "Warnings: ${WARNINGS}"
echo ""

if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}✓ Project is ready for use!${NC}"
  echo ""
  echo "Next steps:"
  echo "1. Configure your environments in envs/"
  echo "2. Update envs/hosts.yml with your infrastructure"
  echo "3. Run: make bundle-create HOST=your-server"
  echo "4. Deploy to your servers"
  echo ""
  echo "Quick test: ./test-local.sh"
  exit 0
else
  echo -e "${RED}✗ Project has errors that need to be fixed${NC}"
  exit 1
fi
