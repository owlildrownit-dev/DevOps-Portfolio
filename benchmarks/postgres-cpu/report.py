#!/usr/bin/env python3
"""Собирает REPORT.md из результатов run.sh. Все числа берутся из файлов в results/."""
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
    # средняя загрузка в "ядрах": процессорные секунды / секунды прогона
    s["cores"] = s["cpu_sec"] / duration
    s["pct_one_core"] = 100 * s["cores"]
    s["pct_host"] = 100 * s["cores"] / ncpu
    s["cpu_ms_per_tx"] = 1000 * s["cpu_sec"] / s["tx"]
    phases[p] = s

b, a = phases["before"], phases["after"]
reduction = 100 * (b["cpu_sec"] - a["cpu_sec"]) / b["cpu_sec"]
reduction_norm = 100 * (b["cpu_ms_per_tx"] - a["cpu_ms_per_tx"]) / b["cpu_ms_per_tx"]
tx_diff = 100 * abs(b["tx"] - a["tx"]) / b["tx"]

# Если база не успевает за заданным rate, нагрузка в прогонах разная и сравнение некорректно
warnings = []
for name, s in (("до", b), ("после", a)):
    if s["tps"] is not None and s["tps"] < 0.95 * rate:
        warnings.append(f"- Прогон «{name}»: фактический TPS {s['tps']:.2f} ниже заданного {rate}. "
                        "База перегружена, уменьшите RATE.")
    if s["lag"] is not None and s["lag"] > 100:
        warnings.append(f"- Прогон «{name}»: средняя задержка расписания {s['lag']:.0f} мс. "
                        "Запросы копятся в очереди, уменьшите RATE.")
validity = ("**Нагрузка сопоставима:** оба прогона выдержали заданный rate."
            if not warnings else "**ВНИМАНИЕ, сравнение некорректно:**\n\n" + "\n".join(warnings))


def f(x, nd=1):
    return "н/д" if x is None else f"{x:,.{nd}f}".replace(",", " ")


def block(name):
    return (res / name).read_text().rstrip()


report = f"""# Отчет: нагрузка CPU PostgreSQL до и после оптимизации

Сгенерирован {datetime.now():%Y-%m-%d %H:%M} скриптом `run.sh`. Замер на тестовом стенде
с синтетическими данными.

## Условия прогона

| Параметр | Значение |
| --- | --- |
| Версия | {pg_version} |
| CPU на хосте | {ncpu} |
| Данные | 200 000 клиентов, 2 000 000 заказов |
| Нагрузка | pgbench, фиксированный rate {rate} TPS, {clients} клиента, {duration} с на прогон |
| Что считается CPU | процессорное время всех процессов кластера по /proc/&lt;pid&gt;/stat |

## Результат

| Показатель | До | После |
| --- | --- | --- |
| Выполнено транзакций | {f(b['tx'], 0)} | {f(a['tx'], 0)} |
| Фактический TPS | {f(b['tps'], 2)} | {f(a['tps'], 2)} |
| Средняя задержка, мс | {f(b['lat'], 3)} | {f(a['lat'], 3)} |
| Задержка расписания pgbench (lag), мс | {f(b['lag'], 3)} | {f(a['lag'], 3)} |
| Процессорное время кластера, с | {f(b['cpu_sec'], 2)} | {f(a['cpu_sec'], 2)} |
| Средняя загрузка, % одного ядра | {f(b['pct_one_core'])} | {f(a['pct_one_core'])} |
| Средняя загрузка, % всего хоста ({ncpu} CPU) | {f(b['pct_host'])} | {f(a['pct_host'])} |
| CPU на транзакцию, мс | {f(b['cpu_ms_per_tx'], 3)} | {f(a['cpu_ms_per_tx'], 3)} |

**Снижение CPU:** ({f(b['cpu_sec'], 2)} - {f(a['cpu_sec'], 2)}) / {f(b['cpu_sec'], 2)} × 100 = **{f(reduction)}%**.

{validity}

**Проверка сопоставимости:** число транзакций в прогонах отличается на {f(tx_diff, 2)}%.
Нормированное снижение (CPU на одну транзакцию): **{f(reduction_norm)}%**.

## Какие запросы нагружали базу (pg_stat_statements)

До оптимизации:

```
{block('top_queries_before.txt')}
```

После оптимизации:

```
{block('top_queries_after.txt')}
```

## Планы запросов

До (`explain_before.txt`):

```
{block('explain_before.txt')}
```

После (`explain_after.txt`):

```
{block('explain_after.txt')}
```
"""

(res / "REPORT.md").write_text(report)
print(f"CPU: before {b['cpu_sec']:.2f}s, after {a['cpu_sec']:.2f}s, reduction {reduction:.1f}%")
