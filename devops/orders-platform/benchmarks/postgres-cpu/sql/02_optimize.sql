-- Same column order as the query: removes both the full scan and the sort.
-- CONCURRENTLY avoids blocking writes.
CREATE INDEX CONCURRENTLY IF NOT EXISTS orders_customer_created_idx
    ON orders (customer_id, created_at DESC);

-- Must match the lower(email) expression used by the query
CREATE INDEX CONCURRENTLY IF NOT EXISTS customers_email_lower_idx
    ON customers (lower(email));

-- The old email index is kept: drop it only after checking pg_stat_user_indexes

ANALYZE orders;
ANALYZE customers;
