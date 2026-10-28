"""orders-api: a small service used throughout this lab.

Endpoints:
  GET /healthz                 liveness: the process is up and responding
  GET /readyz                  readiness: the PostgreSQL connection works
  GET /customers/<id>/orders   a customer's 20 most recent orders (the query from benchmarks/postgres-cpu)
"""
import os

import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://shop:shop@localhost:5432/shop")
APP_VERSION = os.environ.get("APP_VERSION", "dev")


def get_conn():
    return psycopg2.connect(DATABASE_URL, connect_timeout=2)


@app.get("/healthz")
def healthz():
    return jsonify(status="ok", version=APP_VERSION)


@app.get("/readyz")
def readyz():
    try:
        with get_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
        return jsonify(status="ready")
    except psycopg2.Error as exc:
        return jsonify(status="not ready", error=str(exc).strip()), 503


@app.get("/customers/<int:customer_id>/orders")
def customer_orders(customer_id: int):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT id, status, amount, created_at
               FROM orders WHERE customer_id = %s
               ORDER BY created_at DESC LIMIT 20""",
            (customer_id,),
        )
        rows = [
            {"id": r[0], "status": r[1], "amount": float(r[2]), "created_at": r[3].isoformat()}
            for r in cur.fetchall()
        ]
    return jsonify(customer_id=customer_id, orders=rows)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
