SHELL := /bin/bash

-include .env
export

.PHONY: help check-env init users ssh ufw docker deploy_dir wg-server wg-client swarm-allow edge-open edge-close status show-ssh harden wg-client-apply swarm-ports service-vars gen-readme secrets-check secrets-export secrets-to-swarm traefik-up traefik-down logs-up logs-down portainer-up portainer-down fail2ban-ssh net-bootstrap healthcheck quickstart env-select env-list bundle-create bundle-list

help:
	@echo "Targets:"
	@echo "  make check-env           - проверить обязательные переменные окружения"
	@echo "  sudo make init           - базовая инициализация: пакеты, TZ"
	@echo "  sudo make users          - создать пользователей, ключи, sudo"
	@echo "  sudo make ssh            - перенести порт, запретить root+пароли, рестарт sshd"
	@echo "  sudo make ufw            - включить UFW, базовые allow (SSH, WG)"
	@echo "  sudo make docker         - установить Docker CE, добавить пользователей в группу"
	@echo "  sudo make deploy_dir     - создать /srv/deploy и выдать deployer"
	@echo "  sudo make wg-server      - поднять WG-сервер (wg0.conf) на этой ноде"
	@echo "  sudo make wg-client NAME=myvps IP=10.88.0.12 - сгенерить конфиг клиента на сервере"
	@echo "  sudo make wg-client-apply CONFIG=client.conf [IF=wg0] - применить клиентский конфиг"
	@echo "  sudo make swarm-allow    - открыть Swarm-порты только по wg0"
	@echo "  sudo make swarm-ports ACTION=open|close [IF=wg0] - управлять портами Swarm"
	@echo "  sudo make edge-open      - (edge) открыть 80/443"
	@echo "  sudo make edge-close     - закрыть 80/443"
	@echo "  make service-vars        - вывести/экспортировать CID_BE/CID_FE/CID_TRF"
	@echo "  make gen-readme TYPE=.. [OUT=..] - сгенерировать README-сниппет"
	@echo "  make secrets-check SECRET=... [AGE_KEY=...] [OUT=.env] - проверить/раскодировать секрет"
	@echo "  sudo make secrets-to-swarm ENV=.env [PREFIX=app_] - загрузить пары в docker secrets"
	@echo "  sudo make traefik-up/down - поднять/снести Traefik стек"
	@echo "  sudo make logs-up/down    - поднять/снести Loki+Promtail+Grafana"
	@echo "  sudo make portainer-up/down - поднять/снести Portainer CE"
	@echo "  sudo make fail2ban-ssh ACTION=install|enable|disable|status - управлять fail2ban"
	@echo "  sudo make net-bootstrap    - создать overlay-сети: edge, app(enc), infra(enc)"
	@echo "  make status              - показать статусы (без sudo)"
	@echo "  make show-ssh            - показать актуальный sshd_config порт"
	@echo "  make healthcheck         - проверить здоровье системы"
	@echo "  make quickstart          - интерактивная настройка для быстрого старта"
	@echo "  make env-select          - автоматически выбрать конфигурацию по hostname"
	@echo "  make env-list            - показать все доступные конфигурации"
	@echo "  make bundle-create       - создать bundle для деплоя (укажи HOST=hostname)"
	@echo "  make bundle-list         - показать все хосты для создания bundle"

check-env:
	@bash -c '\
	set -e; \
	if [ ! -f .env ]; then \
		echo "ERROR: .env file not found!"; \
		echo "Please copy .env.example to .env and fill in required values:"; \
		echo "  cp .env.example .env"; \
		exit 1; \
	fi; \
	missing=""; \
	for var in ADMIN_PUBKEY DEPLOY_PUBKEY WG_ENDPOINT_IP TRAEFIK_ACME_EMAIL; do \
		val=$${!var}; \
		if [ -z "$$val" ] || [ "$$val" = "ssh-ed25519 AAAAC3... your-key-here" ] || \
		   [ "$$val" = "YOUR_PUBLIC_IP" ] || [ "$$val" = "admin@example.com" ]; then \
			missing="$$missing $$var"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "ERROR: Missing or invalid required variables:$$missing"; \
		echo ""; \
		echo "Please edit .env and set proper values for:"; \
		for var in $$missing; do \
			echo "  - $$var"; \
		done; \
		echo ""; \
		echo "See .env.example for documentation"; \
		exit 1; \
	fi; \
	echo "✓ All required variables are set"; \
	'

init:
	@bash -c '\
	set -e; \
	source scripts/lib.sh; require_root; \
	ensure_pkg curl wget git nano unzip htop jq ca-certificates gnupg lsb-release; \
	timedatectl set-timezone "$${TZ:-UTC}"; \
	echo "Init done"; \
	'

