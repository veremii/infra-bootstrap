# 🚀 Quick Start Guide

Этот гайд поможет развернуть инфраструктуру за 5 минут.

## Предварительные требования

- Сервер с Debian 11/12 или Ubuntu 20.04/22.04
- SSH доступ с sudo правами
- Минимум 2GB RAM, 20GB диска

## Вариант 1: Простая установка (один сервер)

```bash
# На вашем компьютере
git clone https://github.com/your-org/infra-bootstrap.git
cd infra-bootstrap

# Создаём bundle
make bundle-create HOST=prod-server-1

# Копируем на сервер
scp bundle-*.tar.gz user@server:~/

# На сервере
ssh user@server
tar -xzf bundle-*.tar.gz
cd infra-bootstrap
./bootstrap.sh
```

## Вариант 2: Множественные серверы

### 1. Настройте конфигурации

```bash
# Скопируйте примеры
cp envs/production/example.env envs/production/my-edge.env
cp envs/production/example.env envs/production/my-app.env

# Отредактируйте файлы
vim envs/production/my-edge.env  # Настройте для edge ноды
vim envs/production/my-app.env   # Настройте для app ноды

# Обновите hosts.yml
vim envs/hosts.yml
```

Пример hosts.yml:
```yaml
hosts:
  my-edge-server.com:
    env: production
    config: production/my-edge.env
    role: edge
    
  my-app-server.internal:
    env: production  
    config: production/my-app.env
    role: app
```

### 2. Создайте и разверните bundles

```bash
# Создаём bundles для всех серверов
make bundle-create HOST=my-edge-server.com
make bundle-create HOST=my-app-server.internal

# Деплоим на каждый сервер
for host in my-edge-server.com my-app-server.internal; do
  scp bundle-$host.tar.gz admin@$host:~/
  ssh admin@$host "tar -xzf bundle-*.tar.gz && cd infra-bootstrap && ./bootstrap.sh -y"
done
```

## Вариант 3: Минимальная конфигурация

Если не нужны множественные окружения:

```bash
# Создаём простой .env
cp .env.example .env
vim .env  # Заполните обязательные поля

# Запускаем quickstart
./scripts/quickstart.sh
```

## Что дальше?

После базовой установки:

1. **Настройте WireGuard VPN** (для связи между серверами):
   ```bash
   # На главном сервере
   sudo make wg-server
   
   # Создайте клиентов для других серверов
   sudo NAME=app-1 IP=10.88.0.11 make wg-client
   ```

2. **Инициализируйте Docker Swarm**:
   ```bash
   # На главной ноде
   docker swarm init --advertise-addr 10.88.0.1
   
   # На других нодах
   docker swarm join --token SWMTKN-1-... 10.88.0.1:2377
   ```

3. **Разверните сервисы**:
   ```bash
   sudo make net-bootstrap   # Создать сети
   sudo make traefik-up      # Reverse proxy
   sudo make logs-up         # Мониторинг
   sudo make portainer-up    # Docker UI
   ```

4. **Проверьте статус**:
   ```bash
   make healthcheck
   ```

## Troubleshooting

### Проблема: "No configuration found for host"
**Решение**: Проверьте hostname и настройте envs/hosts.yml

### Проблема: "SSH connection refused"
**Решение**: После изменения SSH порта подключайтесь через новый порт (по умолчанию 1255)

### Проблема: "Docker swarm init failed"
**Решение**: Убедитесь что WireGuard работает: `wg show`

## Полезные команды

```bash
# Проверить конфигурацию
make check-env

# Показать все доступные хосты
make bundle-list

# Обновить конфигурацию на сервере
make bundle-create HOST=my-server
scp bundle-*.tar.gz admin@my-server:~/
ssh admin@my-server "cd infra-bootstrap && make env-select"

# Мониторинг
docker service ls
docker stack ls
infra-healthcheck
```

## Безопасность

После установки:
- SSH доступен только по ключам на порту 1255
- Root login отключен
- UFW firewall активен
- Fail2ban защищает от брутфорса
- Docker Swarm трафик изолирован через WireGuard

---

Нужна помощь? Создайте issue в репозитории!
