#!/usr/bin/env bash
# Открывает трафик между контейнерами Docker, если его режет legacy-таблица iptables.
#
# Зачем: в Docker внутри контейнера (GitHub Codespaces) работают две реализации iptables,
# nft и legacy. Docker пишет правила в nft, а при net.bridge.bridge-nf-call-iptables=1
# трафик внутри моста Docker проходит и через legacy-таблицу. Если там FORWARD DROP,
# пакеты между контейнерами молча теряются: тайм-ауты, ping не проходит.
# Разбор: docs/incidents/2026-10-28-container-traffic-timeouts.md
#
# Правило живет до перезапуска машины, поэтому devcontainer.json вызывает скрипт
# при каждом старте codespace (postStartCommand).
set -euo pipefail
SUDO=""; if [[ $(id -u) -ne 0 ]]; then SUDO="sudo"; fi

if command -v iptables-legacy >/dev/null 2>&1 \
   && $SUDO iptables-legacy -S FORWARD 2>/dev/null | grep -q -- '-P FORWARD DROP'; then
  $SUDO iptables-legacy -C FORWARD -i br-+ -o br-+ -j ACCEPT 2>/dev/null \
    || $SUDO iptables-legacy -I FORWARD -i br-+ -o br-+ -j ACCEPT
  echo "iptables-legacy: FORWARD DROP обнаружен, трафик между контейнерами разрешен"
else
  echo "iptables-legacy: блокировки трафика между контейнерами нет"
fi
