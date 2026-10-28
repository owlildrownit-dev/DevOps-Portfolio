#!/usr/bin/env bash
# PostgreSQL CPU time before and after query optimization under the same fixed-rate load.
# Method: README.md. Run as a non-root user.

set -euo pipefail

PG_BIN="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
[[ -x "$PG_BIN/initdb" ]] || { echo "PostgreSQL (initdb) not found. Run scripts/setup-tools.sh or set PG_BIN"; exit 1; }
[[ $(id -u) -ne 0 ]] || { echo "Run as a regular user: initdb refuses to run as root"; exit 1; }
USER="${USER:-$(id -un)}"
PGPORT="${PGPORT:-55432}"
LAB_DIR="${LAB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
DATA_DIR="${DATA_DIR:-$LAB_DIR/.pgdata}"
RESULTS="${RESULTS:-$LAB_DIR/results}"
RATE="${RATE:-5}"           # must not saturate the unoptimized DB, or the comparison is invalid
DURATION="${DURATION:-120}"
CLIENTS="${CLIENTS:-4}"
DB=shop

export PGPORT PGHOST=/tmp PGDATABASE=$DB
PSQL=("$PG_BIN/psql" -X -q -v ON_ERROR_STOP=1)
CLK_TCK=$(getconf CLK_TCK)

mkdir -p "$RESULTS"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

if [[ ! -f "$DATA_DIR/PG_VERSION" ]]; then
  log "initdb in $DATA_DIR"
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

log "Creating database $DB and loading data (2M orders, ~1-2 min)"
"${PSQL[@]}" -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
"${PSQL[@]}" -c "CREATE EXTENSION pg_stat_statements"
"${PSQL[@]}" -f "$LAB_DIR/sql/01_schema_and_data.sql" >/dev/null

# Cluster CPU ticks: postmaster incl. reaped children (cutime/cstime) plus live children
cluster_ticks() {
  local total pid
  total=$(sed 's/^.*) //' "/proc/$PM_PID/stat" | awk '{print $12+$13+$14+$15}')
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
    echo "### Query 1: customer order history"
    "${PSQL[@]}" -c "EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
      SELECT id, status, amount, created_at FROM orders
      WHERE customer_id = 4242 ORDER BY created_at DESC LIMIT 20;"
    echo
    echo "### Query 2: customer lookup by email"
    "${PSQL[@]}" -c "EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
      SELECT id, full_name FROM customers
      WHERE lower(email) = lower('user4242@example.org');"
  } > "$out"
}

run_phase() {
  local phase=$1
  log "Phase '$phase': EXPLAIN, statistics reset, ${DURATION}s run at $RATE TPS"
  explain_queries "$RESULTS/explain_$phase.txt"
  "${PSQL[@]}" -c "SELECT pg_stat_statements_reset()" >/dev/null
  "${PSQL[@]}" -c "SELECT count(*) FROM orders" -c "SELECT count(*) FROM customers" >/dev/null

  local t0 t1
  t0=$(cluster_ticks)
  "$PG_BIN/pgbench" -n -f "$LAB_DIR/sql/workload.pgbench" \
      -c "$CLIENTS" -j 2 -R "$RATE" -T "$DURATION" "$DB" > "$RESULTS/pgbench_$phase.txt" 2>&1
  sleep 2   # give the postmaster time to reap finished backends
  t1=$(cluster_ticks)

  "${PSQL[@]}" -P pager=off -f "$LAB_DIR/sql/top_queries.sql" > "$RESULTS/top_queries_$phase.txt"

  local cpu_sec
  cpu_sec=$(awk -v d=$((t1 - t0)) -v hz="$CLK_TCK" 'BEGIN{printf "%.2f", d/hz}')
  echo "$cpu_sec" > "$RESULTS/cpu_seconds_$phase.txt"
  log "  Cluster CPU time for the run: ${cpu_sec}s"
}

run_phase before

log "Applying the optimization (sql/02_optimize.sql)"
"${PSQL[@]}" -f "$LAB_DIR/sql/02_optimize.sql" >/dev/null

run_phase after

python3 "$LAB_DIR/report.py" "$RESULTS" "$DURATION" "$RATE" "$CLIENTS" \
  "$("$PG_BIN/postgres" --version)" "$(nproc)"
log "Done: $RESULTS/REPORT.md"
