#!/usr/bin/env bash
# HPA load test: generates traffic and watches the replica count grow.
# Stop with Ctrl+C (the load generator pods are removed automatically).
set -euo pipefail
LOADERS="${LOADERS:-3}"

cleanup() { kubectl delete pod -l role=loadgen --ignore-not-found --wait=false >/dev/null; }
trap cleanup EXIT

for i in $(seq 1 "$LOADERS"); do
  kubectl run "loadgen-$i" --labels=role=loadgen --image=busybox:1.36 --restart=Never -- \
    /bin/sh -c 'while true; do wget -q -O /dev/null http://orders-api/customers/1/orders; done'
done

echo "Load started ($LOADERS pods). Watching the HPA (it syncs every 15 s by default):"
kubectl get hpa orders-api -w
