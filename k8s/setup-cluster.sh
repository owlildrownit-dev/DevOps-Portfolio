#!/usr/bin/env bash
# Creates a kind cluster and deploys orders-api with Helm.
# Requires: docker, kind, kubectl, helm.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
CLUSTER=demo
APP_VERSION="${APP_VERSION:-1.0.0}"

step() { printf '\n==== %s ====\n' "$*"; }

step "1. kind cluster (1 control-plane node + 2 workers)"
kind get clusters | grep -qx "$CLUSTER" || kind create cluster --config "$HERE/kind-cluster.yaml"
kubectl cluster-info --context "kind-$CLUSTER"
kubectl get nodes -o wide

TRAEFIK_ARGS=(--set ingressClass.name=traefik --set service.type=NodePort --set ports.web.nodePort=30080)
METRICS_ARGS=(--set 'args={--kubelet-insecure-tls}')

helm repo add traefik https://traefik.github.io/charts >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update >/dev/null

step "1b. Preloading images into the kind nodes"
# kind nodes may have no working DNS or internet access (this happens with Docker
# inside a container, e.g. in Codespaces). Images are therefore pulled on the host and
# loaded into the nodes directly, as in an air-gapped cluster.
PLATFORM="linux/$(dpkg --print-architecture 2>/dev/null || echo amd64)"
images_of() {  # list of images a Helm chart uses with the given values
  helm template tmp "$@" | grep -E '^[[:space:]-]*image:' | sed -E 's/.*image:[[:space:]]*//; s/["'"'"']//g' | sort -u
}
preload() {
  local img=$1 tar
  tar="$(mktemp -d)/image.tar"
  echo "  -> $img"
  docker pull -q --platform "$PLATFORM" "$img" >/dev/null
  # --platform on save: only the required architecture reaches the node (otherwise kind load
  # may fail to find other architectures' layers with the containerd image store)
  docker save --platform "$PLATFORM" -o "$tar" "$img" 2>/dev/null || docker save -o "$tar" "$img"
  kind load image-archive "$tar" --name "$CLUSTER" >/dev/null
  rm -rf "$(dirname "$tar")"
}
for img in $(images_of traefik/traefik "${TRAEFIK_ARGS[@]}") \
           $(images_of metrics-server/metrics-server "${METRICS_ARGS[@]}") \
           postgres:16 busybox:1.36; do
  preload "$img"
done

step "2. Traefik ingress controller (NodePort 30080)"
# ingress-nginx is not used: the Kubernetes project has announced its retirement
# (best-effort maintenance until March 2026), see k8s/README.md
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  "${TRAEFIK_ARGS[@]}" \
  --wait

step "3. metrics-server (required by the HPA)"
# kubelets in kind use self-signed certificates, hence --kubelet-insecure-tls (lab use only!)
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set 'args={--kubelet-insecure-tls}' \
  --wait

step "4. Database password Secret (generated, never stored in git)"
if ! kubectl get secret orders-db >/dev/null 2>&1; then
  PASS=$(openssl rand -hex 16)
  kubectl create secret generic orders-db \
    --from-literal=POSTGRES_PASSWORD="$PASS" \
    --from-literal=DATABASE_URL="postgresql://shop:${PASS}@postgres:5432/shop"
fi

step "5. PostgreSQL (StatefulSet) and schema migration"
kubectl apply -f "$HERE/manifests/postgres.yaml"
kubectl rollout status statefulset/postgres --timeout=180s
kubectl exec -i postgres-0 -- psql -U shop -d shop -v ON_ERROR_STOP=1 \
  < "$ROOT/infra/ansible/roles/db_migrate/files/schema.sql"

step "6. Application image: build and load into the kind nodes"
docker build -t "orders-api:$APP_VERSION" -f "$ROOT/app/Dockerfile" "$ROOT/app"
kind load docker-image "orders-api:$APP_VERSION" --name "$CLUSTER"

step "7. orders-api Helm release"
helm upgrade --install orders-api "$HERE/charts/orders-api" \
  --set image.tag="$APP_VERSION" \
  --wait --timeout 3m
kubectl get deploy,po,svc,ingress,hpa -l app.kubernetes.io/instance=orders-api

step "8. Check through the Ingress"
for i in $(seq 1 15); do
  if curl -fsS -H "Host: orders.demo.local" http://127.0.0.1:8081/healthz; then echo; break; fi
  sleep 2
done
curl -fsS -H "Host: orders.demo.local" http://127.0.0.1:8081/customers/1/orders | head -c 300; echo
