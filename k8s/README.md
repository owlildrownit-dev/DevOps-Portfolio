# k8s: kind + Helm

```bash
./setup-cluster.sh   # кластер, Traefik, metrics-server, PostgreSQL, Helm-релиз orders-api
./load-test.sh       # нагрузка для проверки HPA (Ctrl+C для остановки)
./teardown.sh        # удалить кластер
```

Требования: Docker, kind, kubectl, Helm 3/4.

## Путь запроса

```
curl -H "Host: orders.demo.local" localhost:8081
  → порт 8081 хоста → NodePort 30080 (extraPortMappings в kind-cluster.yaml)
  → Traefik → Ingress по host
  → Service orders-api (ClusterIP) → поды в состоянии Ready
  → контейнер :8000 → Service postgres → StatefulSet postgres-0
```

## Компоненты

| Тема | Где | Решение |
| --- | --- | --- |
| Кластер | `kind-cluster.yaml` | 1 control plane + 2 worker, явные диапазоны подов и сервисов |
| Ingress | `setup-cluster.sh` | Traefik, `ingressClassName: traefik`; ingress-nginx выведен из поддержки ([анонс](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)) |
| Образы | `setup-cluster.sh`, шаг 1b | загрузка с хоста через `kind load image-archive`: узлы работают без доступа к registry |
| Helm | `charts/orders-api` | версия образа через `--set image.tag`, откат `helm rollback` |
| Secret | `setup-cluster.sh`, шаг 4 | создается вне чарта, не попадает в git и историю Helm; Secret в etcd по умолчанию не шифруется ([документация](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)) |
| Probes | `values.yaml` | liveness без проверки БД, readiness с проверкой БД, startup на время запуска |
| HPA | `templates/hpa.yaml` | цель 60% от `requests.cpu`, 2..5 реплик, метрики от metrics-server |
| Обновление | `templates/deployment.yaml` | `maxUnavailable: 0`, `maxSurge: 1`, PodDisruptionBudget |
| Безопасность пода | `templates/deployment.yaml` | не root, read-only root FS, `/tmp` через emptyDir |

## Проверка (GitHub Codespaces, 28.10.2026)

- HPA: CPU до 304% от requests при цели 60%, реплики 2 → 4 → 5 (максимум).
- Обновление до 1.1.0 и `helm rollback orders-api 1`: три ревизии в `helm history`.
- `helm lint`: без ошибок.

![HPA](../docs/screenshots/04-k8s-hpa-scaling.png)
![rolling update](../docs/screenshots/04-k8s-rolling-update.png)
