#!/usr/bin/env bash
# pgbench-бенчмарк ОДНОГО варіанта: 50_benchmark.sh HOST|LAYER|VOLUME|BIND
#
# Методологія:
#  - лише один лабораторний PostgreSQL запущений під час вимірювань
#    (сторонні контейнери користувача не чіпаємо — зафіксовано як обмеження);
#  - pgbench (Homebrew 18.4) на macOS, TCP 127.0.0.1 для ВСІХ варіантів;
#  - scale=30, клієнти 1/8/32 (-j = min(c,8)), warm-up 10 c, 3 x 30 c, медіана;
#  - fsync/full_page_writes/synchronous_commit — заводські (увімкнені);
#  - disk I/O: pg_stat_io (read_bytes/write_bytes) — однакова метрика скрізь;
#  - пам'ять/CPU: docker stats для контейнерів, ps (RSS/pcpu по process group)
#    для native — НЕ повністю еквівалентні (див. звіт).
#
# Вивід: дописує в results/benchmark.csv і results/benchmark_meta.csv
set -euo pipefail
source "$(dirname "$0")/lib.sh"
VAR=${1:?usage: 50_benchmark.sh HOST|LAYER|VOLUME|BIND}
SCALE=30; DURATION=30; WARMUP=10; REPEATS=3
CSV="$LAB_ROOT/results/benchmark.csv"
META="$LAB_ROOT/results/benchmark_meta.csv"
LOG="$LAB_ROOT/results/benchmark.log"
mkdir -p "$LAB_ROOT/results"
[ -f "$CSV" ]  || echo "variant,clients,run,tps,latency_avg_ms,mem_mb,cpu_pct,io_read_mb,io_write_mb" > "$CSV"
[ -f "$META" ] || echo "variant,init_seconds,startup_ms,idle_mem_mb,db_size_mb,pgdata_mb" > "$META"
say() { echo -e "[$VAR] $*" | tee -a "$LOG"; }
now_s() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

port_of() { case "$1" in HOST) echo "$HOST_PORT";; LAYER) echo "$LAYER_PORT";; VOLUME) echo "$VOLUME_PORT";; BIND) echo "$BIND_PORT";; esac; }
PORT=$(port_of "$VAR")
CONT="pg-lab-$(echo "$VAR" | tr '[:upper:]' '[:lower:]')"   # для HOST не використовується

pgb() { # pgbench з правильною автентифікацією
  if [ "$VAR" = HOST ]; then
    "$PGBIN/pgbench" -h 127.0.0.1 -p "$PORT" -U "$(whoami)" "$@" lab
  else
    PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/pgbench" -h 127.0.0.1 -p "$PORT" -U lab "$@" lab
  fi
}

# --- пам'ять/CPU: контейнер через docker stats, native через ps по pgid ---
sample_mem_cpu() { # → "mem_mb cpu_pct"
  if [ "$VAR" = HOST ]; then
    # RSS: macOS не атрибутує спільну пам'ять (shared buffers) процесам — цифра
    # свідомо занижена, порівнювати з docker stats не можна (див. звіт).
    # CPU: миттєвий pcpu у macOS ps ненадійний — рахуємо дельту cputime за 3 с.
    # Діти постмастера на macOS створюють ВЛАСНІ process groups, тому
    # відбираємо процеси за ppid==постмастер (плюс сам постмастер).
    local pid t0 t1 mem
    pid=$(head -1 "$HOST_PGDATA/postmaster.pid")
    cputime_cs() { # сумарний CPU-час дерева процесів у сантисекундах
      ps -ax -o ppid=,pid=,time= | awk -v p="$pid" '$1==p || $2==p {
        n=split($3,t,":"); s=0; for(i=1;i<=n;i++) s=s*60+t[i]; cs+=s*100} END {printf "%.0f", cs}'
    }
    t0=$(cputime_cs); sleep 3; t1=$(cputime_cs)
    mem=$(ps -ax -o ppid=,pid=,rss= | awk -v p="$pid" '$1==p || $2==p {m+=$3} END {printf "%.0f", m/1024}')
    echo "$mem $(( (t1 - t0) / 3 ))" | awk '{printf "%.0f %.1f", $1, $2}'
  else
    docker stats --no-stream --format '{{.MemUsage}} {{.CPUPerc}}' "$CONT" \
      | awk '{mem=$1; cpu=$NF; gsub("%","",cpu);
              gib=(mem ~ /GiB/); gsub(/[A-Za-z]+/,"",mem);
              if (gib) mem*=1024;
              printf "%.0f %.1f", mem, cpu}'
  fi
}

