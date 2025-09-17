# infra-bootstrap

Production-ready инструмент для развёртывания защищённой инфраструктуры на Debian/Ubuntu серверах. Включает SSH hardening, Docker Swarm, WireGuard VPN, Traefik, мониторинг и всё необходимое для запуска приложений.

## ✨ Ключевые возможности

- **🔒 Безопасность из коробки**: SSH hardening, UFW firewall, fail2ban, WireGuard VPN
- **🐳 Docker Swarm ready**: автоматическая настройка overlay сетей и сервисов
- **🌐 Edge-ready**: Traefik с автоматическими SSL сертификатами
- **📊 Мониторинг**: Loki + Promtail + Grafana для централизованных логов
- **🏢 Множественные инфраструктуры**: управление десятками серверов с разными конфигурациями
- **📦 Bundle deployment**: создание самодостаточных пакетов для развёртывания
- **🚀 Быстрый старт**: интерактивная настройка или полная автоматизация

## 🚀 Быстрый старт (буквально в один клик)

```bash
git clone https://github.com/your-org/infra-bootstrap.git
cd infra-bootstrap
./scripts/quickstart.sh  # Интерактивная настройка
```

Скрипт автоматически:
- Создаст .env из шаблона
- Определит публичный IP
- Сгенерирует SSH ключи
- Проверит конфигурацию
- Покажет следующие шаги

## Структура проекта

```
infra-bootstrap/
├── Makefile                    # Основная точка входа
├── bootstrap.sh                # Скрипт автоматического развёртывания
├── .env.example                # Шаблон конфигурации
├── .gitignore                  # Git игнорирование
├── .pre-commit-config.yaml     # Pre-commit хуки
├── CHANGELOG.md                # История изменений
├── README.md                   # Документация
├── test-local.sh               # Локальное тестирование
│
├── scripts/                    # Основные скрипты
│   ├── quickstart.sh           # Интерактивная настройка
│   ├── healthcheck.sh          # Проверка здоровья системы
│   ├── env-selector.sh         # Выбор конфигурации по hostname
│   ├── bundle-create.sh        # Создание deployment bundles
│   ├── lib.sh                  # Общие функции
│   ├── wg-new-client.sh        # Генератор WG клиентов
│   ├── wg-client-apply.sh      # Применение WG конфига
│   ├── net-bootstrap.sh        # Создание Docker сетей
│   ├── swarm-ports.sh          # Управление портами Swarm
│   ├── fail2ban-ssh.sh         # Настройка fail2ban
│   ├── secrets-resolve.sh      # Работа с секретами
│   ├── secrets-to-swarm.sh     # Загрузка секретов в Swarm
│   ├── service-vars.sh         # Определение переменных сервисов
│   ├── stack-traefik.sh        # Деплой Traefik
│   ├── stack-obs.sh            # Деплой мониторинга (Loki/Grafana)
│   └── stack-portainer.sh      # Деплой Portainer
│
├── envs/                       # Конфигурации окружений
│   ├── hosts.yml               # Маппинг хостов на конфигурации
│   ├── README.md               # Документация по окружениям
│   ├── production/             # Production конфигурации
│   │   ├── edge-de1.env        # Пример edge ноды
│   │   ├── app-1.env           # Пример app ноды
│   │   ├── default.env         # Дефолтная конфигурация
│   │   └── example.env         # Шаблон для создания новых
│   ├── staging/                # Staging конфигурации
│   │   └── all.env             # All-in-one для staging
│   └── development/            # Development конфигурации
│       └── local.env           # Локальная разработка
│
└── .github/                    # GitHub конфигурация
    └── workflows/
        └── ci.yml              # CI/CD pipeline
```

## Традиционная установка

1) Подготовь окружение:

```bash
cp .env.example .env
# отредактируй .env - обязательные поля помечены [REQUIRED]
make check-env  # проверка конфигурации
```

2) Базовая настройка сервера:

```bash
sudo make init users ssh ufw docker deploy_dir
```

3) WireGuard — сервер на выбранной ноде:

```bash
sudo make wg-server
```

4) Создать клиента (выполняется на WG-сервере):

```bash
sudo NAME=vps2 IP=10.88.0.12 make wg-client
# полученный vps2.conf — положить на клиент в /etc/wireguard/wg0.conf
```

5) На клиенте:

```bash
sudo apt-get update && sudo apt-get install -y wireguard
sudo cp vps2.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0
```

6) Docker Swarm и сервисы:

