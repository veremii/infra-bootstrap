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

# Проверка необходимых переменных
: "${SSH_PORT:?SSH_PORT not set}"
: "${WG_PORT:?WG_PORT not set}"
: "${EDGE_OPEN_HTTP:=false}"

# Проверка наличия at
if ! command -v at >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠${NC}  Installing 'at' package..."
  apt-get update -qq && apt-get install -y at >/dev/null
  systemctl enable --now atd
fi

# Создаём директорию для бэкапов
BACKUP_DIR="/var/backups/ufw"
mkdir -p "$BACKUP_DIR"

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/ufw-backup-$TIMESTAMP"
ROLLBACK_SCRIPT="/tmp/ufw-rollback.sh"
CONFIRM_FLAG="/tmp/ufw-confirm-$TIMESTAMP"

echo -e "${BLUE}=== UFW Safe Reset ===${NC}"
echo ""

# 1. Бэкап текущих правил
echo -e "${BLUE}1/5 Creating backup...${NC}"
{
  echo "# UFW backup created at $(date)"
  echo "# Status before reset:"
  ufw status numbered
  echo ""
  echo "# Raw rules:"
  iptables-save
} > "$BACKUP_FILE"

echo -e "${GREEN}✓${NC} Backup saved: $BACKUP_FILE"
echo ""

# 2. Создать скрипт отката
echo -e "${BLUE}2/5 Creating rollback script...${NC}"
cat > "$ROLLBACK_SCRIPT" <<'ROLLBACK'
#!/bin/bash
set -e

BACKUP_FILE="BACKUP_FILE_PLACEHOLDER"
CONFIRM_FLAG="CONFIRM_FLAG_PLACEHOLDER"

# Проверить флаг подтверждения
if [ -f "$CONFIRM_FLAG" ]; then
  echo "✓ Changes were confirmed, skipping rollback"
  rm -f "$CONFIRM_FLAG"
  exit 0
fi

echo "⚠️  No confirmation received, rolling back UFW rules..."

# Отключить UFW
ufw --force disable

# Восстановить из бэкапа (простой способ)
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Извлечь и восстановить правила из бэкапа
grep "^ufw allow" "$BACKUP_FILE" 2>/dev/null | while read -r cmd; do
  eval "$cmd" 2>/dev/null || true
done

# Включить UFW
ufw --force enable

echo "✓ UFW rules rolled back from backup"
logger "UFW auto-rollback executed from $BACKUP_FILE"
ROLLBACK

# Подставить реальные значения
sed -i "s|BACKUP_FILE_PLACEHOLDER|$BACKUP_FILE|g" "$ROLLBACK_SCRIPT"
sed -i "s|CONFIRM_FLAG_PLACEHOLDER|$CONFIRM_FLAG|g" "$ROLLBACK_SCRIPT"
chmod +x "$ROLLBACK_SCRIPT"

echo -e "${GREEN}✓${NC} Rollback script ready: $ROLLBACK_SCRIPT"
echo ""

# 3. Запланировать откат через 2 минуты
echo -e "${BLUE}3/5 Scheduling auto-rollback in 2 minutes...${NC}"
ROLLBACK_TIME=$(date -d '+2 minutes' '+%H:%M %Y-%m-%d')
echo "$ROLLBACK_SCRIPT" | at "$ROLLBACK_TIME" 2>/dev/null || {
  echo -e "${RED}✗${NC} Failed to schedule rollback"
  exit 1
}

AT_JOB=$(atq | tail -1 | awk '{print $1}')
echo -e "${GREEN}✓${NC} Rollback scheduled (job #$AT_JOB at $ROLLBACK_TIME)"
echo "$AT_JOB" > "/tmp/ufw-rollback-job-$TIMESTAMP"
echo ""

# 4. Применить новые правила
echo -e "${BLUE}4/5 Applying new UFW rules...${NC}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

echo "  Adding SSH port: $SSH_PORT/tcp"
ufw allow "$SSH_PORT/tcp"

echo "  Adding WireGuard port: $WG_PORT/udp"
ufw allow "$WG_PORT/udp"

if [ "$EDGE_OPEN_HTTP" = "true" ]; then
  echo "  Adding HTTP/HTTPS: 80,443/tcp"
  ufw allow 80/tcp
  ufw allow 443/tcp
fi

ufw --force enable

echo -e "${GREEN}✓${NC} New rules applied"
echo ""

# 5. Показать итоговые правила
echo -e "${BLUE}5/5 Current UFW status:${NC}"
ufw status numbered
echo ""

# Инструкции
echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│  ⚠️   IMPORTANT: Verify SSH access in a NEW session!       │${NC}"
echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo ""
echo -e "  1. ${YELLOW}Open a NEW SSH connection${NC} to verify access:"
echo -e "     ${GREEN}ssh -p $SSH_PORT user@$(hostname -I | awk '{print $1}')${NC}"
echo ""
echo -e "  2. If connection works, ${GREEN}confirm changes${NC}:"
echo -e "     ${GREEN}sudo make ufw-confirm${NC}"
echo ""
echo -e "  3. If connection ${RED}FAILS${NC}:"
echo -e "     ${YELLOW}Wait 2 minutes → rules will auto-rollback${NC}"
echo ""
echo -e "${YELLOW}⏱  Auto-rollback in: 2 minutes (at $ROLLBACK_TIME)${NC}"
echo -e "${YELLOW}📋 Rollback job: #$AT_JOB${NC}"
echo ""

# Сохранить информацию для подтверждения
cat > "/tmp/ufw-confirm-info-$TIMESTAMP" <<INFO
TIMESTAMP=$TIMESTAMP
BACKUP_FILE=$BACKUP_FILE
ROLLBACK_SCRIPT=$ROLLBACK_SCRIPT
CONFIRM_FLAG=$CONFIRM_FLAG
AT_JOB=$AT_JOB
INFO

echo "$TIMESTAMP" > /tmp/ufw-latest-reset