users: check-env
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; ensure_pkg sudo; \
	id -u $(ADMIN_USER) >/dev/null 2>&1 || adduser --disabled-password --gecos "" $(ADMIN_USER); \
	mkdir -p /home/$(ADMIN_USER)/.ssh; echo "$(ADMIN_PUBKEY)" > /home/$(ADMIN_USER)/.ssh/authorized_keys; \
	chmod 700 /home/$(ADMIN_USER)/.ssh; chmod 600 /home/$(ADMIN_USER)/.ssh/authorized_keys; chown -R $(ADMIN_USER):$(ADMIN_USER) /home/$(ADMIN_USER)/.ssh; \
	usermod -aG sudo $(ADMIN_USER); \
	id -u $(DEPLOY_USER) >/dev/null 2>&1 || adduser --disabled-password --gecos "" $(DEPLOY_USER); \
	mkdir -p /home/$(DEPLOY_USER)/.ssh; echo "$(DEPLOY_PUBKEY)" > /home/$(DEPLOY_USER)/.ssh/authorized_keys; \
	chmod 700 /home/$(DEPLOY_USER)/.ssh; chmod 600 /home/$(DEPLOY_USER)/.ssh/authorized_keys; chown -R $(DEPLOY_USER):$(DEPLOY_USER) /home/$(DEPLOY_USER)/.ssh; \
	usermod -aG sudo $(DEPLOY_USER); \
	echo "Пользователи готовы"; \
	'

ssh: check-env
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	backup_file /etc/ssh/sshd_config; \
	sed -i "s/^#\?Port .*/Port $(SSH_PORT)/" /etc/ssh/sshd_config; \
	sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config; \
	sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config; \
	grep -qE "^PubkeyAuthentication" /etc/ssh/sshd_config && \
	  sed -i "s/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/" /etc/ssh/sshd_config || \
	  echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config; \
	systemctl restart ssh || systemctl restart sshd; \
	echo "SSH настроен на порт $(SSH_PORT)"; \
	'

ufw: check-env
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; ensure_ufw; \
	ufw default deny incoming; ufw default allow outgoing; \
	ufw allow $(SSH_PORT)/tcp; \
	ufw allow $(WG_PORT)/udp; \
	if [ "$${EDGE_OPEN_HTTP:-false}" = "true" ]; then ufw allow 80/tcp; ufw allow 443/tcp; fi; \
	yes | ufw enable; ufw status verbose; \
	'

docker:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	install -m 0755 -d /etc/apt/keyrings; \
	curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; chmod a+r /etc/apt/keyrings/docker.gpg; \
	echo "deb [arch=$$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $$(. /etc/os-release && echo $$VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list; \
	apt-get update -y; \
	DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; \
	usermod -aG docker $(ADMIN_USER); \
	usermod -aG docker $(DEPLOY_USER); \
	echo "Docker установлен"; \
	'

deploy_dir:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	mkdir -p /srv/deploy; chown -R $(DEPLOY_USER):$(DEPLOY_USER) /srv/deploy; \
	echo "/srv/deploy готов"; \
	'

wg-server: check-env
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; ensure_pkg wireguard; \
	mkdir -p /etc/wireguard; umask 077; \
	if [ ! -f /etc/wireguard/private.key ]; then wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key; fi; \
	PRIV=$$(cat /etc/wireguard/private.key); \
	cat >/etc/wireguard/$(WG_IF).conf <<-EOF
	[Interface]
	Address = $(WG_SERVER_IP)/24
	PrivateKey = $${PRIV}
	ListenPort = $(WG_PORT)
	MTU = $(WG_MTU)
	SaveConfig = true
	EOF
	; \
	systemctl enable wg-quick@$(WG_IF); systemctl restart wg-quick@$(WG_IF); \
	wg show; echo "WG-сервер поднят на $(WG_SERVER_IP)/24:$(WG_PORT)"; \
	install -m 0755 scripts/wg-new-client.sh /usr/local/bin/wg-new-client; \
	'

wg-client:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	NAME=$${NAME:-client-$$RANDOM}; IP=$${IP:-10.88.0.100}; \
	if ! command -v wg >/dev/null; then apt-get update -y && apt-get install -y wireguard; fi; \
	if ! [ -f /etc/wireguard/$(WG_IF).conf ]; then echo "Это цель запускается НА WG-СЕРВЕРЕ, чтобы сгенерить конфиг клиента." >&2; exit 1; fi; \
	if ! command -v wg-new-client >/dev/null; then install -m 0755 scripts/wg-new-client.sh /usr/local/bin/wg-new-client; fi; \
	wg-new-client $(WG_IF) "$${NAME}" "$${IP}" "$(WG_PORT)" "$(WG_ENDPOINT_IP)" "$(WG_ALLOWED_IPS)" 25; \
	echo "Сгенерен клиент: $${NAME}.conf"; \
	'

swarm-allow:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; ensure_ufw; \
	ufw allow in on $(WG_IF) to any port 2377 proto tcp; \
	ufw allow in on $(WG_IF) to any port 7946 proto tcp; \
	ufw allow in on $(WG_IF) to any port 7946 proto udp; \
	ufw allow in on $(WG_IF) to any port 4789 proto udp; \
	ufw status | sed -n "1,200p"; \
	'

wg-client-apply:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	CONFIG=$${CONFIG:-}; IF=$${IF:-wg0}; \
	if [ -z "$$CONFIG" ]; then echo "Укажи CONFIG=<path to .conf>" >&2; exit 2; fi; \
	bash scripts/wg-client-apply.sh -f "$$CONFIG" -i "$$IF"; \
	'