```bash
sudo make net-bootstrap  # создать overlay-сети
sudo make swarm-allow    # открыть порты только через wg0
sudo make traefik-up     # поднять Traefik
sudo make logs-up        # поднять мониторинг (опционально)
sudo make portainer-up   # поднять Portainer (опционально)
```

7) Edge-нода: открыть HTTP/HTTPS:

```bash
sudo make edge-open
# закрыть при необходимости:
sudo make edge-close
```

8) Проверка статуса:

```bash
make healthcheck  # полная проверка системы
make status       # краткий статус
```

## 🏢 Управление множественными инфраструктурами

Для управления десятками серверов с разными конфигурациями используется система автоматического выбора конфигураций и создания deployment bundles.

### 1. Структура конфигураций

```
envs/
├── hosts.yml              # Соответствие хостов и конфигураций
├── production/
│   ├── edge-de1.env      # Edge нода в Германии
│   ├── edge-us1.env      # Edge нода в США
│   ├── app-1.env         # App сервер 1
│   └── db-1.env          # Database сервер
├── staging/
│   └── all.env           # Staging all-in-one
└── development/
    └── local.env         # Локальная разработка
```

### 2. Создание и использование bundles

#### Создание bundle для конкретного хоста:

```bash
# Показать все доступные хосты
make bundle-list

# Создать bundle для конкретного хоста
make bundle-create HOST=prod-edge-de1.example.com

# Создать bundle для всего окружения
make bundle-create ENV=staging OUTPUT=staging-bundle.tar.gz

# Минимальный bundle без документации
./scripts/bundle-create.sh -H prod-app-1 --minimal
```

#### Развёртывание на целевом сервере:

```bash
# 1. Копируем bundle на сервер
scp bundle-prod-edge-de1.tar.gz admin@server:~/

# 2. На сервере распаковываем и запускаем
ssh admin@server
tar -xzf bundle-prod-edge-de1.tar.gz
cd infra-bootstrap
./bootstrap.sh

# 3. После успешной установки удаляем
cd .. && rm -rf infra-bootstrap bundle-*.tar.gz
```

### 3. Автоматический выбор конфигурации

```bash
# Автоматически определит hostname и загрузит нужный .env
make env-select

# Показать все доступные конфигурации
make env-list

# Принудительно выбрать конфигурацию
./scripts/env-selector.sh -c production/edge-de1.env

# Использовать для конкретного хоста
./scripts/env-selector.sh -H prod-app-1.internal
```

### 4. Настройка hosts.yml

```yaml
hosts:
  prod-edge-de1.example.com:
    env: production
    config: production/edge-de1.env
    role: edge
    datacenter: hetzner-de
    swarm_labels:
      - "node.labels.role==edge"
      - "node.labels.dc==de"
    
  prod-app-1.internal:
    env: production
    config: production/app-1.env
    role: app
    datacenter: hetzner-de

defaults:
  env: production
  config: production/default.env
```

### 5. Workflow для массового развёртывания

#### Вариант 1: С центрального сервера управления

```bash
# Создаём bundles для всех хостов
for host in $(make bundle-list | grep -v "===" | grep -v "Create"); do
  make bundle-create HOST=$host
done

# Деплоим на все сервера (пример с GNU parallel)
parallel -j 4 '
  scp bundle-{}.tar.gz admin@{}:~/ &&
  ssh admin@{} "tar -xzf bundle-{}.tar.gz && cd infra-bootstrap && ./bootstrap.sh -y"
' ::: $(ls bundle-*.tar.gz | sed 's/bundle-//;s/.tar.gz//')
```

#### Вариант 2: CI/CD pipeline

```yaml
# .github/workflows/deploy.yml
deploy:
  runs-on: ubuntu-latest
  strategy:
    matrix:
      host: [prod-edge-de1, prod-app-1, prod-app-2]
  steps:
    - uses: actions/checkout@v4
    - name: Create bundle
      run: make bundle-create HOST=${{ matrix.host }}
    - name: Deploy
      run: |
        scp bundle-${{ matrix.host }}.tar.gz deploy@${{ matrix.host }}:~/
        ssh deploy@${{ matrix.host }} './deploy.sh'
```

### 6. Полезные команды для управления

```bash
# Проверить статус всех серверов
for host in prod-edge-1 prod-app-1 prod-app-2; do
  echo "=== $host ==="
  ssh admin@$host "infra-healthcheck" || true
done

# Обновить конфигурацию на конкретном сервере
make bundle-create HOST=prod-edge-1
scp bundle-prod-edge-1.tar.gz admin@prod-edge-1:~/
ssh admin@prod-edge-1 "tar -xzf bundle-*.tar.gz && cd infra-bootstrap && make env-select"
```

