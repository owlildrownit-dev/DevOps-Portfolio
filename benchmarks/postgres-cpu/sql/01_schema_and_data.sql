-- Sample online store schema: customers and orders.
-- The data is synthetic and generated with generate_series, so it is reproducible.

DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    id          bigint PRIMARY KEY,
    email       text   NOT NULL,
    full_name   text   NOT NULL,
    created_at  timestamptz NOT NULL
);

CREATE TABLE orders (
    id           bigint PRIMARY KEY,
    customer_id  bigint NOT NULL REFERENCES customers(id),
    status       text   NOT NULL,
    amount       numeric(12,2) NOT NULL,
    created_at   timestamptz NOT NULL
);

-- setseed makes the data identical on every run
SELECT setseed(0.42);

-- 200,000 customers. Emails use mixed case, which is common
-- when sign-up does not normalize input
INSERT INTO customers (id, email, full_name, created_at)
SELECT g,
       CASE WHEN g % 3 = 0 THEN 'User' || g || '@Example.org'
            ELSE 'user' || g || '@example.org' END,
       'Customer ' || g,
       now() - (random() * interval '1000 days')
FROM generate_series(1, 200000) AS g;

-- 2,000,000 orders
INSERT INTO orders (id, customer_id, status, amount, created_at)
SELECT g,
       1 + floor(random() * 200000)::bigint,
       (ARRAY['new','paid','shipped','delivered','cancelled'])[1 + floor(random() * 5)::int],
       round((random() * 500)::numeric, 2),
       now() - (random() * interval '365 days')
FROM generate_series(1, 2000000) AS g;

-- Initial state: there is a plain index on email,
-- but the application searches by lower(email), so the index is not used.
CREATE INDEX customers_email_idx ON customers (email);

VACUUM ANALYZE customers;
VACUUM ANALYZE orders;
