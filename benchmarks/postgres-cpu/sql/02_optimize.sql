-- Оптимизация по результатам pg_stat_statements и EXPLAIN (ANALYZE, BUFFERS).

-- Запрос 1 фильтрует по customer_id и сортирует по created_at DESC.
-- Составной индекс в том же порядке убирает и полное сканирование, и сортировку.
-- CONCURRENTLY: индекс строится без блокировки записи в таблицу (важно на проде).
CREATE INDEX CONCURRENTLY IF NOT EXISTS orders_customer_created_idx
    ON orders (customer_id, created_at DESC);

-- Запрос 2 ищет по lower(email). Обычный индекс по email для него бесполезен,
-- нужен индекс по выражению, совпадающему с условием в запросе.
CREATE INDEX CONCURRENTLY IF NOT EXISTS customers_email_lower_idx
    ON customers (lower(email));

-- Старый индекс больше не используется приложением, но удалять его
-- стоит только после проверки pg_stat_user_indexes на проде. Здесь оставляем.

ANALYZE orders;
ANALYZE customers;
