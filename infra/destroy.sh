#!/usr/bin/env bash
# Tears down the environment: Ansible-managed containers (label stand=demo), then the Terraform resources.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

ids=$(docker ps -aq --filter label=stand=demo --filter label=managed=ansible)
if [[ -n "$ids" ]]; then docker rm -f $ids; fi

export TF_VAR_db_password="${DB_PASSWORD:-$(cat .db_password 2>/dev/null || echo unused)}"
terraform -chdir=terraform destroy -auto-approve -input=false
