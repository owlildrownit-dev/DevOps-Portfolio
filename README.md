# orders-platform

Учебный DevOps-проект вокруг небольшого сервиса заказов (`app/`, Flask + PostgreSQL):
инфраструктура как код, автоматическая выкладка, оптимизация Docker-образа и запросов к БД,
развертывание в Kubernetes, сетевая диагностика.

> Данные синтетические, все замеры выполнены на тестовом стенде (GitHub Codespaces).

## Структура

| Каталог | Содержимое |
| --- | --- |
| [`app/`](app/) | Сервис `orders-api`: Flask, gunicorn, psycopg2; multi-stage `Dockerfile` |
| [`infra/`](infra/) | Terraform (сеть, том, PostgreSQL) и Ansible (миграция, сборка, rolling update, nginx, smoke-тест) |
| [`k8s/`](k8s/) | Кластер kind, Helm-чарт `orders-api`: Deployment, Service, Ingress, HPA, PDB |
| [`benchmarks/image-size/`](benchmarks/image-size/) | Сравнение размера однослойного и multi-stage образа |
| [`benchmarks/postgres-cpu/`](benchmarks/postgres-cpu/) | Нагрузка CPU PostgreSQL до и после оптимизации запросов |
| [`network/`](network/) | Референсная схема сети двух офисов, чек-лист диагностики |
| [`docs/`](docs/) | Разборы инцидентов, скриншоты |
| [`scripts/`](scripts/) | Установка инструментов, исправление сети Docker в Codespaces |

## Результаты (GitHub Codespaces, 28.10.2026)

Замеры выкладки, размера образа и PostgreSQL выполнены дважды; исходные файлы второго прогона лежат в каталогах `results/`.

| Задача | Прогон 1 | Прогон 2 | Итог |
| --- | --- | --- | --- |
| Выкладка одной командой (`infra/deploy.sh`) | 81 с (инфраструктура уже создана) | 111 с с нуля, из них Terraform 28 с | обновление до 1.1.0: 80 и 81 с |
| Размер образа, МБ | 704,2 → 198,0 | 704,2 → 198,0 | −71,9% |
| CPU PostgreSQL за 120 с при 3 TPS | 118,30 с → 0,39 с | 125,09 с → 0,43 с | −99,7% |
| Kubernetes | HPA 2 → 5 реплик, обновление и `helm rollback` | | |

Расчеты: (704,2 − 198,0) / 704,2 × 100 ≈ 71,9%; (125,09 − 0,43) / 125,09 × 100 ≈ 99,7%.

**HPA под нагрузкой: 2 → 4 → 5 реплик**

![HPA](docs/screenshots/04-k8s-hpa-scaling.png)

**Helm: обновление и откат**

![Helm rollback](docs/screenshots/04-k8s-helm-rollback.png)

**PostgreSQL: замер с сопоставимой нагрузкой и замер, забракованный проверкой**

![PostgreSQL](docs/screenshots/03-postgres-valid-run.png)
![PostgreSQL overloaded](docs/screenshots/03-postgres-overloaded-warning.png)

**Размер образов и время выкладки**

![Image size](docs/screenshots/02-docker-sizes.png)
![Deploy](docs/screenshots/01-deploy-done.png)

## Запуск

**GitHub Codespaces:** Code → Codespaces → Create codespace. Инструменты ставятся автоматически
(`.devcontainer`, `scripts/setup-tools.sh`).

**Linux / WSL2 с Docker:** `bash scripts/setup-tools.sh`.

```bash
cd benchmarks/postgres-cpu && ./run.sh        # RATE=3 ./run.sh, если отчет пишет «ВНИМАНИЕ»
cd benchmarks/image-size && ./measure.sh
cd infra && ./deploy.sh                       # APP_VERSION=1.1.0 ./deploy.sh для обновления
cd k8s && ./setup-cluster.sh                  # затем ./load-test.sh и ./teardown.sh
```

## Инциденты

- [Тайм-ауты между контейнерами в Codespaces (iptables-legacy)](docs/incidents/2026-10-28-container-traffic-timeouts.md)
