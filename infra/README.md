# infra: Terraform + Ansible

Выкладка сервиса на Docker-хост одной командой.

```bash
./deploy.sh                      # версия 1.0.0
APP_VERSION=1.1.0 ./deploy.sh    # обновление, rolling update по одной реплике
./destroy.sh                     # удалить окружение
```

Требования: Docker, Terraform 1.5+, `ansible-core`, Python-пакет `docker`,
коллекция `community.docker` (все ставит `scripts/setup-tools.sh`).

## Разделение ответственности

| Инструмент | Что делает | Где |
| --- | --- | --- |
| Terraform | Сеть, том, контейнер PostgreSQL с ожиданием healthcheck; генерирует переменные для Ansible | `terraform/` |
| Ansible | Миграция БД, сборка образа через BuildKit, rolling update, nginx, smoke-тест | `ansible/` |
| `deploy.sh` | Оба этапа и запись длительности в `results/deploy_times.csv` | |

## Что автоматизировано

| Шаг | Вручную | Автоматически | Где |
| --- | --- | --- | --- |
| Сеть и хранилище | `docker network/volume create` | Terraform | `docker_network`, `docker_volume` |
| База данных | запуск, пароль, ожидание готовности | Terraform, `wait = true` по healthcheck | `docker_container.db` |
| Параметры для деплоя | копирование имен и адресов в конфиги | файл переменных из Terraform | `local_file.ansible_vars` |
| Миграция схемы | psql вручную | идемпотентная миграция | `roles/db_migrate` |
| Сборка образа | `docker build` на рабочей машине | сборка с тегом версии | `roles/app` |
| Обновление реплик | остановить все и запустить новые | по одной, следующая после healthy | `roles/app/tasks/replica.yml` |
| Балансировщик | правка nginx.conf | шаблон по числу реплик, перезапуск только при изменении | `roles/lb` |
| Проверка | открыть в браузере | liveness, версия, readiness, бизнес-запрос | `roles/smoke_test` |
| Секреты | пароль в заметках | переменная окружения, файл в `.gitignore` | `deploy.sh` |

## Замеры

| Прогон | Версия | Terraform | Ansible | Всего | Условия |
| --- | --- | --- | --- | --- | --- |
| 1 | 1.0.0 | 3 с | 78 с | 81 с | инфраструктура уже создана |
| 1 | 1.1.0 | 3 с | 77 с | 80 с | обновление |
| 2 | 1.0.0 | 28 с | 83 с | 111 с | с нуля после `destroy.sh` |
| 2 | 1.1.0 | 3 с | 78 с | 81 с | обновление |

Прогон 2: [`results/deploy_times.csv`](results/deploy_times.csv).
Прогон 1: [скриншот](../docs/screenshots/01-deploy-done.png).

## Решения

- **State** хранится локально; для командной работы нужен remote backend с блокировкой.
- **Конфиг Ansible** передается через `ANSIBLE_CONFIG`: Ansible игнорирует `ansible.cfg`
  в каталоге, доступном на запись всем (так в Codespaces).
- **Откат:** `APP_VERSION=<предыдущая> ./deploy.sh`, образ прежней версии остается на хосте.