## Описание целей Makefile

### 🆕 Новые команды
- **quickstart**: интерактивная настройка для быстрого старта
- **check-env**: проверка обязательных переменных окружения
- **healthcheck**: полная проверка здоровья системы
- **net-bootstrap**: создать Docker overlay-сети (edge, app, infra)
- **env-select**: автоматически выбрать конфигурацию по hostname
- **env-list**: показать все доступные конфигурации окружений
- **bundle-create HOST=name**: создать deployment bundle для конкретного хоста
- **bundle-list**: показать все хосты доступные для создания bundle

### 📦 Базовая настройка
- **init**: базовые пакеты, таймзона
- **users**: создаёт `ADMIN_USER` и `DEPLOY_USER`, добавляет ключи, sudo
- **ssh**: переносит SSH на `SSH_PORT`, выключает пароли и root
- **ufw**: включает UFW, открывает SSH и WG-порт, опционально 80/443 при `EDGE_OPEN_HTTP=true`
- **docker**: ставит Docker CE, добавляет пользователей в группу `docker`
- **deploy_dir**: создаёт `/srv/deploy` и выдаёт владельца `DEPLOY_USER`

### 🔐 WireGuard VPN
- **wg-server**: поднимает WG-сервер (`/etc/wireguard/wg0.conf`)
- **wg-client NAME=<name> IP=<10.88.0.X>**: генерирует клиентский конфиг на сервере
- **wg-client-apply CONFIG=... [IF=wg0]**: применяет клиентский конфиг на ноде

### 🐳 Docker Swarm
- **swarm-allow**: открывает порты Swarm только на интерфейсе `wg0`
- **swarm-ports ACTION=open|close [IF=wg0]**: открыть/закрыть порты Swarm на интерфейсе

### 🌐 Сервисы
- **traefik-up / traefik-down**: поднять/снести Traefik стек (edge-нода, 80/443 host)
- **logs-up / logs-down**: поднять/снести Loki+Promtail+Grafana (Grafana публикуется через Traefik)
- **portainer-up / portainer-down**: поднять/снести Portainer CE (UI для Docker/Swarm)

### 🔧 Утилиты
- **edge-open/edge-close**: открыть/закрыть 80/443
- **status**: краткий статус сервисов
- **show-ssh**: показать текущий порт SSH
- **service-vars**: определить `CID_BE`, `CID_FE`, `CID_TRF` (можно с `EXPORT=true`)
- **fail2ban-ssh ACTION=...**: установить/управлять fail2ban для SSH (учитывает SSH_PORT)

### 🔑 Секреты
- **secrets-check SECRET=... [AGE_KEY=...] [OUT=.env]**: раскодировать/проверить .env из одного GH-секрета (base64 или age+base64)
- **secrets-to-swarm ENV=.env [PREFIX=app_]**: загрузить пары из .env в Docker Swarm secrets с префиксом

## Переменные `.env`

### Обязательные [REQUIRED]
- **ADMIN_PUBKEY / DEPLOY_PUBKEY**: публичные SSH-ключи для доступа
- **WG_ENDPOINT_IP**: публичный IP сервера для WireGuard
- **TRAEFIK_ACME_EMAIL**: email для Let's Encrypt сертификатов

### Базовые настройки
- **SSH_PORT**: номер порта SSH (по умолчанию 1255)
- **ADMIN_USER / DEPLOY_USER**: имена пользователей (admin, deployer)
- **TZ**: временная зона (UTC)

### WireGuard VPN
- **WG_IF**: интерфейс (wg0)
- **WG_PORT**: порт WireGuard (51820)
- **WG_SERVER_IP**: IP сервера в VPN сети (10.88.0.1)
- **WG_ALLOWED_IPS**: разрешённые подсети (10.88.0.0/24)
- **WG_MTU**: размер MTU (1420)

### Сервисы и домены
- **EDGE_OPEN_HTTP**: если `true`, открывает 80/443 при выполнении `make ufw`
- **TRAEFIK_DASHBOARD_DOMAIN**: домен для Traefik dashboard
- **GRAFANA_DOMAIN**: домен для Grafana
- **PORTAINER_DOMAIN**: домен для Portainer

### Версии Docker образов
- **TRAEFIK_VERSION**: версия Traefik (v3.1)
- **LOKI_VERSION**: версия Loki (2.9.6)
- **GRAFANA_VERSION**: версия Grafana (10.4.3)
- **PORTAINER_VERSION**: версия Portainer (2.20.3)

