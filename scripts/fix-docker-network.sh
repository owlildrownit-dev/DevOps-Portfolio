#!/usr/bin/env bash
# Allows traffic between Docker containers when the legacy iptables table drops it.
#
# Why: Docker running inside a container (GitHub Codespaces) sees two iptables backends,
# nft and legacy. Docker writes its rules to nft, but with net.bridge.bridge-nf-call-iptables=1
# bridged traffic also traverses the legacy table. If that table has a FORWARD DROP policy,
# packets between containers are silently dropped: timeouts, and ping fails.
# Write-up: docs/incidents/2026-10-28-container-traffic-timeouts.md
#
# The rule does not survive a restart, so devcontainer.json runs this script
# every time the codespace starts (postStartCommand).
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
