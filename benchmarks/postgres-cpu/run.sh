#!/usr/bin/env bash
# Лабораторный замер: нагрузка CPU PostgreSQL до и после оптимизации запросов.
#
# Идея замера:
#   - pgbench подает ОДИНАКОВУЮ нагрузку в обоих прогонах (фиксированный rate, -R),
#     поэтому периоды сопоставимы по числу запросов;
#   - CPU считается по счетчикам ядра (/proc/<pid>/stat) для всех процессов
#     кластера PostgreSQL: postmaster + его живые дочерние процессы +
#     уже завершенные дочерние процессы (поля cutime/cstime);
#   - какие запросы "съедают" время, показывает pg_stat_statements.
#
# Запуск: от НЕ-root пользователя (initdb не работает от root), например
#   ./run.sh
# Параметры через переменные окружения (значения по умолчанию ниже).

set -euo pipefail

# Каталог бинарников PostgreSQL: самая новая из установленных версий (нужна 13+)
PG_BIN="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
[[ -x "$PG_BIN/initdb" ]] || { echo "Не найден PostgreSQL (initdb). Запустите scripts/setup-tools.sh или задайте PG_BIN"; exit 1; }
[[ $(id -u) -ne 0 ]] || { echo "Запускайте от обычного пользователя: initdb не работает от root"; exit 1; }
USER="${USER:-$(id -un)}"
PGPORT="${PGPORT:-55432}"
LAB_DIR="${LAB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
DATA_DIR="${DATA_DIR:-$LAB_DIR/.pgdata}"
RESULTS="${RESULTS:-$LAB_DIR/results}"
RATE="${RATE:-5}"           # транзакций в секунду, одинаково для обоих прогонов.
                            # Подбирается так, чтобы база "до" НЕ упиралась в CPU:
                            # иначе она не выдержит rate и сравнение станет некорректным
                            # (report.py это проверит и напишет предупреждение)
DURATION="${DURATION:-120}" # секунд на прогон
CLIENTS="${CLIENTS:-4}"
DB=shop

export PGPORT PGHOST=/tmp PGDATABASE=$DB
PSQL=("$PG_BIN/psql" -X -q -v ON_ERROR_STOP=1)
CLK_TCK=$(getconf CLK_TCK)

mkdir -p "$RESULTS"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---------- 1. Кластер ----------
if [[ ! -f "$DATA_DIR/PG_VERSION" ]]; then
  log "initdb в $DATA_DIR"
  "$PG_BIN/initdb" -D "$DATA_DIR" -U "$USER" --auth=trust >/dev/null
  cat >> "$DATA_DIR/postgresql.conf" <<EOF
port = $PGPORT
unix_socket_directories = '/tmp'
listen_addresses = ''
shared_buffers = 512MB
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = top
track_io_timing = on
EOF
fi

"$PG_BIN/pg_ctl" -D "$DATA_DIR" -l "$RESULTS/postgres.log" -w status >/dev/null 2>&1 \
  || "$PG_BIN/pg_ctl" -D "$DATA_DIR" -l "$RESULTS/postgres.log" -w start >/dev/null
trap '"$PG_BIN/pg_ctl" -D "$DATA_DIR" -m fast stop >/dev/null 2>&1 || true' EXIT

PM_PID=$(head -1 "$DATA_DIR/postmaster.pid")

# ---------- 2. Данные (каждый запуск с чистого листа) ----------
log "Создаю базу $DB и загружаю данные (2 млн заказов, ~1-2 мин)"
"${PSQL[@]}" -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
"${PSQL[@]}" -c "CREATE EXTENSION pg_stat_statements"
"${PSQL[@]}" -f "$LAB_DIR/sql/01_schema_and_data.sql" >/dev/null

# ---------- функции замера ----------
# Суммарное процессорное время кластера в тиках ядра
cluster_ticks() {
  local total pid
  # postmaster: свое время + время уже завершенных дочерних процессов
  total=$(sed 's/^.*) //' "/proc/$PM_PID/stat" | awk '{print $12+$13+$14+$15}')
  # живые дочерние процессы (backend-ы, checkpointer, autovacuum и т.д.)
  for pid in $(pgrep -P "$PM_PID" || true); do
    if [[ -r /proc/$pid/stat ]]; then
      total=$(( total + $(sed 's/^.*) //' "/proc/$pid/stat" | awk '{print $12+$13}') ))
    fi
  done
  echo "$total"
}

explain_queries() {
  local out=$1
  {
    echo "### Запрос 1: история заказов клиента"
    "${PSQL[@]}" -c "EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
      SELECT id, status, amount, created_at FROM orders
      WHERE customer_id = 4242 ORDER BY created_at DESC LIMIT 20;"
    echo
    echo "### Запрос 2: поиск клиента по email"
    "${PSQL[@]}" -c "EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
      SELECT id, full_name FROM customers
      WHERE lower(email) = lower('user4242@example.org');"
  } > "$out"
}

run_phase() {
  local phase=$1
  log "Фаза '$phase': EXPLAIN, сброс статистики, прогон $DURATION с при $RATE TPS"
  explain_queries "$RESULTS/explain_$phase.txt"
  "${PSQL[@]}" -c "SELECT pg_stat_statements_reset()" >/dev/null
  # прогрев кэша, чтобы оба прогона читали данные из памяти
  "${PSQL[@]}" -c "SELECT count(*) FROM orders" -c "SELECT count(*) FROM customers" >/dev/null

  local t0 t1
  t0=$(cluster_ticks)
  "$PG_BIN/pgbench" -n -f "$LAB_DIR/sql/workload.pgbench" \
      -c "$CLIENTS" -j 2 -R "$RATE" -T "$DURATION" "$DB" > "$RESULTS/pgbench_$phase.txt" 2>&1
  sleep 2   # даем postmaster "подобрать" завершившиеся backend-ы
  t1=$(cluster_ticks)

  "${PSQL[@]}" -P pager=off -f "$LAB_DIR/sql/top_queries.sql" > "$RESULTS/top_queries_$phase.txt"

  local cpu_sec
  cpu_sec=$(awk -v d=$((t1 - t0)) -v hz="$CLK_TCK" 'BEGIN{printf "%.2f", d/hz}')
  echo "$cpu_sec" > "$RESULTS/cpu_seconds_$phase.txt"
  log "  CPU кластера за прогон: $cpu_sec с"
}

# ---------- 3. До ----------
run_phase before

# ---------- 4. Оптимизация ----------
log "Применяю оптимизацию (sql/02_optimize.sql)"
"${PSQL[@]}" -f "$LAB_DIR/sql/02_optimize.sql" >/dev/null

# ---------- 5. После ----------
run_phase after

# ---------- 6. Отчет ----------
python3 "$LAB_DIR/report.py" "$RESULTS" "$DURATION" "$RATE" "$CLIENTS" \
  "$("$PG_BIN/postgres" --version)" "$(nproc)"
log "Готово: $RESULTS/REPORT.md"
