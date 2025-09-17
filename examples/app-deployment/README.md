# Application Deployment Example

Пример развёртывания вашего приложения на инфраструктуре, созданной через infra-bootstrap.

## Структура

- `stack.yml` - Docker Stack конфигурация для вашего приложения
- `deploy.sh` - Скрипт деплоя с поддержкой версий и откатов
- `env.production.template` - Шаблон для production секретов

## Подготовка

1. **Убедитесь что инфраструктура готова:**
   ```bash
   # На сервере
   infra-healthcheck
   docker network ls  # Должны быть сети: edge, app, infra
   ```

2. **Подготовьте секреты:**
   ```bash
   cp env.production.template .env.production
   vim .env.production  # Заполните реальными значениями
   ```

3. **Настройте stack.yml:**
   - Замените `ghcr.io/your-org/` на ваш Docker registry
   - Замените `example.com` на ваши домены
   - Настройте лимиты ресурсов под ваши нужды

## Деплой

### Первый деплой

```bash
# Загрузка секретов
./deploy.sh secrets

# Деплой приложения
./deploy.sh deploy

# Проверка статуса
./deploy.sh status
```

### Обновление версии

```bash
# Деплой конкретной версии
./deploy.sh -v v1.2.3 deploy

# Или через переменную окружения
VERSION=v1.2.3 ./deploy.sh deploy
```

### Откат

```bash
# Откат к предыдущей версии
./deploy.sh rollback
```

### Просмотр логов

```bash
# Интерактивный выбор сервиса
./deploy.sh logs

# Или напрямую через Docker
docker service logs -f myapp_backend
```

## CI/CD интеграция

### GitHub Actions

```yaml
name: Deploy to Production

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build and push images
        run: |
          docker build -t ghcr.io/${{ github.repository }}/backend:${{ github.ref_name }} .
          docker push ghcr.io/${{ github.repository }}/backend:${{ github.ref_name }}
      
      - name: Deploy to production
        env:
          DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
          DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
        run: |
          echo "$DEPLOY_KEY" > deploy_key
          chmod 600 deploy_key
          
          scp -i deploy_key -o StrictHostKeyChecking=no \
            examples/app-deployment/* deploy@$DEPLOY_HOST:~/app/
          
          ssh -i deploy_key -o StrictHostKeyChecking=no deploy@$DEPLOY_HOST \
            "cd ~/app && ./deploy.sh -v ${{ github.ref_name }} deploy"
```

## Мониторинг

После деплоя ваше приложение автоматически:
- Публикуется через Traefik с SSL сертификатами
- Логи собираются в Loki (доступны через Grafana)
- Метрики доступны в Portainer

Доступ к сервисам (если настроены домены в инфраструктуре):
- Grafana: https://grafana.your-domain.com
- Portainer: https://portainer.your-domain.com
- Traefik Dashboard: https://traefik.your-domain.com

## Best Practices

1. **Версионирование:**
   - Используйте семантическое версионирование (v1.2.3)
   - Тегируйте Docker образы версией и latest

2. **Секреты:**
   - Никогда не коммитьте .env.production
   - Используйте Docker secrets вместо environment variables
   - Ротируйте секреты регулярно

3. **Health checks:**
   - Всегда добавляйте health checks в stack.yml
   - Мониторьте эндпоинт /health

4. **Ресурсы:**
   - Устанавливайте лимиты CPU и памяти
   - Используйте placement constraints

5. **Zero-downtime деплой:**
   - Настройте update_config в stack.yml
   - Используйте health checks для проверки готовности

## Troubleshooting

### Сервис не стартует
```bash
# Проверьте логи
docker service ps myapp_backend --no-trunc
docker service logs myapp_backend

# Проверьте сети
docker network ls
```

### Секреты не работают
```bash
# Список секретов
docker secret ls

# Пересоздайте секреты
./deploy.sh secrets
```

### Проблемы с Traefik
```bash
# Проверьте лейблы
docker service inspect myapp_frontend

# Проверьте логи Traefik
docker service logs infra-traefik_traefik
```
