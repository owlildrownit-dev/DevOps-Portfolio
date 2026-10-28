# 2026-10-28: тайм-ауты между контейнерами в GitHub Codespaces

**Итог:** трафик между контейнерами Docker отбрасывался legacy-таблицей iptables
(`FORWARD DROP`). Исправлено правилом для мостов Docker, проверка автоматизирована.

| Этап | Что было |
| --- | --- |
| Симптом | Smoke-тест выкладки: `GET 127.0.0.1:8080/healthz` висит до тайм-аута. В логе nginx код 499: клиент закрыл соединение, не дождавшись ответа от upstream. |
| Гипотеза 1 | nginx хранит старые IP реплик. **Опровергнута:** `wget` из контейнера nginx напрямую к `orders-api-1:8000` тоже висит, хотя заново разрешает имя. |
| Гипотеза 2 | В сети остались устаревшие записи после аварийной остановки Docker. **Опровергнута:** `nslookup` через 127.0.0.11, `docker inspect` и `docker network inspect` дают один адрес 172.18.0.3. |
| Сужение | `ping` между контейнерами: 100% потерь; приложение не подключается к БД; с хоста nginx доступен. Проблема в трафике контейнер → контейнер. |
| Причина | `iptables -S`: *iptables-legacy tables present*. Docker пишет правила в nft (FORWARD ACCEPT), а при `net.bridge.bridge-nf-call-iptables = 1` трафик внутри моста проходит и через legacy-таблицу с политикой FORWARD DROP. |
| Исправление | `iptables-legacy -I FORWARD -i br-+ -o br-+ -j ACCEPT`: разрешен только трафик между мостами Docker. Выкладка прошла: 81 с (1.0.0), 80 с (1.1.0). |
| Профилактика | `scripts/fix-docker-network.sh` запускается при каждом старте codespace (`postStartCommand`). |

## Связанные проблемы той же среды

- **Узлы kind без DNS:** резолвер узла указывал на шлюз сети Docker (172.18.0.1:53), где DNS не слушает
  (`ss -lunp`: только 127.0.0.53 на lo). Поды в `ImagePullBackOff`. Решение: загрузка образов в узлы
  с хоста (`k8s/setup-cluster.sh`, шаг 1b).
- **Остановка неактивного codespace:** все контейнеры завершились одновременно с кодом 255,
  кэш BuildKit поврежден (`parent snapshot ... not found`). Решение: `docker builder prune -af`.

Скриншоты: [ping и iptables](../screenshots/05-incident-iptables.png),
[DNS в узле kind](../screenshots/04-k8s-dns-imagepull.png).