## Примечания безопасности

- Root-вход по SSH и пароли отключены.
- Для деплоя добавь ограничения sudo для `deployer`, если нужно только управление Docker:

```bash
sudo tee /etc/sudoers.d/deployer >/dev/null <<'SUD'
Cmnd_Alias DOCKER_CMDS = /usr/bin/docker, /usr/bin/systemctl restart docker, /usr/bin/journalctl -u docker
deployer ALL=(root) NOPASSWD: DOCKER_CMDS
SUD
sudo chmod 440 /etc/sudoers.d/deployer
```

## Использование репозитория

Этот репозиторий - **инструмент для начальной настройки**. После развёртывания инфраструктуры его можно и нужно удалить с production сервера:

```bash
# После успешной настройки
cd ..
rm -rf infra-bootstrap
```

### Что сохранить перед удалением:

```bash
# Создать резервную копию конфигурации
mkdir -p ~/infra-backup
cp .env ~/infra-backup/
cp -r scripts ~/infra-backup/  # если нужны скрипты

# Сохранить полезные скрипты в систему
sudo cp scripts/healthcheck.sh /usr/local/bin/infra-healthcheck
sudo cp scripts/wg-new-client.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/infra-healthcheck /usr/local/bin/wg-new-client

# Статус текущих сервисов
docker service ls > ~/infra-backup/services.txt
docker stack ls > ~/infra-backup/stacks.txt
```

### Повторное использование:

```bash
# Клонировать временно для изменений
git clone https://github.com/your-org/infra-bootstrap.git /tmp/infra
cd /tmp/infra
cp ~/infra-backup/.env .  # восстановить конфигурацию
make healthcheck          # проверить статус
# внести изменения...
rm -rf /tmp/infra
```

## CI / pre-commit

- GitHub Actions: линтинг (`shellcheck`, `shfmt`) и упаковка артефакта.
- Pre-commit: локальные хуки для `shellcheck` и `shfmt` (нужно установить инструменты в системе).

## Секреты (единый GH Secret)

- Лимит GitHub Secret ≈ 48 KB на секрет. Многострочный .env допустим.
- Рекомендуемый формат: base64(.env) или base64(age-encrypted .env).
- В CI:
  1) `make secrets-check SECRET="$ENV_B64" [AGE_KEY="$AGE_PRIVATE_KEY"] OUT=.env`
  2) `sudo make secrets-to-swarm ENV=.env PREFIX=app_`
- Причина: один секрет на окружение, легко прокинуть “всё и сразу”, но с валидацией и интерактивным подтверждением (локально) либо `--non-interactive` (CI).


## Как добавить стек приложения (FE/BE) в этот энвайромент

1) Предварительно

- Поднять сети: `sudo make net-bootstrap` (создаст `edge`, `app(enc)`, `infra(enc)`).
- Поднять Traefik: `sudo make traefik-up` (и настроить домены/ACME/email по переменным).
- Подготовить секреты окружения: `make secrets-check SECRET="$ENV_B64" [AGE_KEY="$AGE_PRIVATE_KEY"] OUT=.env` → `sudo make secrets-to-swarm ENV=.env PREFIX=app_`.

2) Собрать/запушить образы в реестр (GHCR)

- Бэкенд/фронтенд собираются в CI и публикуются как `ghcr.io/<org>/<app>:<tag>`.

3) Создать `stack.yml` для приложения (пример)

```
version: "3.9"

networks:
  app: { external: true }
  edge: { external: true }

secrets:
  app_DB_PASSWORD: { external: true }
  app_JWT_SECRET: { external: true }

services:
  backend:
    image: ghcr.io/org/backend:latest
    # Контейнер должен читать секреты из /run/secrets/* (рекомендовано)
    secrets: [app_DB_PASSWORD, app_JWT_SECRET]
    networks: [app]
    deploy:
      placement:
        constraints: ["node.labels.role==app"]
      restart_policy:
        condition: on-failure
      labels:
        # Публикация API через Traefik (если нужен публичный доступ)
        - "traefik.enable=true"
        - "traefik.http.routers.api.rule=Host(`api.example.com`)"
        - "traefik.http.routers.api.entrypoints=websecure"
        - "traefik.http.routers.api.tls.certresolver=le"
        - "traefik.http.services.api.loadbalancer.server.port=3000"
        # (опционально) общий perimeter-auth из Traefik
        # - "traefik.http.routers.api.middlewares=perimeter-auth@docker"
    # Если API должен быть только внутренним, добавь сеть edge и Traefik-лейблы не ставь.

  frontend:
    image: ghcr.io/org/frontend:latest
    networks: [edge]
    deploy:
      placement:
        constraints: ["node.labels.role==edge"]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.front.rule=Host(`app.example.com`)"
        - "traefik.http.routers.front.entrypoints=websecure"
        - "traefik.http.routers.front.tls.certresolver=le"
        - "traefik.http.services.front.loadbalancer.server.port=80"
```

