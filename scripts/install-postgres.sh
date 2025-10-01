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

# Переменные окружения
POSTGRES_VERSION=${POSTGRES_VERSION:-16}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-changeme}
POSTGRES_DB=${POSTGRES_DB:-appdb}
POSTGRES_USER=${POSTGRES_USER:-appuser}
POSTGRES_PORT=${POSTGRES_PORT:-5432}

echo -e "${BLUE}=== PostgreSQL Installation (Outside Swarm) ===${NC}"
echo ""
echo "Version: PostgreSQL $POSTGRES_VERSION"
echo "Database: $POSTGRES_DB"
echo "User: $POSTGRES_USER"
echo "Port: $POSTGRES_PORT"
echo ""

# 1. Установка PostgreSQL
echo -e "${BLUE}1/5 Installing PostgreSQL $POSTGRES_VERSION...${NC}"

# Добавить репозиторий PostgreSQL
if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then
  echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
fi

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-${POSTGRES_VERSION} postgresql-contrib-${POSTGRES_VERSION}

echo -e "${GREEN}✓${NC} PostgreSQL installed"
echo ""

# 2. Настройка для удалённого доступа через WireGuard
echo -e "${BLUE}2/5 Configuring remote access...${NC}"

# Разрешить подключения с WireGuard сети (10.188.0.0/24)
PGCONF="/etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf"
PGHBA="/etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf"

# Слушать на всех интерфейсах (или только WireGuard)
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PGCONF"
sed -i "s/port = 5432/port = ${POSTGRES_PORT}/" "$PGCONF"

# Разрешить подключения из WireGuard сети
if ! grep -q "10.188.0.0/24" "$PGHBA"; then
  echo "# Allow connections from WireGuard network" >> "$PGHBA"
  echo "host    all             all             10.188.0.0/24           scram-sha-256" >> "$PGHBA"
fi

echo -e "${GREEN}✓${NC} Remote access configured for WireGuard network (10.188.0.0/24)"
echo ""

# 3. Создание пользователя и базы
echo -e "${BLUE}3/5 Creating database and user...${NC}"

systemctl restart postgresql

# Ждём запуска
sleep 2

# Создать пользователя
sudo -u postgres psql -c "SELECT 1 FROM pg_user WHERE usename = '$POSTGRES_USER'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';"

# Создать базу
sudo -u postgres psql -c "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;"

# Выдать права
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;"

echo -e "${GREEN}✓${NC} Database '$POSTGRES_DB' and user '$POSTGRES_USER' created"
echo ""

# 4. Настройка автозапуска
echo -e "${BLUE}4/5 Enabling PostgreSQL service...${NC}"
systemctl enable postgresql
systemctl restart postgresql

echo -e "${GREEN}✓${NC} PostgreSQL service enabled and started"
echo ""

# 5. Проверка
echo -e "${BLUE}5/5 Testing connection...${NC}"

if sudo -u postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT version();" >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} PostgreSQL is working!"
else
  echo -e "${RED}✗${NC} Connection test failed"
  exit 1
fi

echo ""

# Вывод информации для подключения
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ PostgreSQL successfully installed                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Connection details:${NC}"
echo -e "  Host:     ${GREEN}10.188.0.21${NC} (DB node WireGuard IP)"
echo -e "  Port:     ${GREEN}${POSTGRES_PORT}${NC}"
echo -e "  Database: ${GREEN}${POSTGRES_DB}${NC}"
echo -e "  User:     ${GREEN}${POSTGRES_USER}${NC}"
echo -e "  Password: ${YELLOW}${POSTGRES_PASSWORD}${NC}"
echo ""
echo -e "${BLUE}Connection string:${NC}"
echo -e "  ${GREEN}postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@10.188.0.21:${POSTGRES_PORT}/${POSTGRES_DB}${NC}"
echo ""
echo -e "${YELLOW}⚠  Save credentials to .env or secrets manager!${NC}"
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo -e "  sudo -u postgres psql -U $POSTGRES_USER -d $POSTGRES_DB"
echo -e "  systemctl status postgresql"
echo -e "  journalctl -u postgresql -f"

