# syntax=docker/dockerfile:1
# Multi-stage build.
#   Стадия build: компилятор + libpq-dev, собираем wheel-файлы зависимостей.
#   Итоговая стадия: только runtime-библиотека libpq5 и готовые wheel-файлы.

# ---------- стадия сборки ----------
FROM python:3.12-slim AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential libpq-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ---------- итоговый образ ----------
FROM python:3.12-slim

# libpq5: клиентская библиотека, нужна psycopg2 во время работы (без -dev пакетов)
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 app

WORKDIR /app

# wheel-файлы подключаются из стадии build только на время RUN (BuildKit bind mount),
# поэтому сами .whl в слои итогового образа не попадают
RUN --mount=type=bind,from=build,source=/wheels,target=/wheels \
    pip install --no-cache-dir /wheels/*.whl

# код копируем последним: правка кода не сбрасывает кэш слоя с зависимостями
COPY app.py .

USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz')"
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app:app"]
