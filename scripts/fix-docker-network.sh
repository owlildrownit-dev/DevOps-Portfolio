#!/usr/bin/env bash
# Docker writes its rules to nft, but bridged traffic also passes the legacy table,
# whose FORWARD DROP policy silently drops container-to-container packets.
# See docs/incidents/2026-10-28-container-traffic-timeouts.md. Runs on every codespace start.
set -euo pipefail
SUDO=""; if [[ $(id -u) -ne 0 ]]; then SUDO="sudo"; fi

if command -v iptables-legacy >/dev/null 2>&1 \
   && $SUDO iptables-legacy -S FORWARD 2>/dev/null | grep -q -- '-P FORWARD DROP'; then
  $SUDO iptables-legacy -C FORWARD -i br-+ -o br-+ -j ACCEPT 2>/dev/null \
    || $SUDO iptables-legacy -I FORWARD -i br-+ -o br-+ -j ACCEPT
  echo "iptables-legacy: FORWARD DROP detected, container-to-container traffic allowed"
else
  echo "iptables-legacy: container-to-container traffic is not blocked"
fi
