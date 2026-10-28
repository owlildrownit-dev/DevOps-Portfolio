-- Топ запросов по суммарному времени выполнения (pg_stat_statements, PostgreSQL 13+).
SELECT
    calls,
    round(total_exec_time::numeric, 0)                          AS total_ms,
    round(mean_exec_time::numeric, 3)                           AS mean_ms,
    round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 1) AS pct_time,
    shared_blks_hit + shared_blks_read                          AS blocks_touched,
    regexp_replace(left(query, 70), '\s+', ' ', 'g')           AS query
FROM pg_stat_statements
WHERE query NOT ILIKE '%pg_stat_statements%'
  AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 5;