swarm-ports:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	ACTION=$${ACTION:-open}; IF=$${IF:-wg0}; \
	bash scripts/swarm-ports.sh "$$ACTION" -i "$$IF"; \
	'

service-vars:
	@bash -c '\
	set -e; \
	if [ "$${EXPORT:-false}" = "true" ]; then bash scripts/service-vars.sh --export; else bash scripts/service-vars.sh; fi; \
	'

gen-readme:
	@bash -c '\
	set -e; TYPE=$${TYPE:-}; OUT=$${OUT:-}; \
	if [ -z "$$TYPE" ]; then echo "Укажи TYPE (wg-client|swarm-init|traefik)" >&2; exit 2; fi; \
	bash scripts/gen-readme.sh "$$TYPE" "$$OUT"; \
	'

secrets-check:
	@bash -c '\
	set -e; SECRET=$${SECRET:-}; AGE_KEY=$${AGE_KEY:-}; OUT=$${OUT:-}; \
	if [ -z "$$SECRET" ]; then echo "Укажи SECRET=<GH secret value>" >&2; exit 2; fi; \
	if [ -n "$$OUT" ]; then bash scripts/secrets-resolve.sh -s "$$SECRET" ${AGE_KEY:+-k "$$AGE_KEY"} -o "$$OUT" --non-interactive; else bash scripts/secrets-resolve.sh -s "$$SECRET" ${AGE_KEY:+-k "$$AGE_KEY"}; fi; \
	'

secrets-to-swarm:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	ENVF=$${ENV:-.env}; PREFIX=$${PREFIX:-app_}; \
	if [ ! -f "$$ENVF" ]; then echo "Файл $$ENVF не найден. Сначала secrets-check OUT=.env" >&2; exit 2; fi; \
	bash scripts/secrets-to-swarm.sh -f "$$ENVF" -p "$$PREFIX"; \
	'

traefik-up: check-env
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	bash scripts/stack-traefik.sh up; \
	'

traefik-down:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	bash scripts/stack-traefik.sh down; \
	'

logs-up:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	bash scripts/stack-obs.sh up; \
	'

logs-down:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	bash scripts/stack-obs.sh down; \
	'

portainer-up:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	bash scripts/stack-portainer.sh up; \
	'

portainer-down:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	bash scripts/stack-portainer.sh down; \
	'

net-bootstrap:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	bash scripts/net-bootstrap.sh; \
	'

fail2ban-ssh:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; \
	ACTION=$${ACTION:-install}; \
	bash scripts/fail2ban-ssh.sh "$$ACTION"; \
	'

edge-open:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; ensure_ufw; \
	ufw allow 80/tcp; ufw allow 443/tcp; \
	ufw status | sed -n "1,200p"; \
	'

edge-close:
	@bash -c '\
	set -e; source scripts/lib.sh; require_root; ensure_ufw; \
	ufw delete allow 80/tcp || true; ufw delete allow 443/tcp || true; \
	ufw status | sed -n "1,200p"; \
	'

status:
	@echo "=== WG ==="; (wg show 2>/dev/null || echo "wg: not running"); \
	echo "=== Docker ==="; (docker info 2>/dev/null | head -n 20 || echo "docker: not installed"); \
	echo "=== UFW ==="; (sudo ufw status 2>/dev/null || true)

show-ssh:
	@grep -E "^Port " /etc/ssh/sshd_config || echo "Port not set"

healthcheck:
	@bash scripts/healthcheck.sh

quickstart:
	@bash scripts/quickstart.sh

env-select:
	@bash scripts/env-selector.sh

env-list:
	@bash scripts/env-selector.sh --list

bundle-create:
	@bash -c '\
	if [ -z "$${HOST:-}" ]; then \
		echo "Usage: make bundle-create HOST=hostname"; \
		echo "      make bundle-create ENV=staging"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make bundle-create HOST=prod-edge-1.example.com"; \
		echo "  make bundle-create ENV=production OUTPUT=prod.tar.gz"; \
		exit 1; \
	fi; \
	if [ -n "$${HOST:-}" ]; then \
		bash scripts/bundle-create.sh -H "$$HOST" $${OUTPUT:+-o "$$OUTPUT"}; \
	elif [ -n "$${ENV:-}" ]; then \
		bash scripts/bundle-create.sh -e "$$ENV" $${OUTPUT:+-o "$$OUTPUT"}; \
	fi'

bundle-list:
	@bash -c '\
	if [ -f envs/hosts.yml ]; then \
		echo "=== Available hosts for bundle creation ==="; \
		echo ""; \
		grep -E "^[[:space:]]+[^[:space:]]+:" envs/hosts.yml | \
			grep -v "^[[:space:]]*#" | \
			sed "s/^[[:space:]]*//;s/:.*//"; \
		echo ""; \
		echo "Create bundle: make bundle-create HOST=<hostname>"; \
	else \
		echo "No envs/hosts.yml found"; \
		echo "Using single configuration mode"; \
	fi'
