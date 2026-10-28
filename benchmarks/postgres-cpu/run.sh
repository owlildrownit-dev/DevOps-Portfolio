#!/usr/bin/env bash
# Benchmark: PostgreSQL CPU usage before and after query optimization.
#
# Method:
#   - pgbench applies the SAME load in both runs (fixed rate, -R),
#     so both runs execute a comparable number of queries;
#   - CPU time is read from kernel counters (/proc/<pid>/stat) for every process
#     of the PostgreSQL cluster: the postmaster, its live child processes and
#     its already finished children (the cutime/cstime fields);
#   - pg_stat_statements shows which queries consume the time.
#
# Run it as a NON-root user (initdb refuses to run as root), for example
#   ./run.sh
# Parameters are taken from environment variables (defaults below).

set -euo pipefail

# PostgreSQL binaries: the newest installed version (13+ is required)
PG_BIN="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
[[ -x "$PG_BIN/initdb" ]] || { echo "PostgreSQL (initdb) not found. Run scripts/setup-tools.sh or set PG_BIN"; exit 1; }
[[ $(id -u) -ne 0 ]] || { echo "Run as a regular user: initdb refuses to run as root"; exit 1; }
USER="${USER:-$(id -un)}"
PGPORT="${PGPORT:-55432}"
LAB_DIR="${LAB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
DATA_DIR="${DATA_DIR:-$LAB_DIR/.pgdata}"
RESULTS="${RESULTS:-$LAB_DIR/results}"
RATE="${RATE:-5}"           # transactions per second, identical for both runs.
                            # Choose it so that the "before" database is NOT CPU-bound;
                            # otherwise it cannot sustain the rate and the comparison is invalid
                            # (report.py checks this and prints a warning)
DURATION="${DURATION:-120}" # seconds per run
CLIENTS="${CLIENTS:-4}"
DB=shop

export PGPORT PGHOST=/tmp PGDATABASE=$DB
PSQL=("$PG_BIN/psql" -X -q -v ON_ERROR_STOP=1)
CLK_TCK=$(getconf CLK_TCK)

mkdir -p "$RESULTS"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---------- 1. Cluster ----------
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

# ---------- 2. Data (every run starts from scratch) ----------
log "Creating database $DB and loading data (2M orders, ~1-2 min)"
"${PSQL[@]}" -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
"${PSQL[@]}" -c "CREATE EXTENSION pg_stat_statements"
"${PSQL[@]}" -f "$LAB_DIR/sql/01_schema_and_data.sql" >/dev/null

# ---------- measurement helpers ----------
# Total CPU time of the cluster, in kernel clock ticks
cluster_ticks() {
  local total pid
  # postmaster: its own time plus the time of its finished children
  total=$(sed 's/^.*) //' "/proc/$PM_PID/stat" | awk '{print $12+$13+$14+$15}')
  # live child processes (backends, checkpointer, autovacuum, etc.)
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
  # warm up the cache so that both runs read data from memory
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

# ---------- 3. Before ----------
run_phase before

# ---------- 4. Optimization ----------
log "Applying the optimization (sql/02_optimize.sql)"
"${PSQL[@]}" -f "$LAB_DIR/sql/02_optimize.sql" >/dev/null

# ---------- 5. After ----------
run_phase after

# ---------- 6. Report ----------
python3 "$LAB_DIR/report.py" "$RESULTS" "$DURATION" "$RATE" "$CLIENTS" \
  "$("$PG_BIN/postgres" --version)" "$(nproc)"
log "Done: $RESULTS/REPORT.md"
