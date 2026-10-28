#!/usr/bin/env bash
# Full deployment with a single command, plus timing.
#   ./deploy.sh                     deploy version 1.0.0
#   APP_VERSION=1.1.0 ./deploy.sh   upgrade (rolling update)
# Every run appends a line to results/deploy_times.csv
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
mkdir -p results

# DB password: from the environment, or generated once and stored locally (the file is gitignored)
if [[ -z "${DB_PASSWORD:-}" ]]; then
  [[ -f .db_password ]] || { openssl rand -hex 16 > .db_password; chmod 600 .db_password; }
  DB_PASSWORD=$(cat .db_password)
fi
export DB_PASSWORD TF_VAR_db_password="$DB_PASSWORD"
export APP_VERSION="${APP_VERSION:-1.0.0}"

stage() { printf '\n==== %s ====\n' "$*"; }
t0=$(date +%s)

stage "1/2 Terraform: network, volume, PostgreSQL"
terraform -chdir=terraform init -input=false -upgrade=false >/dev/null
terraform -chdir=terraform apply -auto-approve -input=false
t1=$(date +%s)

stage "2/2 Ansible: migration, build, rolling update, load balancer, smoke test"
(cd ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory/hosts.yml site.yml)
t2=$(date +%s)

tf=$((t1 - t0)); an=$((t2 - t1)); total=$((t2 - t0))
[[ -f results/deploy_times.csv ]] || echo "date,app_version,terraform_s,ansible_s,total_s" > results/deploy_times.csv
echo "$(date '+%Y-%m-%d %H:%M:%S'),$APP_VERSION,$tf,$an,$total" >> results/deploy_times.csv

stage "Done"
printf 'Terraform: %ds, Ansible: %ds, total: %dm %ds\n' "$tf" "$an" $((total / 60)) $((total % 60))
echo "Application: http://127.0.0.1:8080/healthz"
echo "Timing history: results/deploy_times.csv"
