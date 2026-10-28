# PostgreSQL CPU usage before and after optimization

`run.sh` starts a dedicated PostgreSQL cluster with `pg_stat_statements`, generates data
(200,000 customers and 2,000,000 orders), applies the same load before and after the optimization,
and writes a report to `results/REPORT.md`.

```bash
./run.sh                    # defaults: 5 TPS, 120 s per run
RATE=3 DURATION=300 ./run.sh
```

Run it as a regular user (`initdb` refuses to run as root).

## Method

- **Identical load:** pgbench at a fixed rate (`-R`) with the same script (`sql/workload.pgbench`).
- **CPU accounting:** CPU time of every cluster process from `/proc/<pid>/stat`
  (the postmaster, its live children, and finished children via `cutime`/`cstime`).
- **Expensive queries:** `pg_stat_statements` ordered by `total_exec_time`, plus `EXPLAIN (ANALYZE, BUFFERS)` plans.
- **Validity check:** if the actual TPS falls below the target or requests start to queue
  (lag above 100 ms), the report flags the comparison as invalid.

## Optimization (`sql/02_optimize.sql`)

| Query | Problem | Fix |
| --- | --- | --- |
| Customer order history | full scan of 2 million rows plus a sort | index on `(customer_id, created_at DESC)` |
| Customer lookup by `lower(email)` | the plain index on `email` cannot be used | expression index on `lower(email)` |

Both indexes are created `CONCURRENTLY`, without blocking writes.

## Results (GitHub Codespaces, 2026-10-28)

| Run | TPS before / after | Lag before | CPU before | CPU after | Verdict |
| --- | --- | --- | --- | --- | --- |
| 1, RATE=5 | 4.92 / 5.12 | 654 ms | 191.75 s | 0.58 s | invalid: requests queued up |
| 1, RATE=3 | 3.03 / 3.19 | 23 ms | 118.30 s | 0.39 s | comparable load |
| 2, RATE=3 ([`results/REPORT.md`](results/REPORT.md)) | 3.20 / 3.01 | 53 ms | 125.09 s | 0.43 s | comparable load |

Reduction in run 2: (125.09 − 0.43) / 125.09 × 100 ≈ 99.7%; per transaction, 99.6%.
In this test almost the entire load comes from two unoptimized queries, which is why the effect is close to 100%.

The run 2 report was re-rendered in English from the raw files of that run with the current `report.py`;
the raw files (`pgbench_*.txt`, `cpu_seconds_*.txt`, `top_queries_*.txt`, `explain_*.txt`) are unchanged
apart from the translated section headings in `explain_*.txt`.

![valid](../../docs/screenshots/03-postgres-valid-run.png)