io_reset()  { psql_port "$PORT" -tAc "SELECT pg_stat_reset_shared('io')" >/dev/null; }
io_read()   { psql_port "$PORT" -tAc "SELECT round(sum(read_bytes)/1048576.0,1), round(sum(write_bytes)/1048576.0,1) FROM pg_stat_io" | tr '|' ' '; }

stop_everything_lab() {
  "$PGBIN/pg_ctl" -D "$HOST_PGDATA" stop -m fast >/dev/null 2>&1 || true
  docker stop pg-lab-layer pg-lab-volume pg-lab-bind >/dev/null 2>&1 || true
}

start_target_timed() { # → startup_ms
  local t0 t1
  t0=$(now_s)
  if [ "$VAR" = HOST ]; then
    "$PGBIN/pg_ctl" -D "$HOST_PGDATA" -l "$LAB_DATA_ROOT/host-postgres.log" \
      -o "-p $HOST_PORT -c listen_addresses=127.0.0.1" start >/dev/null 2>&1
  else
    docker start "$CONT" >/dev/null
  fi
  wait_pg "$PORT"
  t1=$(now_s)
  echo "$t1 $t0" | awk '{printf "%.0f", ($1-$2)*1000}'
}

pgdata_mb() {
  case "$VAR" in
    HOST) du -sm "$HOST_PGDATA" | cut -f1 ;;
    BIND) du -sm "$BIND_DIR" | cut -f1 ;;
    *)    docker exec "$CONT" sh -c 'du -sm $(printenv PGDATA || echo /var/lib/postgresql) 2>/dev/null' | cut -f1 ;;
  esac
}

say "=== Зупиняю всі лабораторні PG, стартую тільки $VAR (порт $PORT) ==="
stop_everything_lab
STARTUP_MS=$(start_target_timed)
say "Час запуску: ${STARTUP_MS} ms"

say "=== pgbench -i -s $SCALE ==="
psql_port "$PORT" -q -c "DROP TABLE IF EXISTS backup_test" 2>/dev/null || true
t0=$(now_s); pgb -i -s $SCALE >>"$LOG" 2>&1; t1=$(now_s)
INIT_S=$(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}')
psql_port "$PORT" -q -c "CHECKPOINT"
sleep 3
IDLE=$(sample_mem_cpu); IDLE_MEM=${IDLE%% *}
DB_MB=$(psql_port "$PORT" -tAc "SELECT pg_database_size('lab')/1048576")
PGD_MB=$(pgdata_mb)
echo "$VAR,$INIT_S,$STARTUP_MS,$IDLE_MEM,$DB_MB,$PGD_MB" >> "$META"
say "init=${INIT_S}s idle_mem=${IDLE_MEM}MB db=${DB_MB}MB pgdata=${PGD_MB}MB"

for C in 1 8 32; do
  J=$(( C < 8 ? C : 8 ))
  say "=== clients=$C (threads=$J): warm-up ${WARMUP}s ==="
  pgb -c "$C" -j "$J" -T $WARMUP >>"$LOG" 2>&1
  for R in 1 2 3; do
    io_reset
    OUT_FILE=$(mktemp)
    pgb -c "$C" -j "$J" -T $DURATION > "$OUT_FILE" 2>>"$LOG" &
    BPID=$!
    sleep 15
    MC=$(sample_mem_cpu) || MC="0 0"
    wait $BPID
    TPS=$(grep -E "^tps" "$OUT_FILE" | tail -1 | awk '{print $3}')
    LAT=$(grep "latency average" "$OUT_FILE" | awk '{print $4}')
    IO=$(io_read)
    MEM=${MC%% *}; CPU=${MC##* }
    RD=${IO%% *}; WR=${IO##* }
    echo "$VAR,$C,$R,$TPS,$LAT,$MEM,$CPU,$RD,$WR" >> "$CSV"
    say "c=$C run=$R: tps=$TPS lat=${LAT}ms mem=${MEM}MB cpu=${CPU}% io=${RD}/${WR}MB"
    rm -f "$OUT_FILE"
  done
done
say "=== Варіант $VAR завершено ==="
