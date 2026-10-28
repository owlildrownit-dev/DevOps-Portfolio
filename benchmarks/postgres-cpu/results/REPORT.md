# Отчет: нагрузка CPU PostgreSQL до и после оптимизации

Сгенерирован 2026-10-28 17:12 скриптом `run_lab.sh`. Это замер на **демо-стенде**
с синтетическими данными, а не данные production.

## Условия прогона

| Параметр | Значение |
| --- | --- |
| Версия | postgres (PostgreSQL) 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1) |
| CPU на хосте | 2 |
| Данные | 200 000 клиентов, 2 000 000 заказов |
| Нагрузка | pgbench, фиксированный rate 3 TPS, 4 клиента, 120 с на прогон |
| Что считается CPU | процессорное время всех процессов кластера по /proc/&lt;pid&gt;/stat |

## Результат

| Показатель | До | После |
| --- | --- | --- |
| Выполнено транзакций | 384 | 360 |
| Фактический TPS | 3.20 | 3.01 |
| Средняя задержка, мс | 393.806 | 0.997 |
| Задержка расписания pgbench (lag), мс | 53.410 | 0.135 |
| Процессорное время кластера, с | 125.09 | 0.43 |
| Средняя загрузка, % одного ядра | 104.2 | 0.4 |
| Средняя загрузка, % всего хоста (2 CPU) | 52.1 | 0.2 |
| CPU на транзакцию, мс | 325.755 | 1.194 |

**Снижение CPU:** (125.09 - 0.43) / 125.09 × 100 = **99.7%**.

**Нагрузка сопоставима:** оба прогона выдержали заданный rate.

**Проверка сопоставимости:** число транзакций в прогонах отличается на 6.25%.
Нормированное снижение (CPU на одну транзакцию): **99.6%**.

## Какие запросы нагружали базу (pg_stat_statements)

До оптимизации:

```
 calls | total_ms | mean_ms | pct_time | blocks_touched |                                 query                                  
-------+----------+---------+----------+----------------+------------------------------------------------------------------------
   384 |    75564 | 196.781 |     58.1 |        6760860 | SELECT id, status, amount, created_at FROM orders WHERE customer_id = 
   384 |    54374 | 141.599 |     41.8 |         791808 | SELECT id, full_name FROM customers WHERE lower(email) = lower($1 || $
     1 |       99 |  98.874 |      0.1 |          17493 | SELECT count(*) FROM orders
     1 |       10 |   9.767 |      0.0 |           2062 | SELECT count(*) FROM customers
   384 |        9 |   0.023 |      0.0 |           1548 | SELECT id, status, amount FROM orders WHERE id = $1 * $2
(5 rows)
```

После оптимизации:

```
 calls | total_ms | mean_ms | pct_time | blocks_touched |                                 query                                  
-------+----------+---------+----------+----------------+------------------------------------------------------------------------
     1 |      106 | 105.899 |     57.5 |          17493 | SELECT count(*) FROM orders
   360 |       48 |   0.135 |     26.3 |           4727 | SELECT id, status, amount, created_at FROM orders WHERE customer_id = 
     1 |       11 |  11.233 |      6.1 |           2062 | SELECT count(*) FROM customers
   360 |       11 |   0.030 |      5.8 |           1440 | SELECT id, full_name FROM customers WHERE lower(email) = lower($1 || $
   360 |        8 |   0.022 |      4.3 |           1440 | SELECT id, status, amount FROM orders WHERE id = $1 * $2
(5 rows)
```

## Планы запросов

До (`explain_before.txt`):

```
### Запрос 1: история заказов клиента
                                         QUERY PLAN                                         
--------------------------------------------------------------------------------------------
 Limit (actual time=156.608..163.737 rows=9 loops=1)
   Buffers: shared hit=17607
   ->  Gather Merge (actual time=156.607..163.734 rows=9 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=17607
         ->  Sort (actual time=126.712..126.713 rows=3 loops=3)
               Sort Key: created_at DESC
               Sort Method: quicksort  Memory: 25kB
               Buffers: shared hit=17607
               Worker 0:  Sort Method: quicksort  Memory: 25kB
               Worker 1:  Sort Method: quicksort  Memory: 25kB
               ->  Parallel Seq Scan on orders (actual time=32.543..126.617 rows=3 loops=3)
                     Filter: (customer_id = 4242)
                     Rows Removed by Filter: 666664
                     Buffers: shared hit=17493
 Planning:
   Buffers: shared hit=89
 Planning Time: 0.550 ms
 Execution Time: 163.813 ms
(20 rows)


### Запрос 2: поиск клиента по email
                                    QUERY PLAN                                    
----------------------------------------------------------------------------------
 Gather (actual time=2.947..72.546 rows=1 loops=1)
   Workers Planned: 1
   Workers Launched: 1
   Buffers: shared hit=2062
   ->  Parallel Seq Scan on customers (actual time=34.007..67.311 rows=0 loops=2)
         Filter: (lower(email) = 'user4242@example.org'::text)
         Rows Removed by Filter: 100000
         Buffers: shared hit=2062
 Planning:
   Buffers: shared hit=81
 Planning Time: 0.357 ms
 Execution Time: 72.582 ms
(12 rows)
```

После (`explain_after.txt`):

```
### Запрос 1: история заказов клиента
                                                  QUERY PLAN                                                  
--------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.199..0.201 rows=9 loops=1)
   Buffers: shared hit=18
   ->  Sort (actual time=0.198..0.199 rows=9 loops=1)
         Sort Key: created_at DESC
         Sort Method: quicksort  Memory: 25kB
         Buffers: shared hit=18
         ->  Bitmap Heap Scan on orders (actual time=0.063..0.159 rows=9 loops=1)
               Recheck Cond: (customer_id = 4242)
               Heap Blocks: exact=9
               Buffers: shared hit=15
               ->  Bitmap Index Scan on orders_customer_created_idx (actual time=0.043..0.043 rows=9 loops=1)
                     Index Cond: (customer_id = 4242)
                     Buffers: shared hit=6
 Planning:
   Buffers: shared hit=116 read=1
   I/O Timings: shared read=0.016
 Planning Time: 0.726 ms
 Execution Time: 0.256 ms
(18 rows)


### Запрос 2: поиск клиента по email
                                            QUERY PLAN                                             
---------------------------------------------------------------------------------------------------
 Index Scan using customers_email_lower_idx on customers (actual time=0.033..0.033 rows=1 loops=1)
   Index Cond: (lower(email) = 'user4242@example.org'::text)
   Buffers: shared hit=4
 Planning:
   Buffers: shared hit=102 read=1
   I/O Timings: shared read=0.014
 Planning Time: 0.428 ms
 Execution Time: 0.057 ms
(8 rows)
```
