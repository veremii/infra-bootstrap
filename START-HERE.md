# 🚀 START HERE - Быстрый старт за 3 минуты

## Что это?

**infra-bootstrap** - инструмент для развёртывания защищённой инфраструктуры на Linux серверах. 
Включает всё необходимое: SSH защиту, Docker, VPN, мониторинг, SSL сертификаты.

## Для кого?

- DevOps инженеры
- Разработчики, деплоящие свои приложения
- Стартапы, которым нужна инфраструктура быстро
- Любой, кто хочет безопасный сервер

## Что умеет?

- 🔒 **Безопасность**: SSH hardening, firewall, VPN
- 🐳 **Docker Swarm**: готовая оркестрация
- 🌐 **Traefik**: автоматические SSL сертификаты
- 📊 **Мониторинг**: централизованные логи
- 🏢 **Multi-server**: управление десятками серверов

## Начнём!

### Вариант 1: Один сервер (самый простой)

```bash
# На вашем компьютере
git clone https://github.com/your-org/infra-bootstrap.git
cd infra-bootstrap

# Запускаем интерактивную настройку
./scripts/quickstart.sh
```

Скрипт:
- Создаст конфигурацию
- Сгенерирует SSH ключи
- Подготовит всё для установки

### Вариант 2: Готовый bundle

```bash
# Создаём пакет для сервера
make bundle-create HOST=my-server.com

# Копируем на сервер
scp bundle-*.tar.gz user@my-server.com:~/

# На сервере
ssh user@my-server.com
tar -xzf bundle-*.tar.gz
cd infra-bootstrap
./bootstrap.sh
```

### Вариант 3: Множество серверов

1. Настройте конфигурации в `envs/`
2. Обновите `envs/hosts.yml`
3. Создайте bundles: `make bundle-create HOST=server1`
4. Разверните на всех серверах

## Что дальше?

После базовой установки вы получите:
- Защищённый SSH на порту 1255
- Docker и Docker Swarm
- Готовые overlay сети
- Возможность деплоить сервисы

### Деплой Traefik (reverse proxy)
```bash
sudo make traefik-up
```

### Деплой мониторинга
```bash
sudo make logs-up
```

### Проверка статуса
```bash
make healthcheck
```

## Документация

- **README.md** - полная документация
- **QUICKSTART.md** - подробный гайд
- **examples/** - примеры деплоя приложений
- **envs/README.md** - про множественные окружения

## Проблемы?

1. Проверьте требования:
   - Debian 11/12 или Ubuntu 20.04/22.04
   - Минимум 2GB RAM
   - SSH доступ с sudo

2. Запустите валидацию:
   ```bash
   ./validate.sh
   ```

3. Создайте issue на GitHub

## Tips & Tricks

- 💡 Используйте `make help` для списка команд
- 💡 Всегда запускайте `make check-env` перед деплоем
- 💡 Сохраните `.env` в безопасном месте
- 💡 После SSH hardening подключайтесь через порт 1255
- 💡 WireGuard VPN изолирует внутренний трафик

---

**Ready? Let's go!** 🚀

```bash
./scripts/quickstart.sh
```
