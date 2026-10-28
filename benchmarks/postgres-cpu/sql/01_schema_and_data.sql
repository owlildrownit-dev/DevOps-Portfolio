-- Демо-схема интернет-магазина: клиенты и заказы.
-- Данные синтетические, генерируются через generate_series, поэтому повторяемы.

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

-- setseed делает данные одинаковыми при каждом запуске
SELECT setseed(0.42);

-- 200 000 клиентов. email в смешанном регистре: так часто бывает,
-- когда регистрация не нормализует ввод
INSERT INTO customers (id, email, full_name, created_at)
SELECT g,
       CASE WHEN g % 3 = 0 THEN 'User' || g || '@Example.org'
            ELSE 'user' || g || '@example.org' END,
       'Customer ' || g,
       now() - (random() * interval '1000 days')
FROM generate_series(1, 200000) AS g;

-- 2 000 000 заказов
INSERT INTO orders (id, customer_id, status, amount, created_at)
SELECT g,
       1 + floor(random() * 200000)::bigint,
       (ARRAY['new','paid','shipped','delivered','cancelled'])[1 + floor(random() * 5)::int],
       round((random() * 500)::numeric, 2),
       now() - (random() * interval '365 days')
FROM generate_series(1, 2000000) AS g;

-- Исходное состояние: индекс по email есть, но обычный,
-- а запрос приложения ищет через lower(email), поэтому индекс не используется.
CREATE INDEX customers_email_idx ON customers (email);

VACUUM ANALYZE customers;
VACUUM ANALYZE orders;
