# 2026-10-28: container-to-container timeouts in GitHub Codespaces

**Summary:** traffic between Docker containers was dropped by the legacy iptables table
(`FORWARD DROP`). It was fixed with a rule scoped to Docker bridges, and the check is now automated.

| Stage | Details |
| --- | --- |
| Symptom | The deployment smoke test hung until timeout on `GET 127.0.0.1:8080/healthz`. The nginx log showed status 499: the client closed the connection before the upstream responded. |
| Hypothesis 1 | nginx had cached stale replica IPs. **Ruled out:** `wget` from the nginx container straight to `orders-api-1:8000` also hung, even though it resolves the name afresh. |
| Hypothesis 2 | Stale network entries were left behind after Docker stopped abruptly. **Ruled out:** `nslookup` via 127.0.0.11, `docker inspect` and `docker network inspect` all returned the same address, 172.18.0.3. |
| Narrowing down | `ping` between containers: 100% packet loss; the app could not reach the database; nginx was reachable from the host. The problem was limited to container-to-container traffic. |
| Root cause | `iptables -S` warned that *iptables-legacy tables* were present. Docker writes its rules to nft (FORWARD ACCEPT), but with `net.bridge.bridge-nf-call-iptables = 1` bridged traffic also traverses the legacy table, whose FORWARD policy was DROP. |
| Fix | `iptables-legacy -I FORWARD -i br-+ -o br-+ -j ACCEPT`, which allows only traffic between Docker bridges. The deployment then succeeded: 81 s (1.0.0) and 80 s (1.1.0). |
| Prevention | `scripts/fix-docker-network.sh` runs on every codespace start (`postStartCommand`). |

## Related issues in the same environment

- **kind nodes without DNS:** the node resolver pointed to the Docker network gateway (172.18.0.1:53),
  where no DNS server listens (`ss -lunp` showed only 127.0.0.53 on lo). Pods were stuck in
  `ImagePullBackOff`. Fix: load images into the nodes from the host (`k8s/setup-cluster.sh`, step 1b).
- **Idle codespace shutdown:** all containers exited at the same moment with code 255, and the BuildKit
  cache was corrupted (`parent snapshot ... not found`). Fix: `docker builder prune -af`.

Screenshots: [ping and iptables](../screenshots/05-incident-iptables.png),
[DNS in a kind node](../screenshots/04-k8s-dns-imagepull.png).
