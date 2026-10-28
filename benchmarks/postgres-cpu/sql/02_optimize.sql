-- Optimization based on pg_stat_statements and EXPLAIN (ANALYZE, BUFFERS).

-- Query 1 filters by customer_id and sorts by created_at DESC.
-- A composite index in the same order removes both the full scan and the sort.
-- CONCURRENTLY builds the index without blocking writes (important in production).
CREATE INDEX CONCURRENTLY IF NOT EXISTS orders_customer_created_idx
    ON orders (customer_id, created_at DESC);

-- Query 2 searches by lower(email). A plain index on email cannot serve it,
-- so it needs an expression index that matches the condition in the query.
CREATE INDEX CONCURRENTLY IF NOT EXISTS customers_email_lower_idx
    ON customers (lower(email));

-- The old index is no longer used by the application, but it should only be dropped
-- after checking pg_stat_user_indexes in production. It is kept here.

ANALYZE orders;
ANALYZE customers;
