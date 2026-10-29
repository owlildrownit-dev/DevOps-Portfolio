#!/usr/bin/env python3
"""Builds REPORT.md from the output of run.sh. Every number comes from the files in results/.

Usage: report.py RESULTS_DIR DURATION RATE CLIENTS PG_VERSION NCPU
Set REPORT_GENERATED_AT to override the timestamp (e.g. when re-rendering an old run).
"""
import os
import re
import sys
from datetime import datetime
from pathlib import Path

res = Path(sys.argv[1])
duration = int(sys.argv[2])
rate = int(sys.argv[3])
clients = int(sys.argv[4])
pg_version = sys.argv[5]
ncpu = int(sys.argv[6])
generated_at = os.environ.get("REPORT_GENERATED_AT") or f"{datetime.now():%Y-%m-%d %H:%M}"


def pgbench_stats(phase):
    text = (res / f"pgbench_{phase}.txt").read_text()

    def grab(pattern):
        m = re.search(pattern, text)
        return float(m.group(1)) if m else None

    return {
        "tx": grab(r"number of transactions actually processed: (\d+)"),
        "tps": grab(r"tps = ([\d.]+)"),
        "lat": grab(r"latency average = ([\d.]+) ms"),
        "lag": grab(r"rate limit schedule lag: avg ([\d.]+)"),
    }


phases = {}
for p in ("before", "after"):
    s = pgbench_stats(p)
    s["cpu_sec"] = float((res / f"cpu_seconds_{p}.txt").read_text().strip())
    s["cores"] = s["cpu_sec"] / duration
    s["pct_one_core"] = 100 * s["cores"]
    s["pct_host"] = 100 * s["cores"] / ncpu
    s["cpu_ms_per_tx"] = 1000 * s["cpu_sec"] / s["tx"]
    phases[p] = s

b, a = phases["before"], phases["after"]
reduction = 100 * (b["cpu_sec"] - a["cpu_sec"]) / b["cpu_sec"]
reduction_norm = 100 * (b["cpu_ms_per_tx"] - a["cpu_ms_per_tx"]) / b["cpu_ms_per_tx"]
tx_diff = 100 * abs(b["tx"] - a["tx"]) / b["tx"]

# A run that could not sustain the target rate saw a different load than the other one
warnings = []
for name, s in (("before", b), ("after", a)):
    if s["tps"] is not None and s["tps"] < 0.95 * rate:
        warnings.append(f"- The \"{name}\" run reached only {s['tps']:.2f} TPS against a target of {rate}. "
                        "The database is overloaded; lower RATE.")
    if s["lag"] is not None and s["lag"] > 100:
        warnings.append(f"- The \"{name}\" run had an average schedule lag of {s['lag']:.0f} ms. "
                        "Requests are queuing up; lower RATE.")
validity = ("**Comparable load:** both runs sustained the target rate."
            if not warnings else "**WARNING, the comparison is invalid:**\n\n" + "\n".join(warnings))


def f(x, nd=1):
    return "n/a" if x is None else f"{x:,.{nd}f}"


def block(name):
    return (res / name).read_text().rstrip()


report = f"""# Report: PostgreSQL CPU usage before and after optimization

Generated on {generated_at} by `run.sh`. Measured on a test environment with synthetic data.

## Test conditions

| Parameter | Value |
| --- | --- |
| Version | {pg_version} |
| Host CPUs | {ncpu} |
| Data | 200,000 customers, 2,000,000 orders |
| Load | pgbench, fixed rate of {rate} TPS, {clients} clients, {duration} s per run |
| CPU accounting | CPU time of all cluster processes from /proc/&lt;pid&gt;/stat |

## Results

| Metric | Before | After |
| --- | --- | --- |
| Transactions processed | {f(b['tx'], 0)} | {f(a['tx'], 0)} |
| Actual TPS | {f(b['tps'], 2)} | {f(a['tps'], 2)} |
| Average latency, ms | {f(b['lat'], 3)} | {f(a['lat'], 3)} |
| pgbench schedule lag, ms | {f(b['lag'], 3)} | {f(a['lag'], 3)} |
| Cluster CPU time, s | {f(b['cpu_sec'], 2)} | {f(a['cpu_sec'], 2)} |
| Average load, % of one core | {f(b['pct_one_core'])} | {f(a['pct_one_core'])} |
| Average load, % of the host ({ncpu} CPUs) | {f(b['pct_host'])} | {f(a['pct_host'])} |
| CPU per transaction, ms | {f(b['cpu_ms_per_tx'], 3)} | {f(a['cpu_ms_per_tx'], 3)} |

**CPU reduction:** ({f(b['cpu_sec'], 2)} - {f(a['cpu_sec'], 2)}) / {f(b['cpu_sec'], 2)} × 100 = **{f(reduction)}%**.

{validity}

**Comparability check:** the transaction counts of the two runs differ by {f(tx_diff, 2)}%.
Normalized reduction (CPU per transaction): **{f(reduction_norm)}%**.

## Top queries (pg_stat_statements)

Before the optimization:

```
{block('top_queries_before.txt')}
```

After the optimization:

```
{block('top_queries_after.txt')}
```

## Query plans

Before (`explain_before.txt`):

```
{block('explain_before.txt')}
```

After (`explain_after.txt`):

```
{block('explain_after.txt')}
```
"""

(res / "REPORT.md").write_text(report)
print(f"CPU: before {b['cpu_sec']:.2f}s, after {a['cpu_sec']:.2f}s, reduction {reduction:.1f}%")
