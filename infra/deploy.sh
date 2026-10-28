#!/usr/bin/env bash
# Полная выкладка стенда одной командой + замер времени.
#   ./deploy.sh              выкладка версии 1.0.0
#   APP_VERSION=1.1.0 ./deploy.sh   обновление (rolling update)
# Каждый запуск дописывает строку в results/deploy_times.csv
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
mkdir -p results

# Пароль БД: из окружения или сгенерированный один раз и сохраненный локально (файл в .gitignore)
if [[ -z "${DB_PASSWORD:-}" ]]; then
  [[ -f .db_password ]] || { openssl rand -hex 16 > .db_password; chmod 600 .db_password; }
  DB_PASSWORD=$(cat .db_password)
fi
export DB_PASSWORD TF_VAR_db_password="$DB_PASSWORD"
export APP_VERSION="${APP_VERSION:-1.0.0}"

stage() { printf '\n==== %s ====\n' "$*"; }
t0=$(date +%s)

stage "1/2 Terraform: сеть, том, PostgreSQL"
terraform -chdir=terraform init -input=false -upgrade=false >/dev/null
terraform -chdir=terraform apply -auto-approve -input=false
t1=$(date +%s)

stage "2/2 Ansible: миграция, сборка, rolling update, балансировщик, smoke-тест"
(cd ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory/hosts.yml site.yml)
t2=$(date +%s)

tf=$((t1 - t0)); an=$((t2 - t1)); total=$((t2 - t0))
[[ -f results/deploy_times.csv ]] || echo "date,app_version,terraform_s,ansible_s,total_s" > results/deploy_times.csv
echo "$(date '+%Y-%m-%d %H:%M:%S'),$APP_VERSION,$tf,$an,$total" >> results/deploy_times.csv

stage "Готово"
printf 'Terraform: %d с, Ansible: %d с, всего: %d мин %d с\n' "$tf" "$an" $((total / 60)) $((total % 60))
echo "Приложение: http://127.0.0.1:8080/healthz"
echo "История замеров: results/deploy_times.csv"
