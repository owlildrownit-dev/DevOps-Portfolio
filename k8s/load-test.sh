#!/usr/bin/env bash
# Нагрузочный тест HPA: подаем нагрузку и смотрим, как растет число реплик.
# Остановить: Ctrl+C (поды нагрузки удаляются автоматически).
set -euo pipefail
LOADERS="${LOADERS:-3}"

cleanup() { kubectl delete pod -l role=loadgen --ignore-not-found --wait=false >/dev/null; }
trap cleanup EXIT

for i in $(seq 1 "$LOADERS"); do
  kubectl run "loadgen-$i" --labels=role=loadgen --image=busybox:1.36 --restart=Never -- \
    /bin/sh -c 'while true; do wget -q -O /dev/null http://orders-api/customers/1/orders; done'
done

echo "Нагрузка подана ($LOADERS пода). Наблюдаем HPA (обновление раз в 15 с по умолчанию):"
kubectl get hpa orders-api -w
