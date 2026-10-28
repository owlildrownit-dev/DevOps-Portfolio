-- Идемпотентная миграция: можно запускать при каждой выкладке.
CREATE TABLE IF NOT EXISTS customers (
    id          bigint PRIMARY KEY,
    email       text   NOT NULL,
    full_name   text   NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
    id           bigint PRIMARY KEY,
    customer_id  bigint NOT NULL REFERENCES customers(id),
    status       text   NOT NULL,
    amount       numeric(12,2) NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- Индексы из 03-postgres-cpu
CREATE INDEX IF NOT EXISTS orders_customer_created_idx ON orders (customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS customers_email_lower_idx  ON customers (lower(email));

-- Демо-данные только если таблицы пустые
INSERT INTO customers (id, email, full_name)
SELECT g, 'user' || g || '@example.org', 'Customer ' || g
FROM generate_series(1, 1000) g
WHERE NOT EXISTS (SELECT 1 FROM customers);

INSERT INTO orders (id, customer_id, status, amount, created_at)
SELECT g, 1 + (g % 1000), (ARRAY['new','paid','shipped'])[1 + g % 3],
       round((random() * 500)::numeric, 2), now() - (g || ' minutes')::interval
FROM generate_series(1, 20000) g
WHERE NOT EXISTS (SELECT 1 FROM orders);
