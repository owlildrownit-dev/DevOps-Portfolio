#!/usr/bin/env bash
# Поднимает кластер kind и выкатывает orders-api через Helm.
# Нужны: docker, kind, kubectl, helm.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
CLUSTER=demo
APP_VERSION="${APP_VERSION:-1.0.0}"

step() { printf '\n==== %s ====\n' "$*"; }

step "1. Кластер kind (1 control plane + 2 worker)"
kind get clusters | grep -qx "$CLUSTER" || kind create cluster --config "$HERE/kind-cluster.yaml"
kubectl cluster-info --context "kind-$CLUSTER"
kubectl get nodes -o wide

TRAEFIK_ARGS=(--set ingressClass.name=traefik --set service.type=NodePort --set ports.web.nodePort=30080)
METRICS_ARGS=(--set 'args={--kubelet-insecure-tls}')

helm repo add traefik https://traefik.github.io/charts >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update >/dev/null

step "1b. Предзагрузка образов в узлы kind"
# Узлы kind могут не иметь своего DNS и выхода в интернет (так бывает в Docker внутри
# контейнера, например в Codespaces). Поэтому образы скачиваются на хост и загружаются
# в узлы напрямую, как в изолированном (air-gapped) кластере.
PLATFORM="linux/$(dpkg --print-architecture 2>/dev/null || echo amd64)"
images_of() {  # список образов, которые использует Helm-чарт с заданными параметрами
  helm template tmp "$@" | grep -E '^[[:space:]-]*image:' | sed -E 's/.*image:[[:space:]]*//; s/["'"'"']//g' | sort -u
}
preload() {
  local img=$1 tar
  tar="$(mktemp -d)/image.tar"
  echo "  -> $img"
  docker pull -q --platform "$PLATFORM" "$img" >/dev/null
  # --platform у save: в узел попадает только нужная архитектура (иначе kind load
  # может не найти слои других архитектур при containerd image store)
  docker save --platform "$PLATFORM" -o "$tar" "$img" 2>/dev/null || docker save -o "$tar" "$img"
  kind load image-archive "$tar" --name "$CLUSTER" >/dev/null
  rm -rf "$(dirname "$tar")"
}
for img in $(images_of traefik/traefik "${TRAEFIK_ARGS[@]}") \
           $(images_of metrics-server/metrics-server "${METRICS_ARGS[@]}") \
           postgres:16 busybox:1.36; do
  preload "$img"
done

step "2. Ingress-контроллер Traefik (NodePort 30080)"
# ingress-nginx здесь не используется: проект Kubernetes объявил о его выводе из поддержки
# (best-effort поддержка до марта 2026), см. README раздела
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  "${TRAEFIK_ARGS[@]}" \
  --wait

step "3. metrics-server (нужен для HPA)"
# в kind у kubelet самоподписанные сертификаты, поэтому --kubelet-insecure-tls (только для стенда!)
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set 'args={--kubelet-insecure-tls}' \
  --wait

step "4. Secret с паролем БД (генерируется, в git не хранится)"
if ! kubectl get secret orders-db >/dev/null 2>&1; then
  PASS=$(openssl rand -hex 16)
  kubectl create secret generic orders-db \
    --from-literal=POSTGRES_PASSWORD="$PASS" \
    --from-literal=DATABASE_URL="postgresql://shop:${PASS}@postgres:5432/shop"
fi

step "5. PostgreSQL (StatefulSet) и миграция схемы"
kubectl apply -f "$HERE/manifests/postgres.yaml"
kubectl rollout status statefulset/postgres --timeout=180s
kubectl exec -i postgres-0 -- psql -U shop -d shop -v ON_ERROR_STOP=1 \
  < "$ROOT/infra/ansible/roles/db_migrate/files/schema.sql"

step "6. Образ приложения: сборка и загрузка в узлы kind"
docker build -t "orders-api:$APP_VERSION" -f "$ROOT/app/Dockerfile" "$ROOT/app"
kind load docker-image "orders-api:$APP_VERSION" --name "$CLUSTER"

step "7. Helm-релиз orders-api"
helm upgrade --install orders-api "$HERE/charts/orders-api" \
  --set image.tag="$APP_VERSION" \
  --wait --timeout 3m
kubectl get deploy,po,svc,ingress,hpa -l app.kubernetes.io/instance=orders-api

step "8. Проверка через Ingress"
for i in $(seq 1 15); do
  if curl -fsS -H "Host: orders.demo.local" http://127.0.0.1:8081/healthz; then echo; break; fi
  sleep 2
done
curl -fsS -H "Host: orders.demo.local" http://127.0.0.1:8081/customers/1/orders | head -c 300; echo
