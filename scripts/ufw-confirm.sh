#!/usr/bin/env bash
set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}✗${NC} This script must be run as root"
  exit 1
fi

echo -e "${BLUE}=== UFW Confirm Changes ===${NC}"
echo ""

# Найти последний reset
if [ ! -f /tmp/ufw-latest-reset ]; then
  echo -e "${RED}✗${NC} No pending UFW changes found"
  echo "   Run 'sudo make ufw-reset-safe' first"
  exit 1
fi

TIMESTAMP=$(cat /tmp/ufw-latest-reset)
INFO_FILE="/tmp/ufw-confirm-info-$TIMESTAMP"

if [ ! -f "$INFO_FILE" ]; then
  echo -e "${RED}✗${NC} Cannot find reset info for timestamp: $TIMESTAMP"
  exit 1
fi

# Загрузить информацию
source "$INFO_FILE"

echo -e "${BLUE}Confirming changes from: $(date -d "@${TIMESTAMP:0:8}" 2>/dev/null || echo "$TIMESTAMP")${NC}"
echo ""

# 1. Создать флаг подтверждения
echo -e "${BLUE}1/3 Creating confirmation flag...${NC}"
touch "$CONFIRM_FLAG"
echo -e "${GREEN}✓${NC} Flag created: $CONFIRM_FLAG"
echo ""

# 2. Отменить at-job отката
echo -e "${BLUE}2/3 Canceling auto-rollback job...${NC}"
if [ -n "${AT_JOB:-}" ]; then
  if atq | grep -q "^$AT_JOB"; then
    atrm "$AT_JOB" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Rollback job #$AT_JOB canceled"
  else
    echo -e "${YELLOW}⚠${NC}  Job #$AT_JOB not found (may have already executed)"
  fi
else
  echo -e "${YELLOW}⚠${NC}  No job ID found"
fi
echo ""

# 3. Очистка временных файлов
echo -e "${BLUE}3/3 Cleaning up...${NC}"
rm -f "$INFO_FILE"
rm -f "/tmp/ufw-rollback-job-$TIMESTAMP"
rm -f /tmp/ufw-latest-reset
rm -f "$ROLLBACK_SCRIPT"
echo -e "${GREEN}✓${NC} Cleanup complete"
echo ""

# Сохранить бэкап на всякий случай
if [ -f "$BACKUP_FILE" ]; then
  echo -e "${BLUE}Backup preserved: $BACKUP_FILE${NC}"
  echo "  (can be deleted manually if not needed)"
  echo ""
fi

# Итоговый статус
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ UFW changes confirmed and saved                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Current UFW status:${NC}"
ufw status numbered
echo ""
echo -e "${GREEN}All done!${NC} New firewall rules are now permanent."

