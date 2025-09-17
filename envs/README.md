# Environment Configurations

Эта директория содержит конфигурации для разных инфраструктур.

## Структура

```
envs/
├── README.md           # Этот файл
├── hosts.yml           # Соответствие хостов и окружений
├── production/
│   ├── edge-1.env     # Конфиг для edge ноды 1
│   ├── edge-2.env     # Конфиг для edge ноды 2
│   └── app-1.env      # Конфиг для app ноды
├── staging/
│   └── all.env        # Единый конфиг для staging
└── development/
    └── local.env      # Локальная разработка
```

## Файл hosts.yml

Определяет соответствие hostname -> environment -> role:

```yaml
hosts:
  # Production
  prod-edge-1.example.com:
    env: production
    config: edge-1.env
    role: edge
    
  prod-edge-2.example.com:
    env: production
    config: edge-2.env
    role: edge
    
  prod-app-1.example.com:
    env: production
    config: app-1.env
    role: app
    
  # Staging
  staging.example.com:
    env: staging
    config: all.env
    role: all
    
  # Development
  dev-local:
    env: development
    config: local.env
    role: all

# Настройки по умолчанию
defaults:
  env: production
  config: default.env
  role: app
```

## Использование

1. Скрипт автоматически определит hostname
2. Найдёт соответствующую конфигурацию в hosts.yml
3. Загрузит нужный .env файл

Если хост не найден, используются настройки по умолчанию.
