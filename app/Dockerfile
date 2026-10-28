# syntax=docker/dockerfile:1
# Multi-stage build.
#   build stage: compiler and libpq-dev, builds wheels for all dependencies.
#   final stage: only the libpq5 runtime library and the prebuilt wheels.

# ---------- build stage ----------
FROM python:3.12-slim AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential libpq-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ---------- final image ----------
FROM python:3.12-slim

# libpq5: the client library psycopg2 needs at runtime (no -dev packages)
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 app

WORKDIR /app

# The wheels are mounted from the build stage only for this RUN (BuildKit bind mount),
# so the .whl files never end up in a layer of the final image
RUN --mount=type=bind,from=build,source=/wheels,target=/wheels \
    pip install --no-cache-dir /wheels/*.whl

# Copy the code last so that code changes do not invalidate the dependency layer cache
COPY app.py .

USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz')"
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app:app"]