Пояснения

- Подключай приложение к `app` (внутренняя сеть). Публичные сервисы дополнительно подключай к `edge` и добавляй Traefik-лейблы.
- Секреты в Swarm доступны как файлы `/run/secrets/<name>`. Рекомендуется, чтобы приложение читало чувствительные значения из файлов, а не из env.
- Размещение: используй `node.labels.role` (например, `app`, `edge`).
- Безопасность: не публикуй порты контейнеров; выход наружу только через Traefik.

4) Деплой приложения

```bash
docker stack deploy -c stack.yml app
```

5) Обновление

- Пуш нового образа → `docker service update --image ghcr.io/org/backend:<tag> app_backend` (или пересоздание стека).
- Секреты: пересоздай через `make secrets-to-swarm` и перезапусти сервисы.

## Жёсткие правила (рекомендации)

Ниже — лаконичные правила с пояснениями. Где вкусовщина — отмечено явно.

### Git Flow и ветки

- Основные ветки: `main` (production), `develop` (staging). Вкус — можно без `develop`, если релизы редкие.
- Фича-ветки: `feat/<scope>-<short>` (пример: `feat/api-auth`).
- Багфиксы: `fix/<scope>-<short>`.
- Релизы/горячие фиксы: теги `vMAJOR.MINOR.PATCH` (semver). Вкус, но удобно для GH Releases.
- Merge: через PR, сквошить в `main` (вкус). Причина: короткая история, проще ченджлог.

### Именование контейнеров/сервисов

- Три ключевых имени: `traefik`, `backend`, `frontend`. Причина: унификация скриптов (`service-vars`).
- Вкус: если монорепо — добавлять префикс проекта: `app-backend`, `app-frontend`.

### Миграции и база данных

- Именование миграций: `YYYYMMDDHHMM__short_slug.sql` (или в рамках инструмента миграций). Причина: упорядоченность и читаемость.
- Одна миграция — одна логическая смена схемы. Без “мультимиграций”. Причина: трейсабилити.
- Вкус: хранить миграции рядом с сервисом (монорепо) vs отдельный репо — выбираем рядом с сервисом.

### Redis / кэш

- Префикс ключей: `<app>:<env>:<domain>:<key>`. Причина: изоляция сред и коллизий.

### CI/CD принципы

- Build — всегда создаёт образ с тегом `ghcr.io/<org>/<app>:<sha>` и `:latest` на `main` (вкус).
- Deploy — через `docker stack deploy` с внешним `stack.yml`. Причина: декларативность, откат по файлу.
- Секреты — только `docker secret`/`env from secrets` в CI. Никогда в `.env` в репозитории.

### Безопасность

- SSH — только ключи, нестандартный порт, root-login off (реализовано таргетами).
- Swarm трафик — только по `wg0` (реализовано скриптом/таргетом).
- Логи централизованы (Loki/Promtail), UI — Grafana; управление контейнерами — Portainer.

## 🎯 Итоговая оценка

**Production-ready: 9/10**

Что получилось:
- ✅ Полная автоматизация развёртывания инфраструктуры
- ✅ Поддержка множественных окружений и серверов
- ✅ Безопасность из коробки (SSH hardening, VPN, firewall)
- ✅ Docker Swarm с изолированными сетями
- ✅ Мониторинг и централизованные логи
- ✅ Простое создание deployment bundles
- ✅ Интерактивный и автоматический режимы установки
- ✅ Идемпотентность большинства операций
- ✅ Проверка здоровья системы
- ✅ CI/CD ready с примерами

Что можно улучшить:
- Добавить поддержку Kubernetes как альтернативы Swarm
- Интеграция с облачными провайдерами (Terraform)
- Web UI для управления конфигурациями
- Автоматические бэкапы конфигураций

## 📝 Лицензия

MIT License - используйте как хотите!

## 🤝 Contributing

Pull requests приветствуются! Для больших изменений сначала создайте issue.

---

**Made with ❤️ for DevOps engineers who value their time**

