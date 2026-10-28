# Размер образов orders-api

Замер: 2026-10-28 17:18, Docker 29.8.0-1

| Образ | Размер, байт | Размер, МБ | Сборка с нуля, с |
| --- | --- | --- | --- |
| orders-api:before | 738410763 | 704.2 | 60 |
| orders-api:after | 207651183 | 198.0 | 53 |

Уменьшение: (738410763 - 207651183) / 738410763 × 100 = **71.9%**

Проверки образа after: gcc в образе: нет; импорт приложения: ok

## Слои before (docker history)
```
SIZE      CREATED BY
0B        CMD ["gunicorn" "--bind" "0.0.0.0:8000" "--workers" "2" "app:app"]
0B        EXPOSE [8000/tcp]
23.1MB    RUN /bin/sh -c pip install -r requirements.txt # buildkit
389MB     RUN /bin/sh -c apt-get update && apt-get install -y build-essential libpq-dev # buildkit
16.4kB    COPY . . # buildkit
8.19kB    WORKDIR /app
0B        CMD ["python3"]
16.4kB    RUN /bin/sh -c set -eux;  for src in idle3 pip3 pydoc3 python3 python3-config; do   dst="$(echo "$src" | tr -d 3)";   [ -s "/usr/l
41.4MB    RUN /bin/sh -c set -eux;   savedAptMark="$(apt-mark showmanual)";  apt-get update;  apt-get install -y --no-install-recommends   d
0B        ENV PYTHON_SHA256=b5796915dc45ff745cfb4e990a7e7c93d6f546328a102ce31448d69ebc37575c
0B        ENV PYTHON_VERSION=3.12.16
0B        ENV GPG_KEY=7169605F62C751356D054A26A821E680E5FA6305
4.93MB    RUN /bin/sh -c set -eux;  apt-get update;  apt-get install -y --no-install-recommends   ca-certificates   netbase   tzdata  ;  apt
0B        ENV LANG=C.UTF-8
0B        ENV PATH=/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
87.7MB    # debian.sh --arch 'amd64' out/ 'trixie' '@1793059200'
```

## Слои after (docker history)
```
SIZE      CREATED BY
0B        CMD ["gunicorn" "--bind" "0.0.0.0:8000" "--workers" "2" "app:app"]
0B        HEALTHCHECK {Test:[CMD-SHELL python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz')"] Interval:
0B        EXPOSE [8000/tcp]
0B        USER app
12.3kB    COPY app.py . # buildkit
18.9MB    RUN /bin/sh -c pip install --no-cache-dir /wheels/*.whl # buildkit
8.19kB    WORKDIR /app
3.9MB     RUN /bin/sh -c apt-get update  && apt-get install -y --no-install-recommends libpq5  && rm -rf /var/lib/apt/lists/*  && useradd --
0B        CMD ["python3"]
16.4kB    RUN /bin/sh -c set -eux;  for src in idle3 pip3 pydoc3 python3 python3-config; do   dst="$(echo "$src" | tr -d 3)";   [ -s "/usr/l
41.4MB    RUN /bin/sh -c set -eux;   savedAptMark="$(apt-mark showmanual)";  apt-get update;  apt-get install -y --no-install-recommends   d
0B        ENV PYTHON_SHA256=b5796915dc45ff745cfb4e990a7e7c93d6f546328a102ce31448d69ebc37575c
0B        ENV PYTHON_VERSION=3.12.16
0B        ENV GPG_KEY=7169605F62C751356D054A26A821E680E5FA6305
4.93MB    RUN /bin/sh -c set -eux;  apt-get update;  apt-get install -y --no-install-recommends   ca-certificates   netbase   tzdata  ;  apt
0B        ENV LANG=C.UTF-8
0B        ENV PATH=/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
87.7MB    # debian.sh --arch 'amd64' out/ 'trixie' '@1793059200'
```
